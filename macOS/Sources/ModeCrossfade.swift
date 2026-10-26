import Foundation
import CoreGraphics

/// Interpolates complete, equally sized scene captures in premultiplied RGBA.
/// Pixels shared by both scenes (including the bucket) retain their exact bytes.
struct ModeCrossfade {
    static let duration: TimeInterval = 0.42

    private let source: CGImage
    private let target: CGImage
    private let sourceBytes: Data
    private let targetBytes: Data
    private let start: TimeInterval
    private let end: TimeInterval
    private let interval: TimeInterval

    init?(from source: CGImage, to target: CGImage, at start: TimeInterval,
          duration: TimeInterval = ModeCrossfade.duration) {
        guard start.isFinite, duration.isFinite, duration > 0,
              source.width == target.width, source.height == target.height,
              source.bytesPerRow == target.bytesPerRow,
              source.bitsPerComponent == 8, target.bitsPerComponent == 8,
              source.bitsPerPixel == 32, target.bitsPerPixel == 32,
              source.bitmapInfo == target.bitmapInfo,
              source.alphaInfo == .premultipliedLast || source.alphaInfo == .premultipliedFirst,
              !source.bitmapInfo.contains(.floatComponents),
              source.decode == nil, target.decode == nil,
              let sourceSpace = source.colorSpace, let targetSpace = target.colorSpace,
              CFEqual(sourceSpace, targetSpace),
              let sourceData = source.dataProvider?.data, let targetData = target.dataProvider?.data else { return nil }
        let (pixelRowSize, rowOverflow) = source.width.multipliedReportingOverflow(by: 4)
        let (byteCount, countOverflow) = source.bytesPerRow.multipliedReportingOverflow(by: source.height)
        guard !rowOverflow, !countOverflow, source.bytesPerRow >= pixelRowSize,
              CFDataGetLength(sourceData) >= byteCount,
              CFDataGetLength(sourceData) == CFDataGetLength(targetData) else { return nil }
        let interval = min(duration, Self.duration), end = start + interval
        guard end.isFinite, end > start else { return nil }
        self.source = source
        self.target = target
        sourceBytes = sourceData as Data
        targetBytes = targetData as Data
        self.start = start
        self.end = end
        self.interval = interval
    }

    func image(at time: TimeInterval) -> CGImage {
        // Comparisons also give NaN a deterministic source fallback.
        guard time > start else { return source }
        guard time < end else { return target }
        let progress = (time - start) / interval
        // Quintic easing has zero velocity and acceleration at both endpoints.
        let amount = min(1, max(0, progress * progress * progress * (progress * (progress * 6 - 15) + 10)))
        var bytes = sourceBytes
        bytes.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            sourceBytes.withUnsafeBytes { (a: UnsafeRawBufferPointer) in
                targetBytes.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                    for row in 0..<source.height {
                        let rowStart = row * source.bytesPerRow
                        for offset in rowStart..<(rowStart + source.width * 4) where a[offset] != b[offset] {
                            let x = Double(a[offset]), y = Double(b[offset])
                            output[offset] = UInt8((x + (y - x) * amount).rounded())
                        }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: bytes as CFData),
              let space = source.colorSpace,
              let image = CGImage(width: source.width, height: source.height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: source.bytesPerRow,
                space: space, bitmapInfo: source.bitmapInfo, provider: provider, decode: nil,
                shouldInterpolate: source.shouldInterpolate, intent: source.renderingIntent) else { return source }
        return image
    }

    func isComplete(at time: TimeInterval) -> Bool { time >= end }
}
