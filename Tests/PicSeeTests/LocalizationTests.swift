import AppKit
import Foundation
import Testing
@testable import PicSee

struct LocalizationTests {
    @Test func resolvesSystemLanguageAndUnsupportedLanguageFallback() {
        #expect(AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN", "en"]) == "zh-Hans")
        #expect(AppLanguage.system.resolved(preferredLanguages: ["en-US", "zh-Hans"]) == "en")
        #expect(AppLanguage.system.resolved(preferredLanguages: ["fr-FR"]) == "en")
        #expect(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]) == "en")
        #expect(AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en"]) == "zh-Hans")
    }

    @Test func rendersBothLanguagesAndKeepsUserContentLiteral() {
        #expect(L10n.render("设置…", language: "en") == "Settings…")
        #expect(L10n.render("设置…", language: "zh-Hans") == "设置…")
        #expect(L10n.render("将图片移到废纸篓？", language: "en") == "Move Image to Trash?")
        #expect(L10n.render("无法打开“%1$@”，当前图片已保留。", arguments: ["照片%2$@.jpg"], language: "en")
                == "Couldn’t open “照片%2$@.jpg”. The current image has been kept.")
        #expect(L10n.render("（当前显示比例 %1$@%）", arguments: ["25"], language: "en")
                == "(Current display scale: 25%)")
    }

    @Test func updateFrequencyAndAboutHaveEnglishTranslations() {
        #expect(L10n.render("自动检查更新：", language: "en") == "Automatically check for updates:")
        #expect(L10n.render("每天", language: "en") == "Daily")
        #expect(L10n.render("每周", language: "en") == "Weekly")
        #expect(L10n.render("每月", language: "en") == "Monthly")
        #expect(L10n.render("从不", language: "en") == "Never")
        #expect(L10n.render("关于", language: "en") == "About")
        #expect(L10n.render("关于…", language: "en") == "About…")
    }

    @Test @MainActor func preferencePersistsAndReloadsWithoutRestart() throws {
        let name = "PicSee.LocalizationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = LanguageSettings(defaults: defaults)
        #expect(settings.selection == .system)
        settings.set(.english)
        #expect(settings.selection == .english)
        #expect(settings.revision == 1)
        #expect(AppLanguage.current(in: defaults) == .english)
        let second = LanguageSettings(defaults: defaults)
        #expect(second.selection == .english)
        defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.defaultsKey)
        settings.reload()
        #expect(settings.selection == .simplifiedChinese)
        #expect(settings.revision == 2)
        settings.set(.simplifiedChinese)
        #expect(settings.revision == 2)
        settings.set(.system)
        #expect(AppLanguage.current(in: defaults) == .system)
    }

    @Test func catalogsHaveIdenticalKeysAndCompleteEnglishTranslations() throws {
        func catalog(_ language: String) throws -> [String: String] {
            let url = try #require(L10n.localizedBundle(language).url(forResource: "Localizable", withExtension: "strings"))
            return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let chinese = try catalog("zh-Hans")
        let english = try catalog("en")
        #expect(chinese.count >= 240)
        #expect(Set(chinese.keys) == Set(english.keys))
        for (key, value) in english {
            #expect(!value.isEmpty, "Empty translation: \(key)")
            #expect(value.range(of: "\\p{Han}", options: .regularExpression) == nil, "Untranslated English value: \(key)")
            let regex = try NSRegularExpression(pattern: "%[1-9][0-9]*\\$@")
            func placeholders(_ string: String) -> [String] {
                regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
                    .map { (string as NSString).substring(with: $0.range) }.sorted()
            }
            #expect(placeholders(key) == placeholders(value), "Placeholder mismatch: \(key)")
        }
    }
}
