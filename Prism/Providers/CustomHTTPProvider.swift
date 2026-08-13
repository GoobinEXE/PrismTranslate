import Foundation

struct CustomHTTPProvider: TranslationProvider {
    let id = ProviderKind.customHTTP.rawValue
    let displayName = ProviderKind.customHTTP.displayName
    let url: String
    let method: String
    let headersJSON: String
    let bodyTemplate: String
    let responseJSONPath: String

    func translate(_ text: String, from: String?, to: String) async throws -> TranslationOutcome {
        guard let endpoint = URL(string: url), !url.isEmpty else {
            throw TranslationError.invalidConfiguration("Configure a URL do Custom HTTP")
        }

        AppLog.info(
            .customHTTP,
            "📡 [Custom HTTP] \(method.uppercased()) \(url) — chars=\(text.count), from=\(from ?? "auto"), to=\(to), path=\(responseJSONPath)"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = 15

        if let headers = try? JSONSerialization.jsonObject(with: Data(headersJSON.utf8)) as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let body = bodyTemplate
            .replacingOccurrences(of: "{{text}}", with: escapedText)
            .replacingOccurrences(of: "{{to}}", with: to)
            .replacingOccurrences(of: "{{from}}", with: from ?? "")

        if method.uppercased() != "GET" {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            AppLog.error(.customHTTP, "❌ [Custom HTTP] HTTP \(http.statusCode): \(bodyText)")
            throw TranslationError.httpStatus(http.statusCode, bodyText)
        }

        if responseJSONPath.isEmpty {
            guard let raw = String(data: data, encoding: .utf8), !raw.isEmpty else {
                throw TranslationError.emptyResponse
            }
            return TranslationOutcome(text: raw)
        }

        let json = try JSONSerialization.jsonObject(with: data)
        guard let extracted = Self.extract(path: responseJSONPath, from: json) else {
            throw TranslationError.emptyResponse
        }
        return TranslationOutcome(text: extracted)
    }

    /// Walks a dot-separated path ("data.translations.0.text") through parsed JSON.
    /// Internal (not private) so unit tests can exercise the parsing directly.
    static func extract(path: String, from json: Any) -> String? {
        let parts = path.split(separator: ".").map(String.init)
        var current: Any = json
        for part in parts {
            if let index = Int(part), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dict = current as? [String: Any], let next = dict[part] {
                current = next
            } else {
                return nil
            }
        }
        if let string = current as? String { return string }
        if let number = current as? NSNumber { return number.stringValue }
        return nil
    }
}
