import Foundation

struct WaterImpulse {
    var age: Double
    var strength: Double
    var x: Double = 0.5
    var y: Double = 0.5
    var kind: Kind = .dip
    var direction: Double = 0

    enum Kind { case dip, stir, wake, drop }
    static let wakeDuration = 1.1
    var duration: Double {
        switch kind { case .dip: return 3.5; case .stir: return 0.35; case .wake: return Self.wakeDuration; case .drop: return 0.8 }
    }
    var isActive: Bool { age > 0 && age < duration && abs(strength) > 1e-6 }
}

enum WaterMotion {
    /// A height field in the water's own plane, before perspective compression.
    /// Displacement and painted crests share this field, so color follows the wave.
    static func height(x: Double, y: Double, impulses: [WaterImpulse]) -> Double {
        let edgeRadius = hypot((x - 0.5) * 2, (y - 0.5) * 2)
        let edge = pow(max(0, 1 - edgeRadius * edgeRadius), 2)
        guard edge > 0 else { return 0 }
        var height = 0.0
        for impulse in impulses where impulse.isActive {
            let t = impulse.age
            let dx = (x - impulse.x) * 2, dy = (y - impulse.y) * 2
            if impulse.kind == .stir {
                let along = dx * cos(impulse.direction) + dy * sin(impulse.direction)
                let radius = hypot(dx, dy)
                let rim = exp(-pow((radius - 0.30) / 0.12, 2))
                let envelope = exp(-t * 8) * pow(1 - t / impulse.duration, 2)
                // A subdued bow wave around the body, with a quiet center.
                height += impulse.strength * envelope * 0.85 * along / max(0.001, radius) * rim * edge
                continue
            }
            if impulse.kind == .wake {
                // Leading ridge and trailing depression follow the cursor's velocity.
                // Only the weak detached wake advects; there is no independent spin.
                let q = t / impulse.duration
                let detached = impulse.kind == .wake
                let envelope = (detached ? 1 - exp(-t * 80) : exp(-t * 8)) * pow(1 - q, 2)
                let c = cos(impulse.direction), s = sin(impulse.direction)
                let drift = detached ? t * 0.3 : 0
                let flowX = dx - c * drift
                let flowY = dy - s * drift
                let along = flowX * c + flowY * s
                let across = -flowX * s + flowY * c
                let radius = hypot(along, across)
                height += impulse.strength * envelope * along * 6 * exp(-radius * radius / 0.6) * edge
                continue
            }
            if impulse.kind == .drop {
                let radius = hypot(dx, dy)
                let front = t * 1.3
                let envelope = (1 - exp(-t * 65)) * pow(1 - t / impulse.duration, 2)
                let crest = exp(-pow((radius - front) / 0.11, 2)) * cos((radius - front) * 20)
                let dent = exp(-(radius * radius) / 0.012) * exp(-t * 22)
                height += impulse.strength * envelope * (crest - dent) * edge
                continue
            }
            let angle = atan2(dy, dx)
            let radius = hypot(dx, dy) * (1 + 0.065 * sin(angle * 3 + 0.4) + 0.035 * cos(angle * 5))
            let attack = 1 - exp(-t * 28)
            let fade = exp(-t * 1.8) * min(1, max(0, (3.5 - t) / 0.5))
            let front = 0.12 + t * 1.7
            let outgoing = exp(-pow((radius - front) / 0.26, 2)) * sin(radius * 15 - t * 17)
            let reflected = 0.12 * min(1, max(0, (front - 0.7) / 0.3))
                * exp(-pow((radius - (1.9 - front)) / 0.32, 2)) * sin(radius * 12 + t * 14)
            let dent = -0.65 * exp(-radius * radius / 0.09) * exp(-t * 7)
            height += impulse.strength * attack * fade * (outgoing + reflected + dent) * edge
        }
        return min(1, max(-1, height))
    }

    /// A smooth stream function splits flow around the cursor and reunites it aft.
    /// Unlike a moving light patch, this advects the original painted texture in X and Y.
    static func flow(x: Double, y: Double, impulses: [WaterImpulse]) -> (x: Double, y: Double) {
        let edge = pow(max(0, 1 - pow((x - 0.5) * 2, 2) - pow((y - 0.5) * 2, 2)), 2)
        guard edge > 0 else { return (0, 0) }
        var vx = 0.0, vy = 0.0
        for impulse in impulses where impulse.isActive && impulse.kind == .stir {
            let dx = (x - impulse.x) * 2, dy = (y - impulse.y) * 2
            let c = cos(impulse.direction), s = sin(impulse.direction)
            let along = dx * c + dy * s, across = -dx * s + dy * c
            let radius2 = along * along + across * across
            let core2 = 0.24 * 0.24
            let core = exp(-radius2 / core2)
            let forward = 1 - core + 2 * across * across / core2 * core
            let sideways = -2 * along * across / core2 * core
            let age = impulse.age / impulse.duration
            let gain = impulse.strength * 0.55 * exp(-impulse.age * 8) * pow(1 - age, 2)
                * exp(-radius2 / 0.6) * edge
            vx += (forward * c - sideways * s) * gain
            vy += (forward * s + sideways * c) * gain
        }
        return (vx, vy)
    }
}


/// Translucent pigment, not specular lighting: retain the grain underneath.
/// Purely spatial brush variation cannot shimmer while the water is still.
enum WaterPigment {
    /// Broken pigment coverage rather than smooth normal-based metallic shading.
    /// Small droplet rings use rgba below unchanged.
    static func watercolor(height: Double, x: Double, y: Double) -> (Float, Float, Float, Float) {
        let radius2 = pow((x - 0.5) * 2, 2) + pow((y - 0.5) * 2, 2)
        let edge = min(1, max(0, (1 - radius2) * 5))
        let wash = sin(x * 39 + sin(y * 31) * 2) * cos(y * 43 - x * 13)
        let flecks = sin(x * 127 + sin(y * 89)) * sin(y * 103)
        let grain = min(1, max(0.12, 0.62 + wash * 0.28 + flecks * 0.22))
        let body = tanh(abs(height) * 6)
        let coverage = Float(body * edge * grain * (height >= 0 ? 0.20 : 0.32))
        let color: (Float, Float, Float) = height >= 0 ? (0.65, 0.74, 0.75) : (0.43, 0.56, 0.59)
        return (color.0 * coverage, color.1 * coverage, color.2 * coverage, coverage)
    }

    static func rgba(height: Double, slopeX: Double, slopeY: Double,
                     x: Double, y: Double) -> (Float, Float, Float, Float) {
        let radius2 = pow((x - 0.5) * 2, 2) + pow((y - 0.5) * 2, 2)
        let edge = min(1, max(0, (1 - radius2) * 4))
        let tone = tanh(height * 8 + slopeX * 0.35 - slopeY * 0.55)
        let grain = 0.84 + 0.16 * sin(x * 93 + sin(y * 67)) * sin(y * 71)
        let coverage = Float(abs(tone) * edge * grain * (tone > 0 ? 0.86 : 0.62))
        let color: (Float, Float, Float) = tone > 0 ? (0.91, 0.93, 0.86) : (0.25, 0.38, 0.43)
        // CIImage RGBAf pixels are premultiplied. Source-atop preserves water alpha.
        return (color.0 * coverage, color.1 * coverage, color.2 * coverage, coverage)
    }
}
