import AppKit
import OSLog

final class WashView: NSView {
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    var bucketImage: NSImage? { didSet { rebuildWaterSurface() } }
    var paintsWaterCrests = true
    var waterImage: NSImage? { didSet { rebuildWaterSurface() } }
    var waterHighlights: NSImage? { didSet { rebuildWaterSurface() } }

    private func rebuildWaterSurface() {
        waterSurface = (waterImage ?? bucketImage).flatMap { source in
            waterHighlights.flatMap { WaterSurface(image: source, highlights: $0) }
        }
        if waterImage != nil && waterHighlights != nil && waterSurface == nil {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CursorWasher", category: "water")
                .error("Water surface unavailable; drawing the original calm image")
        }
        needsDisplay = true
    }
    private var waterSurface: WaterSurface?
    var bucketHitMap: BucketHitMap?
    var onWash: ((CGPoint, NSEvent) -> Void)?
    var onAccessibleWash: (() -> Bool)?
    var onDrag: (() -> Bool)?
    var animationFrame: WashAnimationFrame? { didSet { needsDisplay = true } }
    var onContextMenu: (() -> Bool)?
    var recovery = false { didSet { needsDisplay = true } }
    let cursorSprite = CursorSprite.systemArrow
    private var gesture = WidgetGesture()
    private var dragWindowOrigin: CGPoint?
    private var dragging = false

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Wash Cursor" }
    override func accessibilityHelp() -> String? { "Wash the cursor in the bucket. Drag the bucket to move it." }
    override func accessibilityPerformPress() -> Bool { onAccessibleWash?() ?? false }

    override func mouseDown(with event: NSEvent) {
        cancelInteraction()
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), let window = window else { return }
        dragWindowOrigin = window.frame.origin
        gesture.begin(at: window.convertPoint(toScreen: event.locationInWindow),
                      onBucket: bucketHitMap?.contains(point, imageRect: BucketLayout.imageRect) == true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window, let origin = dragWindowOrigin,
              let offset = gesture.dragOffset(to: window.convertPoint(toScreen: event.locationInWindow)) else { return }
        if !dragging {
            guard onDrag?() == true else { cancelInteraction(); return }
            dragging = true
        }
        window.setFrameOrigin(CGPoint(x: origin.x + offset.x, y: origin.y + offset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let window = window else { cancelInteraction(); return }
        let point = convert(event.locationInWindow, from: nil)
        let shouldWash = gesture.end(at: window.convertPoint(toScreen: event.locationInWindow),
                                     inside: bounds.contains(point))
        cancelInteraction()
        if shouldWash { onWash?(point, event) }
    }

    func cancelInteraction() {
        gesture.cancel()
        dragWindowOrigin = nil
        dragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelInteraction()
        guard onContextMenu?() == true, let menu = menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        bucketImage?.draw(in: BucketLayout.imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        if let surface = waterSurface {
            surface.draw(impulses: animationFrame?.waterImpulses ?? [], paintCrests: paintsWaterCrests)
        } else {
            NSGraphicsContext.saveGraphicsState()
            WaterSurface.path.addClip()
            waterImage?.draw(in: BucketLayout.imageRect, from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        if recovery {
            NSColor.systemRed.setFill()
            NSRect(x: BucketLayout.landing.x - 8, y: BucketLayout.landing.y - 8, width: 16, height: 16).fill()
            return
        }
        // The transformed cursor uses a passive window throughout the animation.
        guard let frame = animationFrame else { return }
        if let splash = frame.splash { drawSplash(progress: splash, origin: frame.splashOrigin ?? CGPoint(x: BucketLayout.water.midX, y: BucketLayout.water.minY)) }
    }

    private func drawSplash(progress: Double, origin: CGPoint) {
        for drop in PaintedSplash.particles(at: progress, origin: origin) {
            PaintedWaterDrop.draw(at: drop.position, pose: drop.pose, opacity: drop.opacity)
        }
    }
}
