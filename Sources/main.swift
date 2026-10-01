import AppKit
import CoreGraphics
import OSLog

final class SystemCursor: CursorDriver {
    func hide() -> Int32 { CGDisplayHideCursor(CGMainDisplayID()).rawValue }
    func show() -> Int32 { CGDisplayShowCursor(CGMainDisplayID()).rawValue }
}

final class WidgetWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class WidgetDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var window: WidgetWindow!
    private let square = WashView(frame: NSRect(x: 0, y: 0, width: BucketLayout.side, height: BucketLayout.side))
    private var animationTimer: Timer?
    private var recoveryTimer: Timer?
    private var recoveryAlert: NSAlert?
    private var pendingTermination = false
    private var escapeMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var observations: [NSObjectProtocol] = []
    private var pendingStart = false
    private var washClickSequence = WashClickSequence()
    private var animation: WashAnimation?
    private var widgetLayer: WidgetLayer = .front
    private var statusItem: NSStatusItem?
    private enum MenuTag: Int { case visibility = 1, front, back }
    private let returnOverlay = ReturnOverlay()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CursorWasher", category: "widget")
    private lazy var session = CursorSession(driver: SystemCursor()) { [weak self] in self?.record($0) }
    private lazy var cursorRecovery = CursorRecovery(session: session)
    private lazy var playback = WashPlayback(session: session,
                                            imageBounds: square.cursorSprite.geometry.imageRect(at: .zero))

    func applicationDidFinishLaunching(_ notification: Notification) {
        previousApp = NSWorkspace.shared.frontmostApplication
        if previousApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier { previousApp = nil }
        setupMenu()
        setupWindow()
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let other = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  other.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.previousApp = other
        })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.finish(reason: "sleep") })
        observations.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.finish(reason: "screens_changed")
            self?.keepWindowOnScreen()
        })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.finish(reason: "accessibility_changed") })
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(reason: "escape", retryRecovery: true); return nil }
            return event
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, self.playback.isRunning else { return event }
            // Keep the status menu usable on the first click while washing.
            if let statusWindow = self.statusItem?.button?.window, event.window === statusWindow {
                self.finish(reason: "status_menu_click")
                return event
            }
            let point = self.square.convert(event.locationInWindow, from: nil)
            let insideWidget = event.window === self.window && self.square.bounds.contains(point)
            if self.washClickSequence.consumesDoubleClick(clickCount: event.clickCount,
                                                         at: event.timestamp,
                                                         insideWidget: insideWidget,
                                                         interval: NSEvent.doubleClickInterval) {
                self.square.cancelInteraction()
                self.record("double_click_continues_wash")
                return nil
            }
            self.sinkCursor(reason: "repeat_click_local")
            // Do not begin a drag or a new wash with this same press/release.
            return nil
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.sinkCursor(reason: "repeat_click_global")
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        record("launch: version=\(version) build=\(build) duration=\(WashAnimation.duration), macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        window.orderFrontRegardless()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard window != nil else { return true }
        bringToFront()
        return false
    }

    private func setupMenu() {
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = StatusBarIcon.make()
        status.button?.imageScaling = .scaleProportionallyDown
        status.button?.toolTip = "CursorWasher"
        status.menu = makeWidgetMenu(context: false)
        statusItem = status
    }

    private func makeWidgetMenu(context: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        func add(_ title: String, _ action: Selector, tag: MenuTag? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag?.rawValue ?? 0
            item.image = nil
            menu.addItem(item)
        }
        if !context {
            add("Hide Bucket", #selector(toggleWidgetVisibility), tag: .visibility)
            menu.addItem(.separator())
        }
        add("Bring to Front", #selector(bringToFront), tag: .front)
        add("Send to Back", #selector(sendToBack), tag: .back)
        menu.addItem(.separator())
        if context {
            add("Hide Bucket", #selector(hideWidget), tag: .visibility)
        } else {
            let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            quit.target = NSApp
            quit.image = nil
            menu.addItem(quit)
        }
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard window != nil else { return }
        if let visibility = menu.item(withTag: MenuTag.visibility.rawValue) {
            visibility.title = visibility.action == #selector(hideWidget) || window.isVisible ? "Hide Bucket" : "Show Bucket"
        }
        menu.item(withTag: MenuTag.front.rawValue)?.state = widgetLayer == .front ? .on : .off
        menu.item(withTag: MenuTag.back.rawValue)?.state = widgetLayer == .back ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        finish(reason: "menu", retryRecovery: true)
        menuNeedsUpdate(menu)
    }

    private func setupWindow() {
        window = WidgetWindow(contentRect: NSRect(x: 0, y: 0, width: BucketLayout.side, height: BucketLayout.side),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Cursor Wash — ведро"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.level = widgetLayer.level
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("CursorWasherBucket") { window.center() }
        window.setFrameAutosaveName("CursorWasherBucket")
        if let saved = UserDefaults.standard.string(forKey: "bucketLayer"),
           let layer = WidgetLayer(rawValue: saved) { widgetLayer = layer }
        window.level = widgetLayer.level
        keepWindowOnScreen()
        window.delegate = self
        window.onEscape = { [weak self] in self?.finish(reason: "escape", retryRecovery: true) }
        let content = TransparentContentView(frame: NSRect(x: 0, y: 0, width: BucketLayout.side, height: BucketLayout.side))
        window.contentView = content
        guard let imageURL = Bundle.main.url(forResource: "bucket", withExtension: "png"),
              let imageData = try? Data(contentsOf: imageURL),
              let image = NSImage(data: imageData),
              let bitmap = NSBitmapImageRep(data: imageData),
              let waterURL = Bundle.main.url(forResource: "water-calm-source", withExtension: "png"),
              let waterImage = NSImage(contentsOf: waterURL) else {
            let alert = NSAlert()
            alert.messageText = "Couldn't load CursorWasher"
            alert.informativeText = "An image is missing or damaged. Please reinstall the app."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        square.bucketImage = image
        square.waterImage = waterImage
        square.bucketHitMap = BucketHitMap(bitmap: bitmap)
        square.onWash = { [weak self] point, event in self?.startWash(at: point, event: event) }
        square.onAccessibleWash = { [weak self] in
            guard let self = self, !self.playback.isRunning, !self.pendingStart else { return false }
            self.startWash(at: self.currentCursorPosition(), timestamp: ProcessInfo.processInfo.systemUptime, clickCount: 1)
            return true
        }
        square.onDrag = { [weak self] in
            guard let self = self else { return false }
            self.finish(reason: "drag", retryRecovery: true)
            return !self.session.ownsHide
        }
        content.addSubview(square)
        square.menu = makeWidgetMenu(context: true)
        square.onContextMenu = { [weak self] in
            guard let self = self else { return false }
            self.finish(reason: "context_menu", retryRecovery: true)
            return !self.session.ownsHide
        }
    }

    private func startWash(at point: CGPoint, event: NSEvent) {
        startWash(at: point, timestamp: event.timestamp, clickCount: event.clickCount)
    }

    private func startWash(at point: CGPoint, timestamp: TimeInterval, clickCount: Int) {
        if session.phase == .recoveryRequired { finish(reason: "manual_recovery", retryRecovery: true); return }
        guard session.phase == .idle, !playback.isRunning, !pendingStart else { return }
        washClickSequence.begin(at: timestamp, clickCount: clickCount)
        animation = WashAnimation(start: point, shape: square.cursorSprite.shape)
        pendingStart = true
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        // Wait until AppKit has completed activation, including clicks from another app.
        DispatchQueue.main.async { [weak self] in self?.beginWhenActive() }
    }

    private func beginWhenActive() {
        guard pendingStart, NSApp.isActive else { return }
        pendingStart = false
        guard square.cursorSprite.isValid else {
            record("start_refused: cursor_image_unavailable")
            return
        }
        guard let animation = animation,
              playback.begin(animation, at: ProcessInfo.processInfo.systemUptime, isActive: NSApp.isActive,
                             reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else {
            return
        }
        self.animation = nil
        square.recovery = false
        square.animationFrame = nil
        record("washing_started: duration=\(playback.duration)")
        animationTimer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.animate() }
        RunLoop.main.add(animationTimer!, forMode: .common)
        animate()
    }

    private func animate() {
        let now = ProcessInfo.processInfo.systemUptime
        // Read the real pointer on every frame, including when it is outside the widget.
        guard let frame = playback.frame(at: now, cursor: currentCursorPosition()) else { return }
        square.animationFrame = frame
        square.displayIfNeeded()
        let origin = window.convertPoint(toScreen: square.convert(.zero, to: nil))
        returnOverlay.show(frame.translated(by: origin), layer: widgetLayer,
                           staysVisibleWhenInactive: playback.state == .sinking)
        if playback.isComplete(at: now) {
            let sunk = playback.state == .sinking
            finish(reason: sunk ? "sunk" : "completed", restoreFocus: !sunk)
        }
    }

    private func currentCursorPosition() -> CGPoint {
        square.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    private func sinkCursor(reason: String) {
        guard playback.isRunning else { return }
        washClickSequence.cancel()
        square.cancelInteraction()
        if playback.interrupt(at: ProcessInfo.processInfo.systemUptime,
                              cursor: currentCursorPosition(), reason: reason) {
            record(playback.state == .sinking ? "sinking_started: reason=\(reason)" : "washing_cancelled: reason=\(reason)")
        }
        guard playback.isRunning else { finish(reason: "sink_recovery"); return }
        animate()
    }

    @objc private func bringToFront() {
        finish(reason: "layer_front", retryRecovery: true)
        guard !session.ownsHide else { return }
        widgetLayer = .front
        UserDefaults.standard.set(widgetLayer.rawValue, forKey: "bucketLayer")
        window.level = widgetLayer.level
        window.orderFrontRegardless()
    }

    @objc private func sendToBack() {
        finish(reason: "layer_back", retryRecovery: true)
        guard !session.ownsHide else { return }
        widgetLayer = .back
        UserDefaults.standard.set(widgetLayer.rawValue, forKey: "bucketLayer")
        window.level = widgetLayer.level
        window.orderBack(nil)
    }

    @objc private func toggleWidgetVisibility() {
        if window.isVisible { hideWidget() }
        else { window.orderFrontRegardless() }
    }

    @objc private func hideWidget() {
        finish(reason: "widget_hidden", retryRecovery: true)
        guard !session.ownsHide else { return }
        window.orderOut(nil)
    }

    private func finish(reason: String, restoreFocus: Bool = false, retryRecovery: Bool = false) {
        // A drag cancels the animation while preserving its own mouse tracking.
        if reason != "drag" { square.cancelInteraction() }
        pendingStart = false
        washClickSequence.cancel()
        returnOverlay.hide()
        animation = nil
        animationTimer?.invalidate()
        animationTimer = nil
        let target = previousApp
        if retryRecovery && session.phase == .recoveryRequired {
            recoveryTimer?.invalidate()
            recoveryTimer = nil
            cursorRecovery.reset()
            if let alert = recoveryAlert {
                window.endSheet(alert.window, returnCode: .abort)
                recoveryAlert = nil
            }
        }
        let restored = playback.stop(reason: reason, retryRecovery: retryRecovery)
        square.animationFrame = nil
        square.recovery = !restored
        updateRecovery(restored: restored)
        if restored && restoreFocus && NSApp.isActive, let target = target, !target.isTerminated {
            record("return_focus: accepted=\(target.activate(options: []))")
        }
    }

    private func record(_ event: String) {
        logger.debug("\(event, privacy: .public)")
    }

    private func updateRecovery(restored: Bool) {
        if restored {
            recoveryTimer?.invalidate()
            recoveryTimer = nil
            cursorRecovery.reset()
            square.recovery = false
            window.level = widgetLayer.level
            statusItem?.button?.toolTip = "CursorWasher"
            if let alert = recoveryAlert {
                window.endSheet(alert.window, returnCode: .abort)
                recoveryAlert = nil
            }
            if pendingTermination {
                pendingTermination = false
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        guard recoveryTimer == nil, recoveryAlert == nil else { return }
        statusItem?.button?.toolTip = "Restoring cursor…"
        guard let delay = cursorRecovery.nextDelay else {
            showRecoveryAlert()
            return
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.recoveryTimer = nil
            self.updateRecovery(restored: self.cursorRecovery.retry())
        }
        recoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func showRecoveryAlert() {
        logger.error("Cursor restoration failed after automatic retries")
        let alert = NSAlert()
        alert.messageText = "Couldn't restore the cursor"
        alert.informativeText = "macOS did not restore the pointer after several attempts. Try again or press Escape. CursorWasher will stay open until the pointer is restored."
        alert.addButton(withTitle: "Try Again")
        recoveryAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            self.recoveryAlert = nil
            guard response == .alertFirstButtonReturn else { return }
            self.cursorRecovery.reset()
            self.finish(reason: "recovery_button", retryRecovery: true)
        }
        window.level = .statusBar
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func keepWindowOnScreen() {
        guard window != nil, !NSScreen.screens.isEmpty else { return }
        func visibleArea(_ screen: CGRect) -> CGFloat {
            let intersection = window.frame.intersection(screen)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        let best = NSScreen.screens.map { $0.visibleFrame }.max { visibleArea($0) < visibleArea($1) }!
        let origin = CGPoint(x: min(max(window.frame.minX, best.minX), max(best.minX, best.maxX - window.frame.width)),
                             y: min(max(window.frame.minY, best.minY), max(best.minY, best.maxY - window.frame.height)))
        window.setFrameOrigin(origin)
    }

    func windowDidMove(_ notification: Notification) {
        window.saveFrame(usingName: "CursorWasherBucket")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if session.phase == .recoveryRequired { finish(reason: "reactivation_recovery") }
        else { beginWhenActive() }
    }
    func applicationWillResignActive(_ notification: Notification) {
        // Activation notifications can precede the asynchronous global click.
        // Release the real cursor now; the passive sinking effect may finish later.
        if playback.isRunning { sinkCursor(reason: "deactivated") }
        else { finish(reason: "deactivated") }
    }
    func applicationDidResignActive(_ notification: Notification) {
        if session.ownsHide { finish(reason: "deactivated_retry") }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWidget()
        return false
    }
    func windowWillMiniaturize(_ notification: Notification) { finish(reason: "minimized") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        finish(reason: "quit", retryRecovery: true)
        pendingTermination = session.ownsHide
        return session.ownsHide ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        finish(reason: "termination")
        animationTimer?.invalidate()
        recoveryTimer?.invalidate()
        if let monitor = escapeMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor) }
        for observation in observations {
            NSWorkspace.shared.notificationCenter.removeObserver(observation)
            NotificationCenter.default.removeObserver(observation)
        }
        if let status = statusItem { NSStatusBar.system.removeStatusItem(status) }
        statusItem = nil
        record("terminated")
    }
}

let app = NSApplication.shared
let delegate = WidgetDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
