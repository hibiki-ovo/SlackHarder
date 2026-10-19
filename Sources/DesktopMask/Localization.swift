import Foundation

enum L10n {
    static let bundle = Bundle.module
    private static let preferredBundle: Bundle = {
        let languages = ["en", "zh-Hans"]
        let language = Bundle.preferredLocalizations(from: languages,
                                                      forPreferences: Locale.preferredLanguages).first ?? "en"
        return localizedBundle(for: language) ?? bundle
    }()

    static func localizedBundle(for language: String) -> Bundle? {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "strings",
                                   subdirectory: nil, localization: language) else { return nil }
        return Bundle(url: url.deletingLastPathComponent())
    }

    static func text(_ key: String) -> String {
        preferredBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
