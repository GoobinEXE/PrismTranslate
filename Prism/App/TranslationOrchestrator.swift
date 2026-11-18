import AppKit
import Foundation

enum TranslationPresentation: Equatable {
    /// Translate and replace in place when editable; otherwise show popup (copy only).
    case replaceInPlace(sendAfter: Bool)
    /// Always show the result panel; Replace enabled when editable.
    case popup
}

/// Como a tradução foi disparada — atalho, Enter ou botão.
enum TranslationTrigger: Equatable {
    case hotkeyTranslateOnly(chord: String)
    case hotkeyTranslateAndSend(chord: String)
    case hotkeyPopup(chord: String)
    case enterKey

    var title: String {
        switch self {
        case .hotkeyTranslateOnly(let chord):
            return "atalho «Traduzir» (\(chord))"
        case .hotkeyTranslateAndSend(let chord):
            return "atalho «Traduzir e enviar» (\(chord))"
        case .hotkeyPopup(let chord):
            return "atalho «Painel» (\(chord))"
        case .enterKey:
            return "tecla Enter (modo «traduz e envia»)"
        }
    }

    var expectedOutcome: String {
        switch self {
        case .hotkeyTranslateOnly:
            return "traduz e substitui no campo, sem enviar"
        case .hotkeyTranslateAndSend, .enterKey:
            return "traduz, substitui e envia (Return)"
        case .hotkeyPopup:
            return "mostra o resultado no painel flutuante"
        }
    }
}

@MainActor
final class TranslationOrchestrator {
    private var settings: AppSettings
    private let engine: TranslationEngine
    private let textIO: FocusedTextIO
    private var isRunning = false
    /// Timestamp when `isRunning` was set to true; used for staleness detection.
    private var runStartDate: Date?
    /// Maximum time a translation can run before `isRunning` is forcibly reset.
    private static let maxRunDuration: TimeInterval = 45

    /// True while a capture/translate or a popup Replace is in flight.
    var isBusy: Bool { isRunning }

    var onStatusChange: ((AppState.Status) -> Void)?
    /// Original e tradução de cada tradução concluída (histórico curto do menu).
    var onTranslated: ((String, String) -> Void)?
    var pressReturnHandler: (() -> Void)?

    init(settings: AppSettings, engine: TranslationEngine, textIO: FocusedTextIO) {
        self.settings = settings
        self.engine = engine
        self.textIO = textIO
    }

    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
        AppLog.debug(
            .orchestrator,
            "Configuração do tradutor atualizada — motor \(settings.engineLogDescription), Prism \(settings.isEnabled ? "ligado" : "desligado"), painel \(settings.popupModeEnabled ? "ligado" : "desligado")"
        )
    }

    /// Select (if needed) → translate → replace or show result panel.
    func translateFocusedText(
        presentation: TranslationPresentation,
        trigger: TranslationTrigger
    ) async {
        let runID = AppLog.beginRun()
        let runStarted = Date()
        defer { AppLog.endRun() }

        AppLog.info(.orchestrator, "── Tradução \(runID) iniciada ──")
        AppLog.info(.orchestrator, "Disparo: \(trigger.title) — \(trigger.expectedOutcome)")
        AppLog.info(.orchestrator, "Motor: \(settings.engineLogDescription)")

        guard settings.isEnabled else {
            AppLog.warning(
                .orchestrator,
                "Ignorado: Prism está desligado. Ligue o interruptor no menu ou em Configurações."
            )
            onStatusChange?(.notice(.paused))
            AppLog.info(
                .orchestrator,
                "── Tradução \(runID) cancelada em \(AppLog.duration(since: runStarted)) — app desligado ──"
            )
            return
        }

        // Staleness check: if a previous run has been stuck for too long, force-reset.
        if isRunning, let start = runStartDate {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > Self.maxRunDuration {
                AppLog.error(
                    .orchestrator,
                    "Tradução anterior presa há \(Int(elapsed)) s — forçando reset para esta nova tentativa"
                )
                isRunning = false
                runStartDate = nil
            }
        }

        guard !isRunning else {
            AppLog.warning(
                .orchestrator,
                "Ignorado: outra tradução ainda está em andamento. Espere ela terminar e tente de novo."
            )
            // Sem trocar o status: o HUD continua em «Traduzindo…» da tradução em curso,
            // e um erro aqui faria o menu voltar a ocioso no meio dela.
            return
        }

        // Capture the currently active application so we can re-activate it before replacing text
        let targetApp = NSWorkspace.shared.frontmostApplication
        let appName = targetApp?.localizedName ?? "app desconhecido"
        AppLog.step(
            .orchestrator, 1, of: 4,
            "App em primeiro plano: \(appName) (\(targetApp?.bundleIdentifier ?? "sem bundle"), pid \(targetApp?.processIdentifier ?? -1))"
        )

        isRunning = true
        runStartDate = Date()
        /// Panel keeps the borrowed clipboard until dismiss so Copiar is not wiped.
        var holdPasteboardForPanel = false
        defer {
            isRunning = false
            runStartDate = nil
            if !holdPasteboardForPanel {
                textIO.finishPasteboardSession()
                AppLog.debug(.orchestrator, "Fim do run — sessão de clipboard encerrada")
            }
        }

        // Começa no ponteiro; assim que a captura informar onde está o texto, o aviso vai para lá.
        StatusHUDController.shared.setAnchor(nil)
        onStatusChange?(.translating)

        do {
            AppLog.step(.orchestrator, 2, of: 4, "Capturando o texto focado em \(appName)…")
            let preferReplaceInPlace: Bool
            let allowSelectAllWhenEditable: Bool
            switch presentation {
            case .replaceInPlace:
                preferReplaceInPlace = true
                allowSelectAllWhenEditable = true
            case .popup:
                // Painel é leitura: sem seleção, nunca ⌘A em host cego para Acessibilidade
                // (no Discord isso pegaria a conversa inteira). Campo editável ainda pode.
                preferReplaceInPlace = false
                allowSelectAllWhenEditable = false
            }
            let capture = try await textIO.selectAndReadFocusedText(
                preferReplaceInPlace: preferReplaceInPlace,
                allowSelectAllWhenEditable: allowSelectAllWhenEditable
            )
            StatusHUDController.shared.setAnchor(capture.selectionScreenRect)
            let trimmed = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                AppLog.warning(
                    .orchestrator,
                    "Nada para traduzir: o campo veio vazio (\(capture.logSummary))"
                )
                onStatusChange?(.notice(.init(message: String(localized: "No text in the focused field"))))
                AppLog.info(
                    .orchestrator,
                    "── Tradução \(runID) cancelada em \(AppLog.duration(since: runStarted)) — texto vazio ──"
                )
                return
            }
            AppLog.info(.orchestrator, "Captura: \(capture.logSummary)")
            AppLog.info(.orchestrator, "Prévia original: \"\(AppLog.preview(trimmed))\"")

            let incomingFrom = settings.resolvedSourceLanguage(outgoing: false)
            let incomingTo = settings.incomingTargetLanguage
            let outgoingFrom = settings.resolvedOutgoingSourceLanguage
            let outgoingTo = settings.outgoingTargetLanguage
            let detected = LanguageDetector.detect(in: trimmed)
            // Discord/Electron: seleção no compose chega como só-leitura. Se o texto já
            // está no idioma de leitura, o par auto→pt é recusado pela Apple — usa o de escrita.
            var usedOutgoingPair = capture.isEditable
            if !capture.isEditable,
                let detected,
                LanguageCode.normalize(detected) == LanguageCode.normalize(incomingTo),
                LanguageCode.normalize(outgoingTo) != LanguageCode.normalize(incomingTo)
            {
                usedOutgoingPair = true
                AppLog.info(
                    .orchestrator,
                    "Texto já em \(LanguageCode.displayName(for: detected)) (idioma de leitura) — usando o par de escrita \(LanguageCode.pairLabel(from: outgoingFrom, to: outgoingTo))"
                )
            }

            // Texto que você escreve já no idioma de destino: traduzir de novo só estraga.
            // Com «traduzir e enviar», apenas envia; sem enviar, avisa.
            if case .replaceInPlace(let sendAfter) = presentation,
                capture.isEditable, usedOutgoingPair,
                let detected,
                LanguageCode.normalize(detected) == LanguageCode.normalize(outgoingTo)
            {
                let language = LanguageCode.displayName(for: outgoingTo)
                if sendAfter {
                    AppLog.info(.orchestrator, "Texto já em \(language) — sem traduzir, só enviando")
                    pressReturnHandler?()
                    // Sem tradução, a mensagem enviada é o próprio retorno: nada de aviso.
                    onStatusChange?(.idle)
                } else {
                    AppLog.info(.orchestrator, "Texto já em \(language) — nada a traduzir")
                    onStatusChange?(.notice(.init(message: String(format: String(localized: "The text is already in %@."), language))))
                }
                return
            }

            var from = usedOutgoingPair ? outgoingFrom : incomingFrom
            var to = usedOutgoingPair ? outgoingTo : incomingTo
            let pairKind = usedOutgoingPair ? "texto que você escreve" : "texto que você lê"
            AppLog.step(
                .orchestrator, 3, of: 4,
                "Traduzindo \(LanguageCode.pairLabel(from: from, to: to)) via \(settings.engineLogDescription) (par: \(pairKind))"
            )
            let translateStarted = Date()
            let outcome: TranslationOutcome
            do {
                outcome = try await engine.translate(
                    trimmed,
                    from: from,
                    to: to
                )
            } catch {
                let canRetryOutgoing =
                    !usedOutgoingPair
                    && LanguageCode.normalize(outgoingTo) != LanguageCode.normalize(incomingTo)
                    && (error as? TranslationError)?.isUnsupportedLanguagePair == true
                guard canRetryOutgoing else { throw error }
                AppLog.info(
                    .orchestrator,
                    "Par de leitura recusado — tentando o par de escrita \(LanguageCode.pairLabel(from: outgoingFrom, to: outgoingTo))"
                )
                from = outgoingFrom
                to = outgoingTo
                usedOutgoingPair = true
                outcome = try await engine.translate(
                    trimmed,
                    from: from,
                    to: to
                )
            }
            AppLog.info(
                .orchestrator,
                "Tradução pronta em \(AppLog.duration(since: translateStarted)) — \(outcome.text.count) caracteres"
                    + (outcome.detectedSourceLanguage.map {
                        ", origem detectada: \(LanguageCode.displayName(for: $0))"
                    } ?? "")
            )
            AppLog.info(.orchestrator, "Prévia traduzida: \"\(AppLog.preview(outcome.text))\"")

            let output = preserveSurroundingWhitespace(
                original: capture.text, translated: outcome.text)
            onTranslated?(trimmed, outcome.text)
            if let failed = outcome.fallbackFrom {
                StatusHUDController.shared.offerNote(
                    String(format: String(localized: "%@ failed, so this Mac translated it."), failed))
            }

            let action = TranslationActionPolicy.resolve(
                presentation: presentation,
                capture: capture
            )
            let showPanel = action.showPanel
            let canReplace = action.canReplace
            let sendAfter = action.sendAfter

            if showPanel {
                let sourceLabel: String
                if let from {
                    sourceLabel = LanguageCode.displayName(for: from)
                } else if let detected = outcome.detectedSourceLanguage {
                    sourceLabel = LanguageCode.displayName(for: detected)
                } else {
                    sourceLabel = LanguageCode.displayName(for: LanguageCode.systemLanguage)
                }
                let targetLabel = LanguageCode.displayName(for: to)
                let replaceHint =
                    canReplace
                    ? "botão Substituir habilitado (⏎)"
                    : "só Copiar (⌘C) — campo não é editável"
                AppLog.step(
                    .orchestrator, 4, of: 4,
                    "Abrindo painel \(sourceLabel) → \(targetLabel) — \(replaceHint)"
                )
                holdPasteboardForPanel = true
                // Linha de base do clipboard na abertura do painel: se o usuário copiar
                // algo enquanto o painel está aberto, o fechamento não restaura por cima.
                let pasteboardBaseline = NSPasteboard.general.changeCount
                TranslationResultPanelController.shared.show(
                    .init(
                        original: capture.text,
                        translated: output,
                        canReplace: canReplace,
                        showOriginal: canReplace,
                        sourceLanguageLabel: sourceLabel,
                        targetLanguageLabel: targetLabel,
                        pairContextLabel: usedOutgoingPair
                            ? String(localized: "Text I write")
                            : String(localized: "Text I read"),
                        capture: capture,
                        targetApp: targetApp,
                        onReplace: { [weak self] capture, text, app in
                            await self?.performReplaceFromPanel(
                                capture: capture, text: text, targetApp: app)
                        },
                        onDismissWithoutReplace: { [weak self] in
                            self?.textIO.finishPasteboardSession(onlyIfChangeCount: pasteboardBaseline)
                        },
                        onKeepClipboard: { [weak self] in
                            self?.textIO.discardPasteboardSession()
                        },
                        targetLanguageCode: to,
                        retranslate: retranslator(text: trimmed, original: capture.text, from: from),
                        notice: outcome.fallbackFrom.map {
                            String(format: String(localized: "%@ failed, so this Mac translated it."), $0)
                        }
                    )
                )
                onStatusChange?(.success)
                AppLog.info(
                    .orchestrator,
                    "── Tradução \(runID) concluída em \(AppLog.duration(since: runStarted)) — painel aberto em \(appName) ──"
                )
                return
            }

            AppLog.step(
                .orchestrator, 4, of: 4,
                sendAfter
                    ? "Substituindo o texto no campo e enviando Return"
                    : "Substituindo o texto no campo (sem enviar)"
            )
            try await performReplace(capture: capture, text: output, targetApp: targetApp)

            if sendAfter {
                try await Task.sleep(nanoseconds: 25_000_000)
                AppLog.info(.orchestrator, "Enviando tecla Return (traduzir e enviar)")
                pressReturnHandler?()
            } else {
                // Mensagem enviada não se desfaz; substituição simples, sim.
                StatusHUDController.shared.offerUndo { [weak self] in
                    self?.undoLastReplace(in: targetApp)
                }
            }

            onStatusChange?(sendAfter ? .sent : .success)
            let ending = sendAfter ? "texto substituído e enviado" : "texto substituído"
            AppLog.info(
                .orchestrator,
                "── Tradução \(runID) concluída em \(AppLog.duration(since: runStarted)) — \(ending) em \(appName) ──"
            )
        } catch {
            AppLog.error(
                .orchestrator,
                "Falhou: \(error.localizedDescription)"
            )
            AppLog.debug(.orchestrator, "Erro técnico: \(error.debugLogSummary)")
            onStatusChange?(.error(error.localizedDescription))
            AppLog.error(
                .orchestrator,
                "── Tradução \(runID) falhou em \(AppLog.duration(since: runStarted)) — \(error.localizedDescription) ──"
            )
        }
    }

    /// Replace from the popup — holds `isRunning` so a concurrent hotkey cannot
    /// capture/paste while the clipboard session is still in use.
    private func performReplaceFromPanel(
        capture: FocusedTextCapture,
        text: String,
        targetApp: NSRunningApplication?
    ) async {
        if isRunning, let start = runStartDate {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > Self.maxRunDuration {
                isRunning = false
                runStartDate = nil
            }
        }
        guard !isRunning else {
            AppLog.warning(
                .orchestrator,
                "Ignorado: substituição do painel enquanto outra tradução ainda corre"
            )
            onStatusChange?(.notice(.init(message: String(localized: "Previous translation still running — wait"))))
            return
        }
        isRunning = true
        runStartDate = Date()
        defer {
            isRunning = false
            runStartDate = nil
            textIO.finishPasteboardSession()
        }
        do {
            try await performReplace(capture: capture, text: text, targetApp: targetApp)
            StatusHUDController.shared.setAnchor(capture.selectionScreenRect)
            StatusHUDController.shared.offerUndo { [weak self] in
                self?.undoLastReplace(in: targetApp)
            }
            onStatusChange?(.success)
        } catch {
            AppLog.error(
                .orchestrator,
                "Não deu para substituir o texto: \(error.localizedDescription)"
            )
            AppLog.debug(
                .orchestrator, "Erro técnico na substituição: \(error.debugLogSummary)")
            onStatusChange?(.error(error.localizedDescription))
        }
    }

    private func performReplace(
        capture: FocusedTextCapture,
        text: String,
        targetApp: NSRunningApplication?
    ) async throws {
        let trimmedOutput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            throw TranslationError.emptyResponse
        }
        if let targetApp, !targetApp.isActive {
            AppLog.info(
                .orchestrator,
                "Reativando \(targetApp.localizedName ?? "o app de origem") (pid \(targetApp.processIdentifier)) para colar a tradução"
            )
            if #available(macOS 14.0, *) {
                targetApp.activate()
            } else {
                targetApp.activate(options: .activateIgnoringOtherApps)
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        AppLog.info(
            .orchestrator,
            "Substituindo seleção — \(text.count) caracteres (\(capture.logSummary))"
        )
        try await textIO.replaceSelection(capture, with: text)
        AppLog.info(.orchestrator, "Substituição concluída")
    }

    /// Desfaz a substituição com ⌘Z no app de origem: a colagem (e a escrita via
    /// Acessibilidade na maioria dos campos nativos) entra no histórico de desfazer dele.
    private func undoLastReplace(in targetApp: NSRunningApplication?) {
        AppLog.info(.orchestrator, "«Desfazer» no aviso — enviando ⌘Z para \(targetApp?.localizedName ?? "o app de origem")")
        Task { @MainActor in
            if let targetApp, !targetApp.isActive {
                targetApp.activate()
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
            KeyboardSimulator.pressCommandKey("z")
        }
    }

    /// Tradução para outro destino a partir do painel (menu de idioma no topo).
    private func retranslator(
        text: String, original: String, from: String?
    ) -> (String) async throws -> String {
        { [weak self] target in
            guard let self else { throw CancellationError() }
            AppLog.info(.orchestrator, "Painel: traduzindo de novo para \(LanguageCode.displayName(for: target))")
            let outcome = try await self.engine.translate(text, from: from, to: target)
            self.onTranslated?(text, outcome.text)
            return self.preserveSurroundingWhitespace(original: original, translated: outcome.text)
        }
    }

    /// Traduz o texto que já está na área de transferência e mostra no painel (só Copiar).
    /// Útil quando não há seleção, por exemplo texto copiado de um PDF protegido.
    func translateClipboard() async {
        guard settings.isEnabled else {
            onStatusChange?(.notice(.paused))
            return
        }
        guard !isRunning else { return }
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onStatusChange?(.notice(.init(message: String(localized: "The clipboard has no text to translate."))))
            return
        }
        isRunning = true
        runStartDate = Date()
        defer {
            isRunning = false
            runStartDate = nil
        }
        StatusHUDController.shared.setAnchor(nil)
        onStatusChange?(.translating)
        // Mesma regra do atalho: texto já no idioma de leitura (ex.: algo que você
        // escreveu em português) vai para o idioma de escrita; a Apple recusa pt → pt.
        var from = settings.resolvedSourceLanguage(outgoing: false)
        var to = settings.incomingTargetLanguage
        if let detected = LanguageDetector.detect(in: trimmed),
            LanguageCode.normalize(detected) == LanguageCode.normalize(to)
        {
            let outgoingTo = settings.outgoingTargetLanguage
            guard LanguageCode.normalize(outgoingTo) != LanguageCode.normalize(to) else {
                onStatusChange?(.notice(.init(message: String(format: String(localized: "The text is already in %@."), LanguageCode.displayName(for: to)))))
                return
            }
            AppLog.info(.orchestrator, "Área de transferência já em \(LanguageCode.displayName(for: detected)) — usando o idioma de escrita")
            from = detected
            to = outgoingTo
        }
        AppLog.info(.orchestrator, "Traduzindo a área de transferência — \(trimmed.count) caracteres, \(LanguageCode.pairLabel(from: from, to: to))")
        do {
            let outcome = try await engine.translate(trimmed, from: from, to: to)
            onTranslated?(trimmed, outcome.text)
            let sourceLabel = LanguageCode.displayName(
                for: from ?? outcome.detectedSourceLanguage ?? LanguageCode.systemLanguage)
            TranslationResultPanelController.shared.show(
                .init(
                    original: trimmed,
                    translated: outcome.text,
                    canReplace: false,
                    showOriginal: true,
                    sourceLanguageLabel: sourceLabel,
                    targetLanguageLabel: LanguageCode.displayName(for: to),
                    pairContextLabel: String(localized: "Clipboard"),
                    capture: FocusedTextCapture(text: trimmed, didSelectAll: false, isEditable: false),
                    targetApp: nil,
                    onReplace: nil,
                    onDismissWithoutReplace: nil,
                    onKeepClipboard: nil,
                    targetLanguageCode: to,
                    retranslate: retranslator(text: trimmed, original: trimmed, from: from),
                    notice: outcome.fallbackFrom.map {
                        String(format: String(localized: "%@ failed, so this Mac translated it."), $0)
                    }
                )
            )
            onStatusChange?(.success)
        } catch {
            AppLog.error(.orchestrator, "Tradução da área de transferência falhou: \(error.localizedDescription)")
            onStatusChange?(.error(error.localizedDescription))
        }
    }

    private func preserveSurroundingWhitespace(original: String, translated: String) -> String {
        let leading = original.prefix(while: { $0.isWhitespace })
        let trailing = original.reversed().prefix(while: { $0.isWhitespace }).reversed()
        return String(leading) + translated.trimmingCharacters(in: .whitespacesAndNewlines)
            + String(trailing)
    }
}
