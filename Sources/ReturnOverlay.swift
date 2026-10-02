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
            let path = NSBezierPath()
            path.move(to: CGPoint(x: bounds.minX, y: waterline))
            if let contact = drawing.immersion {
                path.line(to: CGPoint(x: contact.center.x - contact.halfWidth, y: waterline))
                for step in 0...48 {
                    let x = contact.center.x + contact.halfWidth * (CGFloat(step) / 24 - 1)
                    path.line(to: CGPoint(x: x, y: contact.lowerEdge(at: x)))
                }
            }
            path.line(to: CGPoint(x: bounds.maxX, y: waterline))
            path.line(to: CGPoint(x: bounds.maxX, y: max(bounds.maxY, waterline)))
            path.line(to: CGPoint(x: bounds.minX, y: max(bounds.maxY, waterline)))
            path.close()
            path.addClip()
        }
        let context = NSGraphicsContext.current!.cgContext
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        sprite.draw(at: drawing.position, appearance: drawing.appearance, shadowVisible: drawing.shadowVisible)
        if let contact = drawing.immersion {
            // Tint only the cursor pixels: a submerged, rounded lower face, not a hard stripe.
            context.setBlendMode(.sourceAtop)
            let colors = [CGColor(red: 0.25, green: 0.43, blue: 0.49, alpha: 0.48),
                          CGColor(red: 0.25, green: 0.43, blue: 0.49, alpha: 0)]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient,
                start: CGPoint(x: contact.center.x, y: contact.center.y - contact.depth),
                end: CGPoint(x: contact.center.x, y: contact.center.y + 2), options: [])
            context.setBlendMode(.normal)
        }
        if let line = drawing.waterline,
           let motion = drawing.waterImpulses.first(where: { $0.kind == .contact && $0.isActive }),
           let contact = drawing.immersion ?? sprite.shape.immersion(position: drawing.position,
                appearance: drawing.appearance, waterline: line, depth: 1.35) {
            // The water covers the entire lower face, through to its clipped edge.
            // A stroke alone leaves a black cursor sliver below the meniscus.
            context.setBlendMode(.sourceAtop)
            let fade = exp(-motion.age * 8) * pow(1 - motion.age / motion.duration, 2)
            context.setAlpha(CGFloat(min(1, motion.strength * fade)))
            let base = line - (drawing.immersion?.depth ?? 0)
            let phase = CGFloat(motion.rotation)
            for crest in [false, true] {
                let path = CGMutablePath()
                for step in 0...32 {
                    let t = CGFloat(step) / 32
                    let x = contact.center.x + (t * 2 - 1) * (contact.halfWidth + 1)
                    let y = base + 0.6 + sin(t * .pi) * 0.35
                        + sin(t * 5 + phase) * 0.25 + (crest ? 0.65 : 0.55)
                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                if crest {
                    context.setStrokeColor(CGColor(red: 0.77, green: 0.85, blue: 0.82, alpha: 0.42))
                    context.setLineWidth(0.4)
                    context.addPath(path)
                    context.strokePath()
                } else {
                    path.addLine(to: CGPoint(x: contact.center.x + contact.halfWidth + 1, y: base - 2))
                    path.addLine(to: CGPoint(x: contact.center.x - contact.halfWidth - 1, y: base - 2))
                    path.closeSubpath()
                    context.setFillColor(CGColor(red: 0.34, green: 0.51, blue: 0.54, alpha: 0.96))
                    context.addPath(path)
                    context.fillPath()
                }
            }
            context.setBlendMode(.normal)
        }
        context.endTransparencyLayer()
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
