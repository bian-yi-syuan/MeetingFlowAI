import Foundation
import SwiftData

enum TodoPriority: String, Codable, CaseIterable {
    case high, medium, low

    var title: String {
        switch self { case .high: "高"; case .medium: "中"; case .low: "低" }
    }
}

@Model
final class TodoItem {
    var id: UUID
    var title: String
    var assignee: String
    var dueDate: Date?
    var isCompleted: Bool
    var sourceText: String
    var priorityRaw: String
    var createdAt: Date
    var meeting: Meeting?

    init(
        title: String,
        assignee: String = "",
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        sourceText: String = "",
        priority: TodoPriority = .medium,
        meeting: Meeting? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.assignee = assignee
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.sourceText = sourceText
        self.priorityRaw = priority.rawValue
        self.createdAt = .now
        self.meeting = meeting
    }

    var priority: TodoPriority {
        get { TodoPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}
