import AppKit
import OSLog

/// A calm painting with independently circulating, cached watercolor strokes.
/// Core Graphics composites layers without displacing or resampling the base.
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
    let region = BucketLayout.waterTextureRect
    private let stillImage: CGImage
    private let layers: [CGImage]
    private let contactPaint: CGImage
    private let frameRenderer: ((CGImage) -> CGImage?)?
    private var lastGoodImage: CGImage
    private var reportedFailure = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CursorWasher", category: "water")
    private static let rect = CGRect(x: 0, y: 0, width: textureSide, height: textureSide)

    private static func canvas() -> CGContext? {
        CGContext(data: nil, width: textureSide, height: textureSide, bitsPerComponent: 8,
            bytesPerRow: textureSide * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    init?(image: NSImage, highlights: NSImage, frameRenderer: ((CGImage) -> CGImage?)? = nil) {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let canvas = Self.canvas() else { return nil }
        let layout = BucketLayout.imageRect
        canvas.interpolationQuality = .high
        canvas.scaleBy(x: CGFloat(Self.textureSide) / region.width, y: CGFloat(Self.textureSide) / region.height)
        canvas.translateBy(x: -region.minX, y: -region.minY)
        canvas.draw(source, in: layout)
        guard let calm = canvas.makeImage() else { return nil }
        stillImage = calm
        lastGoodImage = calm
        self.frameRenderer = frameRenderer
        guard let reference = highlights.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let highlightCanvas = Self.canvas() else { return nil }
        highlightCanvas.interpolationQuality = .high
        highlightCanvas.scaleBy(x: CGFloat(Self.textureSide) / region.width, y: CGFloat(Self.textureSide) / region.height)
        highlightCanvas.translateBy(x: -region.minX, y: -region.minY)
        highlightCanvas.draw(reference, in: layout)
        guard let pixels = highlightCanvas.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var painted: [CGImage] = []
        for layerIndex in 0..<3 {
            guard let layer = Self.canvas(), let output = layer.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
            for y in 0..<Self.textureSide { for x in 0..<Self.textureSide {
                let offset = y * highlightCanvas.bytesPerRow + x * 4
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0.05 else { continue }
                // Read the actual watercolor colors, unpremultiplying before selection.
                let rgb = (0..<3).map { min(1, Double(pixels[offset + $0]) / 255 / alpha) }
                let luminance = rgb[0] * 0.25 + rgb[1] * 0.6 + rgb[2] * 0.15
                let u = (Double(x) + 0.5) / Double(Self.textureSide)
                let v = (Double(y) + 0.5) / Double(Self.textureSide)
                let radius = hypot((u - 0.5) * 2, (v - 0.5) * 2)
                let edge = 1 - Self.smooth(0.82, 0.97, radius)
                // Soft annular partitions avoid cutting the source brushwork at a hard seam.
                let inner = 1 - Self.smooth(0.30, 0.44, radius)
                let outer = Self.smooth(0.62, 0.78, radius)
                let weights = [outer, max(0, 1 - inner - outer), inner]
                let coverage = Self.smooth(0.59, 0.87, luminance) * edge * weights[layerIndex]
                let target = y * layer.bytesPerRow + x * 4
                for channel in 0..<3 {
                    output[target + channel] = UInt8((rgb[channel] * coverage * 255).rounded())
                }
                output[target + 3] = UInt8((coverage * 255).rounded())
            } }
            guard let image = layer.makeImage() else { return nil }
            painted.append(image)
        }
        layers = painted
        // Reuse the source watercolor as one local patch. Its brushwork rotates
        // around the rod, including the otherwise quiet strip at the front.
        guard let contactCanvas = Self.canvas() else { return nil }
        for image in painted { contactCanvas.draw(image, in: Self.rect) }
        guard let localPaint = contactCanvas.makeImage() else { return nil }
        contactPaint = localPaint
    }

    private static func smooth(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }

    /// Uneven, tapered ribbons with fixed brush grain, in the water's plane.
    private static func arc(on canvas: CGContext, center: CGPoint, radius: CGFloat,
                            start: CGFloat, end: CGFloat, width: CGFloat, seed: CGFloat,
                            opacity: CGFloat = 1, crest: CGColor? = nil) {
        let count = 80
        canvas.saveGState()
        if opacity != 1 { canvas.setAlpha(opacity) }
        defer { canvas.restoreGState() }
        for shadow in [true, false] {
            let path = CGMutablePath()
            for edge in [1.0, -1.0] {
                let steps = edge > 0 ? Array(0...count) : Array((0...count).reversed())
                for i in steps {
                    let t = CGFloat(i) / CGFloat(count)
                    let angle = start + (end - start) * t
                    let taper = pow(max(0, sin(t * .pi)), 0.55)
                    let grain = 0.78 + 0.16 * sin(t * 47 + seed) + 0.06 * sin(t * 113 + seed)
                    let wobble = sin(angle * 5 + seed) * 1.1 + sin(angle * 11 + seed) * 0.45
                    let thickness = width * 1.4 * (shadow ? 1.8 : 1) * taper * grain
                    let r = radius + wobble + CGFloat(edge) * thickness * 0.5
                    let point = CGPoint(x: center.x + cos(angle) * r,
                                        y: center.y + sin(angle) * r + (shadow ? -2.4 : 0))
                    if i == 0 && edge > 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            path.closeSubpath()
            canvas.setFillColor(shadow
                ? CGColor(red: 0.27, green: 0.40, blue: 0.44, alpha: 0.34)
                : (crest ?? CGColor(red: 0.83, green: 0.89, blue: 0.86, alpha: 0.64)))
            canvas.addPath(path)
            canvas.fillPath()
        }
    }

    private static let waterContour: CGPath = {
        let outline = WaterSurface.path
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for index in 0..<outline.elementCount {
            switch outline.element(at: index, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }()

    /// Progress is distance from the fixed impact to the painted basin boundary.
    /// At one, every part of the front reaches the real rim, in its perspective.
    static func wavePath(origin: CGPoint, progress: CGFloat) -> CGPath {
        var transform = CGAffineTransform(a: progress, b: 0, c: 0, d: progress,
            tx: origin.x * (1 - progress), ty: origin.y * (1 - progress))
        return waterContour.copy(using: &transform)!
    }

    private func ring(on canvas: CGContext, ripple: WaterRipple) {
        let origin = CGPoint(x: region.minX + CGFloat(ripple.x) * region.width,
                             y: region.minY + CGFloat(ripple.y) * region.height)
        let front = Self.wavePath(origin: origin, progress: CGFloat(ripple.radius))
        canvas.saveGState()
        // Work in scene points so the crest does not become a wide horizontal
        // stripe when the square working texture is projected back onto water.
        canvas.scaleBy(x: 256 / region.width, y: 256 / region.height)
        canvas.translateBy(x: -region.minX, y: -region.minY)
        canvas.setLineJoin(.round)
        for shadow in [true, false] {
            canvas.saveGState()
            if shadow { canvas.translateBy(x: 0, y: -0.18) }
            let color: (CGFloat, CGFloat, CGFloat) = shadow ? (0.25, 0.40, 0.44) : (0.81, 0.88, 0.85)
            // Feathered coverage avoids sharp subpixel bands flickering against
            // the rotating watercolor. Grain is supplied by the painting below.
            let bands: [(CGFloat, CGFloat)] = shadow
                ? [(1.5, 0.05), (1.0, 0.12), (0.6, 0.28)]
                : [(1.1, 0.06), (0.7, 0.14), (0.4, 0.62)]
            for (width, alpha) in bands {
                canvas.setStrokeColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: alpha))
                canvas.setLineWidth(width)
                canvas.addPath(front)
                canvas.strokePath()
            }
            canvas.restoreGState()
        }
        canvas.restoreGState()
    }

    func image(impulses: [WaterImpulse], paintCrests: Bool = true) -> CGImage? {
        let active = impulses.filter { $0.isActive }
        guard !active.isEmpty else { return stillImage }
        guard let canvas = Self.canvas() else { return nil }
        canvas.draw(stillImage, in: Self.rect)
        // Preserve the original watercolor alpha exactly, including translucent edges.
        canvas.setBlendMode(.sourceAtop)
        if paintCrests {
            for (index, pose) in WaterMotion.layers(impulses: active).enumerated() where pose.opacity > 0 {
                canvas.saveGState()
                canvas.setAlpha(CGFloat(pose.opacity))
                canvas.translateBy(x: 128 + CGFloat(pose.x) * 256, y: 128 + CGFloat(pose.y) * 256)
                canvas.rotate(by: CGFloat(pose.rotation))
                canvas.translateBy(x: -128, y: -128)
                canvas.draw(layers[index], in: Self.rect)
                canvas.restoreGState()
            }
            for contact in active where contact.kind == .contact {
                let decay = exp(-contact.age * 8) * pow(1 - contact.age / contact.duration, 2)
                let gain = CGFloat(min(1, abs(contact.strength) * decay))
                let phase = CGFloat(contact.rotation)
                let center = CGPoint(x: contact.x * 256, y: contact.y * 256)
                // A wide, shallow pocket leaves room for paint to move directly
                // below the rod while its back half is naturally hidden by it.
                let radius = CGFloat(contact.width * 1.05 + 0.035) * 256
                canvas.saveGState()
                canvas.translateBy(x: center.x, y: center.y)
                canvas.scaleBy(x: 1, y: 0.8)
                // A filled, feathered depression follows the rod. It has no
                // circular outline that could be mistaken for a travelling wave.
                let pocketRadius = radius + CGFloat(contact.width * 0.55 + 0.035) * 256
                let pocketCenter = CGPoint(x: 0, y: 256 / region.height / 0.8)
                let colors = [CGColor(red: 0.23, green: 0.39, blue: 0.43, alpha: 0.52),
                              CGColor(red: 0.23, green: 0.39, blue: 0.43, alpha: 0.38),
                              CGColor(red: 0.23, green: 0.39, blue: 0.43, alpha: 0)]
                let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors as CFArray, locations: [0, 0.52, 1])!
                canvas.setAlpha(gain)
                canvas.drawRadialGradient(shade, startCenter: pocketCenter, startRadius: 0,
                    endCenter: pocketCenter, endRadius: pocketRadius * 1.6, options: [])
                canvas.setAlpha(1)
                // Reflections sit over the shaded water, so their motion remains
                // legible instead of being dulled by a dark overlay.
                canvas.saveGState()
                canvas.rotate(by: phase)
                canvas.setAlpha(gain * 0.95)
                let span = radius * 4.6
                canvas.draw(contactPaint, in: CGRect(x: -span / 2, y: -span / 2, width: span, height: span))
                canvas.restoreGState()

                canvas.restoreGState()
            }
            for ripple in WaterMotion.ripples(impulses: active) {
                canvas.saveGState()
                canvas.setAlpha(CGFloat(ripple.opacity))
                let center = CGPoint(x: ripple.x * 256, y: ripple.y * 256)
                if ripple.isDrop {
                    for (start, end, seed) in [(0.16, 2.91, 3.0), (3.32, 6.05, 8.0)] {
                        Self.arc(on: canvas, center: center, radius: CGFloat(ripple.radius) * 256,
                                 start: start, end: end, width: 2, seed: seed)
                    }
                } else {
                    ring(on: canvas, ripple: ripple)
                }
                canvas.restoreGState()
            }
        }
        guard let result = canvas.makeImage() else { return nil }
        if let frameRenderer = frameRenderer { return frameRenderer(result) }
        return result
    }

    func frame(impulses: [WaterImpulse], paintCrests: Bool = true) -> CGImage {
        if !impulses.contains(where: { $0.isActive }) {
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
        NSImage(cgImage: cgImage, size: region.size).draw(in: region, from: .zero,
                                                       operation: .copy, fraction: 1)
    }
}
