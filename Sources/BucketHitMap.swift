import AppKit

/// Uses the original image alpha, not the rectangular image bounds, to choose dragging.
struct BucketHitMap {
    let bitmap: NSBitmapImageRep

    func contains(_ point: CGPoint, imageRect: CGRect) -> Bool {
        guard imageRect.contains(point), imageRect.width > 0, imageRect.height > 0 else { return false }
        let u = (point.x - imageRect.minX) / imageRect.width
        let v = (point.y - imageRect.minY) / imageRect.height
        let x = min(bitmap.pixelsWide - 1, max(0, Int(u * CGFloat(bitmap.pixelsWide))))
        let y = min(bitmap.pixelsHigh - 1, max(0, Int((1 - v) * CGFloat(bitmap.pixelsHigh))))
        return (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.1
    }
}
