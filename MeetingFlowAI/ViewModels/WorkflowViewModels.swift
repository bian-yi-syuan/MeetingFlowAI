import Foundation

@MainActor
final class RecordingDraftViewModel: ObservableObject {
    @Published var title = ""
    @Published var participants = ""
    @Published private(set) var marks: [TimeInterval] = []
    @Published var quickTodoTitle = ""
    @Published var currentMeeting: Meeting?

    func addMark(at time: TimeInterval) {
        marks.append(time)
    }

    func reset() {
        title = ""
        participants = ""
        marks = []
        quickTodoTitle = ""
        currentMeeting = nil
    }
}

@MainActor
final class MeetingWorkflowViewModel: ObservableObject {
    private let workflowManager: AIWorkflowManaging
    private let todoService: TodoExtracting
    private let emailService: EmailDraftGenerating

    init(
        workflowManager: AIWorkflowManaging = LocalAIWorkflowManager(),
        todoService: TodoExtracting = RuleBasedWorkflowService(),
        emailService: EmailDraftGenerating = RuleBasedWorkflowService()
    ) {
        self.workflowManager = workflowManager
        self.todoService = todoService
        self.emailService = emailService
    }

    func applySummary(to meeting: Meeting) throws {
        let draft = try summaryDraft(for: meeting)
        meeting.purpose = draft.purpose
        meeting.decisions = draft.decisions
        meeting.discussion = draft.discussion
        meeting.issues = draft.issues
        meeting.nextActions = draft.nextActions
        meeting.keywordsText = draft.keywords
        meeting.riskAnalysis = draft.risks
        meeting.followUp = draft.followUp
        meeting.status = .completed
        meeting.updatedAt = .now
    }

    func summaryDraft(for meeting: Meeting) throws -> SummaryDraft {
        try workflowManager.analyze(transcript: meeting.sortedTranscript)
    }

    func todoDrafts(for meeting: Meeting) -> [TodoDraft] {
        todoService.extract(from: meeting.sortedTranscript)
    }

    func emailBody(for meeting: Meeting) -> String {
        emailService.makeEmail(for: meeting)
    }
}
