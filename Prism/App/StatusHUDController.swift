import AppKit
import SwiftUI

/// Toast flutuante perto do ponteiro para status de tradução (atalho).
/// Não ativa o app nem rouba o foco do campo; erros não somem sozinhos.
@MainActor
final class StatusHUDController {
    static let shared = StatusHUDController()

    private final class HUDPanel: NSPanel {
        var allowsKey: Bool = false
        override var canBecomeKey: Bool { allowsKey }
        override var canBecomeMain: Bool { false }
    }

    private var panel: HUDPanel?
    private var hideTask: Task<Void, Never>?
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    private init() {}

    func present(status: AppState.Status, isEnabled: Bool, hudEnabled: Bool = true) {
        guard hudEnabled else {
            hide()
            return
        }

        switch status {
        case .idle:
            hide()
            return
        case .success where TranslationResultPanelController.shared.isVisible:
            // O painel de resultado já é o feedback de conclusão no modo popup.
            hide()
            return
        case .translating where TranslationResultPanelController.shared.isVisible:
            hide()
            return
        case .translating, .success, .error:
            break
        }

        hideTask?.cancel()
        hideTask = nil
        closeChrome()

        let root = StatusHUDView(
            status: status,
            isEnabled: isEnabled,
            onDismiss: { [weak self] in
                self?.hide()
            },
            onOpenDetails: { [weak self] in
                self?.hideAfterCurrentEvent()
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

        let width: CGFloat = 320
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        let height = max(hostingView.fittingSize.height, 44)
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.frame = contentRect

        let needsClicks = if case .error = status { true } else { false }

        let panel = HUDPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.allowsKey = needsClicks
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = !needsClicks
        panel.worksWhenModal = true

        GlassPanelChrome.install(
            contentView: hostingView,
            in: panel,
            frame: contentRect,
            cornerRadius: 12
        )

        panel.setContentSize(NSSize(width: width, height: height))
        positionNearCursor(panel, size: NSSize(width: width, height: height))
        panel.orderFrontRegardless()
        self.panel = panel

        announce(status: status, isEnabled: isEnabled)
        installEscapeMonitorIfNeeded(for: status)

        // «Traduzindo…» fica até sucesso/erro. Erros ficam até o usuário dispensar.
        let dismissNanos: UInt64? =
            switch status {
            case .success: UInt64(1_400_000_000)
            case .translating, .error, .idle: nil
            }

        if let dismissNanos {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: dismissNanos)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        removeEscapeMonitor()
        closeChrome()
    }

    /// Dismiss after the current click finishes so `SettingsLink` can open Preferências.
    func hideAfterCurrentEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.hide()
        }
    }

    private func announce(status: AppState.Status, isEnabled: Bool) {
        let title: String =
            switch status {
            case .idle: isEnabled ? String(localized: "Active") : String(localized: "Paused")
            case .translating: String(localized: "Translating…")
            case .success: String(localized: "Translation complete")
            case .error: String(localized: "Translation failed")
            }
        let message: String =
            if case .error(let detail) = status {
                "\(title). \(detail)"
            } else {
                title
            }
        AccessibilityNotification.Announcement(message).post()
    }

    private func installEscapeMonitorIfNeeded(for status: AppState.Status) {
        removeEscapeMonitor()
        guard case .error = status else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil
            }
            return event
        }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.hide()
                }
            }
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }

    private func closeChrome() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func positionNearCursor(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        var origin = NSPoint(
            x: mouse.x - size.width / 2,
            y: mouse.y - size.height - 28
        )
        if origin.y < visible.minY + 8 {
            origin.y = mouse.y + 20
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}

private struct StatusHUDView: View {
    let status: AppState.Status
    let isEnabled: Bool
    var onDismiss: () -> Void
    var onOpenDetails: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: QTDesign.Spacing.s) {
            Image(systemName: iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: isTranslating && !reduceMotion)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(QTDesign.Fonts.callout.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if case .error = status {
                QTSettingsLink(section: .logs, beforeOpen: onOpenDetails) {
                    Text("View details")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(QTDesign.Fonts.caption)
                .accessibilityLabel("Open Settings, Logs section")
                .accessibilityHint("Shows the logs for the translation failure")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
                .accessibilityLabel("Dismiss notice")
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
        .background {
            if #available(macOS 26.0, *) {
                Color.clear
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
    }

    private var isTranslating: Bool { status == .translating }

    private var title: String {
        switch status {
        case .idle: return isEnabled ? String(localized: "Active") : String(localized: "Paused")
        case .translating: return String(localized: "Translating…")
        case .success: return String(localized: "Translation complete")
        case .error: return String(localized: "Translation failed")
        }
    }

    private var subtitle: String? {
        if case .error(let message) = status {
            return message
        }
        return nil
    }

    private var iconName: String {
        switch status {
        case .idle: return isEnabled ? "globe" : "pause.circle"
        case .translating: return "ellipsis.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .idle: return isEnabled ? .green : .secondary
        case .translating: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
}
