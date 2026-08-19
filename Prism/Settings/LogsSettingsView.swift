import AppKit
import SwiftUI

/// Preferências › Logs — visualização ao vivo do pipeline de tradução.
struct LogsSettingsView: View {
    @ObservedObject private var store = AppLogStore.shared

    @State private var minimumLevel: AppLogLevel = .debug
    @State private var categoryFilter: AppLogCategory?
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var showSource = false
    @State private var copyFeedback: String?
    @State private var exportFeedback: String?

    private var filtered: [AppLogEntry] {
        store.entries.filter { entry in
            guard entry.level >= minimumLevel else { return false }
            if let categoryFilter, entry.category != categoryFilter { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                let hay = "\(entry.message) \(entry.category.title) \(entry.runID ?? "")".lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            if filtered.isEmpty {
                ContentUnavailableView(
                    "No entries",
                    systemImage: "text.alignleft",
                    description: Text("Translate something or adjust the filters to see the log.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filtered) { entry in
                                logRow(entry)
                                    .id(entry.id)
                                Divider().opacity(0.35)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: store.entries.count) { _, _ in
                        guard autoScroll, let last = filtered.last else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Level", selection: $minimumLevel) {
                    ForEach(AppLogLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                Picker("Category", selection: $categoryFilter) {
                    Text("All").tag(AppLogCategory?.none)
                    ForEach(AppLogCategory.allCases) { category in
                        Text(category.title).tag(AppLogCategory?.some(category))
                    }
                }
                .frame(maxWidth: 180)

                Spacer()

                Button {
                    copyAll()
                } label: {
                    Label(
                        copyFeedback ?? String(localized: "Copy all"),
                        systemImage: copyFeedback == nil ? "doc.on.doc" : "checkmark"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.entries.isEmpty)
                .help("Copies the full log to the clipboard (to paste in chat, email, etc.)")
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                Toggle("Source", isOn: $showSource)
                    .toggleStyle(.checkbox)
                    .help("Shows file and line for each entry")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search the log…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func logRow(_ entry: AppLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.level.symbolName)
                .foregroundStyle(entry.level.color)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.formattedTimestamp)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(entry.category.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(entry.level.color.opacity(0.15), in: Capsule())
                    if let runID = entry.runID {
                        Text(runID)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showSource {
                    Text(entry.sourceLocation)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contextMenu {
            Button("Copy line") {
                copyToPasteboard(entry.exportLine, feedback: nil)
            }
            if let runID = entry.runID {
                Button("Filter this run") {
                    searchText = runID
                }
            }
            Button("Copy all") {
                copyAll()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "%lld of %lld on screen"), Int64(filtered.count), Int64(store.entries.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let exportFeedback {
                    Text(exportFeedback)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            Button {
                copyAll()
            } label: {
                Label(copyFeedback ?? String(localized: "Copy all"), systemImage: "doc.on.doc")
            }
            .disabled(store.entries.isEmpty)
            .help("⇧⌘C — log completo no clipboard")

            Button("Save file…") {
                exportFile()
            }
            .disabled(store.entries.isEmpty)
            .help("Saves a full .log to any folder")

            Button("Show in Finder") {
                AppLogExport.revealLogFileInFinder()
            }
            .help(store.logFileURL.path)

            Button("Clear", role: .destructive) {
                store.clear()
            }
            .disabled(store.entries.isEmpty)
        }
    }

    private func copyAll() {
        let lines = AppLogExport.copyToPasteboard()
        guard lines > 0 else { return }
        copyFeedback = String(format: String(localized: "Copied (%lld)"), Int64(lines))
        AppLog.info(.settings, "Botão «Copiar» log (⇧⌘C) — \(lines) linhas na área de transferência")
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if copyFeedback == String(format: String(localized: "Copied (%lld)"), Int64(lines)) {
                copyFeedback = nil
            }
        }
    }

    private func copyToPasteboard(_ text: String, feedback: String?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        guard let feedback else { return }
        copyFeedback = feedback
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if copyFeedback == feedback {
                copyFeedback = nil
            }
        }
    }

    private func exportFile() {
        switch AppLogExport.presentSavePanel() {
        case .success(let url):
            let lines = (try? String(contentsOf: url, encoding: .utf8))
                .map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0
            exportFeedback = String(
                format: String(localized: "Saved: %@ (%lld lines)"),
                url.lastPathComponent,
                Int64(lines)
            )
            AppLog.info(.settings, "Botão «Salvar…» log — \(url.path) (\(lines) linhas)")
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if exportFeedback?.contains(url.lastPathComponent) == true {
                    exportFeedback = nil
                }
            }
        case .failure(let error):
            exportFeedback = String(localized: "Failed")
            AppLog.error(.settings, "Falha ao exportar logs: \(error.localizedDescription)")
        case .none:
            break
        }
    }
}
