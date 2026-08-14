import ApplicationServices
import AppKit
import Foundation
import IOKit.hid

enum Permissions {
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    /// True when Input Monitoring (listen events) is granted — needed by the CGEvent tap
    /// that captures the global hotkeys.
    static func isInputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Asks macOS to show the Input Monitoring permission prompt (no-op if already decided).
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// System Settings › General › Language & Region › Translation Languages
    /// (download packs + On-Device Mode checkbox).
    static func openTranslationLanguagesSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation",
            "x-apple.systempreferences:com.apple.Localization-Settings.extension",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func promptIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "didPromptPermissions"
        guard !defaults.bool(forKey: key) else {
            _ = isAccessibilityTrusted(prompt: false)
            return
        }
        defaults.set(true, forKey: key)
        _ = isAccessibilityTrusted(prompt: true)
        _ = requestInputMonitoring()
    }
}
