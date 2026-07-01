import Foundation

enum AISkillID: String, CaseIterable {
    case transcriptAnalyzer = "TranscriptAnalyzer"
    case meetingPurpose = "MeetingPurpose"
    case decisionAgent = "DecisionAgent"
    case discussionAgent = "DiscussionAgent"
    case issueAgent = "IssueAgent"
    case actionAgent = "ActionAgent"
    case keywordAgent = "KeywordAgent"
    case riskAgent = "RiskAgent"
    case followUpAgent = "FollowUpAgent"
    case emailDraftAgent = "EmailDraftAgent"
}

struct AISkillDefinition: Equatable {
    let id: AISkillID
    let prompt: String
}

struct AISkillLibrary {
    func skill(_ id: AISkillID) -> AISkillDefinition {
        let prompt = (Bundle.main.url(forResource: id.rawValue, withExtension: "md", subdirectory: "AISkills")
            ?? Bundle.main.url(forResource: id.rawValue, withExtension: "md"))
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return AISkillDefinition(id: id, prompt: prompt)
    }

    var allSkills: [AISkillDefinition] { AISkillID.allCases.map(skill) }
}

protocol AIWorkflowManaging {
    func analyze(transcript: [TranscriptSegment]) throws -> SummaryDraft
}

/// 全Skillへ同じTranscriptを渡す統括層。MVPは端末内ルール実装で、将来ここだけをLLM Providerへ交換します。
struct LocalAIWorkflowManager: AIWorkflowManaging {
    private let analyzer: SummaryGenerating
    private let library: AISkillLibrary

    init(analyzer: SummaryGenerating = RuleBasedWorkflowService(), library: AISkillLibrary = AISkillLibrary()) {
        self.analyzer = analyzer
        self.library = library
    }

    func analyze(transcript: [TranscriptSegment]) throws -> SummaryDraft {
        _ = library.allSkills // Bundle内Promptの存在をWorkflow境界で確認します。
        return try analyzer.generate(from: transcript)
    }
}
