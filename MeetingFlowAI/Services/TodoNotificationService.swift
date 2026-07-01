import Foundation
import UserNotifications

enum TodoNotificationError: LocalizedError {
    case accessDenied
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .accessDenied: "通知が許可されていません。iOSの設定から通知を有効にしてください。"
        case .invalidDate: "通知日時が過去になっています。ToDoの期限を更新してください。"
        }
    }
}

struct TodoNotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func schedule(for todo: TodoItem) async throws {
        guard !todo.isCompleted, let dueDate = todo.dueDate else {
            cancel(todoID: todo.id)
            return
        }
        guard dueDate > .now else { throw TodoNotificationError.invalidDate }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { throw TodoNotificationError.accessDenied }

        let content = UNMutableNotificationContent()
        content.title = "ToDoの期限です"
        content.body = todo.title
        content.sound = .default
        content.userInfo = ["todoID": todo.id.uuidString]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier(todo.id), content: content, trigger: trigger))
    }

    func scheduleTest() async throws {
        guard try await requestAuthorization() else { throw TodoNotificationError.accessDenied }
        let content = UNMutableNotificationContent()
        content.title = "MeetingFlow AI"
        content.body = "通知音と右上のベルは正常に動作しています。"
        content.sound = .default
        try await center.add(UNNotificationRequest(
            identifier: "meetingflow-notification-test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        ))
    }

    func cancel(todoID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(todoID)])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.setBadgeCount(0)
    }

    private func identifier(_ id: UUID) -> String { "meetingflow.todo.\(id.uuidString)" }
}
