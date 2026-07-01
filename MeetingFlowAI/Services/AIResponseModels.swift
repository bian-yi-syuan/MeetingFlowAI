import Foundation

struct TranscriptAnalysisResponse: Codable {
    let meeting: MeetingAnalysisObject
}

struct MeetingAnalysisObject: Codable {
    let purpose: String
    let decisions: [String]
    let discussion: [DiscussionResponse]
    let issues: [String]
    let actions: [ActionResponse]
    let keywords: [String]
    let risks: [RiskResponse]
    let followUp: [FollowUpResponse]
}

struct MeetingPurposeResponse: Codable { let meetingPurpose: String }
struct DecisionResponse: Codable { let decisions: [String] }
struct IssueResponse: Codable { let issues: [String] }
struct KeywordResponse: Codable { let keywords: [String] }

struct DiscussionResponse: Codable {
    let topic: String
    let content: String
    let status: String
}

struct ActionResponse: Codable {
    let assignee: String
    let content: String
    let dueDate: String
}

struct RiskResponse: Codable {
    let level: String
    let risk: String
    let evidence: String
}

struct FollowUpResponse: Codable {
    let checked: Bool
    let item: String
}

struct EmailDraftResponse: Codable {
    let subject: String
    let body: String
}
