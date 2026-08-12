import AppKit
import SwiftUI

/// Painel do menu bar (MenuBarExtra estilo .window) — alinhado às HIG de Menu Bar Extras:
/// status no topo, controles frequentes, alertas acionáveis, navegação no rodapé.
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var showFullError = false

    var body: some View {
        VStack(alignment: .leading, spacing: QTDesign.Spacing.m) {
            header

            QTGlassGroup {
                VStack(alignment: .leading, spacing: QTDesign.Spacing.s) {
                    controlsCard
                    languageCard
                }
            }

            if !appState.hotkeysActive {
                permissionBanner
            }

            if let message = appState.lastErrorMessage {
                errorBanner(message)
            }

            Divider()
                .opacity(0.4)

            footer
        }
        .padding(14)
        .frame(width: 320)
        // Bridge para callers AppKit (`AppState.openSettings`) sem seletor privado.
        .onReceive(NotificationCenter.default.publisher(for: .qtRequestOpenSettings)) { _ in
            openSettings()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: QTDesign.Spacing.s) {
            Image(systemName: "globe")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("QuickTranslate")
                .font(QTDesign.Fonts.heading)
            Spacer()
            QTStatusChip(status: appState.status, isEnabled: appState.settings.isEnabled)
        }
    }

    // MARK: - Controles

    private var controlsCard: some View {
        GlassSurface {
            VStack(spacing: 10) {
                Toggle(isOn: appState.settingsBinding(\.isEnabled)) {
                    Label("Ligado", systemImage: "power")
                }
                Divider()
                Toggle(isOn: appState.settingsBinding(\.enterTranslatesAndSends)) {
                    Label("Enter traduz e envia", systemImage: "return")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(QTDesign.Fonts.body)
            .padding(12)
        }
    }

    private var languageCard: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 10) {
                Picker(
                    selection: Binding(
                        get: { appState.settings.incomingTargetLanguage },
                        set: { appState.setIncomingTargetLanguage($0) }
                    )
                ) {
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(language.id)
                    }
                } label: {
                    Label("Texto que leio →", systemImage: "arrow.down.left")
                        .font(QTDesign.Fonts.body)
                }
                .help("Idioma destino ao traduzir texto só leitura (conversas, painel).")

                Divider()

                Picker(
                    selection: Binding(
                        get: { appState.settings.outgoingTargetLanguage },
                        set: { appState.setOutgoingTargetLanguage($0) }
                    )
                ) {
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(language.id)
                    }
                } label: {
                    Label("Texto que escrevo →", systemImage: "arrow.up.right")
                        .font(QTDesign.Fonts.body)
                }
                .help("Idioma destino ao substituir texto em campos editáveis.")

                Divider()

                HStack(spacing: QTDesign.Spacing.s) {
                    Label(appState.settings.providerKind.displayName, systemImage: "gearshape.2")
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(
                            "Motor de tradução: \(appState.settings.providerKind.displayName)")
                    Spacer(minLength: 0)
                    QTOpenSettingsButton(section: .provider) {
                        Text("Configurar…")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(QTDesign.Fonts.caption)
                    .accessibilityLabel("Abrir Configurações, seção Provedor")
                    .accessibilityHint("Abre a janela de Configurações na seção Provedor")
                }
            }
            .padding(12)
        }
    }

    // MARK: - Alertas

    private var permissionBanner: some View {
        QTBanner(
            icon: "keyboard",
            tint: .orange,
            text: "Atalhos inativos. Ative o Monitoramento de Entrada.",
            lineLimit: 2
        ) {
            QTOpenSettingsButton(section: .permissions) {
                Text("Corrigir…")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Abrir Configurações, seção Permissões")
            .accessibilityHint("Abre Configurações para conceder Monitoramento de Entrada")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        let isLong = message.count > 90
        return QTBanner(
            icon: "exclamationmark.triangle.fill",
            tint: .red,
            text: message,
            lineLimit: showFullError ? nil : 2
        ) {
            if isLong {
                Button(showFullError ? "Menos" : "Detalhes") {
                    showFullError.toggle()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Button("Limpar") {
                showFullError = false
                appState.clearLastError()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            QTOpenSettingsButton(section: .logs, beforeOpen: {
                showFullError = false
            }) {
                Text("Ver logs")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Abrir Configurações, seção Logs")
            .accessibilityHint("Abre os logs para diagnosticar a falha")
        }
    }

    // MARK: - Rodapé

    private var footer: some View {
        HStack(spacing: QTDesign.Spacing.m) {
            QTOpenSettingsButton {
                Label("Configurações", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Abrir Configurações")

            Button {
                appState.showOnboarding()
            } label: {
                Label("Ajuda", systemImage: "questionmark.circle")
            }
            .accessibilityLabel("Abrir tutorial de configuração")

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Sair", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .keyboardShortcut("q", modifiers: .command)
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .font(QTDesign.Fonts.caption)
        .foregroundStyle(.secondary)
    }
}
