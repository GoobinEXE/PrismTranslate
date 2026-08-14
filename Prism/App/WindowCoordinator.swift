import AppKit

/// Owns how Preferências, MenuBarExtra and the translation popup share the screen.
///
/// Policy while the result panel is frontmost:
/// - Preferências stays visible if it was already open (Dock unchanged).
/// - Preferências never becomes key and stays below the panel.
/// - Closed Preferências is never opened.
/// - Closing the panel does not `makeKeyAndOrderFront` Preferências.
@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()

    private weak var frontPanel: NSWindow?
    private weak var demotedSettings: NSWindow?
    private var originalSettingsLevel: NSWindow.Level?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    var isTranslationPopupFront: Bool {
        frontPanel?.isVisible == true
    }

    /// Call after the result panel is key and the app is activated.
    func beginTranslationPopupFront(panel: NSWindow) {
        SettingsNavigation.closeMenuBarExtra()
        tearDownGuards(restoreLevel: true)
        frontPanel = panel

        guard let settings = SettingsNavigation.settingsWindow(), settings.isVisible else {
            return
        }

        demotedSettings = settings
        originalSettingsLevel = settings.level
        if settings.level >= panel.level {
            settings.level = NSWindow.Level(rawValue: panel.level.rawValue - 1)
        }
        settings.order(.below, relativeTo: panel.windowNumber)
        installKeyGuards(settings: settings)
    }

    /// Ends popup front policy. Never orders Preferências front. Optionally
    /// returns focus to the app the user was translating in.
    func endTranslationPopupFront(reactivate origin: NSRunningApplication?) {
        tearDownGuards(restoreLevel: true)
        frontPanel = nil
        activateOriginIfNeeded(origin)
    }

    /// After another Prism surface activates (Apple Translation host), give key
    /// back to the popup if it is still up — never to Preferências.
    func restorePopupKeyIfNeeded() {
        guard let panel = frontPanel, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        demoteVisibleSettings(below: panel)
    }

    private func installKeyGuards(settings: NSWindow) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: settings, queue: .main) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                Task { @MainActor [weak self] in
                    self?.handleWindowTryingToBecomeKey(window)
                }
            },
            center.addObserver(forName: NSWindow.didBecomeMainNotification, object: settings, queue: .main) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                Task { @MainActor [weak self] in
                    self?.handleWindowTryingToBecomeKey(window)
                }
            },
        ]
    }

    private func handleWindowTryingToBecomeKey(_ window: NSWindow) {
        guard let panel = frontPanel, panel.isVisible else { return }
        guard window !== panel else { return }
        if window is NSPanel { return }
        panel.makeKeyAndOrderFront(nil)
        demoteVisibleSettings(below: panel)
    }

    private func demoteVisibleSettings(below panel: NSWindow) {
        guard let settings = SettingsNavigation.settingsWindow(), settings.isVisible else { return }
        if demotedSettings == nil {
            demotedSettings = settings
            originalSettingsLevel = settings.level
        }
        if settings.level >= panel.level {
            settings.level = NSWindow.Level(rawValue: panel.level.rawValue - 1)
        }
        settings.order(.below, relativeTo: panel.windowNumber)
    }

    private func tearDownGuards(restoreLevel: Bool) {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        if restoreLevel, let settings = demotedSettings, let level = originalSettingsLevel {
            settings.level = level
        }
        demotedSettings = nil
        originalSettingsLevel = nil
    }

    private func activateOriginIfNeeded(_ origin: NSRunningApplication?) {
        guard let origin, !origin.isTerminated else { return }
        if origin.isActive { return }
        if #available(macOS 14.0, *) {
            origin.activate()
        } else {
            origin.activate(options: .activateIgnoringOtherApps)
        }
    }
}
