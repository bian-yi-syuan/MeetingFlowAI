import Foundation
import SwiftData

enum MeetingStatus: String, Codable, CaseIterable {
    case draft, processing, completed

    var title: String {
        switch self {
        case .draft: "下書き"
        case .processing: "処理中"
        case .completed: "整理済み"
        }
    }
}

@Model
final class Meeting {
    var id: UUID
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var participantsText: String
    var audioFileName: String?
    var statusRaw: String
    var purpose: String
    var decisions: String
    var discussion: String
    var issues: String
    var nextActions: String
    var keywordsText: String
    var riskAnalysis: String = ""
    var followUp: String = ""
    var purposeUserNotes: String = ""
    var decisionsUserNotes: String = ""
    var discussionUserNotes: String = ""
    var issuesUserNotes: String = ""
    var nextActionsUserNotes: String = ""
    var keywordsUserNotes: String = ""
    var riskUserNotes: String = ""
    var followUpUserNotes: String = ""
    var emailTo: String
    var emailSubject: String
    var emailBody: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var transcript: [TranscriptSegment] = []

    @Relationship(deleteRule: .cascade, inverse: \Speaker.meeting)
    var speakers: [Speaker] = []

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.meeting)
    var todos: [TodoItem] = []

    @Relationship(deleteRule: .cascade, inverse: \Participant.meeting)
    var participantRecords: [Participant] = []

    init(
        title: String,
        startedAt: Date = .now,
        duration: TimeInterval = 0,
        participantsText: String = "",
        audioFileName: String? = nil,
        status: MeetingStatus = .draft
    ) {
        self.id = UUID()
        self.title = title
        self.startedAt = startedAt
        self.duration = duration
        self.participantsText = participantsText
        self.audioFileName = audioFileName
        self.statusRaw = status.rawValue
        self.purpose = ""
        self.decisions = ""
        self.discussion = ""
        self.issues = ""
        self.nextActions = ""
        self.keywordsText = ""
        self.riskAnalysis = ""
        self.followUp = ""
        self.purposeUserNotes = ""
        self.decisionsUserNotes = ""
        self.discussionUserNotes = ""
        self.issuesUserNotes = ""
        self.nextActionsUserNotes = ""
        self.keywordsUserNotes = ""
        self.riskUserNotes = ""
        self.followUpUserNotes = ""
        self.emailTo = ""
        self.emailSubject = ""
        self.emailBody = ""
        self.createdAt = .now
        self.updatedAt = .now
    }

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var participants: [String] {
        if !participantRecords.isEmpty {
            return participantRecords.map(\.name).filter { !$0.isEmpty }
        }
        return participantsText
            .components(separatedBy: CharacterSet(charactersIn: ",、\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var sortedTranscript: [TranscriptSegment] {
        transcript.sorted { $0.orderIndex < $1.orderIndex }
    }

    var sortedTodos: [TodoItem] {
        todos.sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    var hasSummary: Bool {
        !purpose.isEmpty || !decisions.isEmpty || !discussion.isEmpty || !nextActions.isEmpty ||
        !purposeUserNotes.isEmpty || !decisionsUserNotes.isEmpty || !nextActionsUserNotes.isEmpty
    }

    var participantEmails: [String] {
        participantRecords.map(\.email).filter { !$0.isEmpty }
    }

    func combined(_ generated: String, notes: String) -> String {
        guard !notes.isEmpty else { return generated }
        guard !generated.isEmpty else { return notes }
        return generated + "\n\n【ユーザー追記】\n" + notes
    }
}
