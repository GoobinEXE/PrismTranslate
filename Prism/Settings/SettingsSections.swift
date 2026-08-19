import AppKit
import Combine
import SwiftUI

// MARK: - Geral

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("The On, Enter, HUD, target language, and popup controls are also on the menu bar icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The Translate shortcut replaces in place if the field is editable; for read-only text it opens the panel (Copy). Popup mode (opt-in) opens the panel for any selection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Translation") {
                Toggle("On", isOn: appState.settingsBinding(\.isEnabled))
                Toggle(
                    "Enter translates and sends",
                    isOn: appState.settingsBinding(\.enterTranslatesAndSends))
                Toggle(
                    "Hint near pointer",
                    isOn: appState.settingsBinding(\.showStatusHUD)
                )
                Text("Shows “Translating…”, done, and errors next to the pointer when you use the shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text I read") {
                Picker(
                    "Translate from",
                    selection: appState.settingsBinding(\.incomingSourceLanguage)
                ) {
                    Text("Detect language").tag(String?.none)
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(String?.some(language.id))
                    }
                }
                Picker(
                    "Translate to",
                    selection: appState.settingsBinding(\.incomingTargetLanguage)
                ) {
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(language.id)
                    }
                }
                Text("Used for read-only text and the panel when reading conversations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text I write") {
                Picker(
                    "Translate from",
                    selection: appState.settingsBinding(\.outgoingSourceLanguage)
                ) {
                    Text("Detect language").tag(String?.none)
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(String?.some(language.id))
                    }
                }
                Picker(
                    "Translate to",
                    selection: appState.settingsBinding(\.outgoingTargetLanguage)
                ) {
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(language.id)
                    }
                }
                Text("Used when replacing text in editable fields.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("More options") {
                Button("Open Shortcuts…") {
                    appState.settingsSelection = .shortcuts
                    appState.rememberSettingsSection(.shortcuts)
                }
                .accessibilityLabel("Go to Shortcuts section")
                .accessibilityHint("Shows the Shortcuts section in this window")
                Button("Open Provider…") {
                    appState.settingsSelection = .provider
                    appState.rememberSettingsSection(.provider)
                }
                .accessibilityLabel("Go to Provider section")
                .accessibilityHint("Shows the Provider section in this window")
            }

            Section("System") {
                Toggle("Open at login", isOn: appState.settingsBinding(\.openAtLogin))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Provedor

struct ProviderSettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var deeplKey: String = KeychainStore.string(for: .deeplAPIKey) ?? ""
    @State private var googleKey: String = KeychainStore.string(for: .googleAPIKey) ?? ""
    @State private var openAIKey: String = KeychainStore.string(for: .openAIAPIKey) ?? ""
    @State private var deeplKeySaveTask: Task<Void, Never>?
    @State private var googleKeySaveTask: Task<Void, Never>?
    @State private var openAIKeySaveTask: Task<Void, Never>?
    @State private var applePackState: LanguagePackState = .checking
    @State private var applePackRows: [ApplePackRow] = []

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Engine", selection: appState.settingsBinding(\.providerKind)) {
                    ForEach(EnginePickerGroup.allCases) { group in
                        Section(group.title) {
                            ForEach(group.providers) { kind in
                                Label {
                                    HStack(spacing: 6) {
                                        Text(kind.displayName)
                                        ForEach(kind.badges, id: \.self) { badge in
                                            EngineBadgeChip(badge: badge)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: kind.symbolName)
                                }
                                .tag(kind)
                                .accessibilityLabel(providerAccessibilityLabel(kind))
                            }
                        }
                    }
                }
                .pickerStyle(.menu)

                HStack(spacing: 6) {
                    Image(systemName: appState.settings.providerKind.symbolName)
                        .foregroundStyle(.secondary)
                    Text(appState.settings.providerKind.displayName)
                        .font(.subheadline.weight(.medium))
                    ForEach(appState.settings.providerKind.badges, id: \.self) { badge in
                        EngineBadgeChip(badge: badge)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)

                if let hint = appState.settings.providerKind.setupHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Configuration") {
                providerFields
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            persistSecrets()
            deeplKey = ""
            googleKey = ""
            openAIKey = ""
        }
        .task(id: applePackTaskID) {
            guard appState.settings.providerKind == .apple else { return }
            await refreshApplePackState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard appState.settings.providerKind == .apple, applePackState != .downloading else { return }
            guard applePackState == .needsDownload || applePackState.isFailed || applePackState == .checking else {
                return
            }
            Task { await refreshApplePackState() }
        }
    }

    @ViewBuilder
    private var providerFields: some View {
        switch appState.settings.providerKind {
        case .apple:
            Text("No API key. Translation runs on this Mac with languages downloaded in macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(applePackRows) { row in
                LabeledContent(row.label) {
                    HStack(spacing: 8) {
                        Image(systemName: packIcon(for: row.state))
                            .foregroundStyle(packColor(for: row.state))
                        Text(packStatusText(for: row.state))
                            .foregroundStyle(packColor(for: row.state))
                        if row.state == .needsDownload || row.state.isFailed {
                            Button("Download…") {
                                Task { await prepareApplePacks(pair: (row.source, row.target)) }
                            }
                            .disabled(applePackState == .downloading)
                        }
                    }
                }
            }

            HStack {
                Label(applePackLabel, systemImage: applePackIcon)
                    .foregroundStyle(applePackColor)
                Spacer()
                if applePackState.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if applePackState == .needsDownload || applePackState.isFailed {
                Button("Download languages in use…") {
                    Task { await prepareApplePacks() }
                }
                .disabled(applePackState == .downloading)
                .accessibilityHint("Opens the system dialog to download source and target packs")
            }

            Button("Open Translation Languages in System Settings…") {
                Permissions.openTranslationLanguagesSettings()
            }
            .accessibilityHint("Opens System Settings to the translation languages list")

            Text(
                "Download source and target. The button above asks macOS to download them; if nothing appears, use Settings › General › Language & Region › Translation Languages. With On-Device Mode on, translation stays offline."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        case .deepl:
            SecureField("DeepL API Key", text: $deeplKey)
                .help("DeepL API key (Free or Pro account). Stored in the Keychain.")
                .accessibilityHint("Secret DeepL API key, stored in the Keychain")
                .onChange(of: deeplKey) { _, newValue in
                    scheduleKeychainSave(newValue, for: .deeplAPIKey, task: &deeplKeySaveTask)
                }
            Toggle(
                "Use Free API (api-free.deepl.com)",
                isOn: appState.settingsBinding(\.deeplUseFreeAPI))
        case .google:
            SecureField("Google Cloud Translation API Key", text: $googleKey)
                .help("Google Cloud Translation API key. Stored in the Keychain.")
                .accessibilityHint("Secret Google Cloud API key, stored in the Keychain")
                .onChange(of: googleKey) { _, newValue in
                    scheduleKeychainSave(newValue, for: .googleAPIKey, task: &googleKeySaveTask)
                }
        case .openAICompatible:
            TextField("Base URL", text: appState.settingsBinding(\.openAIBaseURL))
                .help("OpenAI-compatible endpoint, for example local LM Studio.")
            TextField("Model", text: appState.settingsBinding(\.openAIModel))
            SecureField("API Key (optional)", text: $openAIKey)
                .help("Optional for local servers. Stored in the Keychain.")
                .accessibilityHint("Optional API key, stored in the Keychain")
                .onChange(of: openAIKey) { _, newValue in
                    scheduleKeychainSave(newValue, for: .openAIAPIKey, task: &openAIKeySaveTask)
                }
            Text("Default LM Studio: http://localhost:1234/v1")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .customHTTP:
            TextField("URL", text: appState.settingsBinding(\.customHTTPURL))
            TextField("Method", text: appState.settingsBinding(\.customHTTPMethod))
            SecureField("JSON headers", text: appState.settingsBinding(\.customHTTPHeadersJSON))
                .help("Stored in the Keychain. Use for Authorization or API keys.")
            TextField(
                "Body template", text: appState.settingsBinding(\.customHTTPBodyTemplate),
                axis: .vertical
            )
            .lineLimit(3...6)
            TextField(
                "Response JSON path", text: appState.settingsBinding(\.customHTTPResponsePath))
            Text("Placeholders: {{text}}, {{to}}, {{from}}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var applePackTaskID: String {
        "\(appState.settings.providerKind.rawValue)-\(appState.settings.outgoingTargetLanguage)-\(appState.settings.outgoingSourceLanguage ?? "auto")-\(appState.settings.incomingTargetLanguage)-\(appState.settings.incomingSourceLanguage ?? "auto")"
    }

    private var applePackLabel: String {
        switch applePackState {
        case .checking: return String(localized: "Checking languages…")
        case .installed: return String(localized: "Translation languages ready")
        case .needsDownload: return String(localized: "One or more languages still need downloading")
        case .downloading: return String(localized: "Downloading — confirm the system dialog")
        case .unsupported: return String(localized: "Language pair not supported")
        case .failed(let message): return String(format: String(localized: "Failed: %@"), message)
        }
    }

    private var applePackIcon: String { packIcon(for: applePackState) }
    private var applePackColor: Color { packColor(for: applePackState) }

    private func packStatusText(for state: LanguagePackState) -> String {
        switch state {
        case .checking: return String(localized: "Checking…")
        case .installed: return String(localized: "Ready")
        case .needsDownload: return String(localized: "Not downloaded")
        case .downloading: return String(localized: "Downloading…")
        case .unsupported: return String(localized: "Not supported")
        case .failed: return String(localized: "Failed")
        }
    }

    private func packIcon(for state: LanguagePackState) -> String {
        switch state {
        case .installed: return "checkmark.circle"
        case .checking, .downloading: return "arrow.down.circle"
        case .needsDownload: return "exclamationmark.triangle"
        case .unsupported, .failed: return "xmark.circle"
        }
    }

    private func packColor(for state: LanguagePackState) -> Color {
        switch state {
        case .installed: return .green
        case .checking, .downloading: return .primary
        case .needsDownload: return .orange
        case .unsupported, .failed: return .red
        }
    }

    private func refreshApplePackState() async {
        await Task.yield()
        if applePackRows.isEmpty, let cached = appState.appleBridge.cachedOverallPackState {
            applePackState = cached
        } else if applePackState != .installed && applePackState != .needsDownload && !applePackState.isFailed {
            applePackState = .checking
        }

        var rows: [ApplePackRow] = []
        var worst: LanguagePackState = .installed
        for pair in AppleTranslationBridge.packPairs(settings: appState.settings) {
            let source = pair.source ?? AppleTranslationLanguageMap.concreteSource(
                preferred: nil,
                target: pair.target
            )
            let state = await appState.appleBridge.languagePackState(
                from: source,
                to: pair.target,
                ignoreCache: true
            )
            rows.append(ApplePackRow(source: source, target: pair.target, state: state))
            worst = Self.mergePackState(worst, state)
            if case .unsupported = worst { break }
            if worst.isFailed { break }
        }
        applePackRows = rows
        applePackState = worst
        appState.appleBridge.rememberOverallPackState(worst)
    }

    private func prepareApplePacks(pair: (source: String, target: String)? = nil) async {
        applePackState = .downloading
        var lastError: Error?
        var anyNeedsWork = false
        let pairs: [(source: String?, target: String)] = {
            if let pair { return [(pair.source, pair.target)] }
            return AppleTranslationBridge.packPairs(settings: appState.settings)
        }()
        for item in pairs {
            do {
                try await appState.appleBridge.ensureLanguagePacks(
                    from: item.source, to: item.target)
            } catch {
                lastError = error
                anyNeedsWork = true
            }
        }
        if let lastError, anyNeedsWork {
            let fallback = AppleTranslationBridge.defaultPackPair(settings: appState.settings)
            let current = await appState.appleBridge.languagePackState(
                from: fallback.source,
                to: fallback.target
            )
            applePackState =
                current == .installed
                ? .installed
                : .failed(lastError.localizedDescription)
        } else {
            applePackState = .installed
        }
        await refreshApplePackState()
    }

    private static func mergePackState(_ a: LanguagePackState, _ b: LanguagePackState)
        -> LanguagePackState
    {
        // Prefer the more actionable / worse status for the UI badge.
        let rank: (LanguagePackState) -> Int = { state in
            switch state {
            case .installed: return 0
            case .checking: return 1
            case .needsDownload: return 2
            case .downloading: return 3
            case .unsupported: return 4
            case .failed: return 5
            }
        }
        return rank(b) > rank(a) ? b : a
    }

    private func persistSecrets() {
        deeplKeySaveTask?.cancel()
        googleKeySaveTask?.cancel()
        openAIKeySaveTask?.cancel()
        KeychainStore.set(deeplKey, for: .deeplAPIKey)
        KeychainStore.set(googleKey, for: .googleAPIKey)
        KeychainStore.set(openAIKey, for: .openAIAPIKey)
    }

    private func scheduleKeychainSave(
        _ value: String,
        for key: KeychainStore.Key,
        task: inout Task<Void, Never>?
    ) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            KeychainStore.set(value, for: key)
        }
    }

    private func providerAccessibilityLabel(_ kind: ProviderKind) -> String {
        let badges = kind.badges.map(\.rawValue).joined(separator: ", ")
        if badges.isEmpty { return kind.displayName }
        return "\(kind.displayName), \(badges)"
    }
}

private struct ApplePackRow: Identifiable, Equatable {
    let source: String
    let target: String
    var state: LanguagePackState

    var id: String { "\(source)-\(target)" }
    var label: String { LanguageCode.pairLabel(from: source, to: target) }
}

/// Chip compacto ao lado do nome do motor (substitui sufixos entre parênteses).
private struct EngineBadgeChip: View {
    let badge: EngineBadge

    var body: some View {
        Text(badge.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(foreground)
            .background(background.opacity(0.18), in: Capsule())
            .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch badge {
        case .ai: return .purple
        case .local, .default: return .blue
        case .classic: return .teal
        case .freeTier: return .green
        case .paid: return .orange
        case .advanced: return .secondary
        }
    }

    private var background: Color { foreground }
}

// MARK: - Atalhos

struct ShortcutsSettingsView: View {
    @EnvironmentObject private var appState: AppState

    private var translateConflicts: [HotkeyChord] {
        [
            appState.settings.translateAndSendHotkey,
            appState.settings.popupHotkey,
        ]
    }

    private var sendConflicts: [HotkeyChord] {
        [
            appState.settings.translateOnlyHotkey,
            appState.settings.popupHotkey,
        ]
    }

    private var popupConflicts: [HotkeyChord] {
        [
            appState.settings.translateOnlyHotkey,
            appState.settings.translateAndSendHotkey,
        ]
    }

    var body: some View {
        Form {
            Section("Global shortcuts") {
                HStack {
                    Text("Translate")
                    Spacer()
                    HotkeyRecorderButton(
                        chord: appState.settingsBinding(\.translateOnlyHotkey),
                        conflictingChords: translateConflicts
                    )
                }
                HStack {
                    Text("Translate and send")
                    Spacer()
                    HotkeyRecorderButton(
                        chord: appState.settingsBinding(\.translateAndSendHotkey),
                        conflictingChords: sendConflicts
                    )
                }
                Button("Restore defaults (⌃⌥T / ⌃⌥⏎ / ⌃⌥Y)") {
                    appState.resetHotkeysToDefaults()
                }
            }

            Section("Popup mode") {
                Toggle(
                    "Enable popup mode",
                    isOn: appState.settingsBinding(\.popupModeEnabled)
                )
                HStack {
                    Text("Popup shortcut")
                    Spacer()
                    HotkeyRecorderButton(
                        chord: appState.settingsBinding(\.popupHotkey),
                        conflictingChords: popupConflicts
                    )
                    .disabled(!appState.settings.popupModeEnabled)
                }
                Text(
                    "Shows the translation in a panel. In editable fields, you can Copy or Replace."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text(
                    "Click the shortcut and press the new combination. Esc cancels. Prefer ⌃⌥ to avoid conflicts. Translate replaces in place (editable field) or opens the panel with Copy only (read-only). The popup shortcut — if on — opens the panel for any selection, with Replace when the field is editable. With “Enter translates and sends”, Enter alone also translates and sends."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissões

struct PermissionsSettingsView: View {
    @State private var accessibilityOK = Permissions.isAccessibilityTrusted()
    @State private var inputMonitoringOK = Permissions.isInputMonitoringGranted()
    @State private var didRegisterPrompts = false

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Required") {
                permissionRow(
                    ok: accessibilityOK,
                    okText: "Accessibility granted",
                    pendingText: "Accessibility required",
                    caption: "Read and replace text in the focused field.",
                    open: {
                        Permissions.openAccessibilitySettings()
                    }
                )
                permissionRow(
                    ok: inputMonitoringOK,
                    okText: "Input Monitoring granted",
                    pendingText: "Input Monitoring required",
                    caption: "Captures global shortcuts (⌃⌥T, ⌃⌥⏎) in any app.",
                    open: {
                        Permissions.openInputMonitoringSettings()
                    }
                )
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: registerPrivacyPromptsOnce)
        .onReceive(timer) { _ in
            accessibilityOK = Permissions.isAccessibilityTrusted()
            inputMonitoringOK = Permissions.isInputMonitoringGranted()
        }
    }

    private func registerPrivacyPromptsOnce() {
        guard !didRegisterPrompts else { return }
        didRegisterPrompts = true
        Permissions.registerAccessibilityPromptIfNeeded()
        Permissions.registerInputMonitoringIfNeeded()
    }

    private func permissionRow(
        ok: Bool,
        okText: LocalizedStringKey,
        pendingText: LocalizedStringKey,
        caption: LocalizedStringKey,
        open: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? Color.green : Color.orange)
                Text(ok ? okText : pendingText)
                Spacer()
                if !ok {
                    Button("Open System Settings", action: open)
                        .accessibilityHint("Opens System Settings to grant this permission")
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(ok ? okText : pendingText) + Text(verbatim: ". ") + Text(caption))
    }
}

// MARK: - Teste

struct TestSettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var testText = String(localized: "Hello, world!")
    @State private var isTesting = false
    @State private var testResult: Result<String, Error>?

    var body: some View {
        Form {
            Section("Input") {
                TextField("Text", text: $testText)
                LabeledContent("Current engine") {
                    Label(
                        appState.settings.providerKind.displayName,
                        systemImage: appState.settings.providerKind.symbolName
                    )
                }
                LabeledContent(
                    "Target (outgoing)",
                    value: LanguageCode.displayName(for: appState.settings.outgoingTargetLanguage)
                )
                Button(isTesting ? "Translating…" : "Test translation") {
                    Task { await runTest() }
                }
                .disabled(
                    isTesting
                        || appState.orchestrator.isBusy
                        || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Result") {
                resultView
            }

            Section {
                Text("Checks the engine and the “text I write” pair in this window. Does not open the panel, HUD, or fire shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var resultView: some View {
        if isTesting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Translating…")
                    .foregroundStyle(.secondary)
            }
        } else {
            switch testResult {
            case .none:
                Text("Run a test to validate the configured engine and language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .success(let translated):
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(translated)
                        .textSelection(.enabled)
                }
            case .failure(let error):
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error.localizedDescription)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func runTest() async {
        guard !appState.orchestrator.isBusy else {
            testResult = .failure(
                NSError(
                    domain: "Prism",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            String(localized: "A shortcut translation is still running. Wait and try again.")
                    ]
                )
            )
            return
        }
        isTesting = true
        defer { isTesting = false }
        let runID = AppLog.beginRun(prefix: "TEST")
        defer { AppLog.endRun() }
        let from = appState.settings.resolvedOutgoingSourceLanguage
        let to = appState.settings.outgoingTargetLanguage
        AppLog.info(.settings, "── Teste \(runID) iniciado ──")
        AppLog.info(
            .settings,
            "Disparo: botão «Testar tradução» — \(testText.count) caracteres, «\(AppLog.preview(testText))»"
        )
        AppLog.info(
            .settings,
            "Motor: \(appState.settings.engineLogDescription) · \(LanguageCode.pairLabel(from: from, to: to))"
        )
        do {
            let started = Date()
            let result = try await appState.engine.translate(
                testText,
                from: from,
                to: to
            )
            testResult = .success(result.text)
            AppLog.info(
                .settings,
                "── Teste \(runID) OK em \(AppLog.duration(since: started)) — \(result.text.count) caracteres: «\(AppLog.preview(result.text))» ──"
            )
        } catch {
            testResult = .failure(error)
            AppLog.error(
                .settings,
                "── Teste \(runID) falhou — \(error.localizedDescription) ──"
            )
        }
    }
}

// MARK: - Sobre

struct AboutSettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var isCheckingUpdate = false
    @State private var updateResult: UpdateCheckResult?
    @State private var diagnosticNote: String?

    private var marketingVersion: String { AppRelease.marketingVersion }
    private var buildNumber: String { AppRelease.buildNumber }

    var body: some View {
        Form {
            // ── Identidade ──────────────────────────────────────────
            Section {
                HStack(alignment: .center, spacing: 14) {
                    PrismGlyph(lineWidth: 2.2)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Prism")
                            .font(QTDesign.Fonts.title)
                        Text("Prism Translate")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "Version %@ (%@)"), marketingVersion, buildNumber))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    String(format: String(localized: "Prism Translate, version %@, build %@"), marketingVersion, buildNumber))
            }

            // ── O App ───────────────────────────────────────────────
            Section("The App") {
                Text(
                    "Translates the focused field in any app — one shortcut, in place, no copy and paste."
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Engines: Apple Translation on this Mac, DeepL, Google Translate, and local LM Studio. The interface lives in the menu bar — almost invisible."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            // ── O Time ──────────────────────────────────────────────
            Section("The Team") {
                HStack(alignment: .top, spacing: 12) {
                    AboutDeveloperAvatar()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppCredits.developerName)
                            .font(.body.weight(.medium))
                        Text(AppCredits.developerRole)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)

                Text(AppCredits.bio)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                aboutRow("Location", AppCredits.location)
                Button("GitHub \(AppCredits.githubHandle)") {
                    NSWorkspace.shared.open(AppRelease.githubProfileURL)
                }
                .accessibilityLabel(String(format: String(localized: "Open GitHub for %@"), AppCredits.developerName))
            }

            // ── História ────────────────────────────────────────────
            Section("History") {
                aboutRow("Created", String(localized: "August 2, 2026"))
                aboutRow("Original name", "QuickTranslate")
                aboutRow("Rebrand", String(localized: "Prism Translate — Aug 2026"))
                Text(
                    "It started as a simple menu-bar translator that replaces text in place. The rebrand brought a new identity, but the spirit is the same: translate without getting in the way."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            // ── Novidades ───────────────────────────────────────────
            Section(String(format: String(localized: "What’s new in %@"), marketingVersion)) {
                Text(ChangelogHighlights.summaryForCurrentVersion())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── Atualizações ────────────────────────────────────────
            Section("Updates") {
                aboutRow("Channel", String(localized: "Pre-release"))
                aboutRow("Distribution", String(localized: "GitHub Releases (outside the App Store)"))

                Button {
                    Task { await checkForUpdates() }
                } label: {
                    HStack {
                        Text(isCheckingUpdate ? "Checking…" : "Check for Updates")
                        if isCheckingUpdate {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isCheckingUpdate)
                .accessibilityLabel("Check for Updates")

                if let updateResult {
                    Text(updateMessage(updateResult))
                        .font(.caption)
                        .foregroundStyle(updateMessageColor(updateResult))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .available(let version, let url) = updateResult {
                    Button(String(format: String(localized: "Download %@…"), version)) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            // ── Suporte ─────────────────────────────────────────────
            Section("Support") {
                Button("Reopen setup tutorial…") {
                    appState.showOnboarding()
                }
                .accessibilityLabel("Reopen setup tutorial")

                Button("Report a problem…") {
                    NSWorkspace.shared.open(
                        AppRelease.reportIssueURL(
                            version: marketingVersion,
                            build: buildNumber,
                            macOS: AppRelease.runningMacOS
                        )
                    )
                }
                .accessibilityHint("Opens a GitHub issue with version and system filled in")

                Button("Copy app info") {
                    copyAppInfo()
                    flashDiagnosticNote(String(localized: "Copied info"))
                }
                .accessibilityHint("Copies version, build, identifier, and current engine to the clipboard")

                Button("Open Logs…") {
                    appState.settingsSelection = .logs
                    appState.rememberSettingsSection(.logs)
                }
                .accessibilityHint("Shows the Logs section in this window")

                if let diagnosticNote {
                    Text(diagnosticNote)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }
            }

            // ── Legal ───────────────────────────────────────────────
            Section("Legal") {
                Text(AppRelease.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(AppRelease.licenseName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    "Source code is available for noncommercial use. Apple Translation, DeepL, Google Translate, and LM Studio are trademarks of their owners. Prism uses them as optional translation engines."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

                Button("View license") {
                    if let url = AppRelease.bundledLicenseURL {
                        NSWorkspace.shared.open(url)
                    } else {
                        NSWorkspace.shared.open(AppRelease.licenseURL)
                    }
                }
                .accessibilityLabel("Open the PolyForm Noncommercial license text")

                Button("PolyForm Noncommercial 1.0.0") {
                    NSWorkspace.shared.open(AppRelease.licenseURL)
                }
                .accessibilityLabel("Open the PolyForm Noncommercial license page")

                Button("GitHub repository") {
                    NSWorkspace.shared.open(AppRelease.repositoryURL)
                }
                .accessibilityLabel("Open repository on GitHub")

                Button("Releases page") {
                    NSWorkspace.shared.open(AppRelease.releasesURL)
                }
                .accessibilityLabel("Open the GitHub releases page")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func aboutRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }

    private func copyAppInfo() {
        let info = [
            "Prism Translate \(marketingVersion) (\(buildNumber))",
            "Bundle: \(AppRelease.bundleIdentifier)",
            String(localized: "Channel: pre-release"),
            String(format: String(localized: "System: %@"), AppRelease.runningMacOS),
            String(localized: "Minimum: macOS 15.0"),
            String(format: String(localized: "Engine: %@"), appState.settings.providerKind.displayName),
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
        AppLog.info(.settings, "Botão «Copiar informações» na aba Sobre")
    }

    private func checkForUpdates() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        AppLog.info(.settings, "Botão «Verificar atualizações» — consultando GitHub Releases")
        let result = await GitHubUpdateChecker.check(currentVersion: marketingVersion)
        updateResult = result
        switch result {
        case .available(let version, _):
            AppLog.info(.settings, "Atualização disponível: \(version)")
        case .upToDate:
            AppLog.info(.settings, "Já está na versão mais recente")
        case .aheadOfRelease(let published):
            AppLog.info(.settings, "Build local à frente da publicação \(published)")
        case .nonePublished:
            AppLog.info(.settings, "Nenhum release público no GitHub")
        case .failed(let message):
            AppLog.error(.settings, "Falha ao verificar atualizações: \(message)")
        }
    }

    private func updateMessage(_ result: UpdateCheckResult) -> String {
        switch result {
        case .upToDate:
            return String(localized: "You’re already on the latest version.")
        case .aheadOfRelease(let published):
            return String(format: String(localized: "This build is ahead of the last published release (%@)."), published)
        case .available(let version, _):
            return String(format: String(localized: "Version %@ is available."), version)
        case .nonePublished:
            return String(localized: "No version has been published on GitHub yet. When one is, this button will point to the download.")
        case .failed(let message):
            return String(format: String(localized: "Couldn’t check: %@"), message)
        }
    }

    private func updateMessageColor(_ result: UpdateCheckResult) -> Color {
        switch result {
        case .failed: return .red
        case .available: return .green
        default: return .secondary
        }
    }

    private func flashDiagnosticNote(_ text: String) {
        diagnosticNote = text
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if diagnosticNote == text {
                diagnosticNote = nil
            }
        }
    }
}

private struct AboutDeveloperAvatar: View {
    var body: some View {
        AsyncImage(url: AppRelease.githubAvatarURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
