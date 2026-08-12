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

        AppLog.info(
            .app,
            "AppState init — provider=\(settings.providerKind.displayName), enabled=\(settings.isEnabled), enterMode=\(settings.enterTranslatesAndSends), popup=\(settings.popupModeEnabled), macOS=\(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
        AppLog.info(
            .permissions,
            "AX=\(Permissions.isAccessibilityTrusted()), InputMonitoring=\(Permissions.isInputMonitoringGranted())"
        )

        textIO.withInjection = { [weak self] work in
            self?.hotkeyMonitor.withInjection(work)
        }

        orchestrator.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.applyStatus(status)
            }
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
                AppLog.info(
                    .settings,
                    "settings salvos — provider=\(newSettings.providerKind.rawValue), enabled=\(newSettings.isEnabled), incoming=\(newSettings.incomingSourceLanguage ?? "auto")→\(newSettings.incomingTargetLanguage), outgoing=\(newSettings.outgoingSourceLanguage ?? "auto")→\(newSettings.outgoingTargetLanguage)"
                )
                newSettings.save()
                self.engine.updateSettings(newSettings)
                self.orchestrator.updateSettings(newSettings)
                self.applyHotkeyConfiguration(newSettings)
                if newSettings.providerKind == .apple {
                    let pair = AppleTranslationBridge.defaultPackPair(settings: newSettings)
                    self.appleBridge.prewarm(from: pair.source, to: pair.target)
                }
            }
            .store(in: &cancellables)

        // Persist initial load side-effects (login item) without dropFirst skipping.
        settings.save()

        hotkeyMonitor.onTranslateOnly = { [weak self] in
            Task { @MainActor in
                AppLog.info(.hotkey, "callback onTranslateOnly → orchestrator")
                await self?.orchestrator.translateFocusedText(
                    presentation: .replaceInPlace(sendAfter: false))
            }
        }
        hotkeyMonitor.onTranslateAndSend = { [weak self] in
            Task { @MainActor in
                AppLog.info(.hotkey, "callback onTranslateAndSend → orchestrator")
                await self?.orchestrator.translateFocusedText(
                    presentation: .replaceInPlace(sendAfter: true))
            }
        }
        hotkeyMonitor.onPopup = { [weak self] in
            Task { @MainActor in
                AppLog.info(.hotkey, "callback onPopup → orchestrator")
                await self?.orchestrator.translateFocusedText(presentation: .popup)
            }
        }
        hotkeyMonitor.onTapStatusChange = { [weak self] active in
            Task { @MainActor in
                AppLog.info(.hotkey, "tap status → \(active ? "ativo" : "inativo")")
                self?.hotkeysActive = active
            }
        }

        hotkeyMonitor.start()
        applyHotkeyConfiguration(settings)
        startPermissionWatch()
        scheduleAIModelCatalogRefresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            TranslationHostPanelController.shared.install(bridge: self.appleBridge)
            if self.settings.providerKind == .apple {
                let pair = AppleTranslationBridge.defaultPackPair(settings: self.settings)
                self.appleBridge.prewarm(from: pair.source, to: pair.target)
            }
            if OnboardingController.hasCompleted {
                Permissions.promptIfNeeded()
                if !Permissions.isInputMonitoringGranted() {
                    AppLog.warning(.permissions, "Input Monitoring ausente — solicitando")
                    _ = Permissions.requestInputMonitoring()
                }
            } else {
                AppLog.info(.app, "onboarding pendente — exibindo tutorial")
                OnboardingController.shared.showIfNeeded()
            }
        }
    }

    private func startPermissionWatch() {
        permissionWatchTask?.cancel()
        permissionWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                _ = try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                // Event tap needs Input Monitoring; retry whenever it is still missing.
                self.hotkeyMonitor.retryInstallIfNeeded()
                self.hotkeysActive = self.hotkeyMonitor.isTapActive
            }
        }
    }

    /// Consulta APIs dos motores de IA (quando há chave) e troca modelos descontinuados.
    private func scheduleAIModelCatalogRefresh() {
        Task { [weak self] in
            // Evita competir com o cold start / onboarding / primeiro layout.
            _ = try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self else { return }
            var updated = self.settings
            let result = await AIModelCatalog.refreshModels(settings: &updated, force: false)
            guard result.didChange else { return }
            self.applySettingsAsync(updated)
            AppLog.info(
                .settings,
                "catálogo de modelos atualizou \(result.updatedProviders.map(\.rawValue).joined(separator: ", "))"
            )
        }
    }

    func clearLastError() {
        lastErrorMessage = nil
        if case .error = status { status = .idle }
        StatusHUDController.shared.hide()
    }

    func showOnboarding() {
        SettingsNavigation.closeMenuBarExtra()
        OnboardingController.shared.show()
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

    /// Abre Configurações pedindo à bridge SwiftUI (`SettingsLink` / `openSettings`).
    func openSettings(section: SettingsSection? = nil) {
        prepareSettings(section: section, closeMenuBar: false)
        NotificationCenter.default.post(name: .qtRequestOpenSettings, object: nil)
        SettingsNavigation.closeMenuBarExtra()
    }

    private static func loadRememberedSettingsSection() -> SettingsSection {
        guard let raw = UserDefaults.standard.string(forKey: lastSettingsSectionKey),
            let section = SettingsSection(rawValue: raw)
        else {
            return .general
        }
        return section
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

    func toggleEnabled() {
        settings.isEnabled.toggle()
    }

    func toggleEnterMode() {
        settings.enterTranslatesAndSends.toggle()
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

    /// Aplica settings fora do ciclo de update da view (catálogo de modelos, etc.).
    func applySettingsAsync(_ newSettings: AppSettings) {
        guard newSettings != settings else { return }
        Task { @MainActor in
            await Task.yield()
            guard newSettings != self.settings else { return }
            self.settings = newSettings
        }
    }

    private func applyStatus(_ status: Status) {
        statusResetTask?.cancel()
        self.status = status
        StatusHUDController.shared.present(status: status, isEnabled: settings.isEnabled)
        switch status {
        case .error(let message):
            AppLog.error(.app, "status=error — \(message)")
            lastErrorMessage = message
            statusResetTask = Task {
                _ = try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled { self.status = .idle }
            }
        case .success:
            AppLog.info(.app, "status=success")
            lastErrorMessage = nil
            statusResetTask = Task {
                _ = try? await Task.sleep(nanoseconds: 1_200_000_000)
                if !Task.isCancelled { self.status = .idle }
            }
        case .translating:
            AppLog.info(.app, "status=translating")
        case .idle:
            break
        }
    }
}
