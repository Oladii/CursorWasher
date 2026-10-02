import Foundation
import CoreGraphics

enum BucketLayout {
    static let side: CGFloat = 192
    // The image is exactly half of the previous 256-point size; margins fit a native cursor.
    static let imageRect = CGRect(x: 32, y: 32, width: 128, height: 128)
    static let centerBounds = CGRect(x: 0, y: 0, width: side, height: side)
    // Measured against the supplied 1254-square image, with AppKit's Y pointing up.
    static let water = CGRect(x: 32 + 35, y: 32 + 78.5, width: 63, height: 15)
    // Integral bounds of the painted-water mask, shared with the layered water renderer.
    static let waterTextureRect = CGRect(x: 63, y: 109, width: 70, height: 17)
    static func waterCoordinates(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - waterTextureRect.minX) / waterTextureRect.width,
                y: (point.y - waterTextureRect.minY) / waterTextureRect.height)
    }
    static let washingCenterX = water.midX - 1
    static let stirringCenterY = waterTextureRect.midY - 1.5
    static let dropLandingY = stirringCenterY - 1
    static let landing = CGPoint(x: washingCenterX, y: water.midY + 1.5)

    static func washingPosition(at progress: Double) -> CGPoint {
        let t = min(1, max(0, progress))
        let eased = t * t * (3 - 2 * t)
        return CGPoint(x: washingCenterX + sin(eased * .pi * 8) * 9,
                       y: water.midY + cos(eased * .pi * 8) * 1.5)
    }

    /// Derivative with respect to normalized washing progress, shared with the water.
    static func washingVelocity(at progress: Double) -> CGPoint {
        let t = min(1, max(0, progress))
        let phase = t * t * (3 - 2 * t) * .pi * 8
        let rate = 6 * t * (1 - t) * .pi * 8
        return CGPoint(x: cos(phase) * rate * 9, y: -sin(phase) * rate * 1.5)
    }
}
