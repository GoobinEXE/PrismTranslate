import AppKit
import SwiftUI

/// Floating panel showing translation with Copy / Replace actions.
/// Window lifecycle (AppKit) lives here; appearance stays in `TranslationResultPanelView`.
@MainActor
final class TranslationResultPanelController: NSObject, NSWindowDelegate {
    static let shared = TranslationResultPanelController()

    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    struct Session {
        let original: String
        let translated: String
        let canReplace: Bool
        let showOriginal: Bool
        let sourceLanguageLabel: String
        let targetLanguageLabel: String
        let capture: FocusedTextCapture
        let targetApp: NSRunningApplication?
        var onReplace: ((FocusedTextCapture, String, NSRunningApplication?) async -> Void)?
    }

    private var panel: NSPanel?
    private var session: Session?
    /// Preferências window we ordered out so activate only shows the popup.
    private weak var hiddenSettingsWindow: NSWindow?

    func show(_ session: Session) {
        AppLog.info(
            .resultPanel,
            "show — original=\(session.original.count) chars, translated=\(session.translated.count) chars, canReplace=\(session.canReplace), \(session.sourceLanguageLabel)→\(session.targetLanguageLabel), app=\(session.targetApp?.localizedName ?? "nil")"
        )
        self.session = session
        closePanelChrome(restoreSettings: false)
        present(session)
    }

    func close() {
        AppLog.info(.resultPanel, "close")
        closePanelChrome(restoreSettings: true)
        session = nil
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.panel = nil
            self.session = nil
            self.restoreSettingsIfNeeded()
        }
    }

    private func closePanelChrome(restoreSettings: Bool) {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        if restoreSettings {
            restoreSettingsIfNeeded()
        }
    }

    private func present(_ session: Session) {
        hideSettingsIfNeeded()

        let width: CGFloat = 420
        let root = TranslationResultPanelView(
            original: session.original,
            translated: session.translated,
            canReplace: session.canReplace,
            showOriginal: session.showOriginal,
            sourceLanguageLabel: session.sourceLanguageLabel,
            targetLanguageLabel: session.targetLanguageLabel,
            onCopy: { [weak self] in
                guard let text = self?.session?.translated else { return }
                AppLog.info(.resultPanel, "Copy — \(text.count) chars")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            onReplace: { [weak self] in
                guard let self, let current = self.session else { return }
                AppLog.info(.resultPanel, "Replace acionado — \(current.translated.count) chars")
                let capture = current.capture
                let translated = current.translated
                let app = current.targetApp
                let handler = current.onReplace
                self.close()
                Task { @MainActor in
                    await handler?(capture, translated, app)
                }
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let hostingView: NSView
        if #available(macOS 26.0, *) {
            hostingView = NSHostingView(
                rootView: root.environment(\.preferMaterialOverGlass, true)
            )
        } else {
            hostingView = NSHostingView(rootView: root)
        }

        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        let fittedHeight = max(hostingView.fittingSize.height, 100)
        let height = min(fittedHeight, 440)
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.frame = contentRect

        // Borderless — no traffic-light close; SwiftUI provides the only dismiss control.
        let panel = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        panel.minSize = NSSize(width: 320, height: 100)
        panel.contentMinSize = NSSize(width: 320, height: 100)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: contentRect)
            glass.cornerRadius = 16
            hostingView.autoresizingMask = [.width, .height]
            glass.contentView = hostingView
            panel.contentView = glass
        } else {
            panel.contentView = hostingView
        }

        panel.setContentSize(NSSize(width: width, height: height))
        position(panel, size: NSSize(width: width, height: height), near: session.capture.selectionScreenRect)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Avoid SwiftUI focusing the first Button and drawing the blue focus ring.
        _ = panel.makeFirstResponder(hostingView)
        self.panel = panel
    }

    /// Places the panel just below the selection (or above if it would go off-screen).
    private func position(_ panel: NSPanel, size: NSSize, near selection: CGRect?) {
        let gap: CGFloat = 10
        let anchor = selection.flatMap { $0.isEmpty ? nil : $0 }
            ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        var origin = NSPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - gap - size.height
        )
        // Not enough room below → place above the selection.
        if origin.y < visible.minY + 4 {
            origin.y = anchor.maxY + gap
        }

        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Preferências (hide while popup is frontmost)

    private func hideSettingsIfNeeded() {
        guard let settings = Self.settingsWindow(), settings.isVisible else {
            hiddenSettingsWindow = nil
            return
        }
        settings.orderOut(nil)
        hiddenSettingsWindow = settings
    }

    private func restoreSettingsIfNeeded() {
        guard let settings = hiddenSettingsWindow else { return }
        hiddenSettingsWindow = nil
        settings.makeKeyAndOrderFront(nil)
    }

    /// Same heuristic as `DockIconController.findSettingsWindow` — kept local to avoid coupling.
    private static func settingsWindow() -> NSWindow? {
        if let named = NSApp.windows.first(where: {
            $0.frameAutosaveName == "com_apple_SwiftUI_Settings_window"
        }) {
            return named
        }
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
