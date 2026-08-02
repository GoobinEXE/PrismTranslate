import Combine
import Foundation
import os
import SwiftUI
import Translation

/// View-facing state of the Apple Translation language packs for a pair.
enum LanguagePackState: Equatable {
    case checking
    case installed
    case needsDownload
    case downloading
    case unsupported
    case failed(String)

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Coordinates programmatic Apple Translation via a hidden SwiftUI host.
@MainActor
@available(macOS 15.0, *)
final class AppleTranslationBridge: ObservableObject {
    private static let logger = Logger(subsystem: "com.quicktranslate", category: "AppleTranslationBridge")
    struct Request {
        let id: UUID
        let text: String
        let source: Locale.Language?
        let target: Locale.Language
        /// True when offline language packs are not installed yet.
        let packsLikelyMissing: Bool
        /// When true, always run `prepareTranslation()` (onboarding / Preferências).
        let forcePrepare: Bool
        let continuation: CheckedContinuation<String, Error>
    }

    private struct AvailabilityCacheEntry {
        let packsLikelyMissing: Bool
        let checkedAt: Date
    }

    @Published var configuration: TranslationSession.Configuration?
    private var pending: Request?
    private var timeoutTask: Task<Void, Never>?
    /// Tracks whether the current request has already been retried (avoid infinite loop).
    private var hasRetried = false
    /// Cached LanguageAvailability results keyed by normalized source|target.
    private var availabilityCache: [String: AvailabilityCacheEntry] = [:]
    /// Last published language pair — used to invalidate instead of clear+republish.
    private var publishedPairKey: String?

    /// Notifies the host panel when a request may need the language-download sheet
    /// (true = bring the host window on-screen, false = hide it again).
    var onActivity: ((Bool) -> Void)?

    /// How long to wait for `.translationTask` to pick up a request before failing.
    /// macOS 26's translationd can take longer to spin up on first use after boot.
    private static let requestTimeoutNs: UInt64 = 30_000_000_000
    private static let availabilityCacheTTL: TimeInterval = 300

    func translate(_ text: String, from: String?, to: String) async throws -> String {
        try await enqueue(
            text: text,
            from: from,
            to: to,
            forcePrepare: false
        )
    }

    /// Asks the system download sheet for offline language packs (onboarding / Preferências).
    func ensureLanguagePacks(from: String?, to: String) async throws {
        invalidateAvailabilityCache(from: from, to: to)
        _ = try await enqueue(
            text: Self.sampleText(target: to),
            from: from,
            to: to,
            forcePrepare: true
        )
    }

    /// Publishes a configuration early so the first real translate hits a warm session.
    func prewarm(from: String?, to: String) {
        let sourceLang: Locale.Language? = from.map { Locale.Language(identifier: normalize($0)) }
        let targetLang = Locale.Language(identifier: normalize(to))
        guard pending == nil else { return }
        Self.logger.info("🍏 prewarming session for \(self.pairKey(source: sourceLang, target: targetLang), privacy: .public)")
        publishConfiguration(source: sourceLang, target: targetLang, forceNew: false)
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.checkAvailability(
                source: sourceLang,
                target: targetLang,
                sampleText: Self.sampleText(target: to)
            )
        }
    }

    private func enqueue(
        text: String,
        from: String?,
        to: String,
        forcePrepare: Bool
    ) async throws -> String {
        let sourceLang: Locale.Language? = from.map { Locale.Language(identifier: normalize($0)) }
        let targetLang = Locale.Language(identifier: normalize(to))

        // Fail fast on unsupported pairs. Pack status is advisory — online vs offline
        // follows System Settings › Translation Languages › On-Device Mode.
        let packsLikelyMissing = try await checkAvailability(
            source: sourceLang,
            target: targetLang,
            sampleText: text
        )

        if forcePrepare {
            onActivity?(true)
        }

        return try await withCheckedThrowingContinuation { continuation in
            if let previous = pending {
                previous.continuation.resume(
                    throwing: TranslationError.appleTranslationFailed("Tradução anterior cancelada")
                )
                pending = nil
            }

            hasRetried = false

            let request = Request(
                id: UUID(),
                text: text,
                source: sourceLang,
                target: targetLang,
                packsLikelyMissing: packsLikelyMissing,
                forcePrepare: forcePrepare,
                continuation: continuation
            )
            pending = request
            scheduleTimeout(for: request.id)

            Self.logger.info("🍏 enqueuing translation request \(request.id.uuidString, privacy: .public)")
            publishConfiguration(source: sourceLang, target: targetLang, forceNew: false)
        }
    }

    func handle(session: TranslationSession) async {
        Self.logger.info("🍏 handle(session:) received session!")
        guard let request = pending else {
            // Prewarm / leftover session — keep configuration warm, ignore.
            Self.logger.debug("🍏 handle(session:) with no pending request — keeping warm session")
            return
        }
        pending = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        do {
            let translated = try await translateRespectingSystemMode(session: session, request: request)
            Self.logger.info("🍏 translation session returned successfully!")
            // Packs that were missing are now likely installed after a successful prepare path.
            if request.packsLikelyMissing || request.forcePrepare {
                cacheAvailability(
                    source: request.source,
                    target: request.target,
                    packsLikelyMissing: false
                )
            }
            request.continuation.resume(returning: translated)
        } catch {
            Self.logger.error("🍏 translation session error: \(error.localizedDescription, privacy: .public)")
            // Stale "installed" cache can hide a missing pack — recheck next time.
            if Self.isMissingLanguagePack(error) {
                invalidateAvailabilityCache(
                    source: request.source,
                    target: request.target
                )
            }
            let message = Self.userFacingMessage(
                for: error,
                packsLikelyMissing: request.packsLikelyMissing || request.forcePrepare
            )
            request.continuation.resume(
                throwing: TranslationError.appleTranslationFailed(message)
            )
        }
        // Keep configuration published so the next request can invalidate() without a cold restart.
        onActivity?(false)
    }

    /// Honors On-Device Mode via `translationd`: online when the checkbox is off,
    /// downloaded packs when it is on. Downloads are prompted only when needed.
    private func translateRespectingSystemMode(
        session: TranslationSession,
        request: Request
    ) async throws -> String {
        if request.forcePrepare {
            try await prepareIfPossible(session: session, request: request)
            return try await session.translate(request.text).targetText
        }

        // macOS 26+: the session needs to be warmed up with prepareTranslation()
        // when the packs are installed but not yet loaded into memory. Trying to
        // translate directly on Tahoe often throws "Unable to Translate".
        if #available(macOS 26.0, *) {
            if await session.isReady {
                do {
                    return try await session.translate(request.text).targetText
                } catch {
                    if !(request.packsLikelyMissing || Self.isMissingLanguagePack(error)) {
                        throw error
                    }
                    // Fall through to prepare + retry.
                }
            } else {
                // Session not ready — warm it up before translating.
                // This is critical on macOS 26 where the session doesn't
                // auto-load offline packs without an explicit prepare.
                if request.source != nil {
                    try await session.prepareTranslation()
                }
            }
        }

        // Online path (On-Device Mode off) often works without installed packs.
        do {
            return try await session.translate(request.text).targetText
        } catch {
            guard request.packsLikelyMissing || Self.isMissingLanguagePack(error) else {
                throw error
            }
            onActivity?(true)
            try await prepareIfPossible(session: session, request: request)
            return try await session.translate(request.text).targetText
        }
    }

    /// `prepareTranslation()` requires a concrete source language — with auto-detect
    /// (`source == nil`) Apple throws unableToIdentifyLanguage, so skip and rely on
    /// System Settings / a configured source instead.
    private func prepareIfPossible(
        session: TranslationSession,
        request: Request
    ) async throws {
        if request.source == nil {
            throw TranslationError.appleTranslationFailed(
                "Defina o idioma de origem ou baixe os pacotes em Ajustes › Geral › Idioma e Região › Idiomas de Tradução"
            )
        }
        try await session.prepareTranslation()
    }

    private static func isMissingLanguagePack(_ error: Error) -> Bool {
        // Avoid clashing with our own `TranslationError` enum — match the framework error by text.
        let reflected = String(reflecting: error).lowercased()
        if reflected.contains("notinstalled") { return true }
        let text = error.localizedDescription.lowercased()
        return text.contains("not installed")
            || text.contains("não instalad")
            || text.contains("download")
            || text.contains("unable to translate")
    }

    private static func userFacingMessage(for error: Error, packsLikelyMissing: Bool) -> String {
        let raw = error.localizedDescription
        // Always attach recovery hints for the opaque system failure.
        if packsLikelyMissing || isMissingLanguagePack(error)
            || raw.localizedCaseInsensitiveContains("unable to translate") {
            return "\(raw). Com “Modo no dispositivo” ligado, baixe os idiomas (origem e destino) em Ajustes do Sistema › Geral › Idioma e Região › Idiomas de Tradução — ou desligue o modo para traduzir online."
        }
        return raw
    }

    func failPending(_ error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.continuation.resume(throwing: error)
        pending = nil
        // Drop the warm session only on hard failure so the next attempt starts clean.
        configuration = nil
        publishedPairKey = nil
        onActivity?(false)
    }

    // MARK: - Language packs

    /// Language pair the app will most likely use: configured source (or system
    /// language) → target. Falls back to auto-detect when both would be equal.
    static func defaultPackPair(settings: AppSettings) -> (source: String?, target: String) {
        let target = settings.targetLanguage
        let source = settings.resolvedSourceLanguage ?? LanguageCode.systemLanguage
        return source == target ? (nil, target) : (source, target)
    }

    /// Pack state for a pair; source nil = auto-detect from a sample phrase.
    func languagePackState(from: String?, to: String) async -> LanguagePackState {
        let sourceLang: Locale.Language? = from.map { Locale.Language(identifier: normalize($0)) }
        let targetLang = Locale.Language(identifier: normalize(to))
        switch await availabilityStatus(
            source: sourceLang,
            target: targetLang,
            sampleText: Self.sampleText(target: to)
        ) {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .needsDownload
        }
    }

    /// Sample phrase in a language different from the target so detection works.
    private static func sampleText(target: String) -> String {
        target.hasPrefix("en") ? "Olá, mundo!" : "Hello, world!"
    }

    private func availabilityStatus(
        source: Locale.Language?,
        target: Locale.Language,
        sampleText: String
    ) async -> LanguageAvailability.Status {
        let availability = LanguageAvailability()
        if let source {
            return await availability.status(from: source, to: target)
        }
        // Auto-detect source from the text; assume supported when detection fails.
        return (try? await availability.status(for: sampleText, to: target)) ?? .supported
    }

    /// Returns true when the pair is supported but the language pack still needs downloading.
    private func checkAvailability(
        source: Locale.Language?,
        target: Locale.Language,
        sampleText: String
    ) async throws -> Bool {
        let key = pairKey(source: source, target: target)
        if let cached = availabilityCache[key],
           Date().timeIntervalSince(cached.checkedAt) < Self.availabilityCacheTTL {
            Self.logger.debug("🍏 availability cache hit for \(key, privacy: .public)")
            return cached.packsLikelyMissing
        }

        switch await availabilityStatus(source: source, target: target, sampleText: sampleText) {
        case .unsupported:
            availabilityCache.removeValue(forKey: key)
            throw TranslationError.appleTranslationFailed(
                "Par de idiomas não suportado — escolha outro idioma ou provedor"
            )
        case .supported:
            cacheAvailability(source: source, target: target, packsLikelyMissing: true)
            return true
        case .installed:
            cacheAvailability(source: source, target: target, packsLikelyMissing: false)
            return false
        @unknown default:
            return false
        }
    }

    private func cacheAvailability(
        source: Locale.Language?,
        target: Locale.Language,
        packsLikelyMissing: Bool
    ) {
        let key = pairKey(source: source, target: target)
        availabilityCache[key] = AvailabilityCacheEntry(
            packsLikelyMissing: packsLikelyMissing,
            checkedAt: Date()
        )
    }

    private func invalidateAvailabilityCache(from: String?, to: String) {
        let sourceLang: Locale.Language? = from.map { Locale.Language(identifier: normalize($0)) }
        let targetLang = Locale.Language(identifier: normalize(to))
        invalidateAvailabilityCache(source: sourceLang, target: targetLang)
    }

    private func invalidateAvailabilityCache(source: Locale.Language?, target: Locale.Language) {
        availabilityCache.removeValue(forKey: pairKey(source: source, target: target))
    }

    private func pairKey(source: Locale.Language?, target: Locale.Language) -> String {
        let sourceID = source?.maximalIdentifier ?? "auto"
        return "\(sourceID)|\(target.maximalIdentifier)"
    }

    /// If `.translationTask` never picks up the request (host view unmounted, session broken),
    /// retry once by re-publishing the configuration, then fail on second timeout.
    private func scheduleTimeout(for id: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.requestTimeoutNs)
            guard !Task.isCancelled,
                  let self,
                  let request = self.pending,
                  request.id == id else { return }

            // Retry once: force a brand-new configuration so `.translationTask` restarts.
            if !self.hasRetried {
                self.hasRetried = true
                self.publishConfiguration(
                    source: request.source,
                    target: request.target,
                    forceNew: true
                )
                self.scheduleTimeout(for: request.id)
                return
            }

            self.failPending(TranslationError.appleTranslationFailed(
                "Tempo esgotado — com “Modo no dispositivo” ligado, baixe os idiomas em Ajustes › Geral › Idioma e Região › Idiomas de Tradução"
            ))
        }
    }

    /// Publishes or invalidates the translation configuration.
    /// Prefer `invalidate()` on the same pair to avoid a clear + run-loop hop.
    private func publishConfiguration(
        source: Locale.Language?,
        target: Locale.Language,
        forceNew: Bool
    ) {
        let key = pairKey(source: source, target: target)

        if !forceNew,
           publishedPairKey == key,
           var config = configuration {
            Self.logger.info("🍏 invalidating warm configuration for \(key, privacy: .public)")
            config.invalidate()
            configuration = config
            return
        }

        Self.logger.info("🍏 publishing new configuration for \(key, privacy: .public)")
        publishedPairKey = key
        configuration = TranslationSession.Configuration(
            source: source,
            target: target
        )
    }

    /// Map UI codes to the locale tags Apple's offline packs use (en_US, pt_BR, …).
    private func normalize(_ code: String) -> String {
        switch code {
        case "en": return "en-US"
        case "pt": return "pt-BR"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "it": return "it-IT"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "ru": return "ru-RU"
        case "ar": return "ar-AE"
        case "nl": return "nl-NL"
        case "pl": return "pl-PL"
        case "tr": return "tr-TR"
        case "hi": return "hi-IN"
        case "zh-Hans": return "zh-Hans"
        case "zh-Hant": return "zh-Hant"
        default: return code
        }
    }
}

@available(macOS 15.0, *)
struct AppleTranslationProvider: TranslationProvider {
    let id = ProviderKind.apple.rawValue
    let displayName = ProviderKind.apple.displayName
    let bridge: AppleTranslationBridge

    func translate(_ text: String, from: String?, to: String) async throws -> String {
        try await bridge.translate(text, from: from, to: to)
    }
}
