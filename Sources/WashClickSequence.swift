import Foundation

struct WashClickSequence {
    private var initialRelease: TimeInterval?

    mutating func begin(at timestamp: TimeInterval, clickCount: Int) {
        initialRelease = clickCount == 1 ? timestamp : nil
    }

    mutating func consumesDoubleClick(clickCount: Int, at timestamp: TimeInterval,
                                      insideWidget: Bool, interval: TimeInterval) -> Bool {
        defer { initialRelease = nil }
        guard let initialRelease = initialRelease else { return false }
        let elapsed = timestamp - initialRelease
        return insideWidget && clickCount == 2 && elapsed >= 0 && elapsed <= interval
    }

    mutating func cancel() { initialRelease = nil }
}
