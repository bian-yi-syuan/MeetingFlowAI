import EventKit
import Foundation

enum CalendarServiceError: LocalizedError {
    case accessDenied
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied: "カレンダーへのアクセスが許可されていません。"
        case .noCalendar: "追加先のカレンダーが見つかりません。"
        }
    }
}

protocol CalendarEventCreating {
    func add(title: String, date: Date, notes: String) async throws -> String
}

struct EventKitCalendarService: CalendarEventCreating {
    func add(title: String, date: Date, notes: String) async throws -> String {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw CalendarServiceError.accessDenied }
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarServiceError.noCalendar }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = date
        event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
        event.notes = notes
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
}
