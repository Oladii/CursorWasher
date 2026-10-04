import Foundation

struct WaterImpulse {
    var age: Double
    var strength: Double
    var x: Double = 0.5
    var y: Double = 0.5
    var kind: Kind = .dip
    var direction: Double = 0
    var rotation: Double = 0
    var width: Double = 0.06

    enum Kind { case dip, stir, wake, drop, contact }
    static let wakeDuration = 1.1
    var duration: Double {
        switch kind { case .dip: return 3.5; case .stir, .contact: return 0.35; case .wake: return Self.wakeDuration; case .drop: return 0.8 }
    }
    var isActive: Bool { age > 0 && age < duration && abs(strength) > 1e-6 }
}

/// Offsets are in the water's own plane. Every painted layer keeps its shape.
struct WaterLayerPose: Equatable {
    var x = 0.0
    var y = 0.0
    var opacity = 0.0
    var rotation = 0.0
}

struct WaterRipple {
    let x: Double
    let y: Double
    let radius: Double
    let opacity: Double
    let isDrop: Bool
}

enum WaterMotion {
    static func layers(impulses: [WaterImpulse]) -> [WaterLayerPose] {
        // The accumulated angle carries paint around the bucket continuously.
        // Different angular speeds let broad pigment patches pass one another.
        let travel = [0.20, 0.65, 1.20]
        let arrival = [1.15, 0.32, 0.0]
        let coverage = [0.48, 0.74, 0.90]
        var layers = [WaterLayerPose](repeating: WaterLayerPose(), count: travel.count)
        for impulse in impulses where impulse.isActive && (impulse.kind == .stir || impulse.kind == .wake) {
            let t = impulse.age / impulse.duration
            let attack = impulse.kind == .wake ? 1 - exp(-impulse.age * 40) : 1
            let gain = impulse.strength * attack * exp(-impulse.age * 5) * pow(1 - t, 2)
            for i in layers.indices {
                let depth = travel[i]
                layers[i].x += ((impulse.x - 0.5) * 0.72 + cos(impulse.direction) * 0.11) * gain * 0.35
                layers[i].y += ((impulse.y - 0.5) * 0.20 + sin(impulse.direction) * 0.055) * gain * 0.3
                layers[i].rotation += impulse.rotation * depth
                // Agitation spreads outward with accumulated circulation. It never
                // switches the entire painted surface on at the same moment.
                let phase = abs(impulse.rotation) + (impulse.kind == .wake ? impulse.age * 6 : 0)
                let onset = min(1, max(0, (phase - arrival[i]) / 0.75))
                let spread = onset * onset * (3 - 2 * onset)
                layers[i].opacity += (1 - exp(-abs(gain) * 5)) * coverage[i] * spread
            }
        }
        for i in layers.indices {
            layers[i].x = min(0.18, max(-0.18, layers[i].x))
            layers[i].y = min(0.07, max(-0.07, layers[i].y))
            layers[i].opacity = min(0.58, layers[i].opacity)
        }
        return layers
    }

    /// Independent rings expand and fade; no pixel of the underlying water moves.
    static func ripples(impulses: [WaterImpulse]) -> [WaterRipple] {
        var result: [WaterRipple] = []
        for impulse in impulses where impulse.isActive && (impulse.kind == .dip || impulse.kind == .drop) {
            let drop = impulse.kind == .drop
            for (index, delay) in (drop ? [0.0] : [0.0, 0.20]).enumerated() {
                let age = impulse.age - delay
                let life = drop ? impulse.duration : 1.15
                guard age > 0 && age < life else { continue }
                let radius = drop ? 0.025 + age * 0.30 : 0.04 + age * 0.92 + 0.20 * (1 - exp(-age * 12))
                let atEdge = min(1, max(0, (radius - 0.88) / 0.20))
                let edgeFade = 1 - atEdge * atEdge * (3 - 2 * atEdge)
                let envelope = drop ? (1 - exp(-age * 45)) * pow(1 - age / life, 2)
                    : (1 - exp(-age * 30)) * (1 - min(1, radius) * 0.35) * edgeFade
                let echo = index == 0 ? 1.0 : 0.28
                let opacity = min(0.8, abs(impulse.strength) * envelope * (drop ? 2.2 : 0.90) * echo)
                guard opacity > 0 else { continue }
                result.append(WaterRipple(x: impulse.x, y: impulse.y,
                    // Dip radius is progress toward the basin contour. The front
                    // keeps moving through the rim as its contrast fades out.
                    radius: radius, opacity: opacity,
                    isDrop: drop))
            }
        }
        return result
    }
}
