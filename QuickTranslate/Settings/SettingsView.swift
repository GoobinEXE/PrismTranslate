import AppKit
import SwiftUI

/// Destinos da sidebar de Configurações — padrão System Settings do macOS (HIG).
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case provider
    case test
    case permissions
    case logs
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Geral"
        case .provider: return "Provedor"
        case .shortcuts: return "Atalhos"
        case .permissions: return "Permissões"
        case .test: return "Teste"
        case .logs: return "Logs"
        case .about: return "Sobre"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .provider: return "network"
        case .shortcuts: return "keyboard"
        case .permissions: return "lock.shield"
        case .test: return "checkmark.seal"
        case .logs: return "text.alignleft"
        case .about: return "info.circle"
        }
    }

    /// Grupos da sidebar (card-sorting por tarefa do usuário).
    enum Group: String, CaseIterable, Identifiable {
        case daily
        case translation
        case system
        case help

        var id: String { rawValue }

        var title: String {
            switch self {
            case .daily: return "Uso diário"
            case .translation: return "Tradução"
            case .system: return "Sistema"
            case .help: return "Ajuda"
            }
        }

        var sections: [SettingsSection] {
            switch self {
            case .daily: return [.general, .shortcuts]
            case .translation: return [.provider, .test]
            case .system: return [.permissions, .logs]
            case .help: return [.about]
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    private var selection: Binding<SettingsSection?> {
        Binding(
            get: { appState.settingsSelection },
            set: { newValue in
                let section = newValue ?? .general
                appState.settingsSelection = section
                appState.rememberSettingsSection(section)
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(SettingsSection.Group.allCases) { group in
                    Section(group.title) {
                        ForEach(group.sections) { section in
                            Label(section.title, systemImage: section.symbolName)
                                .tag(section)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 175, max: 210)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(for: appState.settingsSelection)
        }
        .frame(minWidth: 660, minHeight: 460)
        .onAppear {
            DockIconController.shared.showForSettings()
            if let pending = appState.consumePendingSettingsSection() {
                appState.settingsSelection = pending
                appState.rememberSettingsSection(pending)
            }
        }
        .onChange(of: appState.pendingSettingsSection) { _, newValue in
            guard let newValue else { return }
            appState.settingsSelection = newValue
            appState.rememberSettingsSection(newValue)
            _ = appState.consumePendingSettingsSection()
        }
        .accessibilityLabel("Configurações do QuickTranslate")
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        Group {
            switch section {
            case .general: GeneralSettingsView()
            case .provider: ProviderSettingsView()
            case .shortcuts: ShortcutsSettingsView()
            case .permissions: PermissionsSettingsView()
            case .test: TestSettingsView()
            case .logs: LogsSettingsView()
            case .about: AboutSettingsView()
            }
        }
        .navigationTitle(section.title)
    }
}
