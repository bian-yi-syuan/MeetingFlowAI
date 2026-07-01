import Foundation

enum SubtitleLanguage: String, CaseIterable, Identifiable {
    case japanese
    case english

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self { case .japanese: "ja-JP"; case .english: "en-US" }
    }

    var displayName: String {
        switch self { case .japanese: "日本語"; case .english: "English" }
    }
}
