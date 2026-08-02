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

    let engine: TranslationEngine
    let textIO = FocusedTextIO()
    let orchestrator: TranslationOrchestrator
    let hotkeyMonitor: HotkeyMonitor
    let appleBridge = AppleTranslationBridge()

    private var statusResetTask: Task<Void, Never>?
    private var permissionWatchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let settings = AppSettings.load()
        self.settings = settings
        self.engine = TranslationEngine(settings: settings, appleBridge: appleBridge)
        self.orchestrator = TranslationOrchestrator(
            settings: settings,
            engine: engine,
            textIO: textIO
        )
        self.hotkeyMonitor = HotkeyMonitor()

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
                await self?.orchestrator.translateFocusedText(sendAfter: false)
            }
        }
        hotkeyMonitor.onTranslateAndSend = { [weak self] in
            Task { @MainActor in
                await self?.orchestrator.translateFocusedText(sendAfter: true)
            }
        }
        hotkeyMonitor.onTapStatusChange = { [weak self] active in
            Task { @MainActor in
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
                    _ = Permissions.requestInputMonitoring()
                }
            } else {
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
    }

    func showOnboarding() {
        OnboardingController.shared.show()
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

    func setTargetLanguage(_ code: String) {
        var updated = settings
        updated.targetLanguage = code
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
            translateAndSend: settings.translateAndSendHotkey
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
        switch status {
        case .error(let message):
            lastErrorMessage = message
            statusResetTask = Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled { self.status = .idle }
            }
        case .success:
            lastErrorMessage = nil
            statusResetTask = Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if !Task.isCancelled { self.status = .idle }
            }
        case .idle, .translating:
            break
        }
    }
}
