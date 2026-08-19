import Foundation

enum HTTPHostSecurity {
    static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    /// Logs a warning when credentials would be sent over plaintext HTTP to a non-local host.
    static func warnIfPlaintextCredentials(
        urlString: String,
        hasCredentials: Bool,
        category: AppLogCategory,
        engine: String
    ) {
        guard hasCredentials,
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "http",
              let host = url.host,
              !isLocalHost(host)
        else { return }

        AppLog.warning(
            category,
            "\(engine): credenciais serão enviadas sobre HTTP (sem TLS) para \(host) — use https://"
        )
    }
}
