import AppKit
import SwiftUI

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    nonisolated private static let completedKey = "didCompleteOnboarding"

    private var panel: NSPanel?
    private var hosting: NSView?

    nonisolated static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    nonisolated static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func showIfNeeded() {
        guard !Self.hasCompleted else { return }
        show()
    }

    /// - Parameter closeMenuBarAfterPresent: fecha o painel do MenuBarExtra **depois** de
    ///   apresentar o tutorial (evita perder foco num app só menu bar).
    func show(closeMenuBarAfterPresent: Bool = false) {
        DockIconController.shared.retain(.onboarding)

        if let panel, panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            if closeMenuBarAfterPresent {
                SettingsNavigation.closeMenuBarExtra()
            }
            return
        }

        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 520)

        let root = OnboardingView { [weak self] in
            self?.close()
        }
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = contentRect
        self.hosting = hostingView

        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "Welcome to Prism")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
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
        // Tahoe: chrome em Liquid Glass; antes disso a vibrancy fica por conta
        // do VisualEffectBackground dentro da própria OnboardingView.
        GlassPanelChrome.install(
            contentView: hostingView,
            in: panel,
            frame: contentRect,
            cornerRadius: 16
        )
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        if closeMenuBarAfterPresent {
            SettingsNavigation.closeMenuBarExtra()
        }
    }

    func close() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        DockIconController.shared.release(.onboarding)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.panel = nil
            self.hosting = nil
            DockIconController.shared.release(.onboarding)
        }
    }
}
