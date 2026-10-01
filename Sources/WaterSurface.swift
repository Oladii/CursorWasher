import AppKit
import CoreImage
import OSLog

/// Replaces the visible water with its own warped paint, keeping the bucket still.
final class WaterSurface {
    static var path: NSBezierPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: BucketLayout.imageRect.minX + x / 1254 * BucketLayout.imageRect.width,
                    y: BucketLayout.imageRect.minY + (1254 - y) / 1254 * BucketLayout.imageRect.height)
        }
        let path = NSBezierPath()
        path.move(to: p(312, 416))
        path.curve(to: p(976, 417), controlPoint1: p(397, 323), controlPoint2: p(882, 322))
        path.curve(to: p(647, 492), controlPoint1: p(914, 464), controlPoint2: p(782, 489))
        path.curve(to: p(312, 416), controlPoint1: p(513, 492), controlPoint2: p(379, 466))
        path.close()
        return path
    }

    static let textureSide = 256
    static let mapSide = 96
    let region = BucketLayout.waterTextureRect
    private let context: CIContext
    private let texture: CIImage
    private let stillImage: CGImage
    private let filter: CIFilter?
    private let flowKernel: CIKernel?
    private let frameRenderer: ((CIImage) -> CGImage?)?
    private var lastGoodImage: CGImage
    private var reportedFailure = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CursorWasher", category: "water")
    private var values = [Float](repeating: 1, count: WaterSurface.mapSide * WaterSurface.mapSide * 4)
    private var heights = [Double](repeating: 0, count: WaterSurface.mapSide * WaterSurface.mapSide)
    private var dropHeights = [Double](repeating: 0, count: WaterSurface.mapSide * WaterSurface.mapSide)
    private var pigment = [Float](repeating: 0, count: WaterSurface.mapSide * WaterSurface.mapSide * 4)
    private var flowMap = [Float](repeating: 1, count: WaterSurface.mapSide * WaterSurface.mapSide * 16)

    init?(image: NSImage, frameRenderer: ((CIImage) -> CGImage?)? = nil) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        filter = CIFilter(name: "CIDisplacementDistortion")
        flowKernel = CIKernel(source: """
                kernel vec4 cursorFlow(sampler source, sampler offsets, float scale) {
                    vec2 point = destCoord();
                    vec2 shift = (sample(offsets, samplerTransform(offsets, point)).rg - vec2(0.5)) * scale;
                    return sample(source, samplerTransform(source, point - shift));
                }
                """)
        self.frameRenderer = frameRenderer
        context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
                                     .cacheIntermediates: false])
        let source = CIImage(cgImage: cgImage, options: [.colorSpace: NSNull()])
        let layout = BucketLayout.imageRect
        let sx = layout.width / CGFloat(cgImage.width), sy = layout.height / CGFloat(cgImage.height)
        // Flatten the perspective before displacement so waves move in the water's
        // plane instead of stretching vertically across the rim.
        let transform = CGAffineTransform(a: sx * CGFloat(Self.textureSide) / region.width, b: 0,
            c: 0, d: sy * CGFloat(Self.textureSide) / region.height,
            tx: (layout.minX - region.minX) * CGFloat(Self.textureSide) / region.width,
            ty: (layout.minY - region.minY) * CGFloat(Self.textureSide) / region.height)
        let rect = CGRect(x: 0, y: 0, width: Self.textureSide, height: Self.textureSide)
        guard let cached = context.createCGImage(source.transformed(by: transform), from: rect,
                                                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else { return nil }
        texture = CIImage(cgImage: cached, options: [.colorSpace: NSNull()]).clampedToExtent()
        stillImage = cached
        lastGoodImage = cached
        if filter == nil || flowKernel == nil {
            logger.error("Animated water unavailable; using calm water")
        }
    }

    func flowImage(source: CIImage, impulses: [WaterImpulse]) -> CIImage? {
        guard impulses.contains(where: { $0.isActive && $0.kind == .stir }) else { return source }
        guard let flowKernel = flowKernel else { return nil }
        let side = Self.mapSide * 2
        for y in 0..<side { for x in 0..<side {
            // Bitmap rows run downward; the water's local Y axis points upward.
            let flow = WaterMotion.flow(x: (Double(x) + 0.5) / Double(side),
                y: 1 - (Double(y) + 0.5) / Double(side), impulses: impulses)
            let i = (y * side + x) * 4
            flowMap[i] = Float(0.5 + flow.x); flowMap[i + 1] = Float(0.5 + flow.y)
            flowMap[i + 2] = 0.5
        } }
        let data = flowMap.withUnsafeBytes { Data($0) }
        let offsets = CIImage(bitmapData: data, bytesPerRow: side * 16,
            size: CGSize(width: side, height: side), format: .RGBAf, colorSpace: nil)
            .transformed(by: CGAffineTransform(scaleX: CGFloat(Self.textureSide) / CGFloat(side),
                                              y: CGFloat(Self.textureSide) / CGFloat(side)))
            .clampedToExtent()
        let rect = CGRect(x: 0, y: 0, width: Self.textureSide, height: Self.textureSide)
        return flowKernel.apply(extent: rect, roiCallback: { _, rect in rect.insetBy(dx: -128, dy: -128) },
            arguments: [source.clampedToExtent(), offsets, Double(Self.textureSide) * 0.85])
    }

    func image(impulses: [WaterImpulse], paintCrests: Bool = true) -> CGImage? {
        guard let filter = filter, flowKernel != nil else { return nil }
        let impulses = impulses.filter { $0.isActive }
        let side = Self.mapSide
        let fluidImpulses = impulses.filter { $0.kind != .drop }
        let heightImpulses = fluidImpulses.filter { $0.kind != .stir }
        let dropImpulses = impulses.filter { $0.kind == .drop }
        for y in 0..<side {
            for x in 0..<side {
                let u = (Double(x) + 0.5) / Double(side), v = 1 - (Double(y) + 0.5) / Double(side)
                let fluid = WaterMotion.height(x: u, y: v, impulses: fluidImpulses)
                let displacement = WaterMotion.height(x: u, y: v, impulses: heightImpulses)
                let drop = WaterMotion.height(x: u, y: v, impulses: dropImpulses)
                heights[y * side + x] = fluid
                dropHeights[y * side + x] = drop
                let value = Float(0.5 + min(1, max(-1, displacement + drop)) * 0.28)
                let index = (y * side + x) * 4
                values[index] = value
                values[index + 1] = value
                values[index + 2] = value
            }
        }
        let data = values.withUnsafeBytes { Data($0) }
        let map = CIImage(bitmapData: data, bytesPerRow: side * 16,
                          size: CGSize(width: side, height: side), format: .RGBAf, colorSpace: nil)
            .transformed(by: CGAffineTransform(scaleX: CGFloat(Self.textureSide) / CGFloat(side),
                                              y: CGFloat(Self.textureSide) / CGFloat(side)))
            .clampedToExtent()
        filter.setValue(texture, forKey: kCIInputImageKey)
        filter.setValue(map, forKey: "inputDisplacementImage")
        filter.setValue(850, forKey: kCIInputScaleKey)
        guard var output = filter.outputImage else { return nil }
        guard let flowing = flowImage(source: output, impulses: impulses) else { return nil }
        output = flowing
        if paintCrests && !impulses.isEmpty {
            for y in 0..<side {
                for x in 0..<side {
                    let left = dropHeights[y * side + max(0, x - 1)]
                    let right = dropHeights[y * side + min(side - 1, x + 1)]
                    let bottom = dropHeights[min(side - 1, y + 1) * side + x]
                    let top = dropHeights[max(0, y - 1) * side + x]
                    let drops = WaterPigment.rgba(height: dropHeights[y * side + x],
                        slopeX: (right - left) * Double(side) / 2,
                        slopeY: (top - bottom) * Double(side) / 2,
                        x: (Double(x) + 0.5) / Double(side),
                        y: 1 - (Double(y) + 0.5) / Double(side))
                    let fluid = WaterPigment.watercolor(height: heights[y * side + x],
                        x: (Double(x) + 0.5) / Double(side), y: 1 - (Double(y) + 0.5) / Double(side))
                    let keep = 1 - drops.3
                    let i = (y * side + x) * 4
                    pigment[i] = drops.0 + fluid.0 * keep; pigment[i + 1] = drops.1 + fluid.1 * keep
                    pigment[i + 2] = drops.2 + fluid.2 * keep; pigment[i + 3] = drops.3 + fluid.3 * keep
                }
            }
            let colorData = pigment.withUnsafeBytes { Data($0) }
            let color = CIImage(bitmapData: colorData, bytesPerRow: side * 16,
                size: CGSize(width: side, height: side), format: .RGBAf, colorSpace: nil)
                .transformed(by: CGAffineTransform(scaleX: CGFloat(Self.textureSide) / CGFloat(side),
                                                  y: CGFloat(Self.textureSide) / CGFloat(side)))
                .clampedToExtent()
            output = color.applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: output])
        }
        if let frameRenderer = frameRenderer { return frameRenderer(output) }
        return context.createCGImage(output, from: CGRect(x: 0, y: 0, width: Self.textureSide, height: Self.textureSide),
                                     format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    func frame(impulses: [WaterImpulse], paintCrests: Bool = true) -> CGImage {
        let moving = impulses.contains(where: { $0.isActive })
        if !moving {
            lastGoodImage = stillImage
            reportedFailure = false
        } else if let image = image(impulses: impulses, paintCrests: paintCrests) {
            lastGoodImage = image
            reportedFailure = false
        } else if !reportedFailure {
            logger.error("Water frame failed; keeping the last good frame")
            reportedFailure = true
        }
        return lastGoodImage
    }

    func draw(impulses: [WaterImpulse], paintCrests: Bool = true) {
        let cgImage = frame(impulses: impulses, paintCrests: paintCrests)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        Self.path.addClip()
        // Copy replaces both color and the original watercolor alpha, so the
        // static water underneath cannot show through as a second layer.
        NSImage(cgImage: cgImage, size: region.size).draw(in: region, from: .zero,
                                                       operation: .copy, fraction: 1)
    }
}
