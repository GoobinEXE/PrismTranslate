import AppKit
import SwiftUI

/// Floating panel showing translation with Copy / Replace actions.
/// Window lifecycle (AppKit) lives here; appearance stays in `TranslationResultPanelView`.
///
/// Non-activating: does not bring Prism (Dock / Preferências) to the front.
/// Keyboard shortcuts are handled with event monitors because SwiftUI
/// `.keyboardShortcut` is unreliable on a nonactivating panel.
@MainActor
final class TranslationResultPanelController: NSObject, NSWindowDelegate {
    static let shared = TranslationResultPanelController()

    private final class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    struct Session {
        let original: String
        let translated: String
        let canReplace: Bool
        let showOriginal: Bool
        let sourceLanguageLabel: String
        let targetLanguageLabel: String
        /// «Texto que leio» vs «Texto que escrevo».
        let pairContextLabel: String
        let capture: FocusedTextCapture
        let targetApp: NSRunningApplication?
        var onReplace: ((FocusedTextCapture, String, NSRunningApplication?) async -> Void)?
        var onDismissWithoutReplace: (() -> Void)?
        /// Chamado quando o usuário copia a tradução: o clipboard antigo não volta.
        var onKeepClipboard: (() -> Void)?
        /// Código do idioma de destino atual (marca o item no menu de idiomas do painel).
        var targetLanguageCode: String = ""
        /// Traduz de novo para outro destino; nil esconde o menu de idiomas.
        var retranslate: ((String) async throws -> String)? = nil
        /// Aviso curto no painel (ex.: motor reserva usado).
        var notice: String? = nil
    }

    private var panel: NSPanel?
    private var session: Session?
    private var pendingClipboardRestore: (() -> Void)?
    private var localKeyMonitor: Any?
    private var globalEscapeMonitor: Any?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show(_ session: Session) {
        AppLog.info(
            .resultPanel,
            "Painel aberto — \(session.pairContextLabel), \(session.sourceLanguageLabel) → \(session.targetLanguageLabel), original \(session.original.count) caracteres, tradução \(session.translated.count), \(session.canReplace ? "Substituir habilitado (⏎)" : "só Copiar (⌘C)"), app \(session.targetApp?.localizedName ?? "desconhecido")"
        )
        self.session = session
        pendingClipboardRestore = session.onDismissWithoutReplace
        closePanelChrome()
        present(session)
    }

    func close(reason: String = "usuário fechou") {
        AppLog.info(.resultPanel, "Painel fechado — \(reason)")
        closePanelChrome()
        session = nil
        consumeClipboardRestore()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            ResultPanelVisibility.shared.set(false)
            self.removeKeyMonitors()
            self.panel = nil
            self.session = nil
            self.consumeClipboardRestore()
        }
    }

    private func closePanelChrome() {
        ResultPanelVisibility.shared.set(false)
        removeKeyMonitors()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(_ session: Session) {
        StatusHUDController.shared.hide()

        let width: CGFloat = 420
        let root = TranslationResultPanelView(
            original: session.original,
            translated: session.translated,
            canReplace: session.canReplace,
            showOriginal: session.showOriginal,
            sourceLanguageLabel: session.sourceLanguageLabel,
            targetLanguageLabel: session.targetLanguageLabel,
            pairContextLabel: session.pairContextLabel,
            targetLanguageCode: session.targetLanguageCode,
            notice: session.notice,
            onRetarget: session.retranslate == nil ? nil : { [weak self] code in
                self?.retarget(to: code)
            },
            onCopy: { [weak self] in
                // Clique: deixa o ✓ «Copiado» visível por um instante antes de fechar.
                self?.copyAndClose(after: 0.45)
            },
            onReplace: { [weak self] in
                self?.replaceInPlace()
            },
            onClose: { [weak self] in
                AppLog.info(.resultPanel, "Botão «Fechar» (Esc)")
                self?.close(reason: "botão Fechar / Esc")
            }
        )

        let hostingView = NSHostingView(rootView: root)

        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        let fittedHeight = max(hostingView.fittingSize.height, 100)
        let height = min(fittedHeight, 440)
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)
        hostingView.frame = contentRect

        // Borderless + nonactivating — no traffic lights, does not activate Prism.
        let panel = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
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
        panel.worksWhenModal = true
        panel.delegate = self
        panel.minSize = NSSize(width: 320, height: 100)
        panel.contentMinSize = NSSize(width: 320, height: 100)

        GlassPanelChrome.install(
            contentView: hostingView,
            in: panel,
            frame: contentRect,
            cornerRadius: 16
        )

        panel.setContentSize(NSSize(width: width, height: height))
        position(
            panel, size: NSSize(width: width, height: height),
            near: session.capture.selectionScreenRect)
        panel.orderFrontRegardless()
        panel.makeKey()
        // Avoid SwiftUI focusing the first Button and drawing the blue focus ring on open.
        // Keyboard/VoiceOver still reach controls via Tab (HIG accessibility).
        _ = panel.makeFirstResponder(hostingView)
        self.panel = panel
        ResultPanelVisibility.shared.set(true)
        installKeyMonitors()
    }

    private func copyTranslated() {
        guard let text = session?.translated else { return }
        AppLog.info(
            .resultPanel,
            "Botão «Copiar» (⌘C) — \(text.count) caracteres na área de transferência"
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Copiar é uma ação final em qualquer contexto: copia e fecha, seja por clique,
    /// ⌘C ou ⏎ (somente leitura). O backup do clipboard antigo é descartado antes de
    /// fechar; senão a restauração do fechamento apagaria a tradução copiada.
    private func copyAndClose(after delay: TimeInterval) {
        copyTranslated()
        pendingClipboardRestore = nil
        session?.onKeepClipboard?()
        guard delay > 0 else {
            close(reason: "copiou a tradução")
            return
        }
        let copiedFrom = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let copiedFrom, self.panel === copiedFrom else { return }
            self.close(reason: "copiou a tradução")
        }
    }

    /// Troca o idioma de destino sem fechar: traduz de novo e redesenha o painel.
    private func retarget(to code: String) {
        guard let current = session, let retranslate = current.retranslate,
            code != current.targetLanguageCode
        else { return }
        Task { @MainActor in
            do {
                let text = try await retranslate(code)
                guard self.session?.original == current.original else { return }
                var updated = Session(
                    original: current.original,
                    translated: text,
                    canReplace: current.canReplace,
                    showOriginal: current.showOriginal,
                    sourceLanguageLabel: current.sourceLanguageLabel,
                    targetLanguageLabel: LanguageCode.displayName(for: code),
                    pairContextLabel: current.pairContextLabel,
                    capture: current.capture,
                    targetApp: current.targetApp,
                    onReplace: current.onReplace,
                    onDismissWithoutReplace: current.onDismissWithoutReplace,
                    onKeepClipboard: current.onKeepClipboard
                )
                updated.targetLanguageCode = code
                updated.retranslate = retranslate
                // Mantém a sessão de clipboard: só redesenha, sem restaurar nada.
                self.session = updated
                self.closePanelChrome()
                self.present(updated)
            } catch {
                AppLog.error(.resultPanel, "Painel: nova tradução falhou — \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }

    private func replaceInPlace() {
        guard let current = session, current.canReplace else { return }
        // Outra tradução em curso: fechar agora perderia esta. O painel fica aberto.
        if AppState.shared.orchestrator.isBusy {
            AppLog.warning(.resultPanel, "Substituir adiado — outra tradução ainda está em andamento")
            NSSound.beep()
            return
        }
        AppLog.info(
            .resultPanel,
            "Botão «Substituir» (⏎) — colando \(current.translated.count) caracteres em \(current.targetApp?.localizedName ?? "o app de origem")"
        )
        let capture = current.capture
        let translated = current.translated
        let app = current.targetApp
        let handler = current.onReplace
        pendingClipboardRestore = nil
        session = nil
        closePanelChrome()
        Task { @MainActor in
            await handler?(capture, translated, app)
        }
    }

    /// Places the panel just below the selection (or above if it would go off-screen).
    private func position(_ panel: NSPanel, size: NSSize, near selection: CGRect?) {
        let gap: CGFloat = 10
        let anchor =
            selection.flatMap { $0.isEmpty ? nil : $0 }
            ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)

        let screen =
            NSScreen.screens.first { $0.frame.intersects(anchor) }
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

    private func consumeClipboardRestore() {
        let restore = pendingClipboardRestore
        pendingClipboardRestore = nil
        restore?()
    }

    // MARK: - Keyboard (nonactivating panel)

    private func installKeyMonitors() {
        removeKeyMonitors()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleLocalKeyDown(event) else { return event }
            return nil
        }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.close(reason: "Esc")
            }
        }
    }

    private func removeKeyMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }

    /// Returns true when the event was consumed.
    private func handleLocalKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            close(reason: "Esc")
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandOnly = flags.contains(.command)
            && !flags.contains(.shift)
            && !flags.contains(.option)
            && !flags.contains(.control)

        if commandOnly, event.charactersIgnoringModifiers?.lowercased() == "c" {
            copyAndClose(after: 0)
            return true
        }

        // Return / keypad Enter
        if session?.canReplace == true, event.keyCode == 36 || event.keyCode == 76 {
            replaceInPlace()
            return true
        }

        // Somente leitura: ⏎ aciona a ação principal, que é Copiar.
        if session?.canReplace == false, event.keyCode == 36 || event.keyCode == 76 {
            copyAndClose(after: 0)
            return true
        }

        return false
    }
}
