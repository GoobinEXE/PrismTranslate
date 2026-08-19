import Foundation

/// Runtime logging privacy flags — updated from `AppSettings` on load and change.
enum AppLogPreferences {
    private(set) static var logTextPreviews = false

    static func update(from settings: AppSettings) {
        logTextPreviews = settings.logTextPreviews
    }
}
