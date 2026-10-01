import Foundation
import CoreGraphics

enum SpringMotion {
    /// Unit step of a damped mass/spring; a small Hermite residual lands at rest exactly.
    static func progress(_ time: Double, dampingRatio: Double = 1, naturalFrequency: Double = 7,
                         initialVelocity: Double = 0) -> CGFloat {
        let t = min(1, max(0, time))
        guard t > 0 && t < 1 else { return CGFloat(t) }
        func response(_ x: Double) -> (position: Double, velocity: Double) {
            let w = naturalFrequency, z = dampingRatio
            if z >= 1 {
                let decay = exp(-w * x)
                return (1 - (1 + (w - initialVelocity) * x) * decay,
                        (initialVelocity + w * (w - initialVelocity) * x) * decay)
            }
            let wd = w * sqrt(1 - z * z), decay = exp(-z * w * x)
            return (1 - decay * (cos(wd * x) + (z * w - initialVelocity) / wd * sin(wd * x)),
                    decay * (initialVelocity * cos(wd * x) + (w * w - z * w * initialVelocity) / wd * sin(wd * x)))
        }
        let end = response(1)
        return CGFloat(response(t).position + (1 - end.position) * t * t * (3 - 2 * t)
                       + end.velocity * t * t * (1 - t))
    }
}

struct CursorSample {
    let point: CGPoint
    let weight: CGFloat
}

struct CursorShape {
    let bounds: CGRect
    let samples: [CursorSample]

    func dripOrigins(count: Int, appearance: CursorAppearance) -> [CGPoint] {
        let transform = appearance.transform(around: .zero)
        let points = samples.map { $0.point.applying(transform) }
        let rect = bounds.applying(transform)
        let left = points.map { $0.x }.min() ?? rect.minX
        let right = points.map { $0.x }.max() ?? rect.maxX
        return (0..<count).map { index in
            let x = left + (right - left) * CGFloat(index + 1) / CGFloat(count + 1)
            // Spread attachments across real opaque pixels at different heights.
            let distance = points.map { abs($0.x - x) }.min() ?? 0
            let column = points.filter { abs($0.x - x) <= distance + 1e-6 }
            let bottom = column.map { $0.y }.min() ?? rect.minY
            let top = column.map { $0.y }.max() ?? rect.maxY
            let heights: [CGFloat] = [0.2, 0.62, 0.4, 0.78]
            let y = bottom + (top - bottom) * heights[index % heights.count]
            return column.min { abs($0.y - y) < abs($1.y - y) } ?? CGPoint(x: x, y: y)
        }
    }

    func lowerEdge(appearance: CursorAppearance) -> CGPoint {
        let transform = appearance.transform(around: .zero)
        let points = samples.map { CursorSample(point: $0.point.applying(transform), weight: $0.weight) }
        let rect = bounds.applying(transform)
        let bottom = points.map { $0.point.y }.min() ?? rect.minY
        var weight: CGFloat = 0, x: CGFloat = 0
        for sample in points where sample.point.y <= bottom + 1 {
            weight += sample.weight
            x += sample.point.x * sample.weight
        }
        return CGPoint(x: weight > 0 ? x / weight : rect.midX, y: bottom)
    }

    func surfaceContact(position: CGPoint, appearance: CursorAppearance, waterline: CGFloat) -> CGPoint {
        let transform = appearance.transform(around: position)
        let points = samples.map { CursorSample(point: $0.point.applying(transform), weight: $0.weight) }
        let distance = points.map { abs($0.point.y - waterline) }.min() ?? 0
        let crossing = points.filter { abs($0.point.y - waterline) <= distance + 0.6 }
        let weight = crossing.reduce(CGFloat(0)) { $0 + $1.weight }
        let x = crossing.reduce(CGFloat(0)) { $0 + $1.point.x * $1.weight }
        return CGPoint(x: weight > 0 ? x / weight : position.x, y: waterline)
    }

    /// Keep the full shoulder span centered at every depth, including while masked.
    func submergedPosition(appearance: CursorAppearance, waterline: CGFloat, centerX: CGFloat,
                           verticalOffset: CGFloat = 0, depthFraction: CGFloat = 1) -> CGPoint {
        let transform = appearance.transform(around: .zero)
        let points = samples.map { CursorSample(point: $0.point.applying(transform), weight: $0.weight) }
        let transformedBounds = bounds.applying(transform)
        let minY = points.map { $0.point.y }.min() ?? transformedBounds.minY
        let maxY = points.map { $0.point.y }.max() ?? transformedBounds.maxY
        let surface = minY + (maxY - minY) * 0.8 * depthFraction - verticalOffset
        return CGPoint(x: centerX - transformedBounds.midX,
                       y: waterline - surface)
    }
}

enum WashPhase: String, CaseIterable {
    case approach, partialDip, dipLift, dive, wash, rise, shake, turn, sparkle, returning
    static let motionTimeScale = 0.75
    static let sparkleCycleDuration = 0.55 * motionTimeScale

    var duration: Double {
        switch self {
        case .approach: return 0.65 * Self.motionTimeScale
        case .partialDip: return 0.21
        case .dipLift: return 0.15
        case .dive: return 0.35 * Self.motionTimeScale
        case .wash: return 1.3 * Self.motionTimeScale
        case .rise: return 0.4 * Self.motionTimeScale
        case .shake: return 0.8 * Self.motionTimeScale
        case .sparkle: return Self.sparkleCycleDuration * 2
        case .turn: return 0.4 * Self.motionTimeScale
        case .returning: return 0.7 * 0.5
        }
    }

    var start: Double {
        WashPhase.allCases.prefix { $0 != self }.reduce(0) { $0 + $1.duration }
    }
}

/// Local +Y is the trailing end; the round leading end points along velocity.
struct WaterDropPose {
    let angle: CGFloat
    let width: CGFloat
    let height: CGFloat
    let taper: CGFloat
    let variant: Int

    static func moving(velocity: CGPoint, diameter: CGFloat, variant: Int) -> WaterDropPose {
        let speed = hypot(velocity.x, velocity.y)
        let stretch = 1 + min(1, speed / 700) * (0.7 - 0.12 * CGFloat(variant % 3))
        let taper: CGFloat = variant % 3 == 0 ? 0 : 0.3 * min(1, speed / 700)
        return WaterDropPose(angle: speed > 0.001 ? atan2(velocity.y, velocity.x) + .pi / 2 : 0,
            width: diameter / sqrt(stretch), height: diameter * sqrt(stretch), taper: taper, variant: variant)
    }
}

struct WashDrop {
    let id: Int
    var position: CGPoint
    let opacity: CGFloat
    var velocity: CGPoint = .zero
    var pose: WaterDropPose { .moving(velocity: velocity, diameter: 4.7 + CGFloat(id % 3) * 0.65, variant: id) }
    var bounds: CGRect {
        let radius = max(pose.width, pose.height) * 0.7 + 1
        return CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// Shared flight/contact data keeps the falling paint and surface response in sync.
struct DropFlight {
    let id: Int
    let emission: Double
    let lifetime: Double
    let origin: CGPoint
    let landing: CGPoint
    var contact: Double { emission + lifetime }

    func velocity(at time: Double) -> CGPoint {
        let u = CGFloat(min(1, max(0, (time - emission) / lifetime)))
        return CGPoint(x: (landing.x - origin.x) / lifetime,
                       y: (landing.y - origin.y) * (0.6 + 0.8 * u) / lifetime)
    }

    func position(at time: Double) -> CGPoint {
        let u = CGFloat(min(1, max(0, (time - emission) / lifetime)))
        return CGPoint(x: origin.x + (landing.x - origin.x) * u,
                       y: origin.y + (landing.y - origin.y) * (0.6 * u + 0.4 * u * u))
    }
}

struct SplashParticle {
    let id: Int
    let position: CGPoint
    let velocity: CGPoint
    let pose: WaterDropPose
    let opacity: CGFloat
    var angle: CGFloat { pose.angle }
    var width: CGFloat { pose.width }
    var height: CGFloat { pose.height }
}

enum PaintedSplash {
    static func particles(at progress: Double, origin: CGPoint = CGPoint(x: BucketLayout.washingCenterX, y: BucketLayout.water.minY)) -> [SplashParticle] {
        guard progress >= 0 && progress < 1 else { return [] }
        let seeds: [(delay: Double, rise: CGFloat, drift: CGFloat, diameter: CGFloat)] = [
            (0,    27, -29, 6.6),
            (0.05, 42,  18, 7.4),
            (0.02, 34, -11, 5.2),
            (0.09, 25,  34, 6.1),
            (0.03, 46, -21, 5.8),
            (0.07, 36,   8, 7.0)
        ]
        return seeds.enumerated().compactMap { id, seed in
            let gravity: CGFloat = 4000
            let initialVY = sqrt(2 * gravity * seed.rise)
            let lifetime = 2 * initialVY / gravity
            let elapsed = CGFloat((progress - seed.delay) * 0.42 * WashPhase.motionTimeScale)
            let u = elapsed / lifetime
            guard u >= 0 && u < 1 else { return nil }
            let velocity = CGPoint(x: seed.drift / lifetime, y: initialVY - gravity * elapsed)
            return SplashParticle(id: id,
                position: CGPoint(x: origin.x + seed.drift * u,
                                  y: origin.y + initialVY * elapsed - 0.5 * gravity * elapsed * elapsed),
                velocity: velocity,
                pose: .moving(velocity: velocity, diameter: seed.diameter, variant: id),
                opacity: min(1, u * 9) * pow(1 - u, 0.6))
        }
    }
}

struct WashSparkle {
    let id: Int
    var position: CGPoint
    let radius: CGFloat
    let opacity: CGFloat
    var bounds: CGRect {
        CGRect(x: position.x - radius - 1, y: position.y - radius - 1,
               width: (radius + 1) * 2, height: (radius + 1) * 2)
    }
}

struct WashAnimationFrame {
    let phase: WashPhase
    let phaseProgress: Double
    var position: CGPoint
    let appearance: CursorAppearance
    var waterline: CGFloat?
    var shadowVisible: Bool = true
    var drops: [WashDrop] = []
    var sparkles: [WashSparkle] = []
    var splash: Double?
    var splashOrigin: CGPoint?
    var waterImpulses: [WaterImpulse] = []

    func translated(by offset: CGPoint) -> WashAnimationFrame {
        var result = self
        result.position.x += offset.x
        result.position.y += offset.y
        result.waterline = waterline.map { $0 + offset.y }
        result.splashOrigin = splashOrigin.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        result.drops = drops.map {
            WashDrop(id: $0.id, position: CGPoint(x: $0.position.x + offset.x, y: $0.position.y + offset.y), opacity: $0.opacity, velocity: $0.velocity)
        }
        result.sparkles = sparkles.map {
            WashSparkle(id: $0.id, position: CGPoint(x: $0.position.x + offset.x, y: $0.position.y + offset.y),
                        radius: $0.radius, opacity: $0.opacity)
        }
        return result
    }
}

struct WashAnimation {
    static let duration = WashPhase.allCases.reduce(0) { $0 + $1.duration }
    static let partialDipDepthFraction: CGFloat = 0.75
    static let shakeAmplitude: CGFloat = 12
    // Release at the actual bottom reversal of each vertical shake, including its envelope.
    static let dropEmissionFractions: [Double] = [0.25, 0.75].map { start in
        var lower = start, upper = start + 0.25
        for _ in 0..<48 {
            let a = lower + (upper - lower) / 3
            let b = upper - (upper - lower) / 3
            if shakeOffset(a) < shakeOffset(b) { upper = b } else { lower = a }
        }
        return (lower + upper) / 2
    }
    static let dropLifetime = 0.18 * WashPhase.motionTimeScale
    static let dropCounts = [4, 2]
    static func lifetime(particle: Int) -> Double { dropLifetime * (1 - 0.08 * Double(particle % 3)) }
    let start: CGPoint
    let shape: CursorShape
    let water = BucketLayout.water
    private var dipImpactTimes: [Double] = []
    private var dipImpactPoints: [CGPoint] = []
    private struct WaterState {
        let velocity: CGPoint
        let strength: CGFloat
    }
    private static let waterStep = 1.0 / 240
    static let waterSettleDuration = 1.1
    private var waterStates: [WaterState] = []
    private var cachedDropFlights: [DropFlight] = []

    init(start: CGPoint, shape: CursorShape) {
        self.start = start
        self.shape = shape
        dipImpactTimes = [impactTime(for: .partialDip), impactTime(for: .dive)]
        dipImpactPoints = [impactPoint(for: .partialDip), impactPoint(for: .dive)]
        waterStates = makeWaterStates()
        cachedDropFlights = dropFlights
    }

    static func smooth(_ value: Double) -> CGFloat {
        let t = min(1, max(0, value))
        return CGFloat(t * t * (3 - 2 * t))
    }

    static func shakeOffset(_ t: Double) -> CGFloat {
        // Two full back-and-forth motions, with quiet endpoints.
        CGFloat(sin(4 * .pi * t) * pow(sin(.pi * t), 2))
    }

    static func washLift(at progress: Double) -> CGFloat { smooth(progress / 0.06) }

    private static func washLiftVelocity(at progress: Double) -> CGFloat {
        guard progress > 0 && progress < 0.06 else { return 0 }
        let t = progress / 0.06
        return CGFloat(6 * t * (1 - t) / 0.06)
    }

    static func turnOpticalOffset(angle: CGFloat) -> CGFloat {
        let fraction = min(1, max(0, angle / .pi))
        return -3 * pow(sin(.pi * fraction), 2)
    }

    var hoverCenter: CGPoint {
        let bounds = shape.bounds.applying(CursorAppearance(scale: 3, angle: .pi).transform(around: .zero))
        return CGPoint(x: BucketLayout.washingCenterX, y: water.maxY + 8 + bounds.height / 2)
    }

    func hoverPosition(angle: CGFloat = .pi) -> CGPoint {
        let bounds = shape.bounds.applying(CursorAppearance(scale: 3, angle: angle).transform(around: .zero))
        return CGPoint(x: hoverCenter.x - bounds.midX, y: hoverCenter.y - bounds.midY)
    }

    var partialDipPosition: CGPoint {
        shape.submergedPosition(appearance: CursorAppearance(scale: 3, angle: .pi),
            waterline: water.minY, centerX: BucketLayout.washingCenterX, depthFraction: Self.partialDipDepthFraction)
    }

    var interDipPosition: CGPoint { Self.mix(partialDipPosition, hoverPosition(), 0.5) }

    private var dipInitialVelocity: Double {
        let distance = max(0.001, hoverPosition().y - partialDipPosition.y)
        return min(1.5, 120 * WashPhase.partialDip.duration / Double(distance))
    }

    var dipEntryVelocity: CGFloat {
        -CGFloat(dipInitialVelocity) * (hoverPosition().y - partialDipPosition.y) / CGFloat(WashPhase.partialDip.duration)
    }

    func partialDipProgress(_ time: Double) -> CGFloat {
        Self.partialDipProgress(time, initialVelocity: dipInitialVelocity)
    }

    private static func partialDipProgress(_ time: Double, initialVelocity: Double) -> CGFloat {
        SpringMotion.progress(time, initialVelocity: initialVelocity)
    }

    var impactTime: Double { impactTime(for: .dive) }

    static func secondDiveProgress(_ time: Double) -> CGFloat {
        SpringMotion.progress(time, dampingRatio: 0.58, naturalFrequency: 7)
    }

    func impactTime(for phase: WashPhase) -> Double {
        precondition(phase == .partialDip || phase == .dive)
        if !dipImpactTimes.isEmpty { return dipImpactTimes[phase == .partialDip ? 0 : 1] }
        let appearance = CursorAppearance(scale: 3, angle: .pi)
        let departure = phase == .partialDip ? hoverPosition() : interDipPosition
        let submerged = shape.submergedPosition(appearance: appearance, waterline: water.minY,
            centerX: BucketLayout.washingCenterX, depthFraction: phase == .partialDip ? Self.partialDipDepthFraction : 1)
        let edge = shape.lowerEdge(appearance: appearance)
        let travel = max(0.001, departure.y - submerged.y)
        let contact = min(1, max(0, (departure.y + edge.y - water.minY) / travel))
        let initialVelocity = phase == .partialDip ? dipInitialVelocity : 0
        var low = 0.0, high = 1.0
        for _ in 0..<32 {
            let middle = (low + high) / 2
            let progress = phase == .dive ? Self.secondDiveProgress(middle)
                : Self.partialDipProgress(middle, initialVelocity: initialVelocity)
            if progress < contact { low = middle } else { high = middle }
        }
        return phase.start + (low + high) / 2 * phase.duration
    }

    func impactPoint(for phase: WashPhase) -> CGPoint {
        if !dipImpactPoints.isEmpty { return dipImpactPoints[phase == .partialDip ? 0 : 1] }
        let fraction = (impactTime(for: phase) - phase.start) / phase.duration
        let appearance = CursorAppearance(scale: 3, angle: .pi)
        let departure = phase == .partialDip ? hoverPosition() : interDipPosition
        let destination = phase == .partialDip ? partialDipPosition : shape.submergedPosition(
            appearance: appearance, waterline: water.minY, centerX: BucketLayout.washingCenterX)
        var position = Self.mix(departure, destination,
            phase == .partialDip ? SpringMotion.progress(fraction) : Self.secondDiveProgress(fraction))
        if phase == .partialDip { position.y = departure.y + (destination.y - departure.y) * partialDipProgress(fraction) }
        let body = shape.bounds.applying(appearance.transform(around: position))
        return CGPoint(x: body.midX, y: water.minY)
    }

    func frame(at elapsed: Double, cursor: CGPoint) -> WashAnimationFrame {
        let time = min(Self.duration, max(0, elapsed))
        let phase = WashPhase.allCases.first { time < $0.start + $0.duration } ?? .returning
        let t = min(1, max(0, (time - phase.start) / phase.duration))
        let eased = SpringMotion.progress(t)
        var point = hoverPosition()
        var appearance = CursorAppearance(scale: 3, angle: .pi)
        var waterline: CGFloat?
        var drops: [WashDrop] = []
        var sparkles: [WashSparkle] = []
        let submerged = shape.submergedPosition(appearance: appearance, waterline: water.minY, centerX: BucketLayout.washingCenterX)
        switch phase {
        case .approach:
            appearance = CursorAppearance(scale: 1 + 2 * eased, angle: .pi * eased)
            // One arc, with zero launch velocity and the dip's downward velocity
            // at arrival. Easing this path to rest would reintroduce the pause.
            let control = CGPoint(x: point.x,
                                  y: point.y - dipEntryVelocity * CGFloat(WashPhase.approach.duration) / 3)
            let travel = CGFloat(t), u = 1 - travel
            point = CGPoint(x: (u * u * u + 3 * u * u * travel) * start.x
                                + 3 * u * travel * travel * control.x + travel * travel * travel * point.x,
                            y: (u * u * u + 3 * u * u * travel) * start.y
                                + 3 * u * travel * travel * control.y + travel * travel * travel * point.y)
        case .partialDip, .dipLift:
            let partial = partialDipPosition
            point = phase == .partialDip ? Self.mix(point, partial, eased) : Self.mix(partial, interDipPosition, eased)
            if phase == .partialDip {
                point.y = hoverPosition().y + (partial.y - hoverPosition().y) * partialDipProgress(t)
            }
            waterline = water.minY
        case .dive:
            point = Self.mix(interDipPosition, submerged, Self.secondDiveProgress(t))
            waterline = water.minY
        case .wash:
            let motion = BucketLayout.washingPosition(at: t)
            point = shape.submergedPosition(appearance: appearance, waterline: water.minY,
                centerX: motion.x, verticalOffset: motion.y - BucketLayout.landing.y)
            point.y += Self.washLift(at: t)
            waterline = water.minY
        case .rise:
            point = Self.mix(CGPoint(x: submerged.x, y: submerged.y + 1), point, eased)
            waterline = water.minY
        case .shake:
            let offset = Self.shakeOffset(t)
            point.y += offset * Self.shakeAmplitude
        case .sparkle:
            appearance = CursorAppearance(scale: 3, angle: 0)
            point = hoverPosition(angle: 0)
            let body = shape.bounds.applying(appearance.transform(around: point))
            let cycleTime = (time - phase.start) / WashPhase.sparkleCycleDuration
            let secondWave = cycleTime >= 1
            let centers = secondWave
                ? [CGPoint(x: body.maxX + 7, y: body.maxY - 3),
                   CGPoint(x: body.minX - 9, y: body.midY + 1),
                   CGPoint(x: body.maxX + 6, y: body.minY + 7)]
                : [CGPoint(x: body.minX - 8, y: body.maxY - 7),
                           CGPoint(x: body.maxX + 8, y: body.midY + 3),
                           CGPoint(x: body.minX - 7, y: body.minY + 5)]
            let delays = secondWave ? [0.16, 0.0, 0.30] : [0.0, 0.16, 0.30]
            let lifetimes = secondWave ? [0.68, 0.65, 0.70] : [0.65, 0.68, 0.70]
            let radii: [CGFloat] = secondWave ? [5, 7, 4.5] : [7, 5, 6]
            let flashProgress = cycleTime - floor(cycleTime)
            for id in centers.indices {
                let u = (flashProgress - delays[id]) / lifetimes[id]
                guard u > 0 && u < 1 else { continue }
                let pulse = CGFloat(sin(.pi * u))
                sparkles.append(WashSparkle(id: id, position: centers[id],
                    radius: radii[id] * (0.35 + 0.65 * pulse), opacity: pulse))
            }
        case .turn:
            let turn = SpringMotion.progress(t, dampingRatio: 0.78, naturalFrequency: 8.5)
            appearance = CursorAppearance(scale: 3, angle: .pi * (1 - turn))
            point = hoverPosition(angle: appearance.angle)
            point.x += Self.turnOpticalOffset(angle: appearance.angle)
        case .returning:
            appearance = CursorAppearance(scale: 3 - 2 * eased, angle: 0)
            point = Self.mix(hoverPosition(angle: 0), cursor, eased)
            point.y += sin(.pi * eased) * 10
        }
        // Detached drops finish their fall independently, including across the phase boundary.
        let flights = dropFlights
        for flight in flights where time >= flight.emission && time < flight.contact {
            let remaining = CGFloat((flight.contact - time) / flight.lifetime)
            drops.append(WashDrop(id: flight.id, position: flight.position(at: time),
                                  opacity: min(1, remaining * 12), velocity: flight.velocity(at: time)))
        }
        var frame = WashAnimationFrame(phase: phase, phaseProgress: t, position: point,
                                       appearance: appearance, waterline: waterline, drops: drops, sparkles: sparkles)
        frame.shadowVisible = ![WashPhase.partialDip, .dipLift, .dive, .wash].contains(phase)
        let firstImpact = impactTime(for: .partialDip)
        let impacts = [firstImpact, impactTime]
        frame.waterImpulses = impacts.enumerated().compactMap { index, impact in
            guard time >= impact else { return nil }
            let uv = BucketLayout.waterCoordinates(impactPoint(for: index == 0 ? .partialDip : .dive))
            return WaterImpulse(age: time - impact, strength: index == 0 ? 0.75 : 1.15, x: uv.x, y: uv.y)
        }
        frame.waterImpulses += stirImpulses(at: time)
        frame.waterImpulses += flights.compactMap { flight in
            let age = time - flight.contact
            guard age >= 0 && age < 0.8 else { return nil }
            let uv = BucketLayout.waterCoordinates(flight.landing)
            return WaterImpulse(age: age, strength: 0.32, x: uv.x, y: uv.y, kind: .drop)
        }
        let splashDuration = 0.42 * WashPhase.motionTimeScale
        if let impact = impacts.last(where: { time >= $0 && time < $0 + splashDuration }) {
            frame.splash = (time - impact) / splashDuration
            frame.splashOrigin = impactPoint(for: impact == firstImpact ? .partialDip : .dive)
        }
        return frame
    }

    var dropFlights: [DropFlight] {
        if !cachedDropFlights.isEmpty { return cachedDropFlights }
        return Self.dropEmissionFractions.enumerated().flatMap { burst, fraction in
            let origins = shape.dripOrigins(count: Self.dropCounts[burst], appearance: CursorAppearance(scale: 3, angle: .pi))
            return origins.enumerated().map { particle, attachment in
                let origin = CGPoint(x: hoverPosition().x + attachment.x,
                    y: hoverPosition().y + attachment.y + Self.shakeOffset(fraction) * Self.shakeAmplitude)
                let drift = (CGFloat(particle) - CGFloat(origins.count - 1) / 2) * 2
                // Different depths on the painted surface, safely inside the rim.
                let landing = CGPoint(x: origin.x + drift,
                    y: BucketLayout.dropLandingY + CGFloat((particle + burst) % 3 - 1) * 0.75)
                return DropFlight(id: Self.dropCounts.prefix(burst).reduce(0, +) + particle,
                    emission: WashPhase.shake.start + fraction * WashPhase.shake.duration,
                    lifetime: Self.lifetime(particle: particle), origin: origin, landing: landing)
            }
        }
    }

    func stirImpulses(at time: Double) -> [WaterImpulse] {
        let elapsed = time - WashPhase.wash.start
        guard elapsed > 0, elapsed < WashPhase.wash.duration + Self.waterSettleDuration,
              waterStates.count > 1 else { return [] }
        let sample = elapsed / Self.waterStep
        let index = min(Int(sample), waterStates.count - 2)
        let fraction = CGFloat(sample - Double(index))
        let motion = BucketLayout.washingPosition(at: min(1, elapsed / WashPhase.wash.duration))
        let position = BucketLayout.waterCoordinates(CGPoint(x: motion.x,
            y: BucketLayout.stirringCenterY + motion.y - water.midY + Self.washLift(at: elapsed / WashPhase.wash.duration)))
        let velocity = Self.mix(waterStates[index].velocity, waterStates[index + 1].velocity, fraction)
        let strength = waterStates[index].strength + (waterStates[index + 1].strength - waterStates[index].strength) * fraction
        return [WaterImpulse(age: 1e-6, strength: strength, x: position.x, y: position.y,
                             kind: .stir, direction: atan2(velocity.y, velocity.x))]
    }

    private func makeWaterStates() -> [WaterState] {
        var velocity = CGPoint.zero
        var strength: CGFloat = 0
        var states = [WaterState(velocity: velocity, strength: strength)]
        let count = Int(ceil((WashPhase.wash.duration + Self.waterSettleDuration) / Self.waterStep))
        for index in 1...count {
            let time = Double(index) * Self.waterStep
            let progress = min(1, time / WashPhase.wash.duration)
            var cursorVelocity = BucketLayout.washingVelocity(at: progress)
            cursorVelocity.y += Self.washLiftVelocity(at: progress)
            let attack = Self.smooth(time / 0.12)
            let targetVelocity = time < WashPhase.wash.duration
                ? CGPoint(x: cursorVelocity.x / BucketLayout.waterTextureRect.width / WashPhase.wash.duration * attack,
                          y: cursorVelocity.y / BucketLayout.waterTextureRect.height / WashPhase.wash.duration * attack)
                : .zero
            // Water acquires momentum instead of copying every reversal instantly.
            // After the forcing stops, one coherent movement loses energy slowly.
            let release = Double(Self.smooth((time - WashPhase.wash.duration) / 0.08))
            let responseTime = 0.07 + 0.33 * release
            velocity = Self.mix(velocity, targetVelocity, CGFloat(1 - exp(-Self.waterStep / responseTime)))
            let targetStrength = time < WashPhase.wash.duration ? 0.6 * min(1, hypot(velocity.x, velocity.y) / 6) : 0
            strength += (targetStrength - strength) * CGFloat(1 - exp(-Self.waterStep / responseTime))
            let tail = (time - WashPhase.wash.duration) / Self.waterSettleDuration
            let settle = 1 - Self.smooth(tail)
            states.append(WaterState(
                velocity: CGPoint(x: velocity.x * settle, y: velocity.y * settle), strength: strength * settle))
        }
        return states
    }

    private static func mix(_ start: CGPoint, _ end: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }
}
