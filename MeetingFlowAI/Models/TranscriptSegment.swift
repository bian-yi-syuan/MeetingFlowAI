import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    var id: UUID
    var speakerName: String
    var speakerColorHex: String
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var orderIndex: Int
    var isMarked: Bool
    var isLive: Bool = false
    var meeting: Meeting?

    init(
        speakerName: String = "発言者 A",
        speakerColorHex: String = "3B73F1",
        text: String,
        startTime: TimeInterval = 0,
        endTime: TimeInterval = 0,
        orderIndex: Int = 0,
        isMarked: Bool = false,
        isLive: Bool = false,
        meeting: Meeting? = nil
    ) {
        self.id = UUID()
        self.speakerName = speakerName
        self.speakerColorHex = speakerColorHex
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.orderIndex = orderIndex
        self.isMarked = isMarked
        self.isLive = isLive
        self.meeting = meeting
    }
}
