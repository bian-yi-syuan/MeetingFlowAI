import Foundation
import SwiftData

@Model
final class Participant {
    var id: UUID
    var name: String
    var email: String
    var orderIndex: Int
    var meeting: Meeting?

    init(name: String, email: String = "", orderIndex: Int = 0, meeting: Meeting? = nil) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.orderIndex = orderIndex
        self.meeting = meeting
    }
}
