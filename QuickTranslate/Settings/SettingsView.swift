import AppKit
import SwiftUI

/// Destinos da sidebar de Preferências — padrão System Settings do macOS Tahoe.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case provider
    case shortcuts
    case permissions
    case test
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
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 175, max: 210)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(for: selection ?? .general)
        }
        .frame(minWidth: 660, minHeight: 460)
        .onAppear {
            // #region agent log
            AgentDebugLog.write(
                hypothesisId: "H1",
                location: "SettingsView.onAppear",
                message: "settings appear → showForSettings",
                data: ["selection": selection?.rawValue ?? "nil"]
            )
            // #endregion
            DockIconController.shared.showForSettings()
        }
        .onDisappear {
            // #region agent log
            AgentDebugLog.write(
                hypothesisId: "H1",
                location: "SettingsView.onDisappear",
                message: "settings disappear → hideForSettings",
                data: ["selection": selection?.rawValue ?? "nil"]
            )
            // #endregion
            DockIconController.shared.hideForSettings()
        }
        .onChange(of: selection) { oldValue, newValue in
            // #region agent log
            AgentDebugLog.write(
                hypothesisId: "H3",
                location: "SettingsView.onChange(selection)",
                message: "sidebar selection changed",
                data: [
                    "from": oldValue?.rawValue ?? "nil",
                    "to": newValue?.rawValue ?? "nil",
                ]
            )
            // #endregion
        }
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
