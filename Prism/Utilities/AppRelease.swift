import Foundation

/// Identidade pública do produto e links de suporte (GitHub).
enum AppRelease {
    static let githubOwner = "GoobinEXE"
    static let githubRepo = "PrismTranslate"

    static let licenseName = "PolyForm Noncommercial License 1.0.0"
    static var licenseURL: URL {
        URL(string: "https://polyformproject.org/licenses/noncommercial/1.0.0")!
    }

    static var bundledLicenseURL: URL? {
        Bundle.main.url(forResource: "LICENSE", withExtension: nil)
    }

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)")!
    }

    static var releasesURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases")!
    }

    static var newIssueURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/issues/new")!
    }

    static func reportIssueURL(version: String, build: String, macOS: String) -> URL {
        var components = URLComponents(
            string: "https://github.com/\(githubOwner)/\(githubRepo)/issues/new"
        )!
        let body = """
            ## O que aconteceu


            ## O que você esperava


            ## Ambiente
            - Prism \(version) (\(build))
            - \(macOS)
            """
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url ?? newIssueURL
    }

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.marcelopessoa.prism"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 Prism Translate."
    }

    static var runningMacOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var githubProfileURL: URL {
        URL(string: "https://github.com/\(githubOwner)")!
    }

    static var githubAvatarURL: URL {
        URL(string: "https://github.com/\(githubOwner).png?size=128")!
    }
}

/// Créditos do time — texto da aba Sobre.
enum AppCredits {
    static let developerName = "Marcelo Pessoa"
    static let developerRole = String(localized: "Creator and developer")
    static let location = "Curitiba, PR — Brasil"
    static let githubHandle = "@GoobinEXE"
    static let bio =
        String(localized: "Solo project: from idea to design, from code to release. Crafted so translation never gets in the way of people who write all day.")
}

// MARK: - SemVer

struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    static func parse(_ raw: String) -> SemanticVersion? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        let numeric =
            text.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? text
        let parts = numeric.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return SemanticVersion(
            major: parts[0],
            minor: parts.count > 1 ? parts[1] : 0,
            patch: parts.count > 2 ? parts[2] : 0
        )
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

// MARK: - Changelog

enum ChangelogHighlights {
    static func bundledMarkdown() -> String? {
        Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// Texto da aba Sobre: só a seção `### Novidades` (linguagem para o público).
    /// Sem essa seção, usa o parágrafo de abertura — nunca Adicionado/Changed/Fixed.
    static func summary(for version: String, markdown: String) -> String? {
        guard let section = section(for: version, in: markdown) else { return nil }
        if let novidades = subsection(named: "Novidades", in: section) {
            return formatLines(novidades)
        }
        return formatLines(leadParagraph(in: section))
    }

    static func summaryForCurrentVersion() -> String {
        let version = AppRelease.marketingVersion
        if let markdown = bundledMarkdown(),
            let summary = summary(for: version, markdown: markdown)
        {
            return summary
        }
        return fallbackSummary
    }

    /// Usado se o CHANGELOG não estiver no bundle (dev) ou a versão não tiver seção.
    static let fallbackSummary = """
        Melhorias de estabilidade e correção de bugs.
        """

    static func section(for version: String, in markdown: String) -> String? {
        let heading = "## [\(version)]"
        guard let start = markdown.range(of: heading) else { return nil }
        var rest = markdown[start.upperBound...]
        if rest.hasPrefix(" - "), let newline = rest.firstIndex(of: "\n") {
            rest = rest[rest.index(after: newline)...]
        }
        if let next = rest.range(of: "\n## [") {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    private static func subsection(named name: String, in section: String) -> [String]? {
        let needle = "### \(name)".lowercased()
        var collecting = false
        var lines: [String] = []
        for raw in section.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("### ") {
                if collecting { break }
                collecting = line.lowercased().hasPrefix(needle)
                continue
            }
            if collecting, !line.isEmpty {
                lines.append(line)
            }
        }
        return lines.isEmpty ? nil : lines
    }

    private static func leadParagraph(in section: String) -> [String] {
        var lines: [String] = []
        for raw in section.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") { break }
            if line.isEmpty { continue }
            lines.append(line)
        }
        return lines
    }

    private static func formatLines(_ lines: [String]) -> String? {
        let text = lines.map(stripMarkdown).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func stripMarkdown(_ line: String) -> String {
        var text = line
        text = text.replacingOccurrences(of: "**", with: "")
        if text.hasPrefix("- ") {
            text = "• " + text.dropFirst(2)
        } else if text.hasPrefix("* ") {
            text = "• " + text.dropFirst(2)
        }
        return text
    }
}

// MARK: - Updates (GitHub Releases)

enum UpdateCheckResult: Equatable {
    case upToDate
    case aheadOfRelease(published: String)
    case available(version: String, url: URL)
    case nonePublished
    case failed(String)
}

enum GitHubUpdateChecker {
    struct Release: Decodable, Equatable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    static func check(currentVersion: String, session: URLSession = .shared) async
        -> UpdateCheckResult
    {
        guard
            let url = URL(
                string:
                    "https://api.github.com/repos/\(AppRelease.githubOwner)/\(AppRelease.githubRepo)/releases?per_page=10"
            )
        else {
            return .failed("URL inválida.")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(
            "PrismTranslate (\(AppRelease.repositoryURL.absoluteString))",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                return .nonePublished
            }
            guard (200..<300).contains(status) else {
                return .failed("GitHub respondeu HTTP \(status).")
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            return evaluate(releases: releases, currentVersion: currentVersion)
        } catch is DecodingError {
            return .failed("Resposta inesperada do GitHub.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func evaluate(releases: [Release], currentVersion: String) -> UpdateCheckResult {
        let published = releases.filter { !$0.draft }
        guard let latest = published.first else { return .nonePublished }
        guard let latestVersion = SemanticVersion.parse(latest.tagName),
            let current = SemanticVersion.parse(currentVersion)
        else {
            return .failed("Não foi possível comparar as versões.")
        }

        let label =
            latest.tagName.hasPrefix("v") ? String(latest.tagName.dropFirst()) : latest.tagName
        if latestVersion > current {
            if let url = URL(string: latest.htmlURL) {
                return .available(version: label, url: url)
            }
            return .available(version: label, url: AppRelease.releasesURL)
        }
        if latestVersion < current {
            return .aheadOfRelease(published: label)
        }
        return .upToDate
    }
}
