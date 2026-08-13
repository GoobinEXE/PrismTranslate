import Foundation
import NaturalLanguage

enum LanguageDetector {
    /// Best-effort on-device language id for labeling (e.g. when Apple Translation does not report detection).
    static func detect(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return LanguageCode.normalize(dominant.rawValue)
    }
}
