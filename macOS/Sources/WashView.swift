import AppKit
import OSLog

final class WashView: NSView {
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    var bucketImage: NSImage? { didSet {
        basin = bucketImage.map { BucketBasin(bucket: $0) }
        rebuildWaterSurface()
    } }
    var paintsWaterCrests = true
    var waterImage: NSImage? { didSet { rebuildWaterSurface() } }
    var waterHighlights: NSImage? { didSet { rebuildWaterSurface() } }
    var soapImage: NSImage? { didSet { needsDisplay = true } }
    // The soap is an independent decoration; the bucket's image rect never changes.
    // Crop the empty source canvas, retaining the authored soap/bubble silhouette.
    private static let soapSourceRect = CGRect(x: 108, y: 81, width: 454, height: 251)
    static let soapRect = CGRect(x: 46, y: 45, width: 42, height: 42 * 251 / 454)
    var waterDirtAmount: Double = 0 { didSet {
        waterDirtAmount = waterDirtAmount.isFinite ? min(Double(WaterAppearance.maximumLevel), max(0, waterDirtAmount)) : 0
        if oldValue != waterDirtAmount { needsDisplay = true }
    } }
    var waterDirtLevel: Int {
        get { Int(floor(waterDirtAmount)) }
        set { waterDirtAmount = Double(newValue) }
    }
    var foamFrame = FoamFrame() { didSet { needsDisplay = true } }
    private var modeTransition: ModeCrossfade?
    private var modeTransitionImage: CGImage?
    private var modeTransitionTimer: Timer?
    var isChangingMode: Bool { modeTransition != nil }

    /// Blend fixed captures, so switching modes cannot move the painted bucket
    /// or reset a partially completed fade when the user switches back.
    func setFoamMode(_ frame: FoamFrame, animated: Bool,
                     at time: TimeInterval? = nil,
                     rasterScale: CGFloat? = nil) {
        guard animated else {
            finishModeTransition()
            foamFrame = frame
            return
        }
        let scale = rasterScale ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let previous = modeTransition?.image(at: time ?? ProcessInfo.processInfo.systemUptime) ?? captureScene(scale: scale)
        finishModeTransition()
        foamFrame = frame
        guard let previous = previous, let target = captureScene(scale: scale) else { return }
        // Resource decoding/capturing is preparation, not part of the fade.
        let start = time ?? ProcessInfo.processInfo.systemUptime
        guard let transition = ModeCrossfade(from: previous, to: target, at: start) else { return }
        modeTransition = transition
        modeTransitionImage = transition.image(at: start)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.advanceModeTransition(at: ProcessInfo.processInfo.systemUptime)
        }
        modeTransitionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    func advanceModeTransition(at time: TimeInterval) {
        guard let transition = modeTransition else { return }
        if transition.isComplete(at: time) { finishModeTransition() }
        else { modeTransitionImage = transition.image(at: time); needsDisplay = true }
    }

    func finishModeTransition() {
        modeTransitionTimer?.invalidate()
        modeTransitionTimer = nil
        modeTransition = nil
        modeTransitionImage = nil
        needsDisplay = true
    }

    private func captureScene(scale: CGFloat) -> CGImage? {
        guard scale.isFinite, scale > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int((bounds.width * scale).rounded()),
                pixelsHigh: Int((bounds.height * scale).rounded()), bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphics
        graphics.cgContext.scaleBy(x: scale, y: scale)
        drawScene(bounds)
        graphics.flushGraphics()
        return bitmap.cgImage
    }

    deinit { modeTransitionTimer?.invalidate() }

    private func rebuildWaterSurface() {
        surfaces.removeAll()
        calmFrames.removeAll()
        mixedCalm = nil
        soapWaves.removeAll()
        if waterImage != nil && waterHighlights != nil && surface(at: waterDirtLevel) == nil {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CursorWasher", category: "water")
                .error("Water surface unavailable; drawing the original calm image")
        }
        needsDisplay = true
    }
    private var basin: BucketBasin?
    var bucketFrontPath: CGPath? { basin?.frontPath }
    private var surfaces: [Int: WaterSurface] = [:]
    private var calmFrames: [Int: CGImage] = [:]
    private var mixedCalm: (amount: Double, image: CGImage)?
    private var soapWaves: [Int: WaterSurface] = [:]
    private var soapTints: [Int: CGImage] = [:]
    private var mixedSoapTint: (amount: Double, image: CGImage)?
    private static let transparentSoap: NSImage = {
        let canvas = CGContext(data: nil, width: 1254, height: 1254, bitsPerComponent: 8,
            bytesPerRow: 1254 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return NSImage(cgImage: canvas.makeImage()!, size: CGSize(width: 1254, height: 1254))
    }()

    private func soapWave(at level: Int) -> WaterSurface? {
        if let cached = soapWaves[level] { return cached }
        guard let highlights = waterHighlights,
              let result = WaterSurface(image: Self.transparentSoap, highlights: highlights, dirtLevel: level) else { return nil }
        soapWaves[level] = result
        return result
    }

    private func soapTint(_ amount: Double, base: CGImage) -> CGImage {
        guard amount > 0 else { return base }
        if let cached = mixedSoapTint, cached.amount == amount { return cached.image }
        let lower = Int(floor(amount)), upper = Int(ceil(amount))
        for level in Set([lower, upper]) where soapTints[level] == nil {
            soapTints[level] = level == 0 ? base : WaterAppearance.tint(base, level: level)
        }
        guard let a = soapTints[lower], let b = soapTints[upper] else { return base }
        let image = lower == upper ? a : WaterAppearance.mix(a, b, progress: CGFloat(amount - Double(lower)))
        mixedSoapTint = (amount, image)
        return image
    }

    private func drawSoapWater(base: CGImage, in context: CGContext) {
        guard let basin = basin else { return }
        context.saveGState()
        context.addPath(basin.waterPath)
        context.clip()
        basin.clipOpening(in: context, protectingInk: true)
        // Preserve the approved Figma water's own alpha rather than blending
        // the canonical bucket's water underneath its translucent painting.
        context.setBlendMode(.copy)
        context.draw(base, in: BucketLayout.imageRect)
        context.setBlendMode(.normal)
        if waterDirtAmount > 0 {
            context.draw(soapTint(waterDirtAmount, base: base), in: BucketLayout.imageRect)
        }
        context.restoreGState()
        let lower = Int(floor(waterDirtAmount)), upper = Int(ceil(waterDirtAmount))
        guard let low = soapWave(at: lower) else { return }
        let impulses = animationFrame?.waterImpulses ?? []
        let first = low.frame(impulses: impulses, paintCrests: paintsWaterCrests)
        let image: CGImage
        if lower != upper, let high = soapWave(at: upper) {
            image = WaterAppearance.mix(first, high.frame(impulses: impulses, paintCrests: paintsWaterCrests),
                progress: CGFloat(waterDirtAmount - Double(lower)))
        } else { image = first }
        context.saveGState()
        context.addPath(basin.waterPath)
        context.clip()
        basin.clipOpening(in: context, protectingInk: true)
        context.draw(image, in: BucketLayout.waterTextureRect)
        context.restoreGState()
    }

    private func surface(at level: Int) -> WaterSurface? {
        if let cached = surfaces[level] { return cached }
        guard let source = waterImage ?? bucketImage, let highlights = waterHighlights,
              let surface = WaterSurface(image: source, highlights: highlights, dirtLevel: level) else { return nil }
        surfaces[level] = surface
        calmFrames[level] = surface.frame(impulses: [])
        return surface
    }

    private func drawWater(in context: CGContext) {
        let lower = Int(floor(waterDirtAmount)), upper = Int(ceil(waterDirtAmount))
        guard let low = surface(at: lower), let lowCalm = calmFrames[lower] else { return }
        let impulses = animationFrame?.waterImpulses ?? []
        let first = low.frame(impulses: impulses, paintCrests: paintsWaterCrests)
        let image: CGImage, baseline: CGImage
        if lower != upper, let high = surface(at: upper), let highCalm = calmFrames[upper] {
            let progress = CGFloat(waterDirtAmount - Double(lower))
            if let cached = mixedCalm, cached.amount == waterDirtAmount {
                baseline = cached.image
            } else {
                baseline = WaterAppearance.mix(lowCalm, highCalm, progress: progress)
                mixedCalm = (waterDirtAmount, baseline)
            }
            let second = high.frame(impulses: impulses, paintCrests: paintsWaterCrests)
            image = first === lowCalm && second === highCalm ? baseline
                : WaterAppearance.mix(first, second, progress: progress)
        } else {
            image = first
            baseline = lowCalm
        }
        if let basin = basin {
            basin.drawWater(image, baseline: baseline, in: context)
        } else {
            context.saveGState()
            WaterSurface.path.addClip()
            context.draw(image, in: BucketLayout.waterTextureRect)
            context.restoreGState()
        }
    }
    var bucketHitMap: BucketHitMap?
    var onWash: ((CGPoint, NSEvent) -> Void)?
    var onAccessibleWash: (() -> Bool)?
    var onDrag: (() -> Bool)?
    var animationFrame: WashAnimationFrame? { didSet { needsDisplay = true } }
    var onContextMenu: (() -> Bool)?
    var recovery = false { didSet { needsDisplay = true } }
    let cursorSprite = CursorSprite.systemArrow
    private var gesture = WidgetGesture()
    private var dragWindowOrigin: CGPoint?
    private var dragging = false

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Wash Cursor" }
    override func accessibilityHelp() -> String? { "Wash the cursor in the bucket. Drag the bucket to move it." }
    override func accessibilityPerformPress() -> Bool { onAccessibleWash?() ?? false }

    override func mouseDown(with event: NSEvent) {
        cancelInteraction()
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), let window = window else { return }
        dragWindowOrigin = window.frame.origin
        gesture.begin(at: window.convertPoint(toScreen: event.locationInWindow),
                      onBucket: bucketHitMap?.contains(point, imageRect: BucketLayout.imageRect) == true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window, let origin = dragWindowOrigin,
              let offset = gesture.dragOffset(to: window.convertPoint(toScreen: event.locationInWindow)) else { return }
        if !dragging {
            guard onDrag?() == true else { cancelInteraction(); return }
            dragging = true
        }
        window.setFrameOrigin(CGPoint(x: origin.x + offset.x, y: origin.y + offset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let window = window else { cancelInteraction(); return }
        let point = convert(event.locationInWindow, from: nil)
        let shouldWash = gesture.end(at: window.convertPoint(toScreen: event.locationInWindow),
                                     inside: bounds.contains(point))
        cancelInteraction()
        if shouldWash { onWash?(point, event) }
    }

    func cancelInteraction() {
        gesture.cancel()
        dragWindowOrigin = nil
        dragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelInteraction()
        guard onContextMenu?() == true, let menu = menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if let image = modeTransitionImage, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.clear(dirtyRect)
            context.interpolationQuality = .none
            context.draw(image, in: bounds)
            context.restoreGState()
            return
        }
        drawScene(dirtyRect)
    }

    private func drawScene(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        let soapBase = foamFrame.clusters.isEmpty ? nil : FoamSurface.baseImage
        bucketImage?.draw(in: BucketLayout.imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        if let context = NSGraphicsContext.current?.cgContext {
            if let base = soapBase {
                FoamSurface.prefetch(foamFrame, foregroundAt: animationFrame?.waterline)
                drawSoapWater(base: base, in: context)
                basin?.drawFront(in: context)
                if let frame = animationFrame, let splash = frame.splash {
                    context.saveGState()
                    basin?.clipOpening(in: context, protectingInk: true)
                    drawSplash(progress: splash, origin: frame.splashOrigin ?? BucketLayout.landing)
                    context.restoreGState()
                }
                FoamSurface.draw(foamFrame, in: context)
            } else {
                drawWater(in: context)
                basin?.drawFront(in: context)
            }
            if !foamFrame.clusters.isEmpty, let soapImage = soapImage {
                context.saveGState()
                context.clip(to: Self.soapRect)
                soapImage.draw(in: Self.soapRect, from: Self.soapSourceRect, operation: .sourceOver, fraction: 1)
                context.restoreGState()
            }
        }
        if recovery {
            NSColor.systemRed.setFill()
            NSRect(x: BucketLayout.landing.x - 8, y: BucketLayout.landing.y - 8, width: 16, height: 16).fill()
            return
        }
        // The transformed cursor uses a passive window throughout the animation.
        guard let frame = animationFrame else { return }
        if soapBase == nil, let splash = frame.splash { drawSplash(progress: splash, origin: frame.splashOrigin ?? CGPoint(x: BucketLayout.water.midX, y: BucketLayout.water.minY)) }
    }

    private func drawSplash(progress: Double, origin: CGPoint) {
        for drop in PaintedSplash.particles(at: progress, origin: origin) {
            PaintedWaterDrop.draw(at: drop.position, pose: drop.pose, opacity: drop.opacity)
        }
    }
}
