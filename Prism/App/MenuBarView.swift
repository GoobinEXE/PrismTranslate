import AppKit
import SwiftUI

/// Painel do menu bar (MenuBarExtra estilo .window) — alinhado às HIG de Menu Bar Extras:
/// status no topo, controles frequentes, alertas acionáveis, navegação no rodapé.
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
            PrismGlyph()
                .frame(width: 16, height: 16)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Prism")
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
                    Label("On", systemImage: "power")
                }
                Divider()
                Toggle(isOn: appState.settingsBinding(\.enterTranslatesAndSends)) {
                    Label("Enter translates and sends", systemImage: "return")
                }
                Divider()
                Toggle(isOn: appState.settingsBinding(\.showStatusHUD)) {
                    Label("Hint near pointer", systemImage: "cursorarrow.click")
                }
                Divider()
                Toggle(isOn: appState.settingsBinding(\.popupModeEnabled)) {
                    Label("Popup mode", systemImage: "menubar.arrow.up.rectangle")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(QTDesign.Fonts.body)
            .padding(12)
        }
        .help(
            appState.settings.popupModeEnabled
                ? String(
                    format: String(localized: "Panel shortcut: %@. Translate: %@."),
                    appState.settings.popupHotkey.displayString,
                    appState.settings.translateOnlyHotkey.displayString
                )
                : String(
                    format: String(localized: "Translate shortcut: %@. Turn on popup mode for the panel shortcut."),
                    appState.settings.translateOnlyHotkey.displayString
                )
        )
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
                    Label("Text I read →", systemImage: "arrow.down.left")
                        .font(QTDesign.Fonts.body)
                }
                .help("Target language when translating read-only text (chats, panel).")

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
                    Label("Text I write →", systemImage: "arrow.up.right")
                        .font(QTDesign.Fonts.body)
                }
                .help("Target language when replacing text in editable fields.")

                Text(hotkeyCaption)
                    .font(QTDesign.Fonts.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack(spacing: QTDesign.Spacing.s) {
                    Label(
                        appState.settings.providerKind.displayName,
                        systemImage: appState.settings.providerKind.symbolName
                    )
                    .font(QTDesign.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel(
                        String(
                            format: String(localized: "Translation engine: %@"),
                            appState.settings.providerKind.displayName
                        ))
                    ForEach(appState.settings.providerKind.badges.prefix(2), id: \.self) { badge in
                        Text(badge.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    QTOpenSettingsButton(section: .provider) {
                        Text("Configure…")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(QTDesign.Fonts.caption)
                    .accessibilityLabel("Open Settings, Provider section")
                    .accessibilityHint("Opens the Settings window on the Provider section")
                }
            }
            .padding(12)
        }
    }

    private var hotkeyCaption: String {
        let translate = appState.settings.translateOnlyHotkey.displayString
        if appState.settings.popupModeEnabled {
            return String(
                format: String(localized: "Translate %@ · Panel %@"),
                translate,
                appState.settings.popupHotkey.displayString
            )
        }
        return String(format: String(localized: "Translate %@ · Panel off"), translate)
    }

    // MARK: - Alertas

    private var permissionBanner: some View {
        QTBanner(
            icon: "keyboard",
            tint: .orange,
            text: String(localized: "Shortcuts inactive. Turn on Input Monitoring."),
            lineLimit: 2
        ) {
            QTOpenSettingsButton(section: .permissions) {
                Text("Fix…")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open Settings, Permissions section")
            .accessibilityHint("Opens Settings so you can grant Input Monitoring")
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
                Button(showFullError ? "Less" : "Details") {
                    showFullError.toggle()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            Button("Clear") {
                showFullError = false
                appState.clearLastError()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            QTOpenSettingsButton(section: .logs, beforeOpen: {
                showFullError = false
            }) {
                Text("View logs")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open Settings, Logs section")
            .accessibilityHint("Opens the logs to diagnose the failure")
        }
    }

    // MARK: - Rodapé

    private var footer: some View {
        HStack(spacing: QTDesign.Spacing.m) {
            QTOpenSettingsButton {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Open Settings")

            Button {
                AppLog.info(.app, "Botão «Ajuda» no menu — abrindo tutorial")
                appState.showOnboarding()
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }
            .accessibilityLabel("Open setup tutorial")

            Spacer()

            Button {
                AppLog.info(.app, "Botão «Sair» no menu")
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "rectangle.portrait.and.arrow.right")
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
