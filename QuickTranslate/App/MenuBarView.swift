import AppKit
import SwiftUI

/// Painel do menu bar (MenuBarExtra estilo .window) — layout no espírito do
/// Control Center do macOS Tahoe: status no topo, controles agrupados em glass,
/// alertas acionáveis e ações de navegação no rodapé.
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: QTDesign.Spacing.s) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
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
                        get: { appState.settings.targetLanguage },
                        set: { appState.setTargetLanguage($0) }
                    )
                ) {
                    ForEach(LanguageCode.commonTargets) { language in
                        Text(language.displayName).tag(language.id)
                    }
                } label: {
                    Label("Idioma destino", systemImage: "character.bubble")
                        .font(QTDesign.Fonts.body)
                }

                Divider()

                HStack(spacing: QTDesign.Spacing.s) {
                    Label(appState.settings.providerKind.displayName, systemImage: "gearshape.2")
                        .font(QTDesign.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    SettingsLink {
                        Text("Configurar…")
                    }
                    .simultaneousGesture(TapGesture().onEnded { prepareOpenSettings() })
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(QTDesign.Fonts.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "Motor de tradução: \(appState.settings.providerKind.displayName)")
            }
            .padding(12)
        }
    }

    // MARK: - Alertas

    private var permissionBanner: some View {
        QTBanner(
            icon: "keyboard",
            tint: .orange,
            text:
                "Atalhos inativos — conceda Monitoramento de Entrada para usar ⌃⌥T em qualquer app."
        ) {
            Button("Abrir Ajustes…") {
                _ = Permissions.requestInputMonitoring()
                Permissions.openInputMonitoringSettings()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
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
        }
    }

    // MARK: - Rodapé

    private var footer: some View {
        HStack(spacing: QTDesign.Spacing.m) {
            SettingsLink {
                Label("Preferências", systemImage: "gearshape")
            }
            .simultaneousGesture(TapGesture().onEnded { prepareOpenSettings() })
            .keyboardShortcut(",", modifiers: .command)

            Button {
                // #region agent log
                AgentDebugLog.write(
                    hypothesisId: "H3",
                    location: "MenuBarView.footer.Tutorial",
                    message: "open tutorial from menu bar",
                    data: [:]
                )
                // #endregion
                closePanel()
                appState.showOnboarding()
            } label: {
                Label("Tutorial", systemImage: "questionmark.circle")
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Sair", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .font(QTDesign.Fonts.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Navegação

    /// Fecha o painel do MenuBarExtra e mostra o Dock antes do Settings abrir.
    private func prepareOpenSettings() {
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H3",
            location: "MenuBarView.prepareOpenSettings",
            message: "open settings from menu bar",
            data: [:]
        )
        // #endregion
        closePanel()
        DockIconController.shared.showForSettings()
    }

    /// O MenuBarExtra .window não fecha sozinho ao navegar — fecha o painel
    /// antes de abrir outra janela para não deixá-lo pendurado.
    private func closePanel() {
        let targets = NSApp.windows.filter {
            String(describing: type(of: $0)).contains("MenuBarExtra")
        }
        // #region agent log
        AgentDebugLog.write(
            hypothesisId: "H3",
            location: "MenuBarView.closePanel",
            message: "closing MenuBarExtra windows",
            data: [
                "matchCount": targets.count,
                "allClasses": NSApp.windows.map { String(describing: type(of: $0)) },
            ]
        )
        // #endregion
        for window in targets {
            window.close()
        }
    }
}
