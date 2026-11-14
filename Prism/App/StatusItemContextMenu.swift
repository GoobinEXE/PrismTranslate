import AppKit

/// Menu nativo do clique direito (ou ⌃-clique) no prisma da barra de menus.
///
/// O `MenuBarExtra` do SwiftUI só abre o painel e não distingue o botão do mouse.
/// Um monitor local de eventos intercepta o clique direito na janela do item de
/// status e mostra um `NSMenu` ancorado logo abaixo do ícone; o clique esquerdo
/// continua abrindo o painel.
@MainActor
final class StatusItemContextMenu: NSObject {
    static let shared = StatusItemContextMenu()

    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) {
            [weak self] event in
            guard let self, let window = event.window, Self.isStatusItemWindow(window) else {
                return event
            }
            let isContextClick =
                event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            guard isContextClick else { return event }
            self.present(in: window, event: event)
            return nil
        }
        AppLog.info(.app, "Menu de clique direito instalado no ícone da barra de menus")
    }

    /// Janela do item de status (o ícone na barra), não o painel do `MenuBarExtra`.
    private static func isStatusItemWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("NSStatusBarWindow")
    }

    private func present(in window: NSWindow, event: NSEvent) {
        SettingsNavigation.closeMenuBarExtra()
        AppLog.info(.app, "Clique direito no prisma — menu rápido (ícone em \(NSStringFromRect(window.frame)))")
        let menu = buildMenu()
        // Menu de contexto do sistema, no ponto do clique: o macOS o encaixa abaixo da
        // barra de menus. Posicionar à mão (popUp em coordenadas) deixava o primeiro
        // item atrás de uma seta de rolagem.
        guard let view = window.contentView else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    // MARK: - Conteúdo

    /// No máximo 5 itens clicáveis, do estado à saída: Ligado, ação principal
    /// (traduzir a área de transferência), traduções recentes, Configurações (ou
    /// Corrigir permissões, quando falta alguma) e Sair. Idiomas e opções ficam no
    /// painel do clique esquerdo.
    private func buildMenu() -> NSMenu {
        let state = AppState.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(toggleItem(String(localized: "On"), isOn: state.settings.isEnabled, keyPath: \.isEnabled))

        menu.addItem(.separator())

        menu.addItem(
            ActionMenuItem(title: String(localized: "Translate clipboard")) {
                AppLog.info(.app, "Menu rápido — «Traduzir área de transferência»")
                Task { await state.orchestrator.translateClipboard() }
            })
        menu.addItem(recentItem(state.recentTranslations))

        menu.addItem(.separator())

        if state.missingPermissionCount > 0 {
            menu.addItem(
                ActionMenuItem(title: String(localized: "Fix permissions…")) {
                    SettingsNavigation.openSettings(section: .permissions)
                })
        } else {
            let settingsItem = ActionMenuItem(title: String(localized: "Settings…")) {
                SettingsNavigation.openSettings(section: nil)
            }
            settingsItem.keyEquivalent = ","
            menu.addItem(settingsItem)
        }

        menu.addItem(.separator())

        let quit = ActionMenuItem(title: String(localized: "Quit")) {
            AppLog.info(.app, "Menu rápido — «Sair»")
            NSApplication.shared.terminate(nil)
        }
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        return menu
    }

    /// Últimas traduções: clicar copia a tradução de novo, sem chamar o motor.
    private func recentItem(_ recent: [AppState.RecentTranslation]) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Recent translations"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if recent.isEmpty {
            let empty = NSMenuItem(title: String(localized: "No translations yet"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for entry in recent {
            let option = ActionMenuItem(title: Self.shortened(entry.translated)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.translated, forType: .string)
                AppLog.info(.app, "Menu rápido — tradução recente copiada")
            }
            option.toolTip = entry.original
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    private static func shortened(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return line.count > 48 ? String(line.prefix(47)) + "…" : line
    }

    private func toggleItem(
        _ title: String,
        isOn: Bool,
        keyPath: WritableKeyPath<AppSettings, Bool>
    ) -> NSMenuItem {
        let item = ActionMenuItem(title: title) {
            var updated = AppState.shared.settings
            updated[keyPath: keyPath].toggle()
            AppState.shared.settings = updated
        }
        item.state = isOn ? .on : .off
        return item
    }
}

/// `NSMenuItem` com closure no lugar de target/selector.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler), keyEquivalent: "")
        target = self
        isEnabled = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) não é usado")
    }

    @objc private func runHandler() {
        handler()
    }
}
