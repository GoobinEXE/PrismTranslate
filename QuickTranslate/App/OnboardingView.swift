import AppKit
import Combine
import SwiftUI

struct OnboardingStep: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let symbolName: String
    let symbolColor: Color
}

/// Wizard de configuração — 6 etapas com gates suaves: dá para continuar sem a
/// permissão, mas o estado pendente fica visível até o checklist final.
struct OnboardingView: View {
    var onClose: () -> Void

    @ObservedObject private var appState = AppState.shared

    @State private var stepIndex = 0
    @State private var accessibilityOK = Permissions.isAccessibilityTrusted()
    @State private var inputMonitoringOK = Permissions.isInputMonitoringGranted()
    @State private var packState: LanguagePackState = .checking
    @State private var didAutoAttemptDownload = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: "Traduza sem sair do campo",
            subtitle:
                "O QuickTranslate traduz e substitui o texto do campo focado em qualquer app — sem janelas, sem copiar e colar.",
            symbolName: "globe",
            symbolColor: .accentColor
        ),
        OnboardingStep(
            id: 1,
            title: "Permissão de Acessibilidade",
            subtitle:
                "É o que permite ler e substituir o texto do campo em que você digita. Sem ela, a tradução não acontece.",
            symbolName: "accessibility",
            symbolColor: .blue
        ),
        OnboardingStep(
            id: 2,
            title: "Monitoramento de Entrada",
            subtitle:
                "Entrega os atalhos globais ao app mesmo com outro app em primeiro plano. Sem ele, ⌃⌥T parece “não fazer nada”.",
            symbolName: "keyboard",
            symbolColor: .orange
        ),
        OnboardingStep(
            id: 3,
            title: "Idioma e tradução",
            subtitle:
                "Escolha o idioma destino. Com Apple Translation, os pacotes são baixados agora e a tradução roda no aparelho.",
            symbolName: "character.bubble",
            symbolColor: .green
        ),
        OnboardingStep(
            id: 4,
            title: "Atalhos na prática",
            subtitle:
                "Estes são os seus atalhos atuais. Dá para trocá-los em Preferências → Atalhos.",
            symbolName: "command",
            symbolColor: .purple
        ),
        OnboardingStep(
            id: 5,
            title: "Tudo pronto",
            subtitle:
                "Confira o checklist — o ícone do globo fica na barra de menus para ligar/desligar, trocar idioma e abrir as Preferências.",
            symbolName: "checkmark.circle.fill",
            symbolColor: .green
        ),
    ]

    private var isLastStep: Bool { stepIndex >= steps.count - 1 }
    private var current: OnboardingStep { steps[stepIndex] }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            content
            footer
        }
        .frame(width: 480, height: 520)
        .background(windowBackground)
        .onAppear(perform: refreshPermissions)
        .onReceive(timer) { _ in
            refreshPermissions()
        }
        .onChange(of: appState.settings.targetLanguage) { _, _ in
            didAutoAttemptDownload = false
            packState = .checking
            refreshLanguagePack()
        }
    }

    /// No Tahoe o material vem do NSGlassEffectView do controller; antes disso,
    /// vibrancy clássica.
    @ViewBuilder
    private var windowBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear
        } else {
            VisualEffectBackground()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .font(QTDesign.Fonts.heading)
                .foregroundStyle(.secondary)
            Text("Configuração")
                .font(QTDesign.Fonts.heading)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Etapa \(stepIndex + 1) de \(steps.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, QTDesign.Spacing.l)
        .padding(.vertical, 12)
    }

    // MARK: - Conteúdo

    private var content: some View {
        VStack(spacing: QTDesign.Spacing.l) {
            ZStack {
                Circle()
                    .fill(current.symbolColor.opacity(0.14))
                    .frame(width: 88, height: 88)
                Image(systemName: current.symbolName)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(current.symbolColor)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .padding(.top, 8)

            VStack(spacing: QTDesign.Spacing.s) {
                Text(current.title)
                    .font(QTDesign.Fonts.title)
                    .multilineTextAlignment(.center)

                Text(current.subtitle)
                    .font(QTDesign.Fonts.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            .animation(stepAnimation, value: stepIndex)

            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 4)
        }
        .padding(.horizontal, QTDesign.Spacing.xl)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch stepIndex {
        case 0:
            VStack(spacing: QTDesign.Spacing.s) {
                shortcutRow(
                    keys: appState.settings.translateOnlyHotkey.displayString,
                    label: "Traduz e substitui no lugar"
                )
                shortcutRow(
                    keys: appState.settings.translateAndSendHotkey.displayString,
                    label: "Traduz, substitui e envia"
                )
            }
        case 1:
            VStack(spacing: QTDesign.Spacing.s) {
                permissionCard(
                    ok: accessibilityOK,
                    okTitle: "Acessibilidade concedida",
                    pendingTitle: "Acessibilidade necessária"
                ) {
                    _ = Permissions.isAccessibilityTrusted(prompt: true)
                    Permissions.openAccessibilitySettings()
                    refreshPermissions()
                }
                if !accessibilityOK {
                    pendingBadge(
                        "Você pode continuar e conceder depois — a tradução só funciona com esta permissão."
                    )
                }
            }
        case 2:
            VStack(spacing: QTDesign.Spacing.s) {
                permissionCard(
                    ok: inputMonitoringOK,
                    okTitle: "Monitoramento de Entrada concedido",
                    pendingTitle: "Monitoramento de Entrada necessário"
                ) {
                    _ = Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                    refreshPermissions()
                }
                if !inputMonitoringOK {
                    pendingBadge(
                        "Sem ela os atalhos globais ficam inativos — o menu bar avisa quando isso acontecer."
                    )
                }
            }
        case 3:
            VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
                GlassSurface {
                    Picker(
                        "Idioma destino",
                        selection: Binding(
                            get: { appState.settings.targetLanguage },
                            set: { appState.setTargetLanguage($0) }
                        )
                    ) {
                        ForEach(LanguageCode.commonTargets) { language in
                            Text(language.displayName).tag(language.id)
                        }
                    }
                    .font(QTDesign.Fonts.body)
                    .padding(12)
                }
                languagePackCard
                QTTipRow(
                    icon: "key.fill",
                    text:
                        "Prefere DeepL, Google ou LM Studio? Configure depois em Preferências → Provedor."
                )
            }
            .onAppear(perform: refreshLanguagePack)
        case 4:
            VStack(spacing: QTDesign.Spacing.s) {
                shortcutRow(
                    keys: appState.settings.translateOnlyHotkey.displayString,
                    label: "Seleciona o texto do campo, traduz e substitui"
                )
                shortcutRow(
                    keys: appState.settings.translateAndSendHotkey.displayString,
                    label: "Faz o mesmo e envia (Enter)"
                )
                shortcutRow(
                    keys: "⏎",
                    label: "Só se “Enter traduz e envia” estiver ligado"
                )
                Text("Altere os atalhos em Preferências → Atalhos se preferir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        case 5:
            checklist
        default:
            EmptyView()
        }
    }

    // MARK: - Rodapé

    private var footer: some View {
        HStack(spacing: QTDesign.Spacing.m) {
            stepDots

            Spacer()

            if stepIndex == 0 {
                Button("Pular") {
                    finish()
                }
                .foregroundStyle(.secondary)
            } else {
                Button("Voltar") {
                    go(to: stepIndex - 1)
                }
            }

            if isLastStep {
                Button("Concluir") {
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Button(stepIndex == 0 ? "Começar" : "Continuar") {
                    go(to: stepIndex + 1)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, QTDesign.Spacing.l)
        .padding(.vertical, 14)
        .controlSize(.regular)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(steps) { step in
                Capsule()
                    .fill(step.id == stepIndex ? Color.accentColor : Color.secondary.opacity(0.28))
                    .frame(width: step.id == stepIndex ? 16 : 6, height: 6)
            }
        }
        .animation(stepAnimation, value: stepIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Etapa \(stepIndex + 1) de \(steps.count)")
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private func go(to index: Int) {
        if let animation = stepAnimation {
            withAnimation(animation) { stepIndex = index }
        } else {
            stepIndex = index
        }
    }

    private func finish() {
        OnboardingController.markCompleted()
        onClose()
    }

    // MARK: - Componentes de etapa

    private func permissionCard(
        ok: Bool,
        okTitle: String,
        pendingTitle: String,
        openAction: @escaping () -> Void
    ) -> some View {
        GlassSurface {
            VStack(spacing: QTDesign.Spacing.m) {
                HStack(spacing: QTDesign.Spacing.s) {
                    Image(
                        systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(ok ? Color.green : Color.orange)
                    Text(ok ? okTitle : pendingTitle)
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }

                Button("Abrir Ajustes do Sistema…", action: openAction)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pendingBadge(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text(text)
                .font(QTDesign.Fonts.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func shortcutRow(keys: String, label: String) -> some View {
        GlassSurface(cornerRadius: QTDesign.Radius.small) {
            HStack {
                QTKeycap(keys: keys)
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Checklist final

    private var languagesReady: Bool {
        appState.settings.providerKind != .apple || packState == .installed
    }

    private var checklist: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
                checklistRow(ok: accessibilityOK, text: "Acessibilidade") {
                    Permissions.openAccessibilitySettings()
                }
                checklistRow(ok: inputMonitoringOK, text: "Monitoramento de Entrada") {
                    Permissions.openInputMonitoringSettings()
                }
                checklistRow(
                    ok: languagesReady,
                    text:
                        "Idiomas de tradução (\(LanguageCode.displayName(for: appState.settings.targetLanguage)))",
                    fix: nil
                )
                checklistRow(ok: true, text: "Ícone do globo na barra de menus", fix: nil)
            }
            .padding(14)
        }
    }

    private func checklistRow(ok: Bool, text: String, fix: (() -> Void)?) -> some View {
        HStack(spacing: QTDesign.Spacing.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(text)
                .font(.system(size: 12.5))
            Spacer(minLength: 0)
            if !ok, let fix {
                Button("Corrigir…", action: fix)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text): \(ok ? "pronto" : "pendente")")
    }

    // MARK: - Language packs (Apple Translation)

    private var languagePackCard: some View {
        GlassSurface {
            VStack(spacing: QTDesign.Spacing.m) {
                HStack(spacing: QTDesign.Spacing.s) {
                    Image(systemName: packIconName)
                        .foregroundStyle(packIconColor)
                    Text(packTitle)
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                    if packState == .checking || packState == .downloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if case .failed(let message) = packState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if packState == .needsDownload || packState.isFailed {
                    Button(packState.isFailed ? "Tentar de novo" : "Baixar idiomas…") {
                        attemptLanguageDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var packTitle: String {
        let target = LanguageCode.displayName(for: appState.settings.targetLanguage)
        switch packState {
        case .checking: return "Verificando idiomas…"
        case .installed: return "Idiomas prontos (destino: \(target))"
        case .needsDownload: return "Download necessário (destino: \(target))"
        case .downloading: return "Baixando idiomas — confirme o diálogo do sistema"
        case .unsupported: return "Par de idiomas não suportado — mude o destino ou o provedor"
        case .failed: return "Download não concluído"
        }
    }

    private var packIconName: String {
        switch packState {
        case .installed: return "checkmark.circle.fill"
        case .checking, .downloading: return "arrow.down.circle"
        case .needsDownload: return "exclamationmark.triangle.fill"
        case .unsupported, .failed: return "xmark.circle.fill"
        }
    }

    private var packIconColor: Color {
        switch packState {
        case .installed: return .green
        case .checking, .downloading: return .blue
        case .needsDownload: return .orange
        case .unsupported, .failed: return .red
        }
    }

    private func refreshLanguagePack() {
        guard stepIndex == 3 || stepIndex == 5, packState != .downloading else { return }
        Task { @MainActor in
            let settings = appState.settings
            let pair = AppleTranslationBridge.defaultPackPair(settings: settings)
            let state = await appState.appleBridge.languagePackState(
                from: pair.source,
                to: pair.target
            )
            guard stepIndex == 3 || stepIndex == 5, packState != .downloading else { return }
            // Keep the failure visible until the pack actually installs or the user retries.
            if packState.isFailed && state != .installed { return }
            packState = state
            if state == .needsDownload && !didAutoAttemptDownload && stepIndex == 3 {
                attemptLanguageDownload()
            }
        }
    }

    private func attemptLanguageDownload() {
        didAutoAttemptDownload = true
        packState = .downloading
        Task { @MainActor in
            let settings = appState.settings
            let pair = AppleTranslationBridge.defaultPackPair(settings: settings)
            do {
                try await appState.appleBridge.ensureLanguagePacks(
                    from: pair.source,
                    to: pair.target
                )
                packState = .installed
            } catch {
                let current = await appState.appleBridge.languagePackState(
                    from: pair.source,
                    to: pair.target
                )
                packState = current == .installed ? .installed : .failed(error.localizedDescription)
            }
        }
    }

    private func refreshPermissions() {
        accessibilityOK = Permissions.isAccessibilityTrusted()
        inputMonitoringOK = Permissions.isInputMonitoringGranted()
        refreshLanguagePack()
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
