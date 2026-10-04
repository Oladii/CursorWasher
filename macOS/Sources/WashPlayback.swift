import Foundation
import CoreGraphics

/// Visual playback can outlive ownership of the hidden system cursor.
final class WashPlayback {
    enum State { case idle, washing, sinking }
    private(set) var state: State = .idle
    private var washing: WashAnimation?
    private var sinking: SinkAnimation?
    private var startedAt: TimeInterval = 0
    private var reduceMotion = false
    static let reducedDuration: TimeInterval = 0.8
    private let session: CursorSession
    private let imageBounds: CGRect
    var isRunning: Bool { state != .idle }
    var duration: TimeInterval {
        state == .sinking ? (sinking?.duration ?? 0) : (reduceMotion ? Self.reducedDuration : WashAnimation.duration)
    }

    init(session: CursorSession, imageBounds: CGRect) {
        self.session = session
        self.imageBounds = imageBounds
    }

    @discardableResult
    func begin(_ animation: WashAnimation, at time: TimeInterval, isActive: Bool, reduceMotion: Bool = false) -> Bool {
        guard !isRunning, session.begin(isActive: isActive) else { return false }
        washing = animation
        sinking = nil
        startedAt = time
        state = .washing
        self.reduceMotion = reduceMotion
        return true
    }

    func frame(at time: TimeInterval, cursor: CGPoint) -> WashAnimationFrame? {
        switch state {
        case .idle: return nil
        case .washing:
            guard reduceMotion else { return washing?.frame(at: time - startedAt, cursor: cursor) }
            let progress = min(1, max(0, (time - startedAt) / Self.reducedDuration))
            var frame = WashAnimationFrame(phase: .sparkle, phaseProgress: progress,
                position: cursor, appearance: .standard)
            // Keep the native arrow at the real pointer; only two small stars fade in/out.
            let opacity = CGFloat(sin(.pi * progress) * sin(.pi * progress))
            frame.sparkles = [
                WashSparkle(id: 0, position: CGPoint(x: cursor.x + imageBounds.maxX + 3, y: cursor.y + imageBounds.midY), radius: 2.5, opacity: opacity),
                WashSparkle(id: 1, position: CGPoint(x: cursor.x + imageBounds.minX - 3, y: cursor.y + imageBounds.minY + 2), radius: 2, opacity: opacity)
            ]
            return frame
        case .sinking: return sinking?.frame(at: time - startedAt)
        }
    }

    /// Repeated clicks during sinking are consumed without restarting the effect.
    @discardableResult
    func interrupt(at time: TimeInterval, cursor: CGPoint, reason: String) -> Bool {
        guard state == .washing, let animation = washing,
              let source = frame(at: time, cursor: cursor) else { return false }
        if reduceMotion { return stop(reason: reason) }
        let sink = SinkAnimation(source: source, shape: animation.shape, imageBounds: imageBounds)
        guard session.finish(reason: reason) else {
            washing = nil
            state = .idle
            return false
        }
        washing = nil
        sinking = sink
        startedAt = time
        state = .sinking
        return true
    }

    func isComplete(at time: TimeInterval) -> Bool {
        switch state {
        case .idle: return false
        case .washing: return time - startedAt >= duration
        case .sinking: return time - startedAt >= (sinking?.duration ?? 0)
        }
    }

    @discardableResult
    func stop(reason: String, retryRecovery: Bool = false) -> Bool {
        washing = nil
        sinking = nil
        state = .idle
        // System notifications may arrive in pairs or while recovery is pending.
        // Only the recovery policy or an explicit user retry may show again.
        guard session.phase != .recoveryRequired || retryRecovery else { return false }
        return session.finish(reason: reason)
    }
}
