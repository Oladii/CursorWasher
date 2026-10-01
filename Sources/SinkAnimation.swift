import Foundation
import CoreGraphics

/// An interrupted wash sinks below the water; its visible tail triggers a painted splash.
struct SinkAnimation {
    static let splashDuration = 0.42 * WashPhase.motionTimeScale
    let source: WashAnimationFrame
    let transitDuration: Double
    let submergeDuration: Double = 0.32
    let entry: CGPoint
    let destination: CGPoint
    let impactAt: Double
    let impactPoint: CGPoint
    var submergedAt: Double { transitDuration + submergeDuration }
    var duration: Double { max(submergedAt, impactAt + Self.splashDuration) }

    init(source: WashAnimationFrame, shape: CursorShape, imageBounds: CGRect) {
        self.source = source
        let transform = source.appearance.transform(around: .zero)
        let body = shape.bounds.applying(transform)
        let image = imageBounds.applying(transform)
        let water = BucketLayout.water
        let bodyOnScreen = body.offsetBy(dx: source.position.x, dy: source.position.y)
        // A cursor already masked by water can sink directly. A cursor returning
        // elsewhere first passes over the rim, so it cannot vanish outside the bucket.
        let overWater = bodyOnScreen.midX >= water.minX && bodyOnScreen.midX <= water.maxX
        let direct = source.waterline != nil || (overWater && bodyOnScreen.minY >= water.minY)
        transitDuration = direct ? 0 : 0.22
        entry = direct ? source.position : CGPoint(x: BucketLayout.washingCenterX - body.midX,
                                                   y: water.minY + 3 - image.minY)
        // Include transparent padding and shadows, not just the opaque samples.
        destination = CGPoint(x: BucketLayout.washingCenterX - body.midX, y: water.minY - image.maxY - 2)
        let visibleTop = shape.samples.map { $0.point.applying(transform).y }.max() ?? body.maxY
        let travel = max(0.001, entry.y - destination.y)
        let contact = min(1, max(0, (entry.y + visibleTop - water.minY) / travel))
        var lower = 0.0, upper = 1.0
        for _ in 0..<32 {
            let middle = (lower + upper) / 2
            if SpringMotion.progress(middle) < contact { lower = middle } else { upper = middle }
        }
        impactAt = transitDuration + (contact == 0 ? 0 : (lower + upper) / 2 * submergeDuration)
        let progress = SpringMotion.progress((impactAt - transitDuration) / submergeDuration)
        let position = CGPoint(x: entry.x + (destination.x - entry.x) * progress,
                               y: entry.y + (destination.y - entry.y) * progress)
        impactPoint = shape.surfaceContact(position: position, appearance: source.appearance, waterline: water.minY)
    }

    func frame(at elapsed: Double) -> WashAnimationFrame {
        let time = min(duration, max(0, elapsed))
        var point: CGPoint
        var waterline: CGFloat?
        if time < transitDuration {
            let t = SpringMotion.progress(time / transitDuration)
            let u = 1 - t
            let control = CGPoint(x: (source.position.x + entry.x) / 2,
                                  y: max(source.position.y, entry.y) + 20)
            point = CGPoint(x: u * u * source.position.x + 2 * u * t * control.x + t * t * entry.x,
                            y: u * u * source.position.y + 2 * u * t * control.y + t * t * entry.y)
            waterline = source.waterline
        } else {
            let t = SpringMotion.progress((time - transitDuration) / submergeDuration)
            point = CGPoint(x: entry.x + (destination.x - entry.x) * t,
                            y: entry.y + (destination.y - entry.y) * t)
            waterline = BucketLayout.water.minY
        }
        var frame = WashAnimationFrame(phase: .dive, phaseProgress: time / duration,
                                      position: point, appearance: source.appearance, waterline: waterline)
        frame.shadowVisible = false
        frame.waterImpulses = source.waterImpulses.map {
            var impulse = $0
            impulse.age += time
            return impulse
        }
        if time >= impactAt {
            let uv = BucketLayout.waterCoordinates(impactPoint)
            frame.waterImpulses.append(WaterImpulse(age: time - impactAt, strength: 1.2, x: uv.x, y: uv.y))
        }
        // The short cancellation effect settles before its frame is cleared.
        let settle = 1 - Double(SpringMotion.progress((time - impactAt) / max(0.001, duration - impactAt)))
        frame.waterImpulses = frame.waterImpulses.map {
            var impulse = $0
            impulse.strength *= settle
            return impulse
        }
        if time >= impactAt && time < impactAt + Self.splashDuration {
            frame.splash = (time - impactAt) / Self.splashDuration
            frame.splashOrigin = impactPoint
        }
        return frame
    }
}
