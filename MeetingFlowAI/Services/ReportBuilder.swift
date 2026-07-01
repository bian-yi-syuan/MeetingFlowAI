import Foundation

enum ReportBuilder {
    static func text(for meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        let transcript = meeting.sortedTranscript
            .map { "[\(formatDuration($0.startTime))] \($0.speakerName)：\($0.text)" }
            .joined(separator: "\n")
        let todos = meeting.sortedTodos
            .map { "\($0.isCompleted ? "☑" : "□") \($0.title)\($0.assignee.isEmpty ? "" : "（担当：\($0.assignee)）")" }
            .joined(separator: "\n")
        return """
        MeetingFlow AI 会議レポート
        ==============================
        会議名：\(meeting.title)
        日時：\(formatter.string(from: meeting.startedAt))
        参加者：\(meeting.participants.isEmpty ? "未設定" : meeting.participants.joined(separator: "、"))

        【会議の目的】
        \(meeting.combined(meeting.purpose, notes: meeting.purposeUserNotes))

        【決定事項】
        \(meeting.combined(meeting.decisions, notes: meeting.decisionsUserNotes))

        【議論内容】
        \(meeting.combined(meeting.discussion, notes: meeting.discussionUserNotes))

        【課題】
        \(meeting.combined(meeting.issues, notes: meeting.issuesUserNotes))

        【次回アクション】
        \(meeting.combined(meeting.nextActions, notes: meeting.nextActionsUserNotes))

        【リスク】
        \(meeting.combined(meeting.riskAnalysis, notes: meeting.riskUserNotes))

        【フォローアップ】
        \(meeting.combined(meeting.followUp, notes: meeting.followUpUserNotes))

        【ToDo】
        \(todos)

        【文字起こし】
        \(transcript)

        ※このレポートは端末内のデータから作成されました。共有前に機密情報をご確認ください。
        """
    }

    static func backupJSON(meetings: [Meeting]) -> String {
        let objects = meetings.map { meeting -> [String: Any] in
            [
                "id": meeting.id.uuidString,
                "title": meeting.title,
                "startedAt": ISO8601DateFormatter().string(from: meeting.startedAt),
                "participants": meeting.participants,
                "purpose": meeting.purpose,
                "decisions": meeting.decisions,
                "transcript": meeting.sortedTranscript.map { ["speaker": $0.speakerName, "text": $0.text] },
                "todos": meeting.sortedTodos.map { ["title": $0.title, "assignee": $0.assignee, "completed": $0.isCompleted] }
            ]
        }
        guard JSONSerialization.isValidJSONObject(objects),
              let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func formatDuration(_ value: TimeInterval) -> String {
        let total = max(0, Int(value))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
