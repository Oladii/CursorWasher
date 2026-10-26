import AppKit
import ImageIO
import OSLog

/// The approved Figma scene is rasterized at its authored 1254-square size.
/// All native views reuse that immutable layer, including the cursor foreground.
enum FoamSurface {
    static let sourceSide = 1254
    private static let artwork = FoamArtwork.bundled
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CursorWasher", category: "foam")
    private static let sprites: [String: CGImage] = {
        var result: [String: CGImage] = [:]
        for sprite in artwork.sprites {
            guard let image = loadImage(sprite.file) else {
                logger.error("Prepared soap artwork unavailable")
                return [:]
            }
            result[sprite.file] = image
        }
        return result
    }()
    static let baseImage: CGImage? = loadImage(artwork.baseAssetFile)
    private static let basin: BucketBasin? = {
        // The working source is packaged as bucket.png by build.sh.
        let name = Bundle.main.bundleURL.pathExtension == "app" ? "bucket.png" : "bucket-dry.png"
        let url = artwork.directory.deletingLastPathComponent().appendingPathComponent(name)
        return NSImage(contentsOf: url).map { BucketBasin(bucket: $0) }
    }()

    private struct Mask: Decodable {
        struct Vector: Decodable { let windingRule: String; let data: String }
        let relativeTransform: [[CGFloat]]
        let paths: [Vector]
    }
    private static var masks: [String: CGPath] = [:]

    struct Foreground {
        let image: CGImage
        let occluder: CGImage
    }
    private final class Layer {
        let frame: FoamFrame
        let image: CGImage
        var foregroundSelection: [Int]?
        var foreground: Foreground?
        init(frame: FoamFrame, image: CGImage) { self.frame = frame; self.image = image }
    }
    // A view and its passive cursor panel draw the same frame consecutively.
    // Keep the previous layer too, so a still/rest frame does no raster work.
    private static var layers: [Layer] = []
    private final class Pending {
        let frame: FoamFrame
        let group = DispatchGroup()
        var image: CGImage?
        var foregroundSelection: [Int]?
        var foreground: Foreground?
        init(frame: FoamFrame) { self.frame = frame }
    }
    private static var pending: Pending?

    private static func key(for frame: FoamFrame) -> FoamFrame {
        var key = frame
        key.offset = .zero
        key.agitation = 0
        key.foregroundOffset = 0
        key.flowPhase = 0
        return key
    }

    private static func selection(in frame: FoamFrame, at depth: CGFloat) -> [Int] {
        frame.clusters.indices.filter {
            let cluster = frame.clusters[$0]
            return (cluster.occlusionDepthY ?? cluster.supportY ?? (cluster.y + cluster.height * 0.82)) >= depth
        }
    }

    /// Prepare the two independent source rasters while the main view paints
    /// its water. Only immutable paths/images cross into the drawing workers.
    static func prefetch(_ frame: FoamFrame, foregroundAt waterline: CGFloat?) {
        guard !frame.clusters.isEmpty else { return }
        let key = key(for: frame)
        if pending?.frame == key { return }
        let cached = layers.first(where: { $0.frame == key })
        let depth = waterline.map { (160 - ($0 - frame.offset.y)) * 1254 / 128 }
        let selected = depth.map { selection(in: key, at: $0) }
        if let cached = cached, depth == nil || cached.foregroundSelection == selected { return }
        guard let renderer = renderer(for: key) else { return }
        pending?.group.wait()
        let work = Pending(frame: key)
        work.image = cached?.image
        pending = work
        if work.image == nil {
            work.group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                work.image = autoreleasepool { renderer(nil)?.cgImage }
                work.group.leave()
            }
        }
        if let depth = depth {
            work.foregroundSelection = selected
            work.group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                work.foreground = autoreleasepool {
                    guard let bitmap = renderer(depth), let image = bitmap.cgImage,
                          let occluder = downwardOccluder(bitmap) else { return nil }
                    return Foreground(image: image, occluder: occluder)
                }
                work.group.leave()
            }
        }
    }

    private static func loadImage(_ file: String) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(artwork.directory.appendingPathComponent(file) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private static func bitmap(_ draw: (CGContext) -> Void) -> NSBitmapImageRep? {
        guard let result = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: sourceSide, pixelsHigh: sourceSide, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: result) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.clear(CGRect(x: 0, y: 0, width: sourceSide, height: sourceSide))
        context.interpolationQuality = .high
        draw(context)
        return result
    }

    private static func mask(_ file: String) -> CGPath? {
        if let cached = masks[file] { return cached }
        guard let data = try? Data(contentsOf: artwork.directory.appendingPathComponent(file)),
              let saved = try? JSONDecoder().decode(Mask.self, from: data),
              saved.paths.count == 1, saved.paths[0].windingRule == "NONZERO",
              saved.relativeTransform.count == 2,
              saved.relativeTransform.allSatisfy({ $0.count == 3 }),
              let local = path(saved.paths[0].data) else { return nil }
        let m = saved.relativeTransform
        var transform = CGAffineTransform(a: m[0][0], b: -m[1][0],
            c: m[0][1], d: -m[1][1], tx: m[0][2], ty: 1254 - m[1][2])
        guard let result = local.copy(using: &transform) else { return nil }
        masks[file] = result
        return result
    }

    /// Retain the full-precision saved cubic instead of approximating an ellipse.
    private static func path(_ data: String) -> CGPath? {
        guard let expression = try? NSRegularExpression(
            pattern: "[MCZ]|[-+]?(?:[0-9]*\\.)?[0-9]+(?:[eE][-+]?[0-9]+)?") else { return nil }
        let text = data as NSString
        let tokens = expression.matches(in: data, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range) }
        let result = CGMutablePath()
        var index = 0
        func point() -> CGPoint? {
            guard index + 1 < tokens.count,
                  let x = Double(tokens[index]), let y = Double(tokens[index + 1]) else { return nil }
            index += 2
            return CGPoint(x: CGFloat(x), y: CGFloat(y))
        }
        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M":
                guard let p = point() else { return nil }; result.move(to: p)
            case "C":
                guard let a = point(), let b = point(), let end = point() else { return nil }
                result.addCurve(to: end, control1: a, control2: b)
            case "Z": result.closeSubpath()
            default: return nil
            }
        }
        return result
    }

    private static func drawCover(_ image: CGImage, cluster: FoamCluster, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let reveal = cluster.surfaceReveal
        if reveal < 0.999999 {
            let waterY = 1254 - cluster.y - cluster.height
            let surface = CGMutablePath()
            surface.move(to: CGPoint(x: cluster.x - 4, y: waterY))
            for i in 0...40 {
                let x = cluster.x - 4 + (cluster.width + 8) * CGFloat(i) / 40
                surface.addLine(to: CGPoint(x: x, y: waterY + sin(CGFloat(i) * 0.71) * 0.8))
            }
            surface.addLine(to: CGPoint(x: cluster.x + cluster.width + 4, y: 1254))
            surface.addLine(to: CGPoint(x: cluster.x - 4, y: 1254))
            surface.closeSubpath()
            context.addPath(surface)
            context.clip()
        }
        context.translateBy(x: cluster.x,
            y: 1254 - cluster.y - cluster.height - cluster.height * (1 - reveal))
        if cluster.mirrorX {
            context.translateBy(x: cluster.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.setAlpha(min(1, max(0, cluster.opacity)))
        context.clip(to: CGRect(x: 0, y: 0, width: cluster.width, height: cluster.height))
        let scale = max(cluster.width / CGFloat(image.width), cluster.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (cluster.width - width) * 0.5,
            y: (cluster.height - height) * 0.5, width: width, height: height))
    }

    private static func renderer(for frame: FoamFrame) -> ((CGFloat?) -> NSBitmapImageRep?)? {
        guard artwork.isAvailable, !sprites.isEmpty, let basin = basin,
              let authored = mask(frame.maskFile), let outer = mask("anchors/rest-mask.json") else { return nil }
        var horizontal = CGAffineTransform(a: frame.maskHorizontalScale, b: 0, c: 0, d: 1,
            tx: 641 * (1 - frame.maskHorizontalScale), ty: 0)
        guard let raw = authored.copy(using: &horizontal) else { return nil }
        var shift = CGAffineTransform(translationX: frame.maskOffsetX, y: -frame.maskOffsetY)
        guard let shifted = raw.copy(using: &shift) else { return nil }
        var openingShift = CGAffineTransform(translationX: 0, y: -(frame.physicalOpeningOffset ?? 0))
        guard let movingOpening = basin.sourceOpeningPath.copy(using: &openingShift) else { return nil }
        let images = sprites
        return { depth in bitmap { context in
            // Every island shares this measured 689-point boundary. Establish
            // it once on the frame, then inherit it through each saved state.
            context.addPath(basin.safeSourceOpeningPath)
            context.clip(using: .evenOdd)
            if frame.physicalOpeningOffset != nil {
                context.addPath(movingOpening)
                context.clip(using: .evenOdd)
            } else if frame.usePhysicalOpening {
                context.addPath(outer)
                context.clip(using: .winding)
                context.addPath(basin.sourceOpeningPath)
                context.clip(using: .evenOdd)
            }
            for cluster in frame.clusters {
                guard cluster.width > 0, cluster.height > 0,
                      let image = images[cluster.assetFile] else { continue }
                if let depth = depth,
                   (cluster.occlusionDepthY ?? cluster.supportY ?? (cluster.y + cluster.height * 0.82)) < depth { continue }
                context.saveGState()
                var localShift = CGAffineTransform(translationX: 0, y: -cluster.localMaskOffsetY)
                let local = shifted.copy(using: &localShift)!
                if cluster.maskActive && (frame.physicalOpeningOffset != nil || !frame.usePhysicalOpening) {
                    if cluster.maskScale == 1 {
                        context.addPath(local)
                    } else {
                        var expansion = CGAffineTransform(a: cluster.maskScale, b: 0,
                            c: 0, d: cluster.maskScale,
                            tx: 641 * (1 - cluster.maskScale), ty: 834 * (1 - cluster.maskScale))
                        context.addPath(local.copy(using: &expansion)!)
                    }
                    context.clip(using: .winding)
                }
                drawCover(image, cluster: cluster, in: context)
                context.restoreGState()
            }
        } }
    }

    private static func render(_ frame: FoamFrame, depth: CGFloat? = nil) -> NSBitmapImageRep? {
        renderer(for: frame)?(depth)
    }

    private static func layer(for frame: FoamFrame) -> Layer? {
        guard !frame.clusters.isEmpty else { return nil }
        let key = key(for: frame)
        if let work = pending, work.frame == key {
            work.group.wait()
            pending = nil
            if let image = work.image {
                let result = Layer(frame: key, image: image)
                result.foregroundSelection = work.foregroundSelection
                result.foreground = work.foreground
                layers.removeAll(where: { $0.frame == key })
                layers.append(result)
                if layers.count > 2 { layers.removeFirst() }
                return result
            }
        }
        if let index = layers.firstIndex(where: { $0.frame == key }) {
            let found = layers.remove(at: index)
            layers.append(found)
            return found
        }
        guard let image = render(key)?.cgImage else { return nil }
        let result = Layer(frame: key, image: image)
        layers.append(result)
        if layers.count > 2 { layers.removeFirst() }
        return result
    }

    static func image(for frame: FoamFrame) -> CGImage? { layer(for: frame)?.image }

    /// Keep the actual upper silhouette and fill every column below it. This
    /// prevents a second cursor fragment appearing beneath a foreground island.
    private static func downwardOccluder(_ source: NSBitmapImageRep) -> CGImage? {
        guard let result = bitmap({ _ in }), let input = source.bitmapData,
              let output = result.bitmapData else { return nil }
        let columns = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceSide)
        columns.initialize(repeating: 0, count: sourceSide)
        defer { columns.deallocate() }
        let words = UnsafeMutableRawPointer(output).assumingMemoryBound(to: UInt32.self)
        let rowWords = result.bytesPerRow / 4
        for y in 0..<sourceSide { for x in 0..<sourceSide {
            let covered = max(columns[x], input[y * source.bytesPerRow + x * 4 + 3])
            columns[x] = covered
            words[y * rowWords + x] = UInt32(covered) * 0x01010101
        } }
        return result.cgImage
    }

    static func foreground(for frame: FoamFrame, at waterline: CGFloat) -> Foreground? {
        guard let layer = layer(for: frame) else { return nil }
        let depth = (160 - (waterline - frame.offset.y)) * 1254 / 128
        let selection = selection(in: layer.frame, at: depth)
        if layer.foregroundSelection == selection { return layer.foreground }
        guard let foreground = render(layer.frame, depth: depth), let image = foreground.cgImage,
              let occluder = downwardOccluder(foreground) else { return nil }
        let result = Foreground(image: image, occluder: occluder)
        layer.foregroundSelection = selection
        layer.foreground = result
        return result
    }

    static func draw(_ frame: FoamFrame, in context: CGContext, foregroundAt waterline: CGFloat? = nil) {
        let image = waterline.flatMap { foreground(for: frame, at: $0)?.image } ?? self.image(for: frame)
        guard let image = image else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: BucketLayout.imageRect.offsetBy(dx: frame.offset.x, dy: frame.offset.y))
        context.restoreGState()
    }
}
