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
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H1",
            location: "DockIconController.retain",
            message: "retain",
            data: [
                "reason": String(describing: reason),
                "wasEmpty": wasEmpty,
                "reasons": reasons.map { String(describing: $0) }.sorted(),
                "isShowingDock": isShowingDock,
                "activationPolicy": NSApp.activationPolicy().rawValue,
            ]
        )
        // #endregion
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
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H1",
            location: "DockIconController.release",
            message: "release",
            data: [
                "reason": String(describing: reason),
                "reasonsAfter": reasons.map { String(describing: $0) }.sorted(),
                "willHide": reasons.isEmpty,
                "isShowingDock": isShowingDock,
            ]
        )
        // #endregion
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
        guard let window = Self.findSettingsWindow() else {
            attachAttempt += 1
            // #region agent log
            AgentDebugLog.write(
                hypothesisId: "H4",
                location: "DockIconController.attachToSettingsWindowIfNeeded",
                message: "settings window not found",
                data: [
                    "attempt": attachAttempt,
                    "windowCount": NSApp.windows.count,
                    "windowTitles": NSApp.windows.map { $0.title },
                    "autosaveNames": NSApp.windows.map { $0.frameAutosaveName },
                ]
            )
            // #endregion
            guard attachAttempt <= 8 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.reasons.contains(.settings) else { return }
                self.attachToSettingsWindowIfNeeded()
            }
            return
        }
        attachAttempt = 0
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H4",
            location: "DockIconController.attachToSettingsWindowIfNeeded",
            message: "attached settings window",
            data: [
                "title": window.title,
                "autosave": window.frameAutosaveName,
                "isVisible": window.isVisible,
                "className": String(describing: type(of: window)),
            ]
        )
        // #endregion
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
                // #region agent log
                AgentDebugLog.write(
                    hypothesisId: "H1",
                    location: "DockIconController.willCloseNotification",
                    message: "settings willClose → hideForSettings",
                    data: [:]
                )
                // #endregion
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
            // #region agent log
            AgentDebugLog.write(
                hypothesisId: "H1",
                location: "DockIconController.applyDockVisibility",
                message: "noop same state",
                data: ["show": show, "isShowingDock": isShowingDock]
            )
            // #endregion
            return
        }
        isShowingDock = show
        // Changing activation policy rebuilds window chrome — never do this
        // from inside a view's layout path; callers already defer via async.
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H2",
            location: "DockIconController.applyDockVisibility",
            message: "policy flipped",
            data: [
                "show": show,
                "policyAfter": NSApp.activationPolicy().rawValue,
            ]
        )
        // #endregion
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
        let byAppIconName = NSImage(named: NSImage.applicationIconName)
        let byLiteral = NSImage(named: "AppIcon")
        let icon = byAppIconName ?? byLiteral
        if let icon {
            NSApp.applicationIconImage = icon
        }
        let assigned = NSApp.applicationIconImage
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H2",
            location: "DockIconController.refreshApplicationIcon",
            message: "icon refresh",
            data: [
                "loadedApplicationIconName": byAppIconName != nil,
                "loadedAppIconLiteral": byLiteral != nil,
                "didAssign": icon != nil,
                "assignedSize": assigned.map { "\($0.size.width)x\($0.size.height)" } ?? "nil",
                "bundleIconName": Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String ?? "nil",
                "bundleIconFile": Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "nil",
            ]
        )
        // #endregion
    }

    /// Heuristic for the SwiftUI `Settings` scene window.
    private static func findSettingsWindow() -> NSWindow? {
        if let named = NSApp.windows.first(where: {
            $0.frameAutosaveName == "com_apple_SwiftUI_Settings_window"
        }) {
            return named
        }
        // Prefer the key window right after showSettingsWindow:.
        if let key = NSApp.keyWindow,
            !(key is NSPanel),
            key.isVisible,
            key.styleMask.contains(.titled),
            key.styleMask.contains(.closable)
        {
            return key
        }
        return NSApp.windows.first { window in
            window.isVisible
                && !(window is NSPanel)
                && window.styleMask.contains(.titled)
                && window.styleMask.contains(.closable)
        }
    }
}

// #region agent log
enum AgentDebugLog {
    private static let path =
        "/Users/marcelopessoa/CODES/QuickTranslate/.cursor/debug-f73f3a.log"
    private static let sessionId = "f73f3a"

    static func write(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any] = [:],
        runId: String = "pre-fix"
    ) {
        var payload: [String: Any] = [
            "sessionId": sessionId,
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if !data.isEmpty {
            payload["data"] = data
        }
        guard JSONSerialization.isValidJSONObject(payload),
            let json = try? JSONSerialization.data(withJSONObject: payload),
            var line = String(data: json, encoding: .utf8)
        else { return }
        line.append("\n")
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let bytes = line.data(using: .utf8) {
            try? handle.write(contentsOf: bytes)
        }
    }
}
// #endregion
