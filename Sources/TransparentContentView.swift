import AppKit

/// Explicit transparent layer contents provide a rectangular input surface.
/// Mouse delivery still needs verification on each supported macOS version.
final class TransparentContentView: NSView {
    private let transparentImage: NSImage = {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 4, bitsPerPixel: 32)!
        bitmap.bitmapData!.initialize(repeating: 0, count: 4)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.addRepresentation(bitmap)
        return image
    }()

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.contents = transparentImage
        layer?.contentsGravity = .resize
    }
}
