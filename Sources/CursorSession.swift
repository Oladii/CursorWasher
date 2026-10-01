import Foundation

protocol CursorDriver: AnyObject {
    func hide() -> Int32
    func show() -> Int32
}

/// Owns exactly one hide operation. All callers use the main thread.
final class CursorSession {
    enum Phase: String { case idle, washing, recoveryRequired }
    private(set) var phase: Phase = .idle
    private(set) var ownsHide = false
    private let driver: CursorDriver
    private let record: (String) -> Void

    init(driver: CursorDriver, record: @escaping (String) -> Void) {
        self.driver = driver
        self.record = record
    }

    @discardableResult
    func begin(isActive: Bool) -> Bool {
        guard phase == .idle, !ownsHide else {
            record("start_ignored: phase=\(phase.rawValue)")
            return false
        }
        guard isActive else {
            record("start_refused: application_inactive")
            return false
        }
        let result = driver.hide()
        if result == 0 {
            ownsHide = true
            phase = .washing
        }
        record("hide: result=\(result)")
        return result == 0
    }

    /// A failed show retains ownership so a later explicit recovery can retry.
    @discardableResult
    func finish(reason: String) -> Bool {
        guard ownsHide else { return true }
        let result = driver.show()
        if result == 0 {
            ownsHide = false
            phase = .idle
        } else {
            phase = .recoveryRequired
        }
        record("show: reason=\(reason) result=\(result)")
        return result == 0
    }
}

/// Scheduling stays in AppKit; this policy never acquires another hide operation.
final class CursorRecovery {
    static let delays: [TimeInterval] = [0.05, 0.15, 0.35, 0.75, 1.5]
    private let session: CursorSession
    private(set) var attempts = 0

    init(session: CursorSession) { self.session = session }

    var nextDelay: TimeInterval? {
        guard session.ownsHide, attempts < Self.delays.count else { return nil }
        return Self.delays[attempts]
    }

    @discardableResult
    func retry() -> Bool {
        guard session.ownsHide else { reset(); return true }
        guard nextDelay != nil else { return false }
        attempts += 1
        let restored = session.finish(reason: "automatic_recovery_\(attempts)")
        if restored { reset() }
        return restored
    }

    func reset() { attempts = 0 }
}
