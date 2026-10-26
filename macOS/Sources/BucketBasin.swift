import AppKit

/// The physical inner lip and water projection measured in the approved cycle.
/// Foam is occluded by the real metal, never by the flat water silhouette.
final class BucketBasin {
    static let paintRect = CGRect(x: 62, y: 108, width: 72, height: 20)
    let waterPath: CGPath
    let frontPath: CGPath
    let safeFrontPath: CGPath
    let safeOpeningPath: CGPath
    let sourceOpeningPath: CGPath
    let safeSourceOpeningPath: CGPath
    private let frontProfile: [CGPoint]
    private let bucket: CGImage
    private let width: Int
    private let height: Int
    private let mapping: [Pixel]
    private let canvas: CGContext
    private var baselineImage: CGImage?
    private var baselineValues: [CalmPixel] = []
    private var projectedCalm: CGImage?

    private struct Bilinear {
        let a: Int, b: Int, c: Int, d: Int
        let x: Double, y: Double

        init(x: Double, y: Double) {
            let side = WaterSurface.textureSide
            let x = min(Double(side - 1), max(0, x))
            let y = min(Double(side - 1), max(0, y))
            let ix = Int(x), iy = Int(y)
            let nx = min(side - 1, ix + 1), ny = min(side - 1, iy + 1)
            a = (iy * side + ix) * 4
            b = (iy * side + nx) * 4
            c = (ny * side + ix) * 4
            d = (ny * side + nx) * 4
            self.x = x - Double(ix)
            self.y = y - Double(iy)
        }

        @inline(__always)
        func sample(_ pixels: UnsafeRawBufferPointer, channel: Int) -> Double {
            // Preserve the approved evaluation order, including rounding at .5.
            let upper = Double(pixels[a + channel]) * (1 - x) + Double(pixels[b + channel]) * x
            let lower = Double(pixels[c + channel]) * (1 - x) + Double(pixels[d + channel]) * x
            return upper * (1 - y) + lower * y
        }
    }
    private struct Pixel {
        let offset: Int
        let original: Bilinear
        let interior: Bilinear
    }
    private struct CalmPixel {
        let baseR: Double, baseG: Double, baseB: Double
        let originalR: Double, originalG: Double, originalB: Double
    }

    private static func world(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: 32 + x / 1254 * 128, y: 32 + (1254 - y) / 1254 * 128)
    }

    init(bucket: NSImage, pixelScale: Int = 4) {
        precondition(pixelScale > 0)
        guard let image = bucket.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("The bucket artwork must contain a bitmap")
        }
        self.bucket = image
        let bitmap = NSBitmapImageRep(cgImage: image)
        var measured: [CGFloat] = []
        // This scan happens once. It is identical to the approved preview's
        // median-filtered measurement of the first dark physical inner lip.
        for x in 300...988 {
            let t = Double(x - 312) / 664
            let expected = 416 + sin(min(1, max(0, t)) * .pi) * 79
            var row = CGFloat(expected + 9)
            for y in max(0, Int(expected - 12))...min(1252, Int(expected + 30)) {
                guard let a = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = bitmap.colorAt(x: x, y: y + 1)?.usingColorSpace(.deviceRGB) else { continue }
                func luminance(_ color: NSColor) -> CGFloat {
                    color.redComponent * 0.23 + color.greenComponent * 0.60 + color.blueComponent * 0.17
                }
                if luminance(a) < 0.31 && luminance(b) < 0.37 {
                    row = CGFloat(y) + 1.5
                    break
                }
            }
            measured.append(row)
        }
        let front: [CGPoint] = measured.indices.map { index in
            let range = max(0, index - 4)...min(measured.count - 1, index + 4)
            let sorted = range.map { measured[$0] }.sorted()
            return Self.world(CGFloat(index + 300), sorted[sorted.count / 2])
        }
        frontProfile = front
        let water = CGMutablePath()
        water.move(to: front[0])
        water.addCurve(to: front.last!, control1: Self.world(388, 310), control2: Self.world(901, 310))
        for point in front.reversed() { water.addLine(to: point) }
        water.closeSubpath()
        waterPath = water
        let rim = CGMutablePath()
        rim.move(to: CGPoint(x: 32, y: 32))
        rim.addLine(to: CGPoint(x: 160, y: 32))
        rim.addLine(to: CGPoint(x: 160, y: front.last!.y))
        rim.addLine(to: front.last!)
        for point in front.reversed() { rim.addLine(to: point) }
        rim.addLine(to: CGPoint(x: 32, y: front[0].y))
        rim.closeSubpath()
        frontPath = rim

        // The measured lip passes through the antialiased ink. The approved
        // soap scene protects the complete painted edge, including its joins.
        func inkPoint(_ point: CGPoint) -> CGPoint {
            let sourceX = (point.x - 32) * 1254 / 128
            let distance = abs(sourceX - 644) / 343
            let u = min(1, max(0, (distance - 0.78) / 0.18))
            let edge = u * u * u * (10 + u * (-15 + 6 * u))
            let v = min(1, max(0, (360 - sourceX) / 50))
            let leftJoin = v * v * v * (10 + v * (-15 + 6 * v))
            return CGPoint(x: point.x, y: point.y + 0.50 + 0.45 * edge + 0.15 * leftJoin)
        }
        let protected = CGMutablePath()
        rim.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint: protected.move(to: inkPoint(element.pointee.points[0]))
            case .addLineToPoint: protected.addLine(to: inkPoint(element.pointee.points[0]))
            case .closeSubpath: protected.closeSubpath()
            default: preconditionFailure("The measured front lip must remain a polygon")
            }
        }
        safeFrontPath = protected
        let opening = CGMutablePath()
        opening.addRect(BucketLayout.centerBounds)
        opening.addPath(rim)
        let safeOpening = CGMutablePath()
        safeOpening.addRect(BucketLayout.centerBounds)
        safeOpening.addPath(protected)
        safeOpeningPath = safeOpening
        var nativeToSource = CGAffineTransform(a: 1254.0 / 128, b: 0,
            c: 0, d: 1254.0 / 128, tx: -32 * 1254.0 / 128, ty: -32 * 1254.0 / 128)
        sourceOpeningPath = opening.copy(using: &nativeToSource)!
        safeSourceOpeningPath = safeOpening.copy(using: &nativeToSource)!

        width = Int(Self.paintRect.width) * pixelScale
        height = Int(Self.paintRect.height) * pixelScale
        canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let original = BucketLayout.waterTextureRect
        let side = Double(WaterSurface.textureSide)
        var pixels: [Pixel] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height { for x in 0..<width {
            let point = CGPoint(x: Self.paintRect.minX + (CGFloat(x) + 0.5) / CGFloat(pixelScale),
                y: Self.paintRect.maxY - (CGFloat(y) + 0.5) / CGFloat(pixelScale))
            guard water.contains(point) else { continue }
            let ix = Double((point.x - original.minX) / original.width) * side - 0.5
            let iy = Double((original.maxY - point.y) / original.height) * side - 0.5
            let interior = CGPoint(x: original.midX + (point.x - original.midX) * 0.82,
                y: original.midY + (point.y - original.midY) * 0.82)
            let u = Double((interior.x - original.minX) / original.width) * side - 0.5
            let v = Double((original.maxY - interior.y) / original.height) * side - 0.5
            pixels.append(Pixel(offset: (y * width + x) * 4,
                original: Bilinear(x: ix, y: iy), interior: Bilinear(x: u, y: v)))
        } }
        mapping = pixels
    }

    private func validWater(_ image: CGImage) -> Bool {
        image.width == WaterSurface.textureSide && image.height == WaterSurface.textureSide
            && image.bitsPerPixel == 32 && image.bytesPerRow == WaterSurface.textureSide * 4
    }

    private func prepareBaseline(_ baseline: CGImage) -> Bool {
        if baseline === baselineImage { return true }
        guard validWater(baseline), let provider = baseline.dataProvider?.data else { return false }
        let data = provider as Data
        guard data.count >= WaterSurface.textureSide * WaterSurface.textureSide * 4 else { return false }
        baselineValues = data.withUnsafeBytes { pixels in
            mapping.map { point in
                CalmPixel(baseR: point.interior.sample(pixels, channel: 0),
                    baseG: point.interior.sample(pixels, channel: 1),
                    baseB: point.interior.sample(pixels, channel: 2),
                    originalR: point.original.sample(pixels, channel: 0),
                    originalG: point.original.sample(pixels, channel: 1),
                    originalB: point.original.sample(pixels, channel: 2))
            }
        }
        baselineImage = baseline
        projectedCalm = nil
        return true
    }

    func drawWater(_ image: CGImage, baseline: CGImage, in context: CGContext) {
        guard validWater(image), prepareBaseline(baseline) else { return }
        let result: CGImage
        if image === baseline, let cached = projectedCalm {
            result = cached
        } else {
            guard let provider = image.dataProvider?.data else { return }
            let data = provider as Data
            guard data.count >= WaterSurface.textureSide * WaterSurface.textureSide * 4,
                  let target = canvas.data?.assumingMemoryBound(to: UInt8.self) else { return }
            data.withUnsafeBytes { pixels in
                for index in mapping.indices {
                    let point = mapping[index], calm = baselineValues[index]
                    let r = calm.baseR + (point.original.sample(pixels, channel: 0) - calm.originalR)
                    let g = calm.baseG + (point.original.sample(pixels, channel: 1) - calm.originalG)
                    let b = calm.baseB + (point.original.sample(pixels, channel: 2) - calm.originalB)
                    target[point.offset] = UInt8(min(255, max(0, r.rounded())))
                    target[point.offset + 1] = UInt8(min(255, max(0, g.rounded())))
                    target[point.offset + 2] = UInt8(min(255, max(0, b.rounded())))
                    target[point.offset + 3] = 255
                }
            }
            guard let projected = canvas.makeImage() else { return }
            result = projected
            if image === baseline { projectedCalm = projected }
        }
        context.saveGState()
        context.addPath(waterPath)
        context.clip()
        context.draw(result, in: Self.paintRect)
        context.restoreGState()
    }

    func drawFront(in context: CGContext) {
        context.saveGState()
        context.addPath(frontPath)
        context.clip()
        context.draw(bucket, in: BucketLayout.imageRect)
        context.restoreGState()
    }

    /// Inverse of the physical front metal, optionally translated into overlay
    /// coordinates. The water outline is intentionally absent from this mask.
    func clipOpening(in context: CGContext, offset: CGPoint = .zero, protectingInk: Bool = false) {
        context.addRect(CGRect(x: offset.x, y: offset.y,
            width: BucketLayout.side, height: BucketLayout.side))
        var transform = CGAffineTransform(translationX: offset.x, y: offset.y)
        if let front = (protectingInk ? safeFrontPath : frontPath).copy(using: &transform) { context.addPath(front) }
        context.clip(using: .evenOdd)
    }

    func frontY(at x: CGFloat) -> CGFloat {
        let first = frontProfile.first!, last = frontProfile.last!
        let u = min(CGFloat(frontProfile.count - 1),
            max(0, (x - first.x) / (last.x - first.x) * CGFloat(frontProfile.count - 1)))
        let index = min(frontProfile.count - 2, Int(u)), fraction = u - CGFloat(index)
        return frontProfile[index].y + (frontProfile[index + 1].y - frontProfile[index].y) * fraction
    }
}
