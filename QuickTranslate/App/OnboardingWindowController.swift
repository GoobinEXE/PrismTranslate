import AppKit
import SwiftUI

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private static let completedKey = "didCompleteOnboarding"

    private var panel: NSPanel?
    private var hosting: NSView?

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    func showIfNeeded() {
        guard !Self.hasCompleted else { return }
        show()
    }

    func show() {
        if let panel, panel.isVisible {
            // #region agent log
            AgentDebugLog.write(
                hypothesisId: "H5",
                location: "OnboardingController.show",
                message: "reuse visible panel",
                data: [
                    "dockReasonsWouldNeed": "onboarding",
                    "activationPolicy": NSApp.activationPolicy().rawValue,
                ]
            )
            // #endregion
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let contentRect = NSRect(x: 0, y: 0, width: 480, height: 520)

        let root = OnboardingView { [weak self] in
            self?.close()
        }
        // No Tahoe o chrome já é NSGlassEffectView; o conteúdo SwiftUI precisa
        // cair para material (preferMaterialOverGlass) para não aninhar glass.
        let hostingView: NSView
        if #available(macOS 26.0, *) {
            hostingView = NSHostingView(
                rootView: root.environment(\.preferMaterialOverGlass, true)
            )
        } else {
            hostingView = NSHostingView(rootView: root)
        }
        hostingView.frame = contentRect
        self.hosting = hostingView

        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "QuickTranslate"
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
        var usedNestedGlass = false
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: contentRect)
            glass.cornerRadius = 16
            hostingView.autoresizingMask = [.width, .height]
            glass.contentView = hostingView
            panel.contentView = glass
            usedNestedGlass = true
        } else {
            panel.contentView = hostingView
        }
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H5",
            location: "OnboardingController.show",
            message: "created onboarding panel",
            data: [
                "usedNSGlassEffectView": usedNestedGlass,
                "preferMaterialEnvApplied": usedNestedGlass,
                "dockRetainCalled": false,
                "activationPolicy": NSApp.activationPolicy().rawValue,
            ]
        )
        // #endregion
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func close() {
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H5",
            location: "OnboardingController.close",
            message: "close onboarding",
            data: ["hadPanel": panel != nil]
        )
        // #endregion
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            // #region agent log
            AgentDebugLog.write(
                hypothesisId: "H5",
                location: "OnboardingController.windowWillClose",
                message: "onboarding willClose",
                data: [:]
            )
            // #endregion
            self.panel = nil
            self.hosting = nil
        }
    }
}
