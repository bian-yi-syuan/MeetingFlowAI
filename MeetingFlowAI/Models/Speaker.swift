import Foundation
import SwiftData

@Model
final class Speaker {
    var id: UUID
    var name: String
    var colorHex: String
    var meeting: Meeting?

    init(name: String, colorHex: String, meeting: Meeting? = nil) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.meeting = meeting
    }
}
