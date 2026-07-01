import Foundation

struct SummaryDraft: Equatable {
    let purpose: String
    let decisions: String
    let discussion: String
    let issues: String
    let nextActions: String
    let keywords: String
    let risks: String
    let followUp: String
}

struct TodoDraft: Equatable {
    let title: String
    let assignee: String
    let dueDate: Date?
    let sourceText: String
}

protocol SummaryGenerating {
    func generate(from segments: [TranscriptSegment]) throws -> SummaryDraft
}

protocol TodoExtracting {
    func extract(from segments: [TranscriptSegment]) -> [TodoDraft]
}

protocol EmailDraftGenerating {
    func makeEmail(for meeting: Meeting) -> String
}

enum WorkflowError: LocalizedError {
    case emptyTranscript

    var errorDescription: String? {
        "文字起こしが空です。内容を追加してから実行してください。"
    }
}

struct RuleBasedWorkflowService: SummaryGenerating, TodoExtracting, EmailDraftGenerating {
    func generate(from segments: [TranscriptSegment]) throws -> SummaryDraft {
        let sentences = segments
            .flatMap { $0.text.components(separatedBy: CharacterSet(charactersIn: "。！？\n")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !sentences.isEmpty else { throw WorkflowError.emptyTranscript }

        let actionWords = ["までに", "対応", "確認", "共有", "準備", "実施", "提出", "次回", "please", "by tomorrow", "by next week", "we will", "action item", "todo", "follow up"]
        let decisionWords = ["決定", "確定", "予定", "します", "実施", "decided", "we will"]
        let issueWords = ["課題", "懸念", "必要", "遅れ", "問題", "修正", "issue", "problem"]
        let riskWords = ["遅れ", "不足", "不明", "問題", "バグ", "修正", "リスク"]
        let actions = sentences.filter { sentence in actionWords.contains { sentence.contains($0) } }
        let decisions = sentences.filter { sentence in decisionWords.contains { sentence.contains($0) } }
        let issues = sentences.filter { sentence in issueWords.contains { sentence.contains($0) } }
        let risks = sentences.filter { sentence in riskWords.contains { sentence.contains($0) } }
        let actionDrafts = extract(from: segments)

        let commonWords = ["会議", "進捗", "対応", "確認", "資料", "デザイン", "リリース", "プロジェクト", "次回"]
        let keywords = commonWords.filter { word in sentences.contains { $0.contains(word) } }

        return SummaryDraft(
            purpose: String((sentences.first ?? "会議内容の確認").prefix(100)),
            decisions: bullet(decisions.isEmpty ? Array(sentences.prefix(2)) : decisions),
            discussion: sentences.prefix(5).joined(separator: "。") + "。",
            issues: bullet(issues.isEmpty ? ["継続して進捗を確認します"] : issues),
            nextActions: actionDrafts.isEmpty
                ? bullet(actions.isEmpty ? ["担当：未定\n内容：次回までに対応内容を確認する\n期限：未定"] : actions)
                : actionDrafts.map { draft in
                    let due = draft.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "未定"
                    return "・担当：\(draft.assignee.isEmpty ? "未定" : draft.assignee)\n  内容：\(draft.title)\n  期限：\(due)"
                }.joined(separator: "\n"),
            keywords: keywords.isEmpty ? "会議, アクション" : keywords.prefix(10).joined(separator: ", "),
            risks: risks.isEmpty ? "Low：明確なリスクは検出されませんでした。" : risks.map { "Medium：\($0)" }.joined(separator: "\n"),
            followUp: bullet(actions.isEmpty ? ["次回会議で進捗を確認する"] : actions.map { "□ \($0)" })
        )
    }

    func extract(from segments: [TranscriptSegment]) -> [TodoDraft] {
        let keywords = ["までに", "対応", "確認", "共有", "準備", "提出", "実施", "作成", "please", "by tomorrow", "by next week", "we will", "action item", "todo", "follow up"]
        let candidates = segments.flatMap { segment in
            segment.text
                .components(separatedBy: CharacterSet(charactersIn: "。！？\n"))
                .map { ($0.trimmingCharacters(in: .whitespacesAndNewlines), segment) }
        }
        return candidates.compactMap { sentence, segment in
            let normalized = sentence.lowercased()
            guard !sentence.isEmpty, keywords.contains(where: normalized.contains) else { return nil }
            return TodoDraft(
                title: sentence,
                assignee: segment.speakerName,
                dueDate: parseDueDate(from: sentence),
                sourceText: sentence
            )
        }
    }

    func makeEmail(for meeting: Meeting) -> String {
        let decisions = meeting.combined(meeting.decisions, notes: meeting.decisionsUserNotes).isEmpty ? "・会議内容をご確認ください。" : meeting.combined(meeting.decisions, notes: meeting.decisionsUserNotes)
        let actions = meeting.combined(meeting.nextActions, notes: meeting.nextActionsUserNotes).isEmpty ? "・今後の対応事項を確認します。" : meeting.combined(meeting.nextActions, notes: meeting.nextActionsUserNotes)
        let participants = meeting.participants.isEmpty ? "参加者未設定" : meeting.participants.joined(separator: "、")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        let date = formatter.string(from: meeting.startedAt)
        let todoSummary = meeting.sortedTodos.isEmpty
            ? "・登録されたToDoはありません。"
            : meeting.sortedTodos.map { todo in
                let assignee = todo.assignee.isEmpty ? "未定" : todo.assignee
                let due = todo.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "未定"
                let status = todo.isCompleted ? "完了" : "未完了"
                return "・\(todo.title)\n  担当：\(assignee)\n  期限：\(due)\n  優先度：\(todo.priority.title)\n  状態：\(status)"
            }.joined(separator: "\n\n")
        return """
        会議ご参加の皆様

        平素より大変お世話になっております。
        本日の「\(meeting.title)」の内容について、以下の通りご共有いたします。

        【会議情報】
        日時：\(date)
        参加者：\(participants)

        【決定事項】
        \(decisions)

        【今後の対応】
        \(actions)

        【ToDo】
        \(todoSummary)

        ご不明な点がございましたら、お知らせください。
        今後とも何卒よろしくお願い申し上げます。
        """
    }

    private func bullet(_ values: [String]) -> String {
        values.map { "・\($0)" }.joined(separator: "\n")
    }

    private func parseDueDate(from text: String) -> Date? {
        let pattern = #"(\d{1,2})月(\d{1,2})日"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let monthRange = Range(match.range(at: 1), in: text),
              let dayRange = Range(match.range(at: 2), in: text),
              let month = Int(text[monthRange]), let day = Int(text[dayRange]) else { return nil }
        var components = Calendar.current.dateComponents([.year], from: .now)
        components.month = month
        components.day = day
        components.hour = 9
        guard var date = Calendar.current.date(from: components) else { return nil }
        if date < Calendar.current.startOfDay(for: .now) {
            date = Calendar.current.date(byAdding: .year, value: 1, to: date) ?? date
        }
        return date
    }
}
