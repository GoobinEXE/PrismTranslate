import AppKit
import Foundation

/// Temporarily shows the app in the Dock while Preferências / onboarding are open.
/// Keeps `LSUIElement` behavior otherwise (menu-bar-only).
///
/// Uses a reason set so overlapping surfaces (Settings + Tutorial) don't fight
/// over `setActivationPolicy`, and never hides on SwiftUI `onDisappear` (which
/// can fire during remounts while the window is still open).
@MainActor
final class DockIconController {
    static let shared = DockIconController()

    enum Reason: Hashable {
        case settings
        case onboarding
    }

    private var reasons: Set<Reason> = []
    private var settingsWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var isShowingDock = false
    private var attachAttempt = 0

    private init() {}

    /// Begin showing the Dock for a given surface. Idempotent per reason.
    func retain(_ reason: Reason) {
        let wasEmpty = reasons.isEmpty
        reasons.insert(reason)
        if wasEmpty {
            applyDockVisibility(true)
        } else {
            refreshApplicationIcon()
        }
        if reason == .settings {
            // Window may not exist until the next run-loop turn.
            DispatchQueue.main.async { [weak self] in
                self?.attachToSettingsWindowIfNeeded()
            }
        }
    }

    /// Stop showing the Dock for a surface. Hides only when no reasons remain.
    func release(_ reason: Reason) {
        guard reasons.contains(reason) else { return }
        reasons.remove(reason)
        if reason == .settings {
            detachSettingsWindow()
        }
        if reasons.isEmpty {
            // Defer hide one turn so SwiftUI Settings teardown / policy flip
            // doesn't race with another retain in the same frame.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.reasons.isEmpty else { return }
                self.applyDockVisibility(false)
            }
        }
    }

    /// Call before / when opening the Settings scene.
    func showForSettings() {
        retain(.settings)
    }

    /// Call when the Settings window actually closes.
    func hideForSettings() {
        release(.settings)
    }

    private func attachToSettingsWindowIfNeeded() {
        if let existing = settingsWindow {
            if existing.isVisible {
                return
            }
            detachSettingsWindow()
        }
        guard let window = SettingsNavigation.settingsWindow() else {
            attachAttempt += 1
            guard attachAttempt <= 8 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.reasons.contains(.settings) else { return }
                self.attachToSettingsWindowIfNeeded()
            }
            return
        }
        attachAttempt = 0
        track(window)
    }

    private func track(_ window: NSWindow) {
        settingsWindow = window
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hideForSettings()
            }
        }
    }

    private func detachSettingsWindow() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        settingsWindow = nil
        attachAttempt = 0
    }

    private func applyDockVisibility(_ show: Bool) {
        guard show != isShowingDock else {
            if show { refreshApplicationIcon() }
            return
        }
        isShowingDock = show
        // Changing activation policy rebuilds window chrome — never do this
        // from inside a view's layout path; callers already defer via async.
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show {
            refreshApplicationIcon()
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Forces the Dock tile to use the catalog AppIcon after policy flips
    /// (LSUIElement → regular can briefly show a generic icon otherwise).
    private func refreshApplicationIcon() {
        let icon = NSImage(named: NSImage.applicationIconName) ?? NSImage(named: "AppIcon")
        if let icon {
            NSApp.applicationIconImage = icon
        }
    }
}
