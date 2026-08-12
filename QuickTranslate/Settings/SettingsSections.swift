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
    @State private var groqKey: String = KeychainStore.string(for: .groqAPIKey) ?? ""
    @State private var geminiKey: String = KeychainStore.string(for: .geminiAPIKey) ?? ""
    @State private var mistralKey: String = KeychainStore.string(for: .mistralAPIKey) ?? ""
    @State private var deepSeekKey: String = KeychainStore.string(for: .deepSeekAPIKey) ?? ""
    @State private var openRouterKey: String = KeychainStore.string(for: .openRouterAPIKey) ?? ""
    @State private var applePackState: LanguagePackState = .checking
    @State private var isRefreshingModels = false
    @State private var modelRefreshNote: String?

    var body: some View {
        Form {
            Section("Motor") {
                Picker("Motor", selection: appState.settingsBinding(\.providerKind)) {
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

            Section("Configuração") {
                providerFields
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: persistSecrets)
        // Refresh automático fica no AppState (fora do ciclo de layout da Form).
        // Aqui só o botão “Atualizar” força consulta à API.
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
        case .groq:
            SecureField("API Key Groq", text: $groqKey)
                .help("Chave gratuita em console.groq.com. Guardada no Keychain.")
                .accessibilityHint("Chave secreta da API Groq, armazenada no Keychain")
                .onChange(of: groqKey) { _, newValue in
                    KeychainStore.set(newValue, for: .groqAPIKey)
                }
            aiModelFields(
                model: appState.settingsBinding(\.groqModel),
                kind: .groq,
                help: "Ex.: llama-3.1-8b-instant, llama-3.3-70b-versatile"
            )
        case .gemini:
            SecureField("API Key Gemini (AI Studio)", text: $geminiKey)
                .help("Chave gratuita em aistudio.google.com — diferente da Google Cloud Translation. Guardada no Keychain.")
                .accessibilityHint("Chave secreta da API Gemini, armazenada no Keychain")
                .onChange(of: geminiKey) { _, newValue in
                    KeychainStore.set(newValue, for: .geminiAPIKey)
                }
            aiModelFields(
                model: appState.settingsBinding(\.geminiModel),
                kind: .gemini,
                help: "Ex.: gemini-flash-lite-latest, gemini-3.5-flash-lite"
            )
        case .mistral:
            SecureField("API Key Mistral", text: $mistralKey)
                .help("Chave gratuita em console.mistral.ai. Guardada no Keychain.")
                .accessibilityHint("Chave secreta da API Mistral, armazenada no Keychain")
                .onChange(of: mistralKey) { _, newValue in
                    KeychainStore.set(newValue, for: .mistralAPIKey)
                }
            aiModelFields(
                model: appState.settingsBinding(\.mistralModel),
                kind: .mistral,
                help: "Ex.: mistral-small-latest, mistral-medium-latest"
            )
        case .deepSeek:
            SecureField("API Key DeepSeek", text: $deepSeekKey)
                .help("Chave em platform.deepseek.com. Guardada no Keychain.")
                .accessibilityHint("Chave secreta da API DeepSeek, armazenada no Keychain")
                .onChange(of: deepSeekKey) { _, newValue in
                    KeychainStore.set(newValue, for: .deepSeekAPIKey)
                }
            aiModelFields(
                model: appState.settingsBinding(\.deepSeekModel),
                kind: .deepSeek,
                help: "Ex.: deepseek-chat, deepseek-reasoner"
            )
        case .openRouter:
            SecureField("API Key OpenRouter", text: $openRouterKey)
                .help("Chave gratuita em openrouter.ai. Guardada no Keychain.")
                .accessibilityHint("Chave secreta da API OpenRouter, armazenada no Keychain")
                .onChange(of: openRouterKey) { _, newValue in
                    KeychainStore.set(newValue, for: .openRouterAPIKey)
                }
            aiModelFields(
                model: appState.settingsBinding(\.openRouterModel),
                kind: .openRouter,
                help: "Ex.: openrouter/free ou meta-llama/llama-3.3-70b-instruct:free",
                captionExtra: " — roteia modelos gratuitos"
            )
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
        await Task.yield()
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
        KeychainStore.set(groqKey, for: .groqAPIKey)
        KeychainStore.set(geminiKey, for: .geminiAPIKey)
        KeychainStore.set(mistralKey, for: .mistralAPIKey)
        KeychainStore.set(deepSeekKey, for: .deepSeekAPIKey)
        KeychainStore.set(openRouterKey, for: .openRouterAPIKey)
    }

    @ViewBuilder
    private func aiModelFields(
        model: Binding<String>,
        kind: ProviderKind,
        help: String,
        captionExtra: String = ""
    ) -> some View {
        TextField("Modelo", text: model)
            .help(help)
        HStack {
            Text("Recomendado: \(kind.defaultModel ?? "")\(captionExtra)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await refreshModelsIfNeeded(force: true, kinds: [kind]) }
            } label: {
                if isRefreshingModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Atualizar", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isRefreshingModels)
            .help("Consulta a API do provedor e troca o modelo se estiver descontinuado ou houver opção melhor para tradução.")
        }
        if let modelRefreshNote {
            Text(modelRefreshNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func providerAccessibilityLabel(_ kind: ProviderKind) -> String {
        let badges = kind.badges.map(\.rawValue).joined(separator: ", ")
        if badges.isEmpty { return kind.displayName }
        return "\(kind.displayName), \(badges)"
    }

    private func refreshModelsIfNeeded(force: Bool, kinds: [ProviderKind]? = nil) async {
        let kind = appState.settings.providerKind
        let targets = kinds ?? (kind.supportsLiveModelCatalog ? [kind] : [])
        guard !targets.isEmpty else { return }

        // Sai do ciclo de update da view antes de tocar em @State / @Published.
        await Task.yield()
        isRefreshingModels = true
        defer { isRefreshingModels = false }

        var settings = appState.settings
        let result = await AIModelCatalog.refreshModels(
            settings: &settings,
            force: force,
            kinds: targets
        )
        if result.didChange {
            appState.applySettingsAsync(settings)
        }
        if force || result.didChange {
            modelRefreshNote =
                result.notes.isEmpty
                ? "Modelos verificados — configuração atual permanece válida."
                : result.notes.joined(separator: " ")
        }
    }
}

/// Chip compacto ao lado do nome do motor (substitui sufixos entre parênteses).
private struct EngineBadgeChip: View {
    let badge: EngineBadge

    var body: some View {
        Text(badge.rawValue)
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
                LabeledContent("Motor atual") {
                    Label(
                        appState.settings.providerKind.displayName,
                        systemImage: appState.settings.providerKind.symbolName
                    )
                }
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
