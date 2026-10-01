import AppKit

private final class ReturnWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

enum WidgetLayer: String, CaseIterable {
    case front, back
    var level: NSWindow.Level {
        self == .front ? .statusBar : NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 2)
    }
    var cursorLevel: NSWindow.Level { NSWindow.Level(rawValue: level.rawValue + 1) }
}

final class ReturnSpriteView: NSView {
    override var isOpaque: Bool { false }
    let sprite = CursorSprite.systemArrow
    var drawing: WashAnimationFrame? { didSet { needsDisplay = true } }

    func place(_ screenFrame: WashAnimationFrame, contentOrigin: CGPoint) {
        drawing = screenFrame.translated(by: CGPoint(x: -contentOrigin.x, y: -contentOrigin.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        guard let drawing = drawing else { return }
        NSGraphicsContext.saveGraphicsState()
        if let waterline = drawing.waterline {
            NSBezierPath(rect: CGRect(x: bounds.minX, y: max(bounds.minY, waterline), width: bounds.width,
                                     height: max(0, bounds.maxY - max(bounds.minY, waterline)))).addClip()
        }
        sprite.draw(at: drawing.position, appearance: drawing.appearance, shadowVisible: drawing.shadowVisible)
        NSGraphicsContext.restoreGraphicsState()
        for drop in drawing.drops {
            PaintedWaterDrop.draw(at: drop.position, pose: drop.pose, opacity: drop.opacity)
        }
        for sparkle in drawing.sparkles {
            let p = sparkle.position, r = sparkle.radius
            let path = NSBezierPath()
            let offsets: [CGPoint] = [CGPoint(x: 0, y: r), CGPoint(x: r * 0.18, y: r * 0.18),
                CGPoint(x: r * 0.75, y: 0), CGPoint(x: r * 0.18, y: -r * 0.18),
                CGPoint(x: 0, y: -r), CGPoint(x: -r * 0.18, y: -r * 0.18),
                CGPoint(x: -r * 0.75, y: 0), CGPoint(x: -r * 0.18, y: r * 0.18)]
            for (index, offset) in offsets.enumerated() {
                let vertex = CGPoint(x: p.x + offset.x, y: p.y + offset.y)
                if index == 0 { path.move(to: vertex) } else { path.line(to: vertex) }
            }
            path.close()
            NSColor(calibratedRed: 0.45, green: 0.75, blue: 0.9, alpha: sparkle.opacity).setStroke()
            path.lineWidth = 0.8
            path.lineJoinStyle = .round
            path.stroke()
            NSColor(calibratedRed: 0.94, green: 0.99, blue: 1, alpha: sparkle.opacity).setFill()
            path.fill()
        }
    }

    static func panelBounds(for frame: WashAnimationFrame) -> CGRect {
        var rect = CursorSprite.systemArrow.geometry.imageBounds(at: frame.position, appearance: frame.appearance)
        for drop in frame.drops { rect = rect.union(drop.bounds) }
        for sparkle in frame.sparkles { rect = rect.union(sparkle.bounds) }
        return rect.insetBy(dx: -2, dy: -2)
    }
}

/// A passive surface contains the cursor, droplets and sparkles, without stealing input.
final class ReturnOverlay {
    private var window: ReturnWindow?

    func show(_ frame: WashAnimationFrame, layer: WidgetLayer, staysVisibleWhenInactive: Bool = false) {
        let panelRect = ReturnSpriteView.panelBounds(for: frame)
        let panel: ReturnWindow
        if let existing = window { panel = existing } else {
            panel = ReturnWindow(contentRect: panelRect, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
            panel.isExcludedFromWindowsMenu = true
            panel.collectionBehavior = [.transient, .ignoresCycle]
            panel.animationBehavior = .none
            panel.contentView = ReturnSpriteView(frame: NSRect(origin: .zero, size: panelRect.size))
            window = panel
        }
        panel.hidesOnDeactivate = !staysVisibleWhenInactive
        panel.level = layer.cursorLevel
        panel.setFrame(panelRect, display: false)
        if !panel.isVisible { panel.orderFront(nil) }
        if let view = panel.contentView as? ReturnSpriteView {
            view.frame = NSRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size)
            let contentOrigin = panel.convertPoint(toScreen: view.convert(.zero, to: nil))
            view.place(frame, contentOrigin: contentOrigin)
        }
        panel.contentView?.displayIfNeeded()
    }

    func hide() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}
