import AppKit
import Combine
import SwiftUI

// MARK: - Geral

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("Os controles Ligado, Enter e idiomas também ficam no ícone da barra de menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tradução") {
                Toggle("Ligado", isOn: appState.settingsBinding(\.isEnabled))
                Toggle(
                    "Enter traduz e envia",
                    isOn: appState.settingsBinding(\.enterTranslatesAndSends))
            }

            Section("Texto que leio") {
                Picker(
                    "Traduzir de",
                    selection: appState.settingsBinding(\.incomingSourceLanguage)
                ) {
                    Text("Detectar idioma").tag(String?.none)
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(String?.some(language.id))
                    }
                }
                Picker(
                    "Traduzir para",
                    selection: appState.settingsBinding(\.incomingTargetLanguage)
                ) {
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(language.id)
                    }
                }
                Text("Usado em texto só leitura e no painel ao ler conversas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Texto que escrevo") {
                Picker(
                    "Traduzir de",
                    selection: appState.settingsBinding(\.outgoingSourceLanguage)
                ) {
                    Text("Detectar idioma").tag(String?.none)
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(String?.some(language.id))
                    }
                }
                Picker(
                    "Traduzir para",
                    selection: appState.settingsBinding(\.outgoingTargetLanguage)
                ) {
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(language.id)
                    }
                }
                Text("Usado ao substituir texto em campos editáveis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mais opções") {
                Button("Abrir Atalhos…") {
                    appState.settingsSelection = .shortcuts
                    appState.rememberSettingsSection(.shortcuts)
                }
                .accessibilityLabel("Ir para seção Atalhos")
                .accessibilityHint("Mostra a seção Atalhos nesta janela")
                Button("Abrir Provedor…") {
                    appState.settingsSelection = .provider
                    appState.rememberSettingsSection(.provider)
                }
                .accessibilityLabel("Ir para seção Provedor")
                .accessibilityHint("Mostra a seção Provedor nesta janela")
            }

            Section("Sistema") {
                Toggle("Abrir no login", isOn: appState.settingsBinding(\.openAtLogin))
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
    @State private var applePackState: LanguagePackState = .checking

    var body: some View {
        Form {
            Section("Motor") {
                Picker("Motor", selection: appState.settingsBinding(\.providerKind)) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            }

            Section("Configuração") {
                providerFields
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: persistSecrets)
    }

    @ViewBuilder
    private var providerFields: some View {
        switch appState.settings.providerKind {
        case .apple:
            Text("Sem configuração. Usa o Translation framework da Apple (on-device).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Label(applePackLabel, systemImage: applePackIcon)
                    .foregroundStyle(applePackColor)
                Spacer()
                if applePackState == .checking || applePackState == .downloading {
                    ProgressView()
                        .controlSize(.small)
                } else if applePackState != .installed {
                    Button("Preparar idiomas…") {
                        Task { await prepareApplePacks() }
                    }
                }
            }
            .task(
                id:
                    "\(appState.settings.outgoingTargetLanguage)-\(appState.settings.outgoingSourceLanguage ?? "auto")-\(appState.settings.incomingTargetLanguage)-\(appState.settings.incomingSourceLanguage ?? "auto")"
            ) {
                await refreshApplePackState()
            }
        case .deepl:
            SecureField("API Key DeepL", text: $deeplKey)
                .help("Chave da API DeepL (conta Free ou Pro). Guardada no Keychain.")
                .accessibilityHint("Chave secreta da API DeepL, armazenada no Keychain")
                .onChange(of: deeplKey) { _, newValue in
                    KeychainStore.set(newValue, for: .deeplAPIKey)
                }
            Toggle(
                "Usar API Free (api-free.deepl.com)",
                isOn: appState.settingsBinding(\.deeplUseFreeAPI))
        case .google:
            SecureField("API Key Google Cloud Translation", text: $googleKey)
                .help("Chave da API Google Cloud Translation. Guardada no Keychain.")
                .accessibilityHint("Chave secreta da API Google Cloud, armazenada no Keychain")
                .onChange(of: googleKey) { _, newValue in
                    KeychainStore.set(newValue, for: .googleAPIKey)
                }
        case .openAICompatible:
            TextField("Base URL", text: appState.settingsBinding(\.openAIBaseURL))
                .help("Endpoint compatível com OpenAI, por exemplo LM Studio local.")
            TextField("Modelo", text: appState.settingsBinding(\.openAIModel))
            SecureField("API Key (opcional)", text: $openAIKey)
                .help("Opcional para servidores locais. Guardada no Keychain.")
                .accessibilityHint("Chave de API opcional, armazenada no Keychain")
                .onChange(of: openAIKey) { _, newValue in
                    KeychainStore.set(newValue, for: .openAIAPIKey)
                }
            Text("LM Studio padrão: http://localhost:1234/v1")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .customHTTP:
            TextField("URL", text: appState.settingsBinding(\.customHTTPURL))
            TextField("Método", text: appState.settingsBinding(\.customHTTPMethod))
            TextField(
                "Headers JSON", text: appState.settingsBinding(\.customHTTPHeadersJSON),
                axis: .vertical
            )
            .lineLimit(2...4)
            TextField(
                "Body template", text: appState.settingsBinding(\.customHTTPBodyTemplate),
                axis: .vertical
            )
            .lineLimit(3...6)
            TextField(
                "JSON path da resposta", text: appState.settingsBinding(\.customHTTPResponsePath))
            Text("Placeholders: {{text}}, {{to}}, {{from}}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var applePackLabel: String {
        switch applePackState {
        case .checking: return "Verificando idiomas…"
        case .installed: return "Idiomas de tradução prontos"
        case .needsDownload: return "Pacotes de idioma não baixados"
        case .downloading: return "Baixando — confirme o diálogo do sistema"
        case .unsupported: return "Par de idiomas não suportado"
        case .failed(let message): return "Falha: \(message)"
        }
    }

    private var applePackIcon: String {
        switch applePackState {
        case .installed: return "checkmark.circle"
        case .checking, .downloading: return "arrow.down.circle"
        case .needsDownload: return "exclamationmark.triangle"
        case .unsupported, .failed: return "xmark.circle"
        }
    }

    private var applePackColor: Color {
        switch applePackState {
        case .installed: return .green
        case .checking, .downloading: return .primary
        case .needsDownload: return .orange
        case .unsupported, .failed: return .red
        }
    }

    private func refreshApplePackState() async {
        applePackState = .checking
        var worst: LanguagePackState = .installed
        for pair in AppleTranslationBridge.packPairs(settings: appState.settings) {
            let state = await appState.appleBridge.languagePackState(
                from: pair.source,
                to: pair.target
            )
            worst = Self.mergePackState(worst, state)
            if case .unsupported = worst { break }
            if worst.isFailed { break }
        }
        applePackState = worst
    }

    private func prepareApplePacks() async {
        applePackState = .downloading
        var lastError: Error?
        var anyNeedsWork = false
        for pair in AppleTranslationBridge.packPairs(settings: appState.settings) {
            do {
                try await appState.appleBridge.ensureLanguagePacks(
                    from: pair.source, to: pair.target)
            } catch {
                lastError = error
                anyNeedsWork = true
            }
        }
        if let lastError, anyNeedsWork {
            let pair = AppleTranslationBridge.defaultPackPair(settings: appState.settings)
            let current = await appState.appleBridge.languagePackState(
                from: pair.source,
                to: pair.target
            )
            applePackState =
                current == .installed
                ? .installed
                : .failed(lastError.localizedDescription)
        } else {
            applePackState = .installed
        }
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
        KeychainStore.set(deeplKey, for: .deeplAPIKey)
        KeychainStore.set(googleKey, for: .googleAPIKey)
        KeychainStore.set(openAIKey, for: .openAIAPIKey)
    }
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
            Section("Atalhos globais") {
                HStack {
                    Text("Traduzir")
                    Spacer()
                    HotkeyRecorderButton(
                        chord: appState.settingsBinding(\.translateOnlyHotkey),
                        conflictingChords: translateConflicts
                    )
                }
                HStack {
                    Text("Traduzir e enviar")
                    Spacer()
                    HotkeyRecorderButton(
                        chord: appState.settingsBinding(\.translateAndSendHotkey),
                        conflictingChords: sendConflicts
                    )
                }
                Button("Restaurar padrões (⌃⌥T / ⌃⌥⏎ / ⌃⌥Y)") {
                    appState.resetHotkeysToDefaults()
                }
            }

            Section("Modo popup") {
                Toggle(
                    "Ativar modo popup",
                    isOn: appState.settingsBinding(\.popupModeEnabled)
                )
                HStack {
                    Text("Atalho do popup")
                    Spacer()
                    HotkeyRecorderButton(
                        chord: appState.settingsBinding(\.popupHotkey),
                        conflictingChords: popupConflicts
                    )
                    .disabled(!appState.settings.popupModeEnabled)
                }
                Text(
                    "Mostra a tradução num painel. Em campos editáveis, permite Copiar ou Substituir."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text(
                    "Clique no atalho e pressione a nova combinação. Esc cancela. Prefira ⌃⌥ para evitar conflitos com outros apps."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("Com “Enter traduz e envia” ligado, Enter sozinho também traduz e envia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "No atalho principal, texto só leitura abre o painel (Copiar). O atalho de popup funciona em qualquer seleção."
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

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Necessárias") {
                permissionRow(
                    ok: accessibilityOK,
                    okText: "Acessibilidade concedida",
                    pendingText: "Acessibilidade necessária",
                    caption: "Ler e substituir o texto do campo focado.",
                    open: {
                        _ = Permissions.isAccessibilityTrusted(prompt: true)
                        Permissions.openAccessibilitySettings()
                    }
                )
                permissionRow(
                    ok: inputMonitoringOK,
                    okText: "Monitoramento de Entrada concedido",
                    pendingText: "Monitoramento de Entrada necessário",
                    caption: "Captura os atalhos globais (⌃⌥T, ⌃⌥⏎) em qualquer app.",
                    open: {
                        _ = Permissions.requestInputMonitoring()
                        Permissions.openInputMonitoringSettings()
                    }
                )
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            accessibilityOK = Permissions.isAccessibilityTrusted()
            inputMonitoringOK = Permissions.isInputMonitoringGranted()
        }
    }

    private func permissionRow(
        ok: Bool,
        okText: String,
        pendingText: String,
        caption: String,
        open: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? Color.green : Color.orange)
                Text(ok ? okText : pendingText)
                Spacer()
                if !ok {
                    Button("Abrir Ajustes", action: open)
                        .accessibilityHint("Abre Ajustes do Sistema para conceder esta permissão")
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ok ? okText : pendingText). \(caption)")
    }
}

// MARK: - Teste

struct TestSettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var testText = "Olá, mundo!"
    @State private var isTesting = false
    @State private var testResult: Result<String, Error>?

    var body: some View {
        Form {
            Section("Entrada") {
                TextField("Texto", text: $testText)
                LabeledContent("Motor atual", value: appState.settings.providerKind.displayName)
                LabeledContent(
                    "Destino (suas)",
                    value: LanguageCode.displayName(for: appState.settings.outgoingTargetLanguage)
                )
                Button(isTesting ? "Traduzindo…" : "Testar tradução") {
                    Task { await runTest() }
                }
                .disabled(
                    isTesting || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Resultado") {
                resultView
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
                Text("Traduzindo…")
                    .foregroundStyle(.secondary)
            }
        } else {
            switch testResult {
            case .none:
                Text("Rode um teste para validar o motor e o idioma configurados.")
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
        isTesting = true
        defer { isTesting = false }
        AppLog.info(
            .settings,
            "teste manual iniciado — chars=\(testText.count), provider=\(appState.settings.providerKind.displayName)"
        )
        do {
            let result = try await appState.engine.translate(
                testText,
                from: appState.settings.resolvedOutgoingSourceLanguage,
                to: appState.settings.outgoingTargetLanguage
            )
            testResult = .success(result.text)
            AppLog.info(.settings, "teste manual OK — \(result.text.count) chars")
        } catch {
            testResult = .failure(error)
            AppLog.error(.settings, "teste manual falhou: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sobre

struct AboutSettingsView: View {
    @EnvironmentObject private var appState: AppState

    private var version: String {
        let short =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "globe")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QuickTranslate")
                            .font(.headline)
                        Text("Versão \(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Atalhos atuais") {
                Button {
                    appState.settingsSelection = .shortcuts
                    appState.rememberSettingsSection(.shortcuts)
                } label: {
                    LabeledContent(
                        "Traduzir", value: appState.settings.translateOnlyHotkey.displayString)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir seção Atalhos")

                Button {
                    appState.settingsSelection = .shortcuts
                    appState.rememberSettingsSection(.shortcuts)
                } label: {
                    LabeledContent(
                        "Traduzir e enviar",
                        value: appState.settings.translateAndSendHotkey.displayString)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir seção Atalhos")

                if appState.settings.popupModeEnabled {
                    Button {
                        appState.settingsSelection = .shortcuts
                        appState.rememberSettingsSection(.shortcuts)
                    } label: {
                        LabeledContent(
                            "Popup", value: appState.settings.popupHotkey.displayString)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Abrir seção Atalhos")
                }
            }

            Section("Ajuda") {
                Button("Reabrir tutorial de configuração…") {
                    // Tutorial empilha com Dock (.onboarding); Preferências pode permanecer.
                    appState.showOnboarding()
                }
                .accessibilityLabel("Reabrir tutorial de configuração")
            }
        }
        .formStyle(.grouped)
    }
}
