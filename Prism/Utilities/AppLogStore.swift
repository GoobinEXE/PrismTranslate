import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Level / Category

enum AppLogLevel: Int, Codable, CaseIterable, Comparable, Identifiable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return String(localized: "Warning")
        case .error: return String(localized: "Error")
        }
    }

    var symbolName: String {
        switch self {
        case .debug: return "ant.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AppLogCategory: String, Codable, CaseIterable, Identifiable {
    case app
    case orchestrator
    case engine
    case textIO
    case hotkey
    case hostPanel
    case resultPanel
    case deepl
    case google
    case openAI
    case customHTTP
    case apple
    case permissions
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return "App"
        case .orchestrator: return "Orchestrator"
        case .engine: return "Engine"
        case .textIO: return "TextIO"
        case .hotkey: return "Hotkey"
        case .hostPanel: return "HostPanel"
        case .resultPanel: return "ResultPanel"
        case .deepl: return "DeepL"
        case .google: return "Google"
        case .openAI: return "OpenAI"
        case .customHTTP: return "CustomHTTP"
        case .apple: return "Apple"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        }
    }

    fileprivate var osLogger: Logger {
        Logger(subsystem: AppRelease.bundleIdentifier, category: title)
    }
}

// MARK: - Entry

struct AppLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let level: AppLogLevel
    let category: AppLogCategory
    let message: String
    let runID: String?
    let file: String
    let function: String
    let line: Int

    var formattedTimestamp: String {
        Self.timeFormatter.string(from: date)
    }

    var sourceLocation: String {
        "\(file):\(line) \(function)"
    }

    var exportLine: String {
        var parts = ["[\(formattedTimestamp)]", "[\(level.title)]", "[\(category.title)]"]
        if let runID {
            parts.append("[run:\(runID)]")
        }
        parts.append(message)
        parts.append("(\(sourceLocation))")
        return parts.joined(separator: " ")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Store

final class AppLogStore: ObservableObject {
    static let shared = AppLogStore()

    static let maxEntries = 2_000
    static let maxFileBytes = 2 * 1_024 * 1_024

    @Published private(set) var entries: [AppLogEntry] = []

    private let lock = NSLock()
    private var buffer: [AppLogEntry] = []
    private var currentRunID: String?
    private let fileURL: URL
    private let fileQueue = DispatchQueue(
        label: "com.marcelopessoa.prism.applog.file", qos: .utility)

    private init() {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("Prism", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("app.log", isDirectory: false)
        loadTailFromDisk()
        append(
            level: .info,
            category: .app,
            message: "AppLogStore iniciado — arquivo: \(fileURL.path)",
            runID: nil,
            file: #fileID,
            function: #function,
            line: #line
        )
    }

    var logFileURL: URL { fileURL }

    @discardableResult
    func beginRun(prefix: String = "T") -> String {
        let id = "\(prefix)-\(String(UUID().uuidString.prefix(8)))"
        lock.lock()
        currentRunID = id
        lock.unlock()
        return id
    }

    func endRun() {
        lock.lock()
        currentRunID = nil
        lock.unlock()
    }

    func clear() {
        lock.lock()
        buffer = []
        lock.unlock()
        publish([])
        fileQueue.async { [fileURL] in
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        append(
            level: .info,
            category: .app,
            message: "Logs limpos pelo usuário",
            runID: nil,
            file: #fileID,
            function: #function,
            line: #line
        )
    }

    func exportText(minimumLevel: AppLogLevel = .debug) -> String {
        lock.lock()
        let snapshot = buffer
        lock.unlock()
        return
            snapshot
            .filter { $0.level >= minimumLevel }
            .map(\.exportLine)
            .joined(separator: "\n")
    }

    /// Complete log for sharing: prefers the on-disk file (full history), else in-memory buffer.
    func fullExportText() -> String {
        if let disk = try? String(contentsOf: fileURL, encoding: .utf8), !disk.isEmpty {
            return disk.trimmingCharacters(in: .newlines)
        }
        return exportText(minimumLevel: .debug)
    }

    /// Number of lines available for a full copy/export (disk preferred).
    func fullExportLineCount() -> Int {
        let text = fullExportText()
        guard !text.isEmpty else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    func append(
        level: AppLogLevel,
        category: AppLogCategory,
        message: String,
        runID: String?,
        file: String,
        function: String,
        line: Int
    ) {
        let sanitized = Self.redactSecrets(in: message)
        lock.lock()
        let resolvedRun = runID ?? currentRunID
        let entry = AppLogEntry(
            id: UUID(),
            date: Date(),
            level: level,
            category: category,
            message: sanitized,
            runID: resolvedRun,
            file: Self.shortFileName(file),
            function: function,
            line: line
        )
        buffer.append(entry)
        if buffer.count > Self.maxEntries {
            buffer.removeFirst(buffer.count - Self.maxEntries)
        }
        let snapshot = buffer
        lock.unlock()

        publish(snapshot)
        mirrorToOSLog(entry)
        persist(entry)
    }

    // MARK: - Private

    private func publish(_ snapshot: [AppLogEntry]) {
        if Thread.isMainThread {
            entries = snapshot
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.entries = snapshot
            }
        }
    }

    private func mirrorToOSLog(_ entry: AppLogEntry) {
        let logger = entry.category.osLogger
        let text = entry.runID.map { "[\($0)] \(entry.message)" } ?? entry.message
        switch entry.level {
        case .debug:
            logger.debug("\(text, privacy: .private)")
        case .info:
            logger.info("\(text, privacy: .private)")
        case .warning:
            logger.warning("\(text, privacy: .public)")
        case .error:
            logger.error("\(text, privacy: .public)")
        }
    }

    private func persist(_ entry: AppLogEntry) {
        let line = entry.exportLine + "\n"
        let maxBytes = Self.maxFileBytes
        fileQueue.async { [fileURL] in
            guard let data = line.data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: data)
                return
            }
            do {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                let size = try handle.offset()
                if size > maxBytes {
                    try handle.close()
                    Self.trimLogFile(at: fileURL, keepBytes: maxBytes / 2)
                }
            } catch {
                // Best-effort file logging — never crash the app for diagnostics.
            }
        }
    }

    private func loadTailFromDisk() {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty,
            let text = String(data: data, encoding: .utf8)
        else { return }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let recent = lines.suffix(400)
        var loaded: [AppLogEntry] = []
        loaded.reserveCapacity(recent.count)
        for line in recent {
            loaded.append(
                AppLogEntry(
                    id: UUID(),
                    date: Date(),
                    level: .info,
                    category: .app,
                    message: String(line),
                    runID: nil,
                    file: "disk",
                    function: "loadTail",
                    line: 0
                )
            )
        }
        entries = loaded
        buffer = loaded
    }

    private static func trimLogFile(at url: URL, keepBytes: Int) {
        guard let data = try? Data(contentsOf: url), data.count > keepBytes else { return }
        let start = data.count - keepBytes
        var slice = data.subdata(in: start..<data.count)
        if let nl = slice.firstIndex(of: UInt8(ascii: "\n")) {
            slice = slice.subdata(in: slice.index(after: nl)..<slice.endIndex)
        }
        try? slice.write(to: url, options: .atomic)
    }

    private static func shortFileName(_ fileID: String) -> String {
        fileID.split(separator: "/").last.map(String.init) ?? fileID
    }

    /// Strip obvious secrets before storing/displaying.
    static func redactSecrets(in message: String) -> String {
        var result = message
        let patterns: [(String, String)] = [
            (#"(?i)(api[_-]?key|authorization|bearer|token|auth-key)\s*[:=]\s*\S+"#, "$1=***"),
            (#"(?i)DeepL-Auth-Key\s+\S+"#, "DeepL-Auth-Key ***"),
            (#"(?i)Bearer\s+\S+"#, "Bearer ***"),
            (#"(?i)[?&]key=\S+"#, "key=***"),
        ]
        for (pattern, template) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: template
                )
            }
        }
        return redactJSONStringFields(in: result)
    }

    private static func redactJSONStringFields(in message: String) -> String {
        let fieldNames = ["text", "q", "messages", "content", "prompt", "Authorization", "X-Api-Key", "X-Goog-Api-Key"]
        var result = message
        for name in fieldNames {
            let pattern = #"(?i)"\#(name)"\s*:\s*"[^"]*""#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: "\"\(name)\": \"***\""
                )
            }
        }
        return result
    }
}

// MARK: - Export

enum AppLogExport {
    static func exportMayContainPrivateText() -> Bool {
        if AppLogPreferences.logTextPreviews { return true }
        let text = AppLogStore.shared.fullExportText()
        return text.contains("Prévia original:")
            || text.contains("Prévia traduzida:")
            || text.contains("Teste ") && text.contains("OK em")
    }

    @MainActor
    @discardableResult
    static func copyToPasteboard() -> Int {
        guard confirmExportIfNeeded() else { return 0 }
        let store = AppLogStore.shared
        let text = store.fullExportText()
        guard !text.isEmpty else { return 0 }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return store.fullExportLineCount()
    }

    /// `nil` se o usuário cancelar.
    @MainActor
    static func presentSavePanel() -> Result<URL, Error>? {
        guard confirmExportIfNeeded() else { return nil }
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Prism log")
        panel.message = "Arquivo de texto completo — pode anexar ou colar no chat."
        panel.allowedContentTypes = [.plainText, .log]
        panel.nameFieldStringValue = "Prism-\(fileStamp()).log"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let text = AppLogStore.shared.fullExportText()
            try text.write(to: url, atomically: true, encoding: .utf8)
            return .success(url)
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    static func revealLogFileInFinder() {
        let url = AppLogStore.shared.logFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    @MainActor
    private static func confirmExportIfNeeded() -> Bool {
        guard exportMayContainPrivateText() else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Log may contain private text")
        alert.informativeText = String(
            localized:
                "The log may include snippets of translated text. Do not share it if it contains private content."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension UTType {
    fileprivate static var log: UTType {
        UTType(filenameExtension: "log") ?? .plainText
    }
}

// MARK: - Facade

enum AppLog {
    static func debug(
        _ category: AppLogCategory,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.debug, category, message(), file: file, function: function, line: line)
    }

    static func info(
        _ category: AppLogCategory,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, category, message(), file: file, function: function, line: line)
    }

    static func warning(
        _ category: AppLogCategory,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.warning, category, message(), file: file, function: function, line: line)
    }

    static func error(
        _ category: AppLogCategory,
        _ message: @autoclosure () -> String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, category, message(), file: file, function: function, line: line)
    }

    @discardableResult
    static func beginRun(prefix: String = "T") -> String {
        AppLogStore.shared.beginRun(prefix: prefix)
    }

    static func endRun() {
        AppLogStore.shared.endRun()
    }

    /// Prévia curta de texto (quebras viram ⏎) para o log ficar legível.
    static func preview(_ text: String, max: Int = 80) -> String {
        guard AppLogPreferences.logTextPreviews else {
            return "(\(text.count) caracteres)"
        }
        let flat =
            text
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: "⇥")
        let truncated =
            flat.count <= max ? flat : String(flat.prefix(max)) + "…"
        return AppLogStore.redactSecrets(in: truncated)
    }

    static func duration(since date: Date) -> String {
        formatDuration(Int(Date().timeIntervalSince(date) * 1000))
    }

    static func formatDuration(_ milliseconds: Int) -> String {
        if milliseconds < 1000 { return "\(milliseconds) ms" }
        let seconds = Double(milliseconds) / 1000
        if seconds < 10 {
            return String(format: "%.1f s", seconds)
        }
        return "\(Int(seconds.rounded())) s"
    }

    /// Corpo HTTP enxuto — sem quebras, limitado, para caber numa linha.
    static func httpBodyPreview(_ body: String, max: Int = 240) -> String {
        let flat =
            body
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return "(vazio)" }
        let redacted = AppLogStore.redactSecrets(in: flat)
        if redacted.count <= max { return redacted }
        return String(redacted.prefix(max)) + "…"
    }

    static func step(
        _ category: AppLogCategory,
        _ index: Int,
        of total: Int,
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(
            .info,
            category,
            "\(index)/\(total) \(message)",
            file: file,
            function: function,
            line: line
        )
    }

    private static func log(
        _ level: AppLogLevel,
        _ category: AppLogCategory,
        _ message: String,
        file: String,
        function: String,
        line: Int
    ) {
        AppLogStore.shared.append(
            level: level,
            category: category,
            message: message,
            runID: nil,
            file: file,
            function: function,
            line: line
        )
    }
}

// MARK: - Provider HTTP narrative

enum ProviderLog {
    static func sending(
        _ category: AppLogCategory,
        engine: String,
        method: String = "POST",
        endpoint: String,
        chars: Int,
        from: String?,
        to: String,
        model: String? = nil,
        extra: String? = nil
    ) {
        var parts = [
            "\(engine): enviando \(method) \(endpoint)",
            "\(chars) caracteres",
            LanguageCode.pairLabel(from: from, to: to),
        ]
        if let model, !model.isEmpty {
            parts.insert("modelo \(model)", at: 1)
        }
        if let extra, !extra.isEmpty {
            parts.append(extra)
        }
        AppLog.info(category, parts.joined(separator: " · "))
    }

    static func received(
        _ category: AppLogCategory,
        engine: String,
        status: Int,
        bytes: Int,
        since started: Date,
        outChars: Int,
        detected: String? = nil
    ) {
        var parts = [
            "\(engine): resposta HTTP \(status) em \(AppLog.duration(since: started))",
            "\(bytes) bytes recebidos",
            "\(outChars) caracteres traduzidos",
        ]
        if let detected, !detected.isEmpty {
            parts.append("origem detectada: \(LanguageCode.displayName(for: detected))")
        }
        AppLog.info(category, parts.joined(separator: " · "))
    }

    static func failed(
        _ category: AppLogCategory,
        engine: String,
        status: Int?,
        since started: Date,
        body: String
    ) {
        let duration = AppLog.duration(since: started)
        if let status {
            let kind = TranslationError.classifyHTTPFailure(statusCode: status, body: body)
            AppLog.error(
                category,
                "\(engine): falhou HTTP \(status) (\(kind.logLabel)) em \(duration) · \(AppLog.httpBodyPreview(body))"
            )
        } else {
            AppLog.error(
                category,
                "\(engine): resposta inválida em \(duration) · \(AppLog.httpBodyPreview(body))"
            )
        }
    }

    /// Shared 2xx check used by HTTP providers after `URLSession.data`.
    static func requireSuccess(
        data: Data,
        response: URLResponse,
        category: AppLogCategory,
        engine: String,
        since started: Date
    ) throws -> (HTTPURLResponse, Data) {
        guard let http = response as? HTTPURLResponse else {
            failed(category, engine: engine, status: nil, since: started, body: "")
            throw TranslationError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            failed(
                category, engine: engine, status: http.statusCode, since: started, body: bodyText)
            throw TranslationError.httpStatus(http.statusCode, bodyText)
        }
        return (http, data)
    }
}
