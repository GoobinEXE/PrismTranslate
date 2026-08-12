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
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                // Event tap needs Input Monitoring; retry whenever it is still missing.
                self.hotkeyMonitor.retryInstallIfNeeded()
                self.hotkeysActive = self.hotkeyMonitor.isTapActive
            }
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
        var updated = settings
        updated.outgoingTargetLanguage = code
        settings = updated
    }

    func setIncomingTargetLanguage(_ code: String) {
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
    func settingsBinding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
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
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled { self.status = .idle }
            }
        case .success:
            AppLog.info(.app, "status=success")
            lastErrorMessage = nil
            statusResetTask = Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if !Task.isCancelled { self.status = .idle }
            }
        case .translating:
            AppLog.info(.app, "status=translating")
        case .idle:
            break
        }
    }
}
