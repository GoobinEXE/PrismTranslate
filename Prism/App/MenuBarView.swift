import AppKit
import SwiftUI

/// Painel do menu bar (MenuBarExtra estilo .window) — alinhado às HIG de Menu Bar Extras:
/// status no topo, controles frequentes, alertas acionáveis, navegação no rodapé.
struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showFullError = false
    @AppStorage("menuBarOptionsExpanded") private var optionsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: QTDesign.Spacing.m) {
            header

            // Problemas primeiro: o que bloqueia o uso aparece antes de qualquer ajuste.
            if appState.missingPermissionCount > 0 {
                permissionBanner
            }

            if let message = appState.lastErrorMessage {
                errorBanner(message)
            }

            languageCard

            optionsCard

            Text(hotkeyCaption)
                .font(QTDesign.Fonts.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

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
            Text(AppRelease.displayName)
                .font(QTDesign.Fonts.heading)
            Spacer()
            // O interruptor já diz ligado/pausado; o chip só aparece para estados transitórios.
            if appState.status != .idle {
                QTStatusChip(status: appState.status, isEnabled: appState.settings.isEnabled)
            }
            Toggle("On", isOn: appState.settingsBinding(\.isEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Turn Prism on or off")
        }
    }

    // MARK: - Controles

    private var optionsCard: some View {
        QTCard {
            VStack(spacing: 0) {
                // Modo popup liga um atalho a mais (painel); fica visível porque muda o que o usuário tem à mão.
                controlRow("Popup mode", symbol: "menubar.arrow.up.rectangle", keyPath: \.popupModeEnabled)
                rowDivider
                DisclosureGroup(isExpanded: $optionsExpanded) {
                    VStack(spacing: 0) {
                        rowDivider
                        controlRow("Enter translates and sends", symbol: "return", keyPath: \.enterTranslatesAndSends)
                        rowDivider
                        controlRow("Hint near pointer", symbol: "cursorarrow.click", keyPath: \.showStatusHUD)
                    }
                } label: {
                    Text("More options")
                        .font(QTDesign.Fonts.body)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { optionsExpanded.toggle() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
    }

    private var rowDivider: some View {
        Divider().opacity(0.5)
    }

    private func controlRow(
        _ title: LocalizedStringKey,
        symbol: String,
        keyPath: WritableKeyPath<AppSettings, Bool>
    ) -> some View {
        Toggle(isOn: appState.settingsBinding(keyPath)) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(QTDesign.Fonts.body)
        .frame(minHeight: 30)
    }

    private var languageCard: some View {
        QTCard {
            VStack(alignment: .leading, spacing: 0) {
                languageRow(
                    "Text I read →", symbol: "arrow.down.left",
                    help: "Target language when translating read-only text (chats, panel).",
                    get: { appState.settings.incomingTargetLanguage },
                    set: { appState.setIncomingTargetLanguage($0) }
                )
                rowDivider
                languageRow(
                    "Text I write →", symbol: "arrow.up.right",
                    help: "Target language when replacing text in editable fields.",
                    get: { appState.settings.outgoingTargetLanguage },
                    set: { appState.setOutgoingTargetLanguage($0) }
                )
                rowDivider
                engineRow
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func languageRow(
        _ title: LocalizedStringKey,
        symbol: String,
        help: LocalizedStringKey,
        get: @escaping () -> String,
        set: @escaping (String) -> Void
    ) -> some View {
        Picker(
            selection: Binding(get: get, set: set)
        ) {
            ForEach(LanguageCode.commonTargets) { language in
                Text(language.displayName).tag(language.id)
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .font(QTDesign.Fonts.body)
        }
        .pickerStyle(.menu)
        .frame(minHeight: 30)
        .help(help)
    }

    private var engineRow: some View {
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
            icon: appState.accessibilityTrusted ? "keyboard" : "lock.shield",
            tint: .orange,
            text: permissionBannerText,
            lineLimit: 2
        ) {
            QTOpenSettingsButton(section: .permissions) {
                Text("Fix…")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open Settings, Permissions section")
            .accessibilityHint("Opens Settings so you can grant the missing permissions")
        }
    }

    private var permissionBannerText: String {
        switch (appState.accessibilityTrusted, appState.hotkeysActive) {
        case (false, false):
            return String(localized: "Prism needs Accessibility and Input Monitoring to work.")
        case (false, true):
            return String(localized: "Translation needs Accessibility.")
        default:
            return String(localized: "Shortcuts inactive. Turn on Input Monitoring.")
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
            if FocusedTextIOError.isPermissionMessage(message) {
                QTOpenSettingsButton(section: .permissions, beforeOpen: {
                    showFullError = false
                }) {
                    Text("Fix…")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Open Settings, Permissions section")
            } else {
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
                Label("Setup guide", systemImage: "questionmark.circle")
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
