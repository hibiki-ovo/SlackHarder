import Foundation

enum L10n {
    static let bundle = Bundle.module
    private static let localizedBundle: Bundle = {
        let languages = ["en", "zh-Hans"]
        let language = Bundle.preferredLocalizations(from: languages,
                                                      forPreferences: Locale.preferredLanguages).first ?? "en"
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else { return bundle }
        return localized
    }()

    static func text(_ key: String) -> String {
        localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
