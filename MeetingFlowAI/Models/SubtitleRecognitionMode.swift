import Foundation

enum SubtitleRecognitionMode: String, CaseIterable, Identifiable {
    case real
    case simulatorMock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .real: "実際の音声認識"
        case .simulatorMock: "Simulator Mock"
        }
    }
}
