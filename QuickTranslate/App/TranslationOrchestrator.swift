import Foundation
import AppKit
import os

@MainActor
final class TranslationOrchestrator {
    private static let logger = Logger(subsystem: "com.quicktranslate", category: "Orchestrator")

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
    }

    /// Select (if needed) → translate → replace selection in place.
    func translateFocusedText(sendAfter: Bool) async {
        guard settings.isEnabled else {
            Self.logger.warning("⏭ tradução ignorada: app está desligado")
            onStatusChange?(.error("QuickTranslate está desligado — ligue nas Preferências"))
            return
        }

        // Staleness check: if a previous run has been stuck for too long, force-reset.
        if isRunning, let start = runStartDate {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > Self.maxRunDuration {
                Self.logger.error("🔓 isRunning preso há \(Int(elapsed))s — forçando reset")
                isRunning = false
                runStartDate = nil
            }
        }

        guard !isRunning else {
            Self.logger.warning("⏭ tradução ignorada: outra tradução em andamento")
            onStatusChange?(.error("Tradução anterior ainda em andamento — aguarde"))
            return
        }

        // Capture the currently active application so we can re-activate it before replacing text
        let targetApp = NSWorkspace.shared.frontmostApplication

        isRunning = true
        runStartDate = Date()
        defer {
            isRunning = false
            runStartDate = nil
            // If we borrowed the clipboard for read and never pasted (error / empty), restore it.
            textIO.finishPasteboardSession()
        }

        onStatusChange?(.translating)
        Self.logger.info("▶️ iniciando tradução (sendAfter=\(sendAfter), app=\(targetApp?.localizedName ?? "desconhecido", privacy: .public))")

        do {
            // 1) Auto-select when nothing is highlighted, then capture.
            Self.logger.debug("📋 lendo texto focado…")
            let capture = try await textIO.selectAndReadFocusedText()
            let trimmed = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Self.logger.warning("⚠️ texto capturado está vazio após trim")
                onStatusChange?(.error("Nenhum texto no campo focado"))
                return
            }
            Self.logger.info("📋 capturado \(trimmed.count) chars (didSelectAll=\(capture.didSelectAll))")

            // 2) Translate (selection may drop during this await — replace re-selects if needed).
            let sourceLang = settings.resolvedSourceLanguage ?? "auto"
            let targetLang = settings.targetLanguage
            let providerName = settings.providerKind.displayName
            Self.logger.info("🌐 traduzindo via '\(providerName, privacy: .public)' de '\(sourceLang, privacy: .public)' para '\(targetLang, privacy: .public)'…")
            let translated = try await engine.translate(
                trimmed,
                from: settings.resolvedSourceLanguage,
                to: settings.targetLanguage
            )
            Self.logger.info("🌐 tradução OK: \(translated.count) chars")

            let output = preserveSurroundingWhitespace(original: capture.text, translated: translated)

            // Re-activate target app if it lost focus during async translation
            if let targetApp, !targetApp.isActive {
                Self.logger.info("🎯 reativando app de origem '\(targetApp.localizedName ?? "", privacy: .public)'...")
                if #available(macOS 14.0, *) {
                    targetApp.activate()
                } else {
                    targetApp.activate(options: .activateIgnoringOtherApps)
                }
                try await Task.sleep(nanoseconds: 20_000_000)
            }

            // 3) Replace the selection with the translation.
            Self.logger.debug("✏️ substituindo seleção…")
            try await textIO.replaceSelection(capture, with: output)
            Self.logger.info("✅ substituição concluída")

            if sendAfter {
                try await Task.sleep(nanoseconds: 25_000_000)
                pressReturnHandler?()
                Self.logger.info("⏎ Return enviado")
            }

            onStatusChange?(.success)
        } catch {
            Self.logger.error("❌ erro na tradução: \(error.localizedDescription, privacy: .public)")
            onStatusChange?(.error(error.localizedDescription))
        }
    }

    private func preserveSurroundingWhitespace(original: String, translated: String) -> String {
        let leading = original.prefix(while: { $0.isWhitespace })
        let trailing = original.reversed().prefix(while: { $0.isWhitespace }).reversed()
        return String(leading) + translated.trimmingCharacters(in: .whitespacesAndNewlines) + String(trailing)
    }
}
