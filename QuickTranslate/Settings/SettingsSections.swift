import AppKit
import Combine
import SwiftUI

// MARK: - Geral

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Tradução") {
                Toggle("Ligado", isOn: appState.settingsBinding(\.isEnabled))
                Toggle(
                    "Enter traduz e envia",
                    isOn: appState.settingsBinding(\.enterTranslatesAndSends))
            }

            Section("Idiomas") {
                Picker("Idioma origem", selection: appState.settingsBinding(\.sourceLanguage)) {
                    Text("Automático").tag(String?.none)
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(String?.some(language.id))
                    }
                }

                Picker("Idioma destino", selection: appState.settingsBinding(\.targetLanguage)) {
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(language.id)
                    }
                }
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
                    "\(appState.settings.targetLanguage)-\(appState.settings.sourceLanguage ?? "auto")"
            ) {
                await refreshApplePackState()
            }
        case .deepl:
            SecureField("API Key DeepL", text: $deeplKey)
                .onChange(of: deeplKey) { _, newValue in
                    KeychainStore.set(newValue, for: .deeplAPIKey)
                }
            Toggle(
                "Usar API Free (api-free.deepl.com)",
                isOn: appState.settingsBinding(\.deeplUseFreeAPI))
        case .google:
            SecureField("API Key Google Cloud Translation", text: $googleKey)
                .onChange(of: googleKey) { _, newValue in
                    KeychainStore.set(newValue, for: .googleAPIKey)
                }
        case .openAICompatible:
            TextField("Base URL", text: appState.settingsBinding(\.openAIBaseURL))
            TextField("Modelo", text: appState.settingsBinding(\.openAIModel))
            SecureField("API Key (opcional)", text: $openAIKey)
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
        let pair = AppleTranslationBridge.defaultPackPair(settings: appState.settings)
        applePackState = await appState.appleBridge.languagePackState(
            from: pair.source,
            to: pair.target
        )
    }

    private func prepareApplePacks() async {
        applePackState = .downloading
        let pair = AppleTranslationBridge.defaultPackPair(settings: appState.settings)
        do {
            try await appState.appleBridge.ensureLanguagePacks(from: pair.source, to: pair.target)
            applePackState = .installed
        } catch {
            let current = await appState.appleBridge.languagePackState(
                from: pair.source,
                to: pair.target
            )
            applePackState =
                current == .installed
                ? .installed
                : .failed(error.localizedDescription)
        }
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

    var body: some View {
        Form {
            Section("Atalhos globais") {
                HStack {
                    Text("Traduzir")
                    Spacer()
                    HotkeyRecorderButton(
                        chord: appState.settingsBinding(\.translateOnlyHotkey),
                        otherChord: appState.settings.translateAndSendHotkey
                    )
                }
                HStack {
                    Text("Traduzir e enviar")
                    Spacer()
                    HotkeyRecorderButton(
                        chord: appState.settingsBinding(\.translateAndSendHotkey),
                        otherChord: appState.settings.translateOnlyHotkey
                    )
                }
                Button("Restaurar padrões (⌃⌥T / ⌃⌥⏎)") {
                    appState.resetHotkeysToDefaults()
                }
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
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
                    "Destino",
                    value: LanguageCode.displayName(for: appState.settings.targetLanguage)
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
        do {
            let result = try await appState.engine.translate(
                testText,
                from: appState.settings.resolvedSourceLanguage,
                to: appState.settings.targetLanguage
            )
            testResult = .success(result)
        } catch {
            testResult = .failure(error)
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
                LabeledContent(
                    "Traduzir", value: appState.settings.translateOnlyHotkey.displayString)
                LabeledContent(
                    "Traduzir e enviar",
                    value: appState.settings.translateAndSendHotkey.displayString)
            }

            Section("Ajuda") {
                Button("Reabrir tutorial de configuração…") {
                    appState.showOnboarding()
                }
            }
        }
        .formStyle(.grouped)
    }
}
