import XCTest

@testable import Prism

final class AppReleaseTests: XCTestCase {
    func testParseStripsVPrefixAndCompares() {
        XCTAssertEqual(SemanticVersion.parse("v0.6.0"), SemanticVersion(major: 0, minor: 6, patch: 0))
        XCTAssertEqual(SemanticVersion.parse("1.10.2"), SemanticVersion(major: 1, minor: 10, patch: 2))
        XCTAssertLessThan(SemanticVersion.parse("0.5.0")!, SemanticVersion.parse("0.6.0")!)
        XCTAssertGreaterThan(SemanticVersion.parse("0.10.0")!, SemanticVersion.parse("0.9.0")!)
    }

    func testChangelogSummaryUsesNovidadesNotTechnicalSections() {
        let markdown = """
        ## [0.6.0] - 2026-08-13

        Resumo técnico para o CHANGELOG.

        ### Novidades

        - Novos controles no menu da barra
        - Melhorias de estabilidade e correção de bugs

        ### Changed

        - Cache de tradução inclui motor/modelo/endpoint
        - Google Translate v2 envia `q` no POST

        ### Notas de maturidade

        - Validado E2E: Apple Translation.

        ## [0.5.0] - 2026-08-13

        Rebrand.
        """
        let summary = ChangelogHighlights.summary(for: "0.6.0", markdown: markdown)
        XCTAssertEqual(
            summary,
            """
            • Novos controles no menu da barra
            • Melhorias de estabilidade e correção de bugs
            """
        )
        XCTAssertFalse(summary?.contains("Cache de tradução") == true)
        XCTAssertNil(ChangelogHighlights.summary(for: "9.9.9", markdown: markdown))
    }

    func testChangelogSummaryFallsBackToLeadParagraph() {
        let markdown = """
        ## [0.5.0] - 2026-08-13

        Novo nome e visual do app.

        ### Changed

        - bundle ID `com.marcelopessoa.prism`
        """
        XCTAssertEqual(
            ChangelogHighlights.summary(for: "0.5.0", markdown: markdown),
            "Novo nome e visual do app."
        )
    }

    func testUpdateCheckAvailableAndNonePublished() {
        let newer = GitHubUpdateChecker.Release(
            tagName: "v0.7.0",
            htmlURL: "https://github.com/GoobinEXE/PrismTranslate/releases/tag/v0.7.0",
            draft: false,
            prerelease: false
        )
        let result = GitHubUpdateChecker.evaluate(releases: [newer], currentVersion: "0.6.0")
        XCTAssertEqual(result, .available(version: "0.7.0", url: URL(string: newer.htmlURL)!))

        XCTAssertEqual(GitHubUpdateChecker.evaluate(releases: [], currentVersion: "0.6.0"), .nonePublished)
        XCTAssertEqual(
            GitHubUpdateChecker.evaluate(releases: [newer], currentVersion: "0.7.0"),
            .upToDate
        )
        XCTAssertEqual(
            GitHubUpdateChecker.evaluate(releases: [newer], currentVersion: "0.8.0"),
            .aheadOfRelease(published: "0.7.0")
        )
    }

    func testUpdateCheckIgnoresDrafts() {
        let draft = GitHubUpdateChecker.Release(
            tagName: "v1.0.0",
            htmlURL: "https://example.com",
            draft: true,
            prerelease: false
        )
        XCTAssertEqual(
            GitHubUpdateChecker.evaluate(releases: [draft], currentVersion: "0.6.0"),
            .nonePublished
        )
    }

    func testLicenseIdentity() {
        XCTAssertEqual(AppRelease.licenseName, "PolyForm Noncommercial License 1.0.0")
        XCTAssertEqual(AppRelease.githubRepo, "PrismTranslate")
        XCTAssertEqual(AppRelease.licenseURL.host, "polyformproject.org")
        XCTAssertTrue(
            AppRelease.repositoryURL.absoluteString.contains("PrismTranslate")
        )
    }
}
