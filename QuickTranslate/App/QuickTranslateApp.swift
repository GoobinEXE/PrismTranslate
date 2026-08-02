import AppKit
import SwiftUI
import Translation

@main
struct QuickTranslateApp: App {
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
            Image(systemName: appState.statusIconName)
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("QuickTranslate")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
