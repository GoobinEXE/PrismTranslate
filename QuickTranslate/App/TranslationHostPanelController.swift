import AppKit
import SwiftUI
import Translation

/// Panel that provides a visible window for the Apple Translation download sheet
/// AND hosts the persistent SwiftUI view with `.translationTask` so Apple Translation
/// works even when the MenuBarExtra popover is closed.
@MainActor
@available(macOS 15.0, *)
final class TranslationHostPanelController {
    static let shared = TranslationHostPanelController()
    /// Borderless panels refuse key status by default; the download sheet needs it.
    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private var panel: NSPanel?

    func install(bridge: AppleTranslationBridge) {
        guard panel == nil else { return }

        bridge.onActivity = { [weak self] active in
            self?.setActive(active)
        }

        let hostView = TranslationHostView(bridge: bridge)
        let hostingView = NSHostingView(rootView: hostView)

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel

        AppLog.info(.hostPanel, "🍏 TranslationHostPanelController installed with persistent NSHostingView")
    }

    /// Brings a visible panel on-screen so `prepareTranslation()` can anchor
    /// the system download sheet; hides it again when done.
    private func setActive(_ active: Bool) {
        guard let panel else { return }
        if active {
            let size = NSSize(width: 480, height: 160)
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let origin = NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            panel.ignoresMouseEvents = false
            panel.alphaValue = 1
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        } else {
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
    }
}

@available(macOS 15.0, *)
private struct TranslationHostView: View {
    @ObservedObject var bridge: AppleTranslationBridge
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.configuration) { session in
                AppLog.info(.hostPanel, "🍏 .translationTask triggered by configuration change!")
                await bridge.handle(session: session)
            }
    }
}
