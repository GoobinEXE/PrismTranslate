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
        case .general: return String(localized: "General")
        case .provider: return String(localized: "Provider")
        case .shortcuts: return String(localized: "Shortcuts")
        case .permissions: return String(localized: "Permissions")
        case .test: return String(localized: "Test")
        case .logs: return String(localized: "Logs")
        case .about: return String(localized: "About")
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
            case .daily: return String(localized: "Daily use")
            case .translation: return String(localized: "Translation")
            case .system: return String(localized: "System")
            case .help: return String(localized: "Help")
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
        .accessibilityLabel("Prism Settings")
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
