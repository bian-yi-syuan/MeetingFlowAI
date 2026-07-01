import Foundation
import SwiftData

enum ParticipantSyncService {
    static let colors = ["517CF6", "3FB98A", "6C63F2", "E55757", "F3A52B", "2E9AB8"]

    @MainActor
    static func syncNames(from text: String, meeting: Meeting, context: ModelContext) {
        let names = parseNames(text)
        let existing = meeting.participantRecords.sorted { $0.orderIndex < $1.orderIndex }

        for (index, name) in names.enumerated() {
            if index < existing.count {
                let participant = existing[index]
                if participant.name != name {
                    renameSpeaker(from: participant.name, to: name, meeting: meeting)
                    participant.name = name
                }
                participant.orderIndex = index
            } else {
                context.insert(Participant(name: name, orderIndex: index, meeting: meeting))
                if !meeting.speakers.contains(where: { $0.name == name }) {
                    context.insert(Speaker(name: name, colorHex: colors[index % colors.count], meeting: meeting))
                }
            }
        }

        if existing.count > names.count {
            for participant in existing.dropFirst(names.count) {
                if !meeting.transcript.contains(where: { $0.speakerName == participant.name }) {
                    meeting.speakers.filter { $0.name == participant.name }.forEach(context.delete)
                }
                context.delete(participant)
            }
        }
        meeting.participantsText = names.joined(separator: "、")
        meeting.updatedAt = .now
    }

    static func parseNames(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",、\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    static func renameSpeaker(from oldName: String, to newName: String, meeting: Meeting) {
        meeting.speakers.filter { $0.name == oldName }.forEach { $0.name = newName }
        meeting.transcript.filter { $0.speakerName == oldName }.forEach { $0.speakerName = newName }
    }
}
