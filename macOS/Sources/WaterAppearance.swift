import AppKit

/// Color only: no resampling, displacement, alpha changes or changes to wave motion.
enum WaterAppearance {
    private static let amounts: [CGFloat] = [0, 0.12, 0.30, 0.46, 0.64, 1]
    static let maximumLevel = (amounts.count - 1) * 2

    private static func approvedRGB(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, level: Int) -> (CGFloat, CGFloat, CGFloat) {
        let amount = amounts[level]
        guard amount > 0 else { return (r, g, b) }
        let luminance = r * 0.23 + g * 0.60 + b * 0.17
        let highlight = min(1, max(0, (luminance - 0.65) / 0.30))
        let shade = 1 - amount * (0.40 - 0.14 * highlight)
        let saturation = 1 - amount * 0.98
        let gray = luminance * shade
        return (gray + (r - luminance) * saturation * shade,
                gray + (g - luminance) * saturation * shade,
                gray + (b - luminance) * saturation * shade + amount * 0.008 * (1 - luminance))
    }

    /// Retain the approved colors at even levels and insert their midpoints at odd levels.
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, level: Int) -> (CGFloat, CGFloat, CGFloat) {
        let level = min(maximumLevel, max(0, level))
        let a = approvedRGB(r, g, b, level: level / 2)
        guard level % 2 != 0 else { return a }
        let z = approvedRGB(r, g, b, level: level / 2 + 1)
        return ((a.0 + z.0) / 2, (a.1 + z.1) / 2, (a.2 + z.2) / 2)
    }

    /// Change color continuously within each of the ten washes.
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, amount: Double) -> (CGFloat, CGFloat, CGFloat) {
        let amount = amount.isFinite ? min(Double(maximumLevel), max(0, amount)) : 0
        let lower = Int(floor(amount)), upper = Int(ceil(amount))
        let a = rgb(r, g, b, level: lower)
        guard lower != upper else { return a }
        let z = rgb(r, g, b, level: upper), t = CGFloat(amount - Double(lower))
        return (a.0 + (z.0 - a.0) * t, a.1 + (z.1 - a.1) * t, a.2 + (z.2 - a.2) * t)
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat, level: Int) -> CGColor {
        let (r, g, b) = rgb(r, g, b, level: level)
        return CGColor(red: r, green: g, blue: b, alpha: alpha)
    }

    static func paintColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat, level: Int) -> NSColor {
        let (r, g, b) = rgb(r, g, b, level: level)
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }

    static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat, amount: Double) -> CGColor {
        let (r, g, b) = rgb(r, g, b, amount: amount)
        return CGColor(red: r, green: g, blue: b, alpha: alpha)
    }

    static func paintColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat, amount: Double) -> NSColor {
        let (r, g, b) = rgb(r, g, b, amount: amount)
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }

    /// Blend equally posed cached surfaces without compositing their translucent edges twice.
    /// RGB is interpolated directly while every source alpha byte is retained.
    static func mix(_ a: CGImage, _ b: CGImage, progress: CGFloat) -> CGImage {
        guard progress.isFinite, progress > 0 else { return a }
        guard progress < 1 else { return b }
        guard a.width == b.width, a.height == b.height, a.bytesPerRow == b.bytesPerRow,
              a.bitsPerPixel == 32, b.bitsPerPixel == 32,
              let space = a.colorSpace,
              let sourceData = a.dataProvider?.data, let nextData = b.dataProvider?.data else { return a }
        let start = sourceData as Data, end = nextData as Data
        guard start.count == end.count else { return a }
        var output = start
        let t = Double(progress), count = output.count
        output.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) in
            start.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                end.withUnsafeBytes { (next: UnsafeRawBufferPointer) in
                    for offset in stride(from: 0, to: count, by: 4) {
                        assert(source[offset + 3] == next[offset + 3], "Dirt must preserve every water alpha")
                        for channel in 0..<3 {
                            let x = Double(source[offset + channel]), y = Double(next[offset + channel])
                            target[offset + channel] = UInt8((x + (y - x) * t).rounded())
                        }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: output as CFData),
              let result = CGImage(width: a.width, height: a.height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: a.bytesPerRow,
                space: space, bitmapInfo: a.bitmapInfo, provider: provider, decode: nil,
                shouldInterpolate: true, intent: .defaultIntent) else { return a }
        return result
    }

    /// Cached painted layers are tinted once when the water changes, not every frame.
    static func tint(_ image: CGImage, level: Int) -> CGImage? {
        guard level > 0 else { return image }
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for offset in stride(from: 0, to: context.bytesPerRow * image.height, by: 4) {
            let alpha = CGFloat(pixels[offset + 3])
            guard alpha > 0 else { continue }
            let (r, g, b) = rgb(CGFloat(pixels[offset]) / alpha,
                                CGFloat(pixels[offset + 1]) / alpha,
                                CGFloat(pixels[offset + 2]) / alpha, level: level)
            for (channel, value) in [r, g, b].enumerated() {
                pixels[offset + channel] = UInt8(min(alpha, max(0, (value * alpha).rounded())))
            }
        }
        return context.makeImage()
    }
}
