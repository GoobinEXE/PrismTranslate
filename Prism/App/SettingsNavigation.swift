import AppKit
import Foundation
import SwiftUI

/// Ponto único de navegação entre MenuBarExtra, Preferências e superfícies AppKit.
@MainActor
enum SettingsNavigation {
    private static let settingsAutosaveName = "com_apple_SwiftUI_Settings_window"

    /// `OpenSettingsAction` capturada da view SwiftUI persistente (host da tradução),
    /// para abrir Configurações a partir de código AppKit, como o menu de clique direito.
    static var openSettingsAction: OpenSettingsAction?

    /// Abre Configurações fora de uma view SwiftUI (menu de clique direito).
    static func openSettings(section: SettingsSection?) {
        AppState.shared.prepareSettings(section: section, closeMenuBar: true)
        NSApp.activate(ignoringOtherApps: true)
        if let openSettingsAction {
            openSettingsAction()
        } else {
            AppLog.warning(.app, "OpenSettingsAction indisponível — usando showSettingsWindow:")
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    static func closeMenuBarExtra() {
        for window in menuBarExtraWindows() {
            window.close()
        }
    }

    /// Mostra o Dock (e opcionalmente fecha o MenuBarExtra) antes de Preferências.
    static func prepareOpenSettings(closeMenuBar: Bool = true) {
        DockIconController.shared.showForSettings()
        if closeMenuBar {
            closeMenuBarExtra()
        }
    }

    /// Janela da scene `Settings` — usada pelo Dock enquanto Preferências está aberta.
    static func settingsWindow() -> NSWindow? {
        if let named = NSApp.windows.first(where: {
            $0.frameAutosaveName == settingsAutosaveName
        }) {
            return named
        }
        if let key = NSApp.keyWindow,
            !(key is NSPanel),
            key.isVisible,
            key.styleMask.contains(.titled),
            key.styleMask.contains(.closable)
        {
            return key
        }
        return NSApp.windows.first { window in
            window.isVisible
                && !(window is NSPanel)
                && window.styleMask.contains(.titled)
                && window.styleMask.contains(.closable)
        }
    }

    private static func menuBarExtraWindows() -> [NSWindow] {
        NSApp.windows.filter {
            String(describing: type(of: $0)).contains("MenuBarExtra")
        }
    }
}

/// Abre a scene Settings com a API suportada (`SettingsLink`), preparando seção/Dock no toque.
struct QTSettingsLink<Label: View>: View {
    var section: SettingsSection? = nil
    var beforeOpen: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        SettingsLink {
            label()
        }
        // TapGesture não engole o clique do SettingsLink (DragGesture(minimumDistance:0) engolia).
        .simultaneousGesture(
            TapGesture().onEnded {
                AppState.shared.prepareSettings(section: section, closeMenuBar: false)
                beforeOpen?()
                SettingsNavigation.closeMenuBarExtra()
            }
        )
    }
}

/// Botão que abre Preferências via `OpenSettingsAction` (MenuBarExtra / scenes SwiftUI).
struct QTOpenSettingsButton<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    var section: SettingsSection? = nil
    var beforeOpen: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            beforeOpen?()
            AppState.shared.prepareSettings(section: section, closeMenuBar: false)
            openSettings()
            SettingsNavigation.closeMenuBarExtra()
        } label: {
            label()
        }
    }
}
