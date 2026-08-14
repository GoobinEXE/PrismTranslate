import XCTest

@testable import Prism

final class LanguageMappingTests: XCTestCase {
    // MARK: LanguageCode

    func testDisplayNameForKnownLanguages() {
        XCTAssertEqual(LanguageCode.displayName(for: "pt"), "Português")
        XCTAssertEqual(LanguageCode.displayName(for: "en"), "English")
        XCTAssertEqual(LanguageCode.displayName(for: "zh-Hans"), "中文 (简体)")
        XCTAssertEqual(LanguageCode.displayName(for: "zh-Hant"), "中文 (繁體)")
    }

    func testPairLabel() {
        XCTAssertEqual(
            LanguageCode.pairLabel(from: "pt", to: "en"),
            "Português → English"
        )
        XCTAssertEqual(
            LanguageCode.pairLabel(from: nil, to: "en"),
            "detecção automática → English"
        )
    }

    func testDisplayNameFallsBackToRawCode() {
        XCTAssertEqual(LanguageCode.displayName(for: "xx"), "xx")
    }

    func testCommonTargetsHaveUniqueIDs() {
        let ids = LanguageCode.commonTargets.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testSystemDefaultTargetIsAlwaysAKnownTarget() {
        let id = LanguageCode.systemDefaultTarget
        XCTAssertTrue(
            LanguageCode.commonTargets.contains(where: { $0.id == id }),
            "systemDefaultTarget (\(id)) deve existir em commonTargets"
        )
    }

    func testSystemLanguageIsAlwaysAKnownTarget() {
        let id = LanguageCode.systemLanguage
        XCTAssertTrue(
            LanguageCode.commonTargets.contains(where: { $0.id == id }),
            "systemLanguage (\(id)) deve existir em commonTargets"
        )
    }

    func testSystemDefaultTargetDiffersFromSystemLanguage() {
        XCTAssertNotEqual(
            LanguageCode.systemLanguage,
            LanguageCode.systemDefaultTarget,
            "origem e destino padrão não devem coincidir"
        )
    }

    // MARK: DeepL

    func testDeepLTargetDistinguishesChineseVariants() {
        XCTAssertEqual(DeepLProvider.apiCode(for: "zh-Hans", isTarget: true), "ZH-HANS")
        XCTAssertEqual(DeepLProvider.apiCode(for: "zh-Hant", isTarget: true), "ZH-HANT")
    }

    func testDeepLSourceCollapsesChineseToZH() {
        // source_lang do DeepL só aceita o idioma base (ZH), sem variante de escrita.
        XCTAssertEqual(DeepLProvider.apiCode(for: "zh-Hans", isTarget: false), "ZH")
        XCTAssertEqual(DeepLProvider.apiCode(for: "zh-Hant", isTarget: false), "ZH")
        XCTAssertEqual(DeepLProvider.apiCode(for: "zh", isTarget: false), "ZH")
    }

    func testDeepLPortugueseMapping() {
        XCTAssertEqual(DeepLProvider.apiCode(for: "pt", isTarget: true), "PT-BR")
        XCTAssertEqual(DeepLProvider.apiCode(for: "pt-PT", isTarget: true), "PT-PT")
        XCTAssertEqual(DeepLProvider.apiCode(for: "pt", isTarget: false), "PT")
        XCTAssertEqual(DeepLProvider.apiCode(for: "pt-BR", isTarget: false), "PT")
    }

    func testDeepLPassthroughUppercasesUnknownCodes() {
        XCTAssertEqual(DeepLProvider.apiCode(for: "fr", isTarget: true), "FR")
        XCTAssertEqual(DeepLProvider.apiCode(for: "ja", isTarget: false), "JA")
    }

    // MARK: Google

    func testGoogleChineseMapping() {
        XCTAssertEqual(GoogleTranslateProvider.apiCode(for: "zh-Hans"), "zh-CN")
        XCTAssertEqual(GoogleTranslateProvider.apiCode(for: "zh-Hant"), "zh-TW")
    }

    func testGooglePassthroughForOtherCodes() {
        XCTAssertEqual(GoogleTranslateProvider.apiCode(for: "pt"), "pt")
        XCTAssertEqual(GoogleTranslateProvider.apiCode(for: "en"), "en")
    }

    // MARK: Apple Translation locale map

    func testAppleSpecUsesRegionWithoutScript() {
        XCTAssertEqual(AppleTranslationLanguageMap.spec(forAppCode: "en").bcp47, "en-US")
        XCTAssertEqual(AppleTranslationLanguageMap.spec(forAppCode: "pt").bcp47, "pt-BR")
        XCTAssertEqual(AppleTranslationLanguageMap.spec(forAppCode: "zh-Hans").bcp47, "zh-CN")
        XCTAssertEqual(AppleTranslationLanguageMap.spec(forAppCode: "zh-Hant").bcp47, "zh-TW")
        XCTAssertNil(AppleTranslationLanguageMap.spec(forAppCode: "en").script)
    }

    func testAppleMakeLanguageOmitsLatnScript() {
        let english = AppleTranslationLanguageMap.makeLanguage(forAppCode: "en")
        XCTAssertEqual(english.languageCode?.identifier, "en")
        XCTAssertEqual(english.region?.identifier, "US")
        XCTAssertNil(english.script)
    }

    func testApplePickPrefersMatchingRegionFromSupportedList() {
        let enGB = Locale.Language(
            components: .init(
                languageCode: Locale.LanguageCode("en"),
                script: nil,
                region: Locale.Region("GB")
            )
        )
        let enUS = Locale.Language(
            components: .init(
                languageCode: Locale.LanguageCode("en"),
                script: nil,
                region: Locale.Region("US")
            )
        )
        let picked = AppleTranslationLanguageMap.pick(appCode: "en", from: [enGB, enUS])
        XCTAssertEqual(picked?.region?.identifier, "US")
    }

    func testAppleAppCodeCollapsesChineseRegions() {
        let zhCN = Locale.Language(
            components: .init(
                languageCode: Locale.LanguageCode("zh"),
                script: nil,
                region: Locale.Region("CN")
            )
        )
        let zhTW = Locale.Language(
            components: .init(
                languageCode: Locale.LanguageCode("zh"),
                script: nil,
                region: Locale.Region("TW")
            )
        )
        XCTAssertEqual(AppleTranslationLanguageMap.appCode(from: zhCN), "zh-Hans")
        XCTAssertEqual(AppleTranslationLanguageMap.appCode(from: zhTW), "zh-Hant")
    }

    func testAppleConcreteSourceAvoidsSameLanguageAsTarget() {
        let source = AppleTranslationLanguageMap.concreteSource(preferred: "pt", target: "pt")
        XCTAssertNotEqual(source, "pt")
        XCTAssertFalse(source.isEmpty)
    }

    func testAppleConcreteSourceKeepsDistinctPreferred() {
        XCTAssertEqual(
            AppleTranslationLanguageMap.concreteSource(preferred: "en", target: "pt"),
            "en"
        )
    }
}
