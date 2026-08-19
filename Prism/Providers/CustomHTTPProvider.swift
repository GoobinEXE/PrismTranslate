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
            throw TranslationError.invalidConfiguration(String(localized: "Set the Custom HTTP URL"))
        }

        let hasSensitiveHeaders = Self.headersContainCredentials(headersJSON)
        HTTPHostSecurity.warnIfPlaintextCredentials(
            urlString: url,
            hasCredentials: hasSensitiveHeaders,
            category: .customHTTP,
            engine: "HTTP personalizado"
        )

        ProviderLog.sending(
            .customHTTP,
            engine: "HTTP personalizado",
            method: method.uppercased(),
            endpoint: url,
            chars: text.count,
            from: from,
            to: to,
            extra: "caminho JSON \(responseJSONPath.isEmpty ? "(corpo inteiro)" : responseJSONPath)"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = 15

        if let headers = try? JSONSerialization.jsonObject(with: Data(headersJSON.utf8)) as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let body = bodyTemplate
            .replacingOccurrences(of: "{{text}}", with: Self.jsonEscape(text))
            .replacingOccurrences(of: "{{to}}", with: Self.jsonEscape(to))
            .replacingOccurrences(of: "{{from}}", with: Self.jsonEscape(from ?? ""))

        if method.uppercased() != "GET" {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let started = Date()
        let (raw, response) = try await URLSession.shared.data(for: request)
        let (http, data) = try ProviderLog.requireSuccess(
            data: raw,
            response: response,
            category: .customHTTP,
            engine: "HTTP personalizado",
            since: started
        )

        if responseJSONPath.isEmpty {
            guard let raw = String(data: data, encoding: .utf8), !raw.isEmpty else {
                ProviderLog.failed(
                    .customHTTP,
                    engine: "HTTP personalizado",
                    status: http.statusCode,
                    since: started,
                    body: "corpo vazio"
                )
                throw TranslationError.emptyResponse
            }
            ProviderLog.received(
                .customHTTP,
                engine: "HTTP personalizado",
                status: http.statusCode,
                bytes: data.count,
                since: started,
                outChars: raw.count
            )
            return TranslationOutcome(text: raw)
        }

        let json = try JSONSerialization.jsonObject(with: data)
        guard let extracted = Self.extract(path: responseJSONPath, from: json) else {
            ProviderLog.failed(
                .customHTTP,
                engine: "HTTP personalizado",
                status: http.statusCode,
                since: started,
                body: "caminho JSON '\(responseJSONPath)' não encontrado"
            )
            throw TranslationError.emptyResponse
        }
        ProviderLog.received(
            .customHTTP,
            engine: "HTTP personalizado",
            status: http.statusCode,
            bytes: data.count,
            since: started,
            outChars: extracted.count
        )
        return TranslationOutcome(text: extracted)
    }

    /// Escapes a string for safe embedding inside a JSON string value.
    static func jsonEscape(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")
        result = result.replacingOccurrences(of: "\0", with: "")
        result = String(
            result.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
                    || $0 == "\n" || $0 == "\r" || $0 == "\t"
            }
        )
        return result
    }

    static func headersContainCredentials(_ headersJSON: String) -> Bool {
        guard let headers = try? JSONSerialization.jsonObject(with: Data(headersJSON.utf8)) as? [String: String]
        else { return false }
        let sensitiveNames = ["authorization", "x-api-key", "x-goog-api-key", "api-key"]
        return headers.keys.contains { key in
            sensitiveNames.contains(key.lowercased())
                || headers[key]?.lowercased().hasPrefix("bearer ") == true
        }
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
