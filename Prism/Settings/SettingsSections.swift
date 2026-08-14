import AppKit
import Combine
import SwiftUI

// MARK: - Geral

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                Text("Os controles Ligado, Enter, HUD, idiomas destino e modo popup também ficam no ícone da barra de menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("O atalho Traduzir substitui no lugar se o campo for editável; em texto só leitura abre o painel (Copiar). O modo popup (opt-in) abre o painel em qualquer seleção.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tradução") {
                Toggle("Ligado", isOn: appState.settingsBinding(\.isEnabled))
                Toggle(
                    "Enter traduz e envia",
                    isOn: appState.settingsBinding(\.enterTranslatesAndSends))
                Toggle(
                    "Aviso perto do ponteiro",
                    isOn: appState.settingsBinding(\.showStatusHUD)
                )
                Text("Mostra «Traduzindo…», concluído e erros junto ao mouse ao usar o atalho.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    @State private var applePackRows: [ApplePackRow] = []
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
        // Refresh automático de modelos fica no AppState (fora do ciclo de layout da Form).
        // Aqui só o botão “Atualizar” força consulta à API.
    }

    @ViewBuilder
    private var providerFields: some View {
        switch appState.settings.providerKind {
        case .apple:
            Text("Sem API key. A tradução roda no aparelho com os idiomas baixados no macOS.")
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
                            Button("Baixar…") {
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
                Button("Baixar idiomas usados…") {
                    Task { await prepareApplePacks() }
                }
                .disabled(applePackState == .downloading)
                .accessibilityHint("Abre o diálogo do sistema para baixar os pacotes de origem e destino")
            }

            Button("Abrir Idiomas de Tradução nos Ajustes…") {
                Permissions.openTranslationLanguagesSettings()
            }
            .accessibilityHint("Abre Ajustes do Sistema na lista de idiomas de tradução")

            Text(
                "Baixe origem e destino. O botão acima pede o download pelo diálogo do macOS; se ele não aparecer, use Ajustes › Geral › Idioma e Região › Idiomas de Tradução. Com “Modo no dispositivo” ligado, a tradução fica offline."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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

    private var applePackTaskID: String {
        "\(appState.settings.providerKind.rawValue)-\(appState.settings.outgoingTargetLanguage)-\(appState.settings.outgoingSourceLanguage ?? "auto")-\(appState.settings.incomingTargetLanguage)-\(appState.settings.incomingSourceLanguage ?? "auto")"
    }

    private var applePackLabel: String {
        switch applePackState {
        case .checking: return "Verificando idiomas…"
        case .installed: return "Idiomas de tradução prontos"
        case .needsDownload: return "Falta baixar um ou mais idiomas"
        case .downloading: return "Baixando — confirme o diálogo do sistema"
        case .unsupported: return "Par de idiomas não suportado"
        case .failed(let message): return "Falha: \(message)"
        }
    }

    private var applePackIcon: String { packIcon(for: applePackState) }
    private var applePackColor: Color { packColor(for: applePackState) }

    private func packStatusText(for state: LanguagePackState) -> String {
        switch state {
        case .checking: return "Verificando…"
        case .installed: return "Pronto"
        case .needsDownload: return "Não baixado"
        case .downloading: return "Baixando…"
        case .unsupported: return "Não suportado"
        case .failed: return "Falhou"
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
        if force {
            AppLog.info(
                .settings,
                "Botão «Atualizar» modelos — consultando \(targets.map(\.displayName).joined(separator: ", "))"
            )
        }
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
                    "Clique no atalho e pressione a nova combinação. Esc cancela. Prefira ⌃⌥ para evitar conflitos. O atalho Traduzir substitui no lugar (campo editável) ou abre o painel só com Copiar (só leitura). O atalho de popup — se estiver ligado — abre o painel em qualquer seleção, com Substituir quando o campo for editável. Com “Enter traduz e envia”, Enter sozinho também traduz e envia."
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
                    isTesting
                        || appState.orchestrator.isBusy
                        || testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Resultado") {
                resultView
            }

            Section {
                Text("Valida o motor e o par «texto que escrevo» nesta janela. Não abre o painel, o HUD nem dispara atalhos.")
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
        guard !appState.orchestrator.isBusy else {
            testResult = .failure(
                NSError(
                    domain: "Prism",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Uma tradução por atalho ainda está em andamento. Aguarde e tente de novo."
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
                        Text("Versão \(marketingVersion) (\(buildNumber))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Prism Translate, versão \(marketingVersion), build \(buildNumber)")
            }

            // ── O App ───────────────────────────────────────────────
            Section("O App") {
                Text(
                    "Traduz o texto do campo focado em qualquer app — um atalho, no lugar, sem copiar e colar."
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Motores: Apple Translation no aparelho, DeepL, Google Translate e IA (Gemini, Groq, Mistral e outros). A interface fica na barra de menus — quase invisível."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            // ── O Time ──────────────────────────────────────────────
            Section("O Time") {
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

                aboutRow("Localização", AppCredits.location)
                Button("GitHub \(AppCredits.githubHandle)") {
                    NSWorkspace.shared.open(AppRelease.githubProfileURL)
                }
                .accessibilityLabel("Abrir GitHub de \(AppCredits.developerName)")
            }

            // ── História ────────────────────────────────────────────
            Section("História") {
                aboutRow("Criado em", "2 de agosto de 2026")
                aboutRow("Nome original", "QuickTranslate")
                aboutRow("Rebrand", "Prism Translate — ago. 2026")
                Text(
                    "Nasceu como um tradutor simples de menu bar focado em substituir o texto no lugar. O rebrand trouxe uma identidade nova, mas o espírito continua o mesmo: traduzir sem atrapalhar."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            // ── Novidades ───────────────────────────────────────────
            Section("Novidades da \(marketingVersion)") {
                Text(ChangelogHighlights.summaryForCurrentVersion())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── Atualizações ────────────────────────────────────────
            Section("Atualizações") {
                aboutRow("Canal", "Pré-lançamento")
                aboutRow("Distribuição", "GitHub Releases (fora da App Store)")

                Button {
                    Task { await checkForUpdates() }
                } label: {
                    HStack {
                        Text(isCheckingUpdate ? "Verificando…" : "Verificar atualizações")
                        if isCheckingUpdate {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isCheckingUpdate)
                .accessibilityLabel("Verificar atualizações")

                if let updateResult {
                    Text(updateMessage(updateResult))
                        .font(.caption)
                        .foregroundStyle(updateMessageColor(updateResult))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .available(let version, let url) = updateResult {
                    Button("Baixar \(version)…") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            // ── Suporte ─────────────────────────────────────────────
            Section("Suporte") {
                Button("Reabrir tutorial de configuração…") {
                    appState.showOnboarding()
                }
                .accessibilityLabel("Reabrir tutorial de configuração")

                Button("Reportar problema…") {
                    NSWorkspace.shared.open(
                        AppRelease.reportIssueURL(
                            version: marketingVersion,
                            build: buildNumber,
                            macOS: AppRelease.runningMacOS
                        )
                    )
                }
                .accessibilityHint("Abre uma issue no GitHub com versão e sistema preenchidos")

                Button("Copiar informações do app") {
                    copyAppInfo()
                    flashDiagnosticNote("Informações copiadas")
                }
                .accessibilityHint("Copia versão, build, identificador e motor atual para a área de transferência")

                Button("Abrir Logs…") {
                    appState.settingsSelection = .logs
                    appState.rememberSettingsSection(.logs)
                }
                .accessibilityHint("Mostra a seção Logs nesta janela")

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

                Text(
                    "Apple Translation, DeepL, Google Translate e os provedores de IA são marcas dos respectivos donos. O Prism os usa como motores de tradução opcionais."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Repositório no GitHub") {
                    NSWorkspace.shared.open(AppRelease.repositoryURL)
                }
                .accessibilityLabel("Abrir repositório no GitHub")

                Button("Página de releases") {
                    NSWorkspace.shared.open(AppRelease.releasesURL)
                }
                .accessibilityLabel("Abrir página de releases no GitHub")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func aboutRow(_ title: String, _ value: String) -> some View {
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
            "Canal: pré-lançamento",
            "Sistema: \(AppRelease.runningMacOS)",
            "Mínimo: macOS 15.0",
            "Motor: \(appState.settings.providerKind.displayName)",
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
            return "Você já está na versão mais recente."
        case .aheadOfRelease(let published):
            return "Esta build está à frente da última publicação (\(published))."
        case .available(let version, _):
            return "Versão \(version) disponível."
        case .nonePublished:
            return "Ainda não há versão publicada no GitHub. Quando houver, este botão aponta para o download."
        case .failed(let message):
            return "Não foi possível verificar: \(message)"
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
