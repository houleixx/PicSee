import AppKit
import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Sendable {
    case system, simplifiedChinese = "zh-Hans", english = "en"

    static let defaultsKey = "PicSee.Language"

    var title: String {
        switch self {
        case .system: L10n.text("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .system
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if self != .system { return rawValue }
        return Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages).first ?? "en"
    }
}

/// Explicit bundle selection supports changing language without restarting the process.
/// Stateless lookups are also safe from background image and file operations.
enum L10n {
    static var languageCode: String { AppLanguage.current().resolved() }
    static var locale: Locale { Locale(identifier: languageCode) }

    static func text(_ key: String, _ arguments: String...) -> String {
        render(key, arguments: arguments, language: languageCode)
    }

    static func render(_ key: String, arguments: [String] = [], language: String) -> String {
        let bundle = localizedBundle(language)
        let template = bundle.localizedString(forKey: key, value: key, table: nil)
        // Replace placeholders once, so filenames containing placeholders stay literal.
        let expression = try! NSRegularExpression(pattern: "%([1-9][0-9]*)\\$@")
        let source = template as NSString
        var result = template
        for match in expression.matches(in: template, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let index = Int(source.substring(with: match.range(at: 1))), index <= arguments.count,
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index - 1])
        }
        return result
    }

    static func errorDescription(_ error: Error) -> String {
        if let error = error as? UpdateInstaller.Failure { return error.errorDescription ?? "" }
        if let error = error as? ImageExporterError { return error.errorDescription ?? "" }
        if let error = error as? DefaultImageAppError { return error.errorDescription ?? "" }
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return L10n.text("没有访问此文件的权限。")
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return L10n.text("文件不存在或已被移动。")
            case NSFileWriteOutOfSpaceError:
                return L10n.text("磁盘空间不足。")
            default: break
            }
        }
        return L10n.text("操作失败（%1$@，错误码 %2$@）。", error.domain, String(error.code))
    }

    static func localizedBundle(_ language: String) -> Bundle {
        let resources = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("PicSee_PicSee.bundle"))
        } ?? Bundle.module
        // SwiftPM lowercases localization directory names. Construct the exact URL;
        // Bundle.path(forResource:) may apply the process language's fallback rules.
        let root = resources.resourceURL!
        return Bundle(url: root.appendingPathComponent(language.lowercased() + ".lproj"))
            ?? Bundle(url: root.appendingPathComponent("en.lproj"))!
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    @Published private(set) var selection: AppLanguage
    @Published private(set) var revision = 0
    private var resolvedLanguage: String
    private var observations = Set<AnyCancellable>()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = AppLanguage.current(in: defaults)
        resolvedLanguage = AppLanguage.current(in: defaults).resolved()
        for publisher in [
            NotificationCenter.default.publisher(for: ViewerPreferenceChange.notification).eraseToAnyPublisher(),
            DistributedNotificationCenter.default().publisher(for: ViewerPreferenceChange.distributedNotification).eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification).eraseToAnyPublisher()
        ] {
            publisher.sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reload() }
            }.store(in: &observations)
        }
    }

    func set(_ language: AppLanguage) {
        guard language != selection else { return }
        defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey)
        reload()
        ViewerPreferenceChange.post(in: defaults)
    }

    func reload() {
        defaults.synchronize()
        let latest = AppLanguage.current(in: defaults)
        let resolved = latest.resolved()
        guard latest != selection || resolved != resolvedLanguage else { return }
        selection = latest
        resolvedLanguage = resolved
        revision += 1
    }
}

@MainActor
extension LanguageSettings {
    private static var bindingKey: UInt8 = 0

    /// Retain the subscription with the native control, never the control with the subscription.
    static func bind<T: NSObject>(_ owner: T, update: @escaping @MainActor (T) -> Void) {
        update(owner)
        let observation = shared.$revision.dropFirst().sink { [weak owner] _ in
            guard let owner else { return }
            update(owner)
        }
        objc_setAssociatedObject(owner, &bindingKey, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
