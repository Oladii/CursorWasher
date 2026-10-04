import Foundation
import CoreGraphics

struct CursorAppearance {
    static let standard = CursorAppearance(scale: 1, angle: 0)
    let scale: CGFloat
    let angle: CGFloat

    func transform(around position: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: position.x, y: position.y)
            .rotated(by: angle).scaledBy(x: scale, y: scale)
    }
}

struct CursorGeometry {
    static let visibleTailFraction: CGFloat = 0.2
    let size: CGSize
    /// AppKit cursor hotspots are measured from the image's top-left corner.
    let hotSpot: CGPoint

    func imageRect(at position: CGPoint) -> CGRect {
        CGRect(x: position.x - hotSpot.x,
               y: position.y - (size.height - hotSpot.y),
               width: size.width, height: size.height)
    }

    var localHotSpot: CGPoint { CGPoint(x: hotSpot.x, y: size.height - hotSpot.y) }

    func imageBounds(at position: CGPoint, appearance: CursorAppearance) -> CGRect {
        imageRect(at: .zero).applying(appearance.transform(around: position))
    }
}
