import AppKit

/// Small irregular blobs of watercolor. The round head leads; the soft tail trails.
enum PaintedWaterDrop {
    static func draw(at position: CGPoint, pose: WaterDropPose, opacity: CGFloat) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: position.x, y: position.y)
        context.rotate(by: pose.angle)
        let w = pose.width, h = pose.height
        let taper = pose.taper
        let skew = CGFloat(sin(Double(pose.variant) * 2.4)) * 0.045 * w
        let path = NSBezierPath()
        path.move(to: CGPoint(x: skew, y: h * 0.5))
        path.curve(to: CGPoint(x: -w * 0.5, y: -h * 0.03),
            controlPoint1: CGPoint(x: -w * (0.34 - taper * 0.2) + skew, y: h * 0.5),
            controlPoint2: CGPoint(x: -w * 0.51, y: h * 0.23))
        path.curve(to: CGPoint(x: -skew, y: -h * 0.5),
            controlPoint1: CGPoint(x: -w * 0.49, y: -h * 0.33),
            controlPoint2: CGPoint(x: -w * 0.28, y: -h * 0.5))
        path.curve(to: CGPoint(x: w * 0.49, y: -h * 0.01),
            controlPoint1: CGPoint(x: w * 0.3, y: -h * 0.5),
            controlPoint2: CGPoint(x: w * 0.51, y: -h * 0.3))
        path.curve(to: CGPoint(x: skew, y: h * 0.5),
            controlPoint1: CGPoint(x: w * 0.48, y: h * 0.24),
            controlPoint2: CGPoint(x: w * (0.3 - taper * 0.2) + skew, y: h * 0.5))
        path.close()
        NSColor(calibratedRed: 0.55, green: 0.68, blue: 0.69, alpha: opacity * 0.85).setFill()
        path.fill()
        NSColor(calibratedRed: 0.3, green: 0.43, blue: 0.45, alpha: opacity * 0.48).setStroke()
        path.lineWidth = 0.45
        path.stroke()
        let highlight = NSBezierPath()
        highlight.move(to: CGPoint(x: -w * 0.18, y: h * 0.13))
        highlight.curve(to: CGPoint(x: -w * 0.2, y: -h * 0.2),
            controlPoint1: CGPoint(x: -w * 0.33, y: h * 0.06),
            controlPoint2: CGPoint(x: -w * 0.34, y: -h * 0.1))
        NSColor(calibratedRed: 0.92, green: 0.93, blue: 0.85, alpha: opacity * 0.72).setStroke()
        highlight.lineWidth = 0.65
        highlight.lineCapStyle = .round
        highlight.stroke()
    }
}
