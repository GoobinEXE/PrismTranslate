import AppKit
import Carbon.HIToolbox
import Foundation

/// Global hotkey / Enter interceptor via CGEvent tap.
final class HotkeyMonitor {
    var onTranslateOnly: (() -> Void)?
    var onTranslateAndSend: (() -> Void)?
    var onPopup: (() -> Void)?
    /// Fired on the main queue whenever tap install state changes.
    var onTapStatusChange: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var retryTimer: Timer?
    private var didPromptInputMonitoring = false

    private let lock = NSLock()
    private var enabled = true
    private var enterTranslatesAndSends = false
    private var popupModeEnabled = false
    private var injectionDepth = 0
    private var isRecordingHotkey = false
    private var translateOnly = HotkeyChord.translateOnlyDefault
    private var translateAndSend = HotkeyChord.translateAndSendDefault
    private var popupChord = HotkeyChord.popupDefault

    var isTapActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventTap != nil
    }

    func updateConfiguration(
        enabled: Bool,
        enterTranslatesAndSends: Bool,
        translateOnly: HotkeyChord,
        translateAndSend: HotkeyChord,
        popupModeEnabled: Bool = false,
        popup: HotkeyChord = .popupDefault
    ) {
        lock.lock()
        self.enabled = enabled
        self.enterTranslatesAndSends = enterTranslatesAndSends
        self.translateOnly = translateOnly
        self.translateAndSend = translateAndSend
        self.popupModeEnabled = popupModeEnabled
        self.popupChord = popup
        lock.unlock()
    }

    /// While true, all hotkey matching is skipped so the settings recorder can capture keys.
    func setRecordingHotkey(_ recording: Bool) {
        lock.lock()
        isRecordingHotkey = recording
        lock.unlock()
    }

    func start() {
        guard thread == nil else { return }

        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            _ = self.installTap()
            if self.eventTap == nil {
                self.scheduleRetry()
            }
            CFRunLoopRun()
        }
        thread.name = "QuickTranslate.HotkeyMonitor"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    /// Ask the monitor thread to try installing the tap again (e.g. after permissions change).
    func retryInstallIfNeeded() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self, self.eventTap == nil else { return }
            if self.installTap() {
                self.retryTimer?.invalidate()
                self.retryTimer = nil
            }
        }
        CFRunLoopWakeUp(runLoop)
    }

    func stop() {
        guard let runLoop else {
            tearDownTap(on: CFRunLoopGetCurrent())
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            self?.tearDownTap(on: runLoop)
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
        thread = nil
        self.runLoop = nil
    }

    private func tearDownTap(on runLoop: CFRunLoop) {
        retryTimer?.invalidate()
        retryTimer = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        let hadTap = eventTap != nil
        eventTap = nil
        runLoopSource = nil
        if hadTap {
            DispatchQueue.main.async { self.onTapStatusChange?(false) }
        }
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if self.installTap() {
                timer.invalidate()
                self.retryTimer = nil
            }
        }
        retryTimer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    @discardableResult
    private func installTap() -> Bool {
        guard eventTap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            AppLog.error(.hotkey, "falha ao criar event tap — Input Monitoring provavelmente negado")
            if !didPromptInputMonitoring {
                didPromptInputMonitoring = true
                DispatchQueue.main.async {
                    _ = Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                }
            }
            DispatchQueue.main.async { self.onTapStatusChange?(false) }
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AppLog.info(.hotkey, "event tap instalado com sucesso")
        DispatchQueue.main.async { self.onTapStatusChange?(true) }
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            AppLog.warning(.hotkey, "⚠️ event tap desabilitado (\(type == .tapDisabledByTimeout ? "timeout" : "user input")) — reabilitando")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let isEnabled = enabled
        let enterMode = enterTranslatesAndSends
        let popupEnabled = popupModeEnabled
        let injecting = injectionDepth > 0
        let recording = isRecordingHotkey
        let onlyChord = translateOnly
        let sendChord = translateAndSend
        let popup = popupChord
        lock.unlock()

        if !isEnabled || injecting || recording || type != .keyDown {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Configured: translate only
        if onlyChord.matches(keyCode: keyCode, flags: flags) {
            AppLog.info(.hotkey, "🎯 hotkey translateOnly matched (keyCode=\(keyCode))")
            Task { @MainActor in self.onTranslateOnly?() }
            return nil
        }

        // Configured: translate and send
        if sendChord.matches(keyCode: keyCode, flags: flags) {
            AppLog.info(.hotkey, "🎯 hotkey translateAndSend matched (keyCode=\(keyCode))")
            Task { @MainActor in self.onTranslateAndSend?() }
            return nil
        }

        // Configured: popup panel (opt-in)
        if popupEnabled, popup.matches(keyCode: keyCode, flags: flags) {
            AppLog.info(.hotkey, "🎯 hotkey popup matched (keyCode=\(keyCode))")
            Task { @MainActor in self.onPopup?() }
            return nil
        }

        // Enter mode: plain Return/Enter translates and sends (text fields only)
        if enterMode,
           (keyCode == Int64(kVK_Return) || keyCode == Int64(kVK_ANSI_KeypadEnter)),
           !flags.contains(.maskCommand),
           !flags.contains(.maskAlternate),
           !flags.contains(.maskControl) {
            let editable = FocusedTextIO.isFocusedTextEditable()
            AppLog.debug(.hotkey, "⏎ Enter-mode: isFocusedTextEditable=\(editable)")
            if editable {
                AppLog.info(.hotkey, "🎯 Enter-mode triggered — translateAndSend")
                Task { @MainActor in self.onTranslateAndSend?() }
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Marks synthetic key injection so the tap does not re-intercept it.
    /// Supports nesting (⌘A then later ⌘C) via a depth counter.
    func withInjection(_ work: () -> Void) {
        lock.lock()
        injectionDepth += 1
        lock.unlock()
        work()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.injectionDepth = max(0, self.injectionDepth - 1)
            self.lock.unlock()
        }
    }
}
