import AppKit

struct CursorSprite {
    let image: NSImage
    let shadowlessImage: NSImage
    let geometry: CursorGeometry
    let visibleRect: CGRect
    let visibleTailRect: CGRect
    let visibleTailCenter: CGPoint
    let sourcePixelSize: CGSize
    let samples: [CursorSample]
    var shape: CursorShape { CursorShape(bounds: visibleRect, samples: samples) }
    var isValid: Bool {
        geometry.size.width > 0 && geometry.size.height > 0 &&
        geometry.hotSpot.x >= 0 && geometry.hotSpot.y >= 0 &&
        geometry.hotSpot.x <= geometry.size.width && geometry.hotSpot.y <= geometry.size.height
    }

    static let systemArrow: CursorSprite = {
        let cursor = NSCursor.arrow
        let original = cursor.image
        let geometry = CursorGeometry(size: original.size, hotSpot: cursor.hotSpot)
        // Resolve the highest-resolution system representation explicitly. NSImage's
        // automatic choice can ignore the animated drawing transform and use 1x.
        let bitmap = original.representations.compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        guard let bitmap = bitmap, let cgImage = bitmap.cgImage,
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            return CursorSprite(image: original, shadowlessImage: original, geometry: geometry,
                                visibleRect: geometry.imageRect(at: .zero),
                                visibleTailRect: geometry.imageRect(at: .zero), visibleTailCenter: .zero,
                                sourcePixelSize: .zero, samples: [])
        }
        let image = NSImage(cgImage: cgImage, size: original.size)
        let cleanBitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let darkHalo = color.alphaComponent < 0.99 &&
                max(color.redComponent, max(color.greenComponent, color.blueComponent)) < 0.5
            // The opaque body and translucent white antialiasing remain intact.
            cleanBitmap.setColor(darkHalo ? NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0) : color,
                                 atX: x, y: y)
        } }
        let shadowlessImage = NSImage(cgImage: cleanBitmap.cgImage!, size: original.size)
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        var samples: [CursorSample] = []
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                if x % 2 == 0 && y % 2 == 0 {
                    samples.append(CursorSample(point: CGPoint(
                        x: (CGFloat(x) + 0.5) * original.size.width / CGFloat(bitmap.pixelsWide) - geometry.hotSpot.x,
                        y: geometry.hotSpot.y - (CGFloat(y) + 0.5) * original.size.height / CGFloat(bitmap.pixelsHigh)),
                        weight: bitmap.colorAt(x: x, y: y)!.alphaComponent))
                }
            }
        }
        let sx = original.size.width / CGFloat(bitmap.pixelsWide)
        let sy = original.size.height / CGFloat(bitmap.pixelsHigh)
        let visible = maxX >= minX && maxY >= minY
            ? CGRect(x: CGFloat(minX) * sx - geometry.hotSpot.x,
                     y: original.size.height - CGFloat(maxY + 1) * sy - geometry.localHotSpot.y,
                     width: CGFloat(maxX - minX + 1) * sx, height: CGFloat(maxY - minY + 1) * sy)
            : geometry.imageRect(at: .zero)
        var tailMinX = bitmap.pixelsWide, tailMaxX = -1
        var tailWeight: CGFloat = 0
        var tailWeightedX: CGFloat = 0
        if maxY >= minY {
            let firstTailRow = minY + Int(CGFloat(maxY - minY + 1) * (1 - CursorGeometry.visibleTailFraction))
            for y in firstTailRow...maxY {
                for x in minX...maxX where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 {
                    tailMinX = min(tailMinX, x); tailMaxX = max(tailMaxX, x)
                    let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
                    tailWeight += alpha
                    tailWeightedX += (CGFloat(x) + 0.5) * alpha
                }
            }
        }
        let tail = tailMaxX >= tailMinX
            ? CGRect(x: CGFloat(tailMinX) * sx - geometry.hotSpot.x, y: visible.minY,
                     width: CGFloat(tailMaxX - tailMinX + 1) * sx,
                     height: visible.height * CursorGeometry.visibleTailFraction)
            : visible
        // A tiny corner at the waterline can widen the bounding box. Center the
        // visible pixels themselves so the main tail doesn't remain off-center.
        let tailCenter = CGPoint(x: tailWeight > 0 ? tailWeightedX / tailWeight * sx - geometry.hotSpot.x : tail.midX,
                                 y: tail.midY)
        return CursorSprite(image: image, shadowlessImage: shadowlessImage, geometry: geometry, visibleRect: visible, visibleTailRect: tail,
                            visibleTailCenter: tailCenter,
                            sourcePixelSize: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh), samples: samples)
    }()

    func draw(at position: CGPoint, appearance: CursorAppearance = .standard, opacity: CGFloat = 1,
              shadowVisible: Bool = true) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.concatenate(appearance.transform(around: position))
        NSGraphicsContext.current?.imageInterpolation = .high
        let context = NSGraphicsContext.current!.cgContext
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        (shadowVisible ? image : shadowlessImage).draw(in: geometry.imageRect(at: .zero), from: .zero,
                   operation: .sourceOver, fraction: opacity)
        context.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }
}
