import AppKit
import SwiftUI
import Translation

@main
struct PrismApp: App {
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                // The `.translationTask` modifier must live inside a SwiftUI-managed
                // scene for macOS 26 to activate it. Placing it on an NSPanel with
                // NSHostingView doesn't participate in SwiftUI's scene lifecycle,
                // causing the modifier to never fire (timeout).
                .translationTask(appState.appleBridge.configuration) { session in
                    await appState.appleBridge.handle(session: session)
                }
        } label: {
            Image(nsImage: menuBarNSImage)
                .renderingMode(.template)
                .accessibilityLabel("Prism")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    /// `MenuBarExtra` só rasteriza bem `Image` (SF Symbol ou NSImage template).
    private var menuBarNSImage: NSImage {
        if appState.showsPrismMenuBarGlyph {
            return PrismMenuBarImage.prism
        }
        let image = NSImage(
            systemSymbolName: appState.statusIconName,
            accessibilityDescription: nil
        ) ?? PrismMenuBarImage.prism
        image.isTemplate = true
        return image
    }
}
