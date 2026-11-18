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

    /// Retângulo do texto selecionado (coordenadas Cocoa). Com ele, o aviso aparece junto
    /// do texto, e não do ponteiro; sem ele (leitura via clipboard), cai no ponteiro.
    private var anchorRect: CGRect?
    /// Ação «Desfazer» oferecida no aviso de sucesso de uma substituição.
    private var pendingUndo: (() -> Void)?
    /// Linha extra no aviso de sucesso (ex.: motor reserva usado).
    private var pendingNote: String?
    /// App em primeiro plano quando um aviso descartável apareceu; trocar de app o fecha.
    private var dismissibleOwnerPID: pid_t?
    private var appActivationObserver: NSObjectProtocol?

    private init() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            Task { @MainActor in
                self?.handleAppActivation(pid: pid)
            }
        }
    }

    /// Outro app veio para a frente: o aviso de sucesso ou informativo já não se refere a ele.
    private func handleAppActivation(pid: pid_t?) {
        guard let owner = dismissibleOwnerPID, let pid,
            pid != owner, pid != ProcessInfo.processInfo.processIdentifier
        else { return }
        hide()
    }

    /// Tecla real digitada depois de um aviso descartável (chamado pelo event tap).
    /// Enviar a mensagem ou continuar escrevendo invalida o «Desfazer»: ⌘Z já não
    /// desfaria a tradução, e sim o envio ou a digitação.
    func dismissForUserInput() {
        guard dismissibleOwnerPID != nil else { return }
        hide()
    }

    func setAnchor(_ rect: CGRect?) {
        anchorRect = rect.flatMap { $0.isEmpty ? nil : $0 }
        if let panel {
            position(panel, size: panel.frame.size)
        }
    }

    /// Registra o «Desfazer» para o próximo aviso de sucesso.
    func offerUndo(_ action: @escaping () -> Void) {
        pendingUndo = action
    }

    /// Texto curto mostrado sob «Tradução concluída» no próximo sucesso.
    func offerNote(_ note: String) {
        pendingNote = note
    }

    func present(status: AppState.Status, isEnabled: Bool, hudEnabled: Bool = true) {
        guard hudEnabled else {
            hide()
            return
        }

        switch status {
        case .idle:
            hide()
            return
        case .success where TranslationResultPanelController.shared.isVisible,
            .sent where TranslationResultPanelController.shared.isVisible:
            // O painel de resultado já é o feedback de conclusão no modo popup.
            hide()
            return
        case .translating where TranslationResultPanelController.shared.isVisible:
            hide()
            return
        case .translating, .success, .sent, .notice, .error:
            break
        }

        hideTask?.cancel()
        hideTask = nil
        closeChrome()
        // O aviso anterior pode ter armado o fechamento por tecla; este decide de novo abaixo.
        dismissibleOwnerPID = nil
        HUDInputDismissal.shared.disarm()

        let undo: (() -> Void)? = if case .success = status { pendingUndo } else { nil }
        pendingUndo = nil
        let note: String? = if case .success = status { pendingNote } else { nil }
        if case .translating = status {} else { pendingNote = nil }

        let root = StatusHUDView(
            status: status,
            isEnabled: isEnabled,
            note: note,
            onTurnOn: {
                AppState.shared.settingsBinding(\.isEnabled).wrappedValue = true
            },
            onUndo: undo.map { action in
                { [weak self] in
                    self?.hide()
                    action()
                }
            },
            onDismiss: { [weak self] in
                self?.hide()
            },
            onOpenDetails: { [weak self] in
                self?.hideAfterCurrentEvent()
            }
        )

        let hostingView = NSHostingView(rootView: root)

        let width: CGFloat = 320
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        let height = max(hostingView.fittingSize.height, 44)
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.frame = contentRect

        let needsClicks: Bool =
            switch status {
            case .error: true
            case .notice(let notice): notice.offersTurnOn
            default: undo != nil
            }

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
        position(panel, size: NSSize(width: width, height: height))
        panel.orderFrontRegardless()
        self.panel = panel

        announce(status: status, isEnabled: isEnabled)
        installEscapeMonitorIfNeeded(for: status)

        // «Traduzindo…» fica até sucesso/erro. Erros ficam até o usuário dispensar.
        let dismissNanos: UInt64? =
            switch status {
            // Com «Desfazer», tempo suficiente para ler e decidir.
            case .success: undo == nil && note == nil ? UInt64(1_400_000_000) : UInt64(5_000_000_000)
            case .sent: UInt64(1_200_000_000)
            case .notice(let notice): notice.offersTurnOn ? UInt64(4_000_000_000) : UInt64(2_500_000_000)
            case .translating, .error, .idle: nil
            }

        // Sucesso e avisos somem na próxima tecla ou troca de app; erros esperam o usuário.
        switch status {
        case .success, .sent, .notice:
            dismissibleOwnerPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            HUDInputDismissal.shared.arm()
        case .translating, .error, .idle:
            break
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
        dismissibleOwnerPID = nil
        HUDInputDismissal.shared.disarm()
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
            case .sent: String(localized: "Translated and sent")
            case .notice(let notice): notice.message
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

    private func position(_ panel: NSPanel, size: NSSize) {
        if let anchorRect {
            positionNearSelection(panel, size: size, selection: anchorRect)
        } else {
            positionNearCursor(panel, size: size)
        }
    }

    /// Logo abaixo do texto selecionado (acima, se não couber), como o painel de resultado.
    private func positionNearSelection(_ panel: NSPanel, size: NSSize, selection: CGRect) {
        let gap: CGFloat = 8
        let screen =
            NSScreen.screens.first { $0.frame.intersects(selection) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var origin = NSPoint(
            x: selection.minX,
            y: selection.minY - gap - size.height
        )
        if origin.y < visible.minY + 8 {
            origin.y = selection.maxY + gap
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
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
    var note: String?
    var onTurnOn: () -> Void
    var onUndo: (() -> Void)?
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
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if let onUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(QTDesign.Fonts.caption)
                    .accessibilityHint("Puts the original text back")
            }

            if case .notice(let notice) = status, notice.offersTurnOn {
                Button("Turn on") {
                    onTurnOn()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(QTDesign.Fonts.caption)
                .accessibilityHint("Turns Prism back on")
            }

            if case .error(let detail) = status {
                // Falta de permissão se resolve em Permissões, não lendo logs.
                if FocusedTextIOError.isPermissionMessage(detail) {
                    QTSettingsLink(section: .permissions, beforeOpen: onOpenDetails) {
                        Text("Fix…")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(QTDesign.Fonts.caption)
                    .accessibilityLabel("Open Settings, Permissions section")
                } else {
                    QTSettingsLink(section: .logs, beforeOpen: onOpenDetails) {
                        Text("View details")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(QTDesign.Fonts.caption)
                    .accessibilityLabel("Open Settings, Logs section")
                    .accessibilityHint("Shows the logs for the translation failure")
                }

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
        case .sent: return String(localized: "Translated and sent")
        case .notice(let notice): return notice.message
        case .error: return String(localized: "Translation failed")
        }
    }

    private var subtitle: String? {
        if case .error(let message) = status {
            return message
        }
        if case .success = status { return note }
        return nil
    }

    private var iconName: String {
        switch status {
        case .idle: return isEnabled ? "globe" : "pause.circle"
        case .translating: return "ellipsis.circle.fill"
        case .success, .sent: return "checkmark.circle.fill"
        case .notice(let notice): return notice.offersTurnOn ? "pause.circle.fill" : "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .idle: return isEnabled ? .green : .secondary
        case .translating: return .blue
        case .success, .sent: return .green
        case .notice: return .secondary
        case .error: return .red
        }
    }
}

/// Ponte entre o event tap (thread própria) e o HUD: armada enquanto há um aviso
/// que deve sumir na próxima tecla real. `consume()` dispara uma única vez.
final class HUDInputDismissal: @unchecked Sendable {
    static let shared = HUDInputDismissal()
    private let lock = NSLock()
    private var armed = false

    func arm() {
        lock.lock()
        armed = true
        lock.unlock()
    }

    func disarm() {
        lock.lock()
        armed = false
        lock.unlock()
    }

    /// True se estava armada (e desarma).
    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasArmed = armed
        armed = false
        return wasArmed
    }
}
