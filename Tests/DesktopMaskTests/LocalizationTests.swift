import Foundation
import Testing
@testable import DesktopMask

private func translations(_ language: String) throws -> [String: String] {
    let url = try #require(L10n.bundle.url(forResource: "Localizable", withExtension: "strings",
                                          subdirectory: nil, localization: language))
    let data = try Data(contentsOf: url)
    return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

@Test func translationKeysAndFormatArgumentsMatch() throws {
    let english = try translations("en")
    let chinese = try translations("zh-Hans")
    #expect(!english.isEmpty)
    #expect(Set(english.keys) == Set(chinese.keys))
    for (key, value) in english {
        let translated = try #require(chinese[key])
        #expect(value == key)
        #expect(!translated.isEmpty)
        #expect(value.matches(of: /%@|%%/).map { String($0.output) }
                == translated.matches(of: /%@|%%/).map { String($0.output) })
    }
}

@Test(arguments: ["en", "zh-Hans"])
func translatedMenusAndDynamicLabels(_ language: String) throws {
    let path = try #require(L10n.bundle.path(forResource: language, ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let mode = bundle.localizedString(forKey: "Automatic Mode", value: nil, table: nil)
    #expect(mode == (language == "en" ? "Automatic Mode" : "自动模式"))
    let format = bundle.localizedString(forKey: "Overlay Opacity: %@%%", value: nil, table: nil)
    let percentage = "40"
    let label = String(format: format, percentage)
    #expect(label == (language == "en" ? "Overlay Opacity: 40%" : "遮罩不透明度：40%"))
    let attachmentFormat = bundle.localizedString(forKey: "Attached: %@ · %@ (click to change)", value: nil, table: nil)
    let attachment = String(format: attachmentFormat, "Safari", "Example")
    #expect(attachment == (language == "en"
        ? "Attached: Safari · Example (click to change)"
        : "已附着：Safari · Example（点击重新选择）"))
}
