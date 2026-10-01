import Foundation
import CoreGraphics

struct WidgetGesture {
    static let movementThreshold: CGFloat = 4
    private var start: CGPoint?
    private var startedOnBucket = false
    private var moved = false

    mutating func begin(at point: CGPoint, onBucket: Bool) {
        start = point
        startedOnBucket = onBucket
        moved = false
    }

    mutating func dragOffset(to point: CGPoint) -> CGPoint? {
        guard let start = start else { return nil }
        let offset = CGPoint(x: point.x - start.x, y: point.y - start.y)
        if hypot(offset.x, offset.y) >= Self.movementThreshold { moved = true }
        return startedOnBucket && moved ? offset : nil
    }

    mutating func end(at point: CGPoint, inside: Bool) -> Bool {
        guard start != nil else { return false }
        _ = dragOffset(to: point)
        let shouldWash = inside && !moved
        cancel()
        return shouldWash
    }

    mutating func cancel() {
        start = nil
        startedOnBucket = false
        moved = false
    }
}
