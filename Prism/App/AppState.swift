import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Status: Equatable {
        case idle
        case translating
        case success
        case error(String)
    }

    @Published var settings: AppSettings
    @Published var status: Status = .idle
    @Published var lastErrorMessage: String?
    /// False until the CGEvent tap is installed (needs Input Monitoring).
    @Published var hotkeysActive: Bool = false

    /// Seção ativa na sidebar de Preferências.
    @Published var settingsSelection: SettingsSection
    /// Deep-link pendente (consumido por `SettingsView` no appear/onChange).
    @Published var pendingSettingsSection: SettingsSection?

    let engine: TranslationEngine
    let textIO = FocusedTextIO()
    let orchestrator: TranslationOrchestrator
    let hotkeyMonitor: HotkeyMonitor
    let appleBridge = AppleTranslationBridge()

    private static let lastSettingsSectionKey = "lastSettingsSection"

    private var statusResetTask: Task<Void, Never>?
    private var permissionWatchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    /// Snapshot used to describe which control changed in the log.
    private var lastLoggedSettings: AppSettings?

    private init() {
        // Touch the log store early so session file + startup entry exist.
        _ = AppLogStore.shared

        let settings = AppSettings.load()
        self.settings = settings
        self.settingsSelection = Self.loadRememberedSettingsSection()
        self.engine = TranslationEngine(settings: settings, appleBridge: appleBridge)
        self.orchestrator = TranslationOrchestrator(
            settings: settings,
            engine: engine,
            textIO: textIO
        )
        self.hotkeyMonitor = HotkeyMonitor()

        AppLogPreferences.update(from: settings)

        AppLog.info(
            .app,
            "Prism iniciado — \(AppRelease.marketingVersion) (\(AppRelease.buildNumber)), \(AppRelease.runningMacOS), motor \(settings.engineLogDescription), \(settings.isEnabled ? "ligado" : "desligado"), Enter traduz \(settings.enterTranslatesAndSends ? "sim" : "não"), painel \(settings.popupModeEnabled ? "ligado" : "desligado")"
        )
        AppLog.info(
            .hotkey,
            "Atalhos: Traduzir \(settings.translateOnlyHotkey.displayString), Traduzir e enviar \(settings.translateAndSendHotkey.displayString), Painel \(settings.popupModeEnabled ? settings.popupHotkey.displayString : "desligado")"
        )
        AppLog.info(
            .permissions,
            "Permissões — Acessibilidade \(Permissions.isAccessibilityTrusted() ? "ok" : "ausente"), Monitoramento de Entrada \(Permissions.isInputMonitoringGranted() ? "ok" : "ausente")"
        )

        textIO.withInjection = { [weak self] work in
            self?.hotkeyMonitor.withInjection(work)
        }

        orchestrator.onStatusChange = { [weak self] status in
            self?.applyStatus(status)
        }
        orchestrator.pressReturnHandler = { [weak self] in
            self?.hotkeyMonitor.withInjection {
                KeyboardSimulator.pressReturn()
            }
        }

        $settings
            .dropFirst()
            .sink { [weak self] newSettings in
                guard let self else { return }
                let previous = self.lastLoggedSettings
                self.logSettingsDelta(from: previous, to: newSettings)
                self.lastLoggedSettings = newSettings
                AppLogPreferences.update(from: newSettings)
                newSettings.save()
                self.engine.updateSettings(newSettings)
                self.orchestrator.updateSettings(newSettings)
                self.applyHotkeyConfiguration(newSettings)
                if !newSettings.showStatusHUD {
                    StatusHUDController.shared.hide()
                }
                if newSettings.providerKind == .apple {
                    let pair = AppleTranslationBridge.defaultPackPair(settings: newSettings)
                    self.appleBridge.prewarm(from: pair.source, to: pair.target)
                }
            }
            .store(in: &cancellables)

        // Persist initial load side-effects (login item) without dropFirst skipping.
        settings.save()
        lastLoggedSettings = settings

        hotkeyMonitor.onTranslateOnly = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.orchestrator.translateFocusedText(
                    presentation: .replaceInPlace(sendAfter: false),
                    trigger: .hotkeyTranslateOnly(chord: self.settings.translateOnlyHotkey.displayString)
                )
            }
        }
        hotkeyMonitor.onTranslateAndSend = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.orchestrator.translateFocusedText(
                    presentation: .replaceInPlace(sendAfter: true),
                    trigger: .hotkeyTranslateAndSend(chord: self.settings.translateAndSendHotkey.displayString)
                )
            }
        }
        hotkeyMonitor.onEnterTranslateAndSend = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.orchestrator.translateFocusedText(
                    presentation: .replaceInPlace(sendAfter: true),
                    trigger: .enterKey
                )
            }
        }
        hotkeyMonitor.onPopup = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.orchestrator.translateFocusedText(
                    presentation: .popup,
                    trigger: .hotkeyPopup(chord: self.settings.popupHotkey.displayString)
                )
            }
        }
        hotkeyMonitor.onTapStatusChange = { [weak self] active in
            Task { @MainActor in
                AppLog.info(
                    .hotkey,
                    active
                        ? "Atalhos globais ativos"
                        : "Atalhos globais inativos — verifique Monitoramento de Entrada"
                )
                self?.hotkeysActive = active
            }
        }

        hotkeyMonitor.start()
        applyHotkeyConfiguration(settings)
        startPermissionWatch()
        observeBackgroundCacheClear()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            TranslationHostPanelController.shared.install(bridge: self.appleBridge)
            if self.settings.providerKind == .apple {
                let pair = AppleTranslationBridge.defaultPackPair(settings: self.settings)
                self.appleBridge.prewarm(from: pair.source, to: pair.target)
            }
            if OnboardingController.hasCompleted {
                if !Permissions.isAccessibilityTrusted() || !Permissions.isInputMonitoringGranted() {
                    AppLog.info(
                        .permissions,
                        "Permissões pendentes — use o menu ou Configurações › Permissões (sem prompt automático no arranque)"
                    )
                }
            } else {
                AppLog.info(.app, "Onboarding pendente — abrindo o tutorial")
                DispatchQueue.main.async {
                    OnboardingController.shared.showIfNeeded()
                }
            }
        }
    }

    private func startPermissionWatch() {
        permissionWatchTask?.cancel()
        permissionWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let tapActive = self.hotkeyMonitor.isTapActive
                self.hotkeysActive = tapActive
                if !tapActive {
                    self.hotkeyMonitor.retryInstallIfNeeded()
                    _ = try? await Task.sleep(nanoseconds: 2_000_000_000)
                } else {
                    _ = try? await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
        }
    }

    func clearLastError() {
        lastErrorMessage = nil
        if case .error = status { status = .idle }
        StatusHUDController.shared.hide()
    }

    func showOnboarding() {
        DispatchQueue.main.async {
            OnboardingController.shared.show(closeMenuBarAfterPresent: true)
        }
    }

    func rememberSettingsSection(_ section: SettingsSection) {
        UserDefaults.standard.set(section.rawValue, forKey: Self.lastSettingsSectionKey)
    }

    func consumePendingSettingsSection() -> SettingsSection? {
        let pending = pendingSettingsSection
        pendingSettingsSection = nil
        return pending
    }

    /// Prepara deep-link + Dock. Abrir a scene com `SettingsLink` / `OpenSettingsAction`.
    func prepareSettings(section: SettingsSection? = nil, closeMenuBar: Bool = false) {
        let target = section ?? settingsSelection
        pendingSettingsSection = target
        settingsSelection = target
        rememberSettingsSection(target)
        SettingsNavigation.prepareOpenSettings(closeMenuBar: closeMenuBar)
    }

    private static func loadRememberedSettingsSection() -> SettingsSection {
        guard let raw = UserDefaults.standard.string(forKey: lastSettingsSectionKey),
            let section = SettingsSection(rawValue: raw)
        else {
            return .general
        }
        return section
    }

    /// Ícone prisma no idle ligado; SF Symbols nos demais estados.
    var showsPrismMenuBarGlyph: Bool {
        if case .idle = status { return settings.isEnabled }
        return false
    }

    var statusIconName: String {
        switch status {
        case .idle:
            return settings.isEnabled ? "globe" : "pause.circle"
        case .translating:
            return "ellipsis.circle"
        case .success:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    func setOutgoingTargetLanguage(_ code: String) {
        guard settings.outgoingTargetLanguage != code else { return }
        var updated = settings
        updated.outgoingTargetLanguage = code
        settings = updated
    }

    func setIncomingTargetLanguage(_ code: String) {
        guard settings.incomingTargetLanguage != code else { return }
        var updated = settings
        updated.incomingTargetLanguage = code
        settings = updated
    }

    func resetHotkeysToDefaults() {
        var updated = settings
        updated.resetHotkeysToDefaults()
        settings = updated
    }

    func setHotkeyRecording(_ recording: Bool) {
        hotkeyMonitor.setRecordingHotkey(recording)
    }

    private func applyHotkeyConfiguration(_ settings: AppSettings) {
        hotkeyMonitor.updateConfiguration(
            enabled: settings.isEnabled,
            enterTranslatesAndSends: settings.enterTranslatesAndSends,
            translateOnly: settings.translateOnlyHotkey,
            translateAndSend: settings.translateAndSendHotkey,
            popupModeEnabled: settings.popupModeEnabled,
            popup: settings.popupHotkey
        )
    }

    private func logSettingsDelta(from previous: AppSettings?, to next: AppSettings) {
        guard let previous else {
            AppLog.info(.settings, "Configurações iniciais — motor \(next.engineLogDescription)")
            return
        }
        if previous.isEnabled != next.isEnabled {
            AppLog.info(
                .settings,
                "Controle «Ligado»: \(next.isEnabled ? "ativado" : "desativado")"
            )
        }
        if previous.enterTranslatesAndSends != next.enterTranslatesAndSends {
            AppLog.info(
                .settings,
                "Controle «Enter traduz e envia»: \(next.enterTranslatesAndSends ? "ativado" : "desativado")"
            )
        }
        if previous.providerKind != next.providerKind
            || previous.engineLogDescription != next.engineLogDescription
        {
            AppLog.info(
                .settings,
                "Motor: \(previous.engineLogDescription) → \(next.engineLogDescription)"
            )
        }
        if previous.incomingSourceLanguage != next.incomingSourceLanguage
            || previous.incomingTargetLanguage != next.incomingTargetLanguage
        {
            AppLog.info(
                .settings,
                "Idioma (texto que leio): \(LanguageCode.pairLabel(from: previous.incomingSourceLanguage, to: previous.incomingTargetLanguage)) → \(LanguageCode.pairLabel(from: next.incomingSourceLanguage, to: next.incomingTargetLanguage))"
            )
        }
        if previous.outgoingSourceLanguage != next.outgoingSourceLanguage
            || previous.outgoingTargetLanguage != next.outgoingTargetLanguage
        {
            AppLog.info(
                .settings,
                "Idioma (texto que escrevo): \(LanguageCode.pairLabel(from: previous.outgoingSourceLanguage, to: previous.outgoingTargetLanguage)) → \(LanguageCode.pairLabel(from: next.outgoingSourceLanguage, to: next.outgoingTargetLanguage))"
            )
        }
        if previous.translateOnlyHotkey != next.translateOnlyHotkey {
            AppLog.info(
                .settings,
                "Atalho «Traduzir»: \(previous.translateOnlyHotkey.displayString) → \(next.translateOnlyHotkey.displayString)"
            )
        }
        if previous.translateAndSendHotkey != next.translateAndSendHotkey {
            AppLog.info(
                .settings,
                "Atalho «Traduzir e enviar»: \(previous.translateAndSendHotkey.displayString) → \(next.translateAndSendHotkey.displayString)"
            )
        }
        if previous.popupModeEnabled != next.popupModeEnabled
            || previous.popupHotkey != next.popupHotkey
        {
            let old = previous.popupModeEnabled ? previous.popupHotkey.displayString : "desligado"
            let new = next.popupModeEnabled ? next.popupHotkey.displayString : "desligado"
            AppLog.info(.settings, "Atalho «Painel»: \(old) → \(new)")
        }
        if previous.showStatusHUD != next.showStatusHUD {
            AppLog.info(
                .settings,
                "Controle «Aviso perto do ponteiro»: \(next.showStatusHUD ? "ativado" : "desativado")"
            )
        }
        if previous.openAtLogin != next.openAtLogin {
            AppLog.info(
                .settings,
                "Controle «Abrir no login»: \(next.openAtLogin ? "ativado" : "desativado")"
            )
        }
        if previous.deeplUseFreeAPI != next.deeplUseFreeAPI {
            AppLog.info(
                .settings,
                "DeepL: \(next.deeplUseFreeAPI ? "API gratuita" : "API Pro")"
            )
        }
        if previous.logTextPreviews != next.logTextPreviews {
            AppLog.info(
                .settings,
                "Privacidade — prévias de texto nos logs: \(next.logTextPreviews ? "ativado" : "desativado")"
            )
        }
        if previous.cacheTranslations != next.cacheTranslations {
            AppLog.info(
                .settings,
                "Privacidade — cache de traduções: \(next.cacheTranslations ? "ativado" : "desativado")"
            )
        }
    }

    private func observeBackgroundCacheClear() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.engine.clearCacheOnBackground()
            }
        }
    }

    /// Binding que grava de volta em `settings` (dispara save/apply via publisher).
    /// Ignora writes idênticos — Pickers/Forms do SwiftUI reaplicam o valor durante
    /// o update da view; republicar `@Published` nesse momento gera
    /// “Publishing changes from within view updates…”.
    func settingsBinding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = self.settings
                updated[keyPath: keyPath] = newValue
                guard updated != self.settings else { return }
                self.settings = updated
            }
        )
    }

    private func applyStatus(_ status: Status) {
        statusResetTask?.cancel()
        self.status = status
        StatusHUDController.shared.present(
            status: status,
            isEnabled: settings.isEnabled,
            hudEnabled: settings.showStatusHUD
        )
        switch status {
        case .error(let message):
            AppLog.error(.app, "Status: erro — \(message)")
            lastErrorMessage = message
            statusResetTask = Task {
                _ = try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled { self.status = .idle }
            }
        case .success:
            AppLog.info(.app, "Status: sucesso")
            lastErrorMessage = nil
            statusResetTask = Task {
                _ = try? await Task.sleep(nanoseconds: 1_200_000_000)
                if !Task.isCancelled { self.status = .idle }
            }
        case .translating:
            AppLog.info(.app, "Status: traduzindo…")
        case .idle:
            break
        }
    }
}
