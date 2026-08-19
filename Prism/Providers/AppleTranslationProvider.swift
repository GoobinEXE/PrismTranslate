import Combine
import Foundation
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

    var isBusy: Bool {
        self == .checking || self == .downloading
    }
}

/// Maps app language ids (`en`, `pt`, `zh-Hans`) onto the `Locale.Language`
/// values Apple's Translation framework actually lists in `supportedLanguages`.
///
/// `Locale.Language(identifier: "en-US")` often becomes `en-Latn-US` (maximal),
/// which `LanguageAvailability.status` treats as a different pair than the
/// installed `en` + region `US` pack — so the UI keeps saying the pack is missing.
enum AppleTranslationLanguageMap {
    struct Spec: Equatable {
        var languageCode: String
        var region: String?
        var script: String?
        var appCode: String

        var bcp47: String {
            if let region { return "\(languageCode)-\(region)" }
            if let script { return "\(languageCode)-\(script)" }
            return languageCode
        }
    }

    static func spec(forAppCode raw: String) -> Spec {
        let code = LanguageCode.normalize(raw)
        switch code {
        case "en": return Spec(languageCode: "en", region: "US", script: nil, appCode: "en")
        case "pt": return Spec(languageCode: "pt", region: "BR", script: nil, appCode: "pt")
        case "es": return Spec(languageCode: "es", region: "ES", script: nil, appCode: "es")
        case "fr": return Spec(languageCode: "fr", region: "FR", script: nil, appCode: "fr")
        case "de": return Spec(languageCode: "de", region: "DE", script: nil, appCode: "de")
        case "it": return Spec(languageCode: "it", region: "IT", script: nil, appCode: "it")
        case "ja": return Spec(languageCode: "ja", region: "JP", script: nil, appCode: "ja")
        case "ko": return Spec(languageCode: "ko", region: "KR", script: nil, appCode: "ko")
        case "ru": return Spec(languageCode: "ru", region: "RU", script: nil, appCode: "ru")
        case "ar": return Spec(languageCode: "ar", region: "AE", script: nil, appCode: "ar")
        case "nl": return Spec(languageCode: "nl", region: "NL", script: nil, appCode: "nl")
        case "pl": return Spec(languageCode: "pl", region: "PL", script: nil, appCode: "pl")
        case "tr": return Spec(languageCode: "tr", region: "TR", script: nil, appCode: "tr")
        case "hi": return Spec(languageCode: "hi", region: "IN", script: nil, appCode: "hi")
        case "zh-Hans": return Spec(languageCode: "zh", region: "CN", script: nil, appCode: "zh-Hans")
        case "zh-Hant": return Spec(languageCode: "zh", region: "TW", script: nil, appCode: "zh-Hant")
        default:
            let language = Locale.Language(identifier: code)
            return Spec(
                languageCode: language.languageCode?.identifier ?? code,
                region: language.region?.identifier,
                script: nil,
                appCode: code
            )
        }
    }

    static func makeLanguage(forAppCode code: String) -> Locale.Language {
        let spec = spec(forAppCode: code)
        return Locale.Language(
            components: Locale.Language.Components(
                languageCode: Locale.LanguageCode(spec.languageCode),
                script: spec.script.map { Locale.Script($0) },
                region: spec.region.map { Locale.Region($0) }
            )
        )
    }

    static func pick(appCode: String, from supported: [Locale.Language]) -> Locale.Language? {
        let spec = spec(forAppCode: appCode)
        if let region = spec.region,
           let match = supported.first(where: {
               $0.languageCode?.identifier == spec.languageCode
                   && $0.region?.identifier == region
           })
        {
            return match
        }
        if spec.appCode == "zh-Hans" || spec.appCode == "zh-Hant" {
            let wantedScript = spec.appCode == "zh-Hant" ? "Hant" : "Hans"
            if let match = supported.first(where: {
                $0.languageCode?.identifier == "zh"
                    && $0.script?.identifier == wantedScript
            }) {
                return match
            }
        }
        return supported.first(where: {
            $0.languageCode?.identifier == spec.languageCode
                && AppleTranslationLanguageMap.appCode(from: $0) == spec.appCode
        })
            ?? supported.first(where: { $0.languageCode?.identifier == spec.languageCode })
    }

    static func appCode(from language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.maximalIdentifier
        if code == "zh" {
            let script = language.script?.identifier
            let region = language.region?.identifier
            if script == "Hant" || region == "TW" || region == "HK" || region == "MO" {
                return "zh-Hant"
            }
            return "zh-Hans"
        }
        return LanguageCode.normalize(code)
    }

    static func alternates(of language: Locale.Language, in supported: [Locale.Language]) -> [Locale.Language] {
        let code = AppleTranslationLanguageMap.appCode(from: language)
        let matches = supported.filter { AppleTranslationLanguageMap.appCode(from: $0) == code }
        return matches.isEmpty ? [language] : matches
    }

    /// Auto-detect (`nil` source) cannot drive `prepareTranslation()` or a reliable
    /// pack check — pick a concrete counterpart that isn't the target.
    static func concreteSource(preferred: String?, target: String) -> String {
        let targetCode = LanguageCode.normalize(target)
        if let preferred, !preferred.isEmpty {
            let sourceCode = LanguageCode.normalize(preferred)
            if sourceCode != targetCode { return sourceCode }
        }
        let system = LanguageCode.systemLanguage
        if system != targetCode { return system }
        return LanguageCode.systemDefaultTarget
    }
}

/// Coordinates programmatic Apple Translation via a hidden SwiftUI host.
@MainActor
@available(macOS 15.0, *)
final class AppleTranslationBridge: ObservableObject {
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
    /// Reused — a new instance per check was returning `.supported` for packs already on disk.
    private let languageAvailability = LanguageAvailability()
    private var supportedLanguagesCache: [Locale.Language] = []
    private var supportedLanguagesFetchedAt: Date?
    /// Last merged pack status, so Preferências can reopen without flashing “não baixados”.
    private(set) var cachedOverallPackState: LanguagePackState?

    /// Notifies the host panel when a request may need the language-download sheet
    /// (true = bring the host window on-screen, false = hide it again).
    var onActivity: ((Bool) -> Void)?

    /// How long to wait for `.translationTask` to pick up a request before failing.
    /// macOS 26's translationd can take longer to spin up on first use after boot.
    private static let requestTimeoutNs: UInt64 = 30_000_000_000
    private static let availabilityCacheTTL: TimeInterval = 300
    private static let supportedLanguagesTTL: TimeInterval = 600

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
        let source = AppleTranslationLanguageMap.concreteSource(preferred: from, target: to)
        invalidateAvailabilityCache(from: source, to: to)
        _ = try await enqueue(
            text: Self.sampleText(target: to),
            from: source,
            to: to,
            forcePrepare: true
        )
    }

    /// Publishes a configuration early so the first real translate hits a warm session.
    func prewarm(from: String?, to: String) {
        guard pending == nil else { return }
        Task { [weak self] in
            guard let self, self.pending == nil else { return }
            let sourceLang = await self.resolvedSourceLanguage(from)
            let targetLang = await self.resolvedAppleLanguage(for: to)
            AppLog.info(
                .apple,
                "Preparando sessão Apple Translation para \(self.pairKey(source: sourceLang, target: targetLang))"
            )
            self.publishConfiguration(source: sourceLang, target: targetLang, forceNew: false)
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
        let sourceLang = await resolvedSourceLanguage(from)
        let targetLang = await resolvedAppleLanguage(for: to)

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
                    throwing: TranslationError.appleTranslationFailed(String(localized: "Previous translation canceled"))
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

            AppLog.info(
                .apple,
                "Fila: pedido \(request.id.uuidString.prefix(8)) — \(request.text.count) caracteres, pacotes \(request.packsLikelyMissing ? "provavelmente ausentes" : "ok")"
            )
            publishConfiguration(source: sourceLang, target: targetLang, forceNew: false)
        }
    }

    func handle(session: TranslationSession) async {
        AppLog.info(.apple, "Sessão Apple Translation recebida do sistema")
        guard let request = pending else {
            AppLog.debug(.apple, "Sessão sem pedido pendente — mantendo aquecida")
            return
        }
        pending = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        do {
            let translated = try await translateRespectingSystemMode(session: session, request: request)
            AppLog.info(.apple, "Sessão devolveu a tradução com sucesso")
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
            AppLog.error(.apple, "Sessão Apple Translation falhou: \(error.localizedDescription)")
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
                String(localized: "Set a source language or download packs in Settings › General › Language & Region › Translation Languages")
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
            return "\(raw). \(String(localized: "With On-Device Mode on, download source and target languages in System Settings › General › Language & Region › Translation Languages — or turn the mode off to translate online."))"
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

    /// Language pairs the app will most likely use (outgoing + incoming).
    static func defaultPackPair(settings: AppSettings) -> (source: String?, target: String) {
        // Prefer outgoing for Apple prewarm (writing path); packs for incoming are
        // prepared on demand / via Preferências.
        let target = settings.outgoingTargetLanguage
        let source = settings.resolvedOutgoingSourceLanguage ?? LanguageCode.systemLanguage
        return source == target ? (nil, target) : (source, target)
    }

    /// Distinct concrete pairs to check/download (auto-detect is resolved to a counterpart).
    static func packPairs(settings: AppSettings) -> [(source: String?, target: String)] {
        var pairs: [(String?, String)] = []
        var seen = Set<String>()

        func add(preferred: String?, target: String) {
            let source = AppleTranslationLanguageMap.concreteSource(preferred: preferred, target: target)
            let key = "\(source)|\(target)"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            pairs.append((source, target))
        }

        add(
            preferred: settings.resolvedOutgoingSourceLanguage,
            target: settings.outgoingTargetLanguage
        )
        add(
            preferred: settings.resolvedSourceLanguage(outgoing: false),
            target: settings.incomingTargetLanguage
        )
        return pairs
    }

    /// Pack state for a pair; auto-detect source is resolved to a concrete counterpart.
    func languagePackState(from: String?, to: String, ignoreCache: Bool = false) async -> LanguagePackState {
        let sourceCode = AppleTranslationLanguageMap.concreteSource(preferred: from, target: to)
        let sourceLang = await resolvedAppleLanguage(for: sourceCode)
        let targetLang = await resolvedAppleLanguage(for: to)
        let key = pairKey(source: sourceLang, target: targetLang)

        if !ignoreCache,
           let cached = availabilityCache[key],
           Date().timeIntervalSince(cached.checkedAt) < Self.availabilityCacheTTL {
            let state: LanguagePackState = cached.packsLikelyMissing ? .needsDownload : .installed
            AppLog.debug(.apple, "🍏 pack cache hit \(key) → \(state)")
            return state
        }

        switch await pairStatus(from: sourceLang, to: targetLang) {
        case .installed:
            cacheAvailability(source: sourceLang, target: targetLang, packsLikelyMissing: false)
            return .installed
        case .supported:
            cacheAvailability(source: sourceLang, target: targetLang, packsLikelyMissing: true)
            return .needsDownload
        case .unsupported:
            return .unsupported
        @unknown default:
            return .needsDownload
        }
    }

    func rememberOverallPackState(_ state: LanguagePackState) {
        cachedOverallPackState = state
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
        if let source {
            let resolvedSource = await resolvedAppleLanguage(
                for: AppleTranslationLanguageMap.appCode(from: source)
            )
            let resolvedTarget = await resolvedAppleLanguage(
                for: AppleTranslationLanguageMap.appCode(from: target)
            )
            return await pairStatus(from: resolvedSource, to: resolvedTarget)
        }
        if let detected = try? await languageAvailability.status(for: sampleText, to: target) {
            return detected
        }
        // Detection failed — do not claim the pack is missing.
        return .installed
    }

    private func pairStatus(
        from source: Locale.Language,
        to target: Locale.Language
    ) async -> LanguageAvailability.Status {
        let primary = await languageAvailability.status(from: source, to: target)
        AppLog.debug(
            .apple,
            "🍏 LanguageAvailability \(AppleTranslationLanguageMap.appCode(from: source))→\(AppleTranslationLanguageMap.appCode(from: target)) = \(primary)"
        )
        if primary == .installed || primary == .unsupported {
            return primary
        }

        let supported = await cachedSupportedLanguages()
        let sourceAlts = AppleTranslationLanguageMap.alternates(of: source, in: supported)
        let targetAlts = AppleTranslationLanguageMap.alternates(of: target, in: supported)
        for src in sourceAlts {
            for dst in targetAlts {
                if src == source && dst == target { continue }
                let status = await languageAvailability.status(from: src, to: dst)
                if status == .installed {
                    AppLog.info(
                        .apple,
                        "🍏 pack installed via alternate \(AppleTranslationLanguageMap.appCode(from: src))→\(AppleTranslationLanguageMap.appCode(from: dst))"
                    )
                    return .installed
                }
            }
        }
        return primary
    }

    private func resolvedSourceLanguage(_ from: String?) async -> Locale.Language? {
        guard let from, !from.isEmpty else { return nil }
        return await resolvedAppleLanguage(for: from)
    }

    private func resolvedAppleLanguage(for code: String) async -> Locale.Language {
        let supported = await cachedSupportedLanguages()
        return AppleTranslationLanguageMap.pick(appCode: code, from: supported)
            ?? AppleTranslationLanguageMap.makeLanguage(forAppCode: code)
    }

    private func cachedSupportedLanguages() async -> [Locale.Language] {
        if !supportedLanguagesCache.isEmpty,
           let fetched = supportedLanguagesFetchedAt,
           Date().timeIntervalSince(fetched) < Self.supportedLanguagesTTL {
            return supportedLanguagesCache
        }
        let list = await languageAvailability.supportedLanguages
        supportedLanguagesCache = list
        supportedLanguagesFetchedAt = Date()
        AppLog.debug(.apple, "🍏 supportedLanguages=\(list.count)")
        return list
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
            AppLog.debug(.apple, "🍏 availability cache hit for \(key)")
            return cached.packsLikelyMissing
        }

        switch await availabilityStatus(source: source, target: target, sampleText: sampleText) {
        case .unsupported:
            availabilityCache.removeValue(forKey: key)
            throw TranslationError.appleTranslationFailed(
                String(localized: "Language pair not supported — choose another language or provider")
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
        let sourceLang = from.map { AppleTranslationLanguageMap.makeLanguage(forAppCode: $0) }
        let targetLang = AppleTranslationLanguageMap.makeLanguage(forAppCode: to)
        invalidateAvailabilityCache(source: sourceLang, target: targetLang)
    }

    private func invalidateAvailabilityCache(source: Locale.Language?, target: Locale.Language) {
        availabilityCache.removeValue(forKey: pairKey(source: source, target: target))
    }

    private func pairKey(source: Locale.Language?, target: Locale.Language) -> String {
        let sourceID = source.map { AppleTranslationLanguageMap.appCode(from: $0) } ?? "auto"
        return "\(sourceID)|\(AppleTranslationLanguageMap.appCode(from: target))"
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
                String(localized: "Timed out — with On-Device Mode on, download languages in Settings › General › Language & Region › Translation Languages")
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
            AppLog.info(.apple, "Reusando sessão aquecida para \(key) (invalidate)")
            config.invalidate()
            configuration = config
            return
        }

        AppLog.info(.apple, "Publicando nova sessão Apple Translation para \(key)")
        publishedPairKey = key
        configuration = TranslationSession.Configuration(
            source: source,
            target: target
        )
    }
}

@available(macOS 15.0, *)
struct AppleTranslationProvider: TranslationProvider {
    let id = ProviderKind.apple.rawValue
    let displayName = ProviderKind.apple.displayName
    let bridge: AppleTranslationBridge

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        AppLog.info(
            .apple,
            "Apple Translation: \(LanguageCode.pairLabel(from: from, to: to)), \(text.count) caracteres"
        )
        let started = Date()
        do {
            let text = try await bridge.translate(text, from: from, to: to)
            AppLog.info(
                .apple,
                "Apple Translation concluiu em \(AppLog.duration(since: started)) — \(text.count) caracteres"
            )
            return TranslationOutcome(text: text)
        } catch {
            AppLog.error(
                .apple,
                "Apple Translation falhou em \(AppLog.duration(since: started)): \(error.localizedDescription)"
            )
            throw error
        }
    }
}
