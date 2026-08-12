import Foundation
import AppKit

enum TranslationPresentation: Equatable {
    /// Translate and replace in place when editable; otherwise show popup (copy only).
    case replaceInPlace(sendAfter: Bool)
    /// Always show the result panel; Replace enabled when editable.
    case popup
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

    var onStatusChange: ((AppState.Status) -> Void)?
    var pressReturnHandler: (() -> Void)?

    init(settings: AppSettings, engine: TranslationEngine, textIO: FocusedTextIO) {
        self.settings = settings
        self.engine = engine
        self.textIO = textIO
    }

    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
        AppLog.info(
            .orchestrator,
            "settings atualizados (enabled=\(settings.isEnabled), provider=\(settings.providerKind.displayName), popup=\(settings.popupModeEnabled))"
        )
    }

    /// Backward-compatible entry used by existing call sites.
    func translateFocusedText(sendAfter: Bool) async {
        await translateFocusedText(presentation: .replaceInPlace(sendAfter: sendAfter))
    }

    /// Select (if needed) → translate → replace or show result panel.
    func translateFocusedText(presentation: TranslationPresentation) async {
        let runID = AppLog.beginRun()
        defer { AppLog.endRun() }

        AppLog.info(
            .orchestrator,
            "▶︎ início — presentation=\(String(describing: presentation)), enabled=\(settings.isEnabled), provider=\(settings.providerKind.displayName)"
        )

        guard settings.isEnabled else {
            AppLog.warning(.orchestrator, "tradução ignorada: app está desligado")
            onStatusChange?(.error("QuickTranslate está desligado — ligue nas Preferências"))
            return
        }

        // Staleness check: if a previous run has been stuck for too long, force-reset.
        if isRunning, let start = runStartDate {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > Self.maxRunDuration {
                AppLog.error(.orchestrator, "isRunning preso há \(Int(elapsed))s — forçando reset")
                isRunning = false
                runStartDate = nil
            }
        }

        guard !isRunning else {
            AppLog.warning(.orchestrator, "tradução ignorada: outra tradução em andamento (run anterior)")
            onStatusChange?(.error("Tradução anterior ainda em andamento — aguarde"))
            return
        }

        // Capture the currently active application so we can re-activate it before replacing text
        let targetApp = NSWorkspace.shared.frontmostApplication
        AppLog.info(
            .orchestrator,
            "app alvo: name=\(targetApp?.localizedName ?? "nil"), bundle=\(targetApp?.bundleIdentifier ?? "nil"), pid=\(targetApp?.processIdentifier ?? -1)"
        )

        isRunning = true
        runStartDate = Date()
        defer {
            isRunning = false
            runStartDate = nil
            // If we borrowed the clipboard for read and never pasted (error / empty), restore it.
            textIO.finishPasteboardSession()
            AppLog.debug(.orchestrator, "fim do run — isRunning=false, pasteboard session finalizada")
        }

        onStatusChange?(.translating)

        do {
            // 1) Auto-select when nothing is highlighted (editable only), then capture.
            AppLog.info(.orchestrator, "etapa 1/3 — capturando texto focado")
            let capture = try await textIO.selectAndReadFocusedText()
            let trimmed = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                AppLog.warning(
                    .orchestrator,
                    "texto capturado vazio após trim (rawLen=\(capture.text.count), editable=\(capture.isEditable), didSelectAll=\(capture.didSelectAll), clipboard=\(capture.usedClipboardForRead))"
                )
                onStatusChange?(.error("Nenhum texto no campo focado"))
                return
            }
            let preview = Self.preview(trimmed)
            AppLog.info(
                .orchestrator,
                "captura OK — chars=\(trimmed.count), didSelectAll=\(capture.didSelectAll), editable=\(capture.isEditable), clipboardRead=\(capture.usedClipboardForRead), rect=\(String(describing: capture.selectionScreenRect)), preview=\"\(preview)\""
            )

            // 2) Translate with the pair for this context (incoming = read-only, outgoing = editable).
            let useOutgoing = capture.isEditable
            let from = settings.resolvedSourceLanguage(outgoing: useOutgoing)
            let to = settings.targetLanguage(outgoing: useOutgoing)
            let sourceLang = from ?? "auto"
            let providerName = settings.providerKind.displayName
            AppLog.info(
                .orchestrator,
                "etapa 2/3 — traduzindo via '\(providerName)' \(sourceLang) → \(to) (outgoingPair=\(useOutgoing))"
            )
            let translateStarted = Date()
            let outcome = try await engine.translate(
                trimmed,
                from: from,
                to: to
            )
            let translateMs = Int(Date().timeIntervalSince(translateStarted) * 1000)
            AppLog.info(
                .orchestrator,
                "tradução OK — \(outcome.text.count) chars em \(translateMs)ms, detected=\(outcome.detectedSourceLanguage ?? "nil"), preview=\"\(Self.preview(outcome.text))\""
            )

            let output = preserveSurroundingWhitespace(original: capture.text, translated: outcome.text)

            let showPanel: Bool
            let canReplace: Bool
            let sendAfter: Bool
            switch presentation {
            case .replaceInPlace(let send):
                showPanel = !capture.isEditable
                canReplace = false
                sendAfter = send
            case .popup:
                showPanel = true
                canReplace = capture.isEditable
                sendAfter = false
            }

            AppLog.info(
                .orchestrator,
                "etapa 3/3 — decisão de saída: showPanel=\(showPanel), canReplace=\(canReplace), sendAfter=\(sendAfter)"
            )

            if showPanel {
                let sourceLabel: String
                if let from {
                    sourceLabel = LanguageCode.displayName(for: from)
                } else if let detected = outcome.detectedSourceLanguage {
                    sourceLabel = LanguageCode.displayName(for: detected)
                } else {
                    // Last resort — should be rare after on-device NLLanguageRecognizer fallback.
                    sourceLabel = LanguageCode.displayName(for: LanguageCode.systemLanguage)
                }
                let targetLabel = LanguageCode.displayName(for: to)
                AppLog.info(
                    .orchestrator,
                    "abrindo painel — source=\(sourceLabel), target=\(targetLabel), canReplace=\(canReplace)"
                )
                TranslationResultPanelController.shared.show(
                    .init(
                        original: capture.text,
                        translated: output,
                        canReplace: canReplace,
                        showOriginal: canReplace,
                        sourceLanguageLabel: sourceLabel,
                        targetLanguageLabel: targetLabel,
                        capture: capture,
                        targetApp: targetApp,
                        onReplace: { [weak self] capture, text, app in
                            await self?.performReplace(capture: capture, text: text, targetApp: app)
                        }
                    )
                )
                onStatusChange?(.success)
                AppLog.info(.orchestrator, "run \(runID) concluído com sucesso (painel)")
                return
            }

            // 3) Replace the selection with the translation.
            await performReplace(capture: capture, text: output, targetApp: targetApp)

            if sendAfter {
                try await Task.sleep(nanoseconds: 25_000_000)
                AppLog.info(.orchestrator, "enviando Return (translate-and-send)")
                pressReturnHandler?()
            }

            onStatusChange?(.success)
            AppLog.info(.orchestrator, "run \(runID) concluído com sucesso (replace)")
        } catch {
            AppLog.error(
                .orchestrator,
                "run \(runID) falhou: \(error.localizedDescription) | \(String(describing: error))"
            )
            onStatusChange?(.error(error.localizedDescription))
        }
    }

    private func performReplace(
        capture: FocusedTextCapture,
        text: String,
        targetApp: NSRunningApplication?
    ) async {
        do {
            if let targetApp, !targetApp.isActive {
                AppLog.info(
                    .orchestrator,
                    "reativando app de origem '\(targetApp.localizedName ?? "")' (pid=\(targetApp.processIdentifier))"
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
                "substituindo seleção — chars=\(text.count), didSelectAll=\(capture.didSelectAll), clipboardPath=\(capture.usedClipboardForRead)"
            )
            try await textIO.replaceSelection(capture, with: text)
            AppLog.info(.orchestrator, "substituição concluída")
            onStatusChange?(.success)
        } catch {
            AppLog.error(
                .orchestrator,
                "erro ao substituir: \(error.localizedDescription) | \(String(describing: error))"
            )
            onStatusChange?(.error(error.localizedDescription))
        }
    }

    private func preserveSurroundingWhitespace(original: String, translated: String) -> String {
        let leading = original.prefix(while: { $0.isWhitespace })
        let trailing = original.reversed().prefix(while: { $0.isWhitespace }).reversed()
        return String(leading) + translated.trimmingCharacters(in: .whitespacesAndNewlines) + String(trailing)
    }

    private static func preview(_ text: String, max: Int = 80) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: "⇥")
        if flat.count <= max { return flat }
        return String(flat.prefix(max)) + "…"
    }
}
