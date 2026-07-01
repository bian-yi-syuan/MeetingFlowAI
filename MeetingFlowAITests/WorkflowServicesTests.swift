import XCTest
@testable import MeetingFlowAI

final class WorkflowServicesTests: XCTestCase {
    private let service = RuleBasedWorkflowService()

    func testSummaryUsesTranscriptAndFindsActions() throws {
        let segments = [
            TranscriptSegment(speakerName: "田中さん", text: "プロジェクトの進捗を確認します。"),
            TranscriptSegment(speakerName: "佐藤さん", text: "7月10日までに資料を共有します。")
        ]

        let result = try service.generate(from: segments)

        XCTAssertTrue(result.purpose.contains("進捗"))
        XCTAssertTrue(result.nextActions.contains("資料を共有"))
        XCTAssertTrue(result.keywords.contains("進捗"))
    }

    func testEmptyTranscriptThrowsClearError() {
        XCTAssertThrowsError(try service.generate(from: [])) { error in
            XCTAssertEqual(error.localizedDescription, WorkflowError.emptyTranscript.localizedDescription)
        }
    }

    func testTodoExtractionKeepsSpeakerAndDueDate() {
        let segment = TranscriptSegment(
            speakerName: "佐藤さん",
            text: "7月10日までに見積書を確認してください。"
        )

        let result = service.extract(from: [segment])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.assignee, "佐藤さん")
        XCTAssertNotNil(result.first?.dueDate)
    }

    func testEmailContainsMeetingTitleAndBusinessGreeting() {
        let meeting = Meeting(title: "企画レビュー")
        meeting.decisions = "・次回案を作成する"
        meeting.todos = [TodoItem(title: "見積書を確認", assignee: "田中さん", meeting: meeting)]

        let body = service.makeEmail(for: meeting)

        XCTAssertTrue(body.contains("企画レビュー"))
        XCTAssertTrue(body.contains("お世話になっております"))
        XCTAssertTrue(body.contains("【ToDo】"))
        XCTAssertTrue(body.contains("見積書を確認"))
        XCTAssertTrue(body.contains("【会議情報】"))
        XCTAssertTrue(body.contains("【決定事項】"))
        XCTAssertTrue(body.contains("【今後の対応】"))
        XCTAssertFalse(body.contains("□"))
    }

    func testAudioFileServiceRejectsPathTraversal() {
        XCTAssertThrowsError(try LocalAudioFileService().url(for: "../secret.m4a"))
    }

    func testMultipleEmailAddressesAreValidatedAndDeduplicated() {
        let values = EmailAddressParser.parse("A@example.com, b@example.co.jp; invalid, a@example.com")
        XCTAssertEqual(values, ["a@example.com", "b@example.co.jp"])
    }

    @MainActor
    func testRegenerationPreservesUserNotes() throws {
        let meeting = Meeting(title: "再生成テスト")
        meeting.transcript = [TranscriptSegment(text: "来週までに資料を共有します。", meeting: meeting)]
        meeting.decisionsUserNotes = "ユーザーが追記した重要事項"

        try MeetingWorkflowViewModel().applySummary(to: meeting)

        XCTAssertEqual(meeting.decisionsUserNotes, "ユーザーが追記した重要事項")
        XCTAssertFalse(meeting.decisions.isEmpty)
    }
}
