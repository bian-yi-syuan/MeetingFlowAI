import SwiftUI
import SwiftData

struct CalendarIntegrationView: View {
    @Query(sort: \TodoItem.createdAt) private var allTodos: [TodoItem]
    var meeting: Meeting?
    @State private var selectedDate = Date()
    @State private var confirmation: String?
    @State private var errorMessage: String?
    @State private var isSyncing = false

    init(meeting: Meeting? = nil) {
        self.meeting = meeting
    }

    private var todos: [TodoItem] {
        allTodos.filter { todo in
            guard let meeting else { return true }
            return todo.meeting?.id == meeting.id
        }
    }

    private var selectedTodos: [TodoItem] {
        todos.filter { todo in
            guard let date = todo.dueDate else { return false }
            return Calendar.current.isDate(date, inSameDayAs: selectedDate)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                monthHeader
                monthGrid
                selectedDayList
                privacyNote
            }
            .padding(18)
        }
        .navigationTitle("カレンダー")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            MFPrimaryButton(title: isSyncing ? "登録中…" : "未完了ToDoをカレンダーへ登録", icon: "calendar.badge.plus", disabled: isSyncing) {
                Task { await syncAll() }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .alert("完了", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(confirmation ?? "") }
        .alert("登録できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .mfScreenBackground()
    }

    private var monthHeader: some View {
        HStack {
            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(selectedDate.formatted(.dateTime.year().month(.wide))).font(.headline)
            Spacer()
            Button("今日") { selectedDate = .now }.font(.caption.weight(.semibold))
            Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
        }
        .mfCard()
    }

    private var monthGrid: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { weekday in
                    Text(weekday).font(.caption2.weight(.semibold)).foregroundStyle(MFColor.secondaryText)
                }
                ForEach(Array(monthDates.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button { selectedDate = date } label: {
                            VStack(spacing: 4) {
                                Text(date.formatted(.dateTime.day()))
                                    .font(.subheadline.weight(Calendar.current.isDateInToday(date) ? .bold : .medium))
                                    .frame(width: 34, height: 34)
                                    .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? .white : MFColor.text)
                                    .background(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? MFColor.primary : Color.clear)
                                    .clipShape(Circle())
                                HStack(spacing: 2) {
                                    ForEach(priorityDots(for: date), id: \.rawValue) { priority in
                                        Circle().fill(color(for: priority)).frame(width: 5, height: 5)
                                    }
                                }
                                .frame(height: 6)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(calendarAccessibilityLabel(date))
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
            HStack(spacing: 14) {
                legend("高", .high)
                legend("中", .medium)
                legend("低", .low)
                Spacer()
            }
        }
        .mfCard(padding: 12)
    }

    private var selectedDayList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.headline)
            if selectedTodos.isEmpty {
                Text("この日の予定はありません。ToDoで期限を設定してください。")
                    .font(.subheadline)
                    .foregroundStyle(MFColor.secondaryText)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(selectedTodos) { todo in
                    HStack(alignment: .top, spacing: 12) {
                        Text(todo.dueDate?.formatted(date: .omitted, time: .shortened) ?? "--:--")
                            .font(.subheadline.weight(.semibold)).frame(width: 50, alignment: .leading)
                        Rectangle().fill(color(for: todo.priority)).frame(width: 3, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(todo.title).font(.subheadline.weight(.semibold))
                            Text(todo.assignee.isEmpty ? "担当者未設定" : todo.assignee).font(.caption).foregroundStyle(MFColor.secondaryText)
                        }
                        Spacer()
                        Button { Task { await add(todo) } } label: { Image(systemName: "calendar.badge.plus") }
                            .accessibilityLabel("このToDoをカレンダーに追加")
                    }
                    if todo.id != selectedTodos.last?.id { Divider() }
                }
            }
        }
        .mfCard()
    }

    private var monthDates: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: selectedDate),
              let days = calendar.range(of: .day, in: .month, for: selectedDate) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let mondayOffset = (weekday + 5) % 7
        var result = Array<Date?>(repeating: nil, count: mondayOffset)
        result.append(contentsOf: days.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: interval.start)
        })
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private func priorityDots(for date: Date) -> [TodoPriority] {
        let values = todos.filter { todo in
            guard let due = todo.dueDate, !todo.isCompleted else { return false }
            return Calendar.current.isDate(due, inSameDayAs: date)
        }.map(\.priority)
        return TodoPriority.allCases.filter(values.contains)
    }

    private func color(for priority: TodoPriority) -> Color {
        switch priority { case .high: MFColor.danger; case .medium: MFColor.warning; case .low: MFColor.mint }
    }

    private func legend(_ title: String, _ priority: TodoPriority) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color(for: priority)).frame(width: 7, height: 7)
            Text(title).font(.caption2).foregroundStyle(MFColor.secondaryText)
        }
    }

    private func moveMonth(_ value: Int) {
        let start = Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        selectedDate = Calendar.current.date(byAdding: .month, value: value, to: start) ?? selectedDate
    }

    private func calendarAccessibilityLabel(_ date: Date) -> String {
        let priorities = priorityDots(for: date).map(\.title).joined(separator: "、")
        return date.formatted(date: .long, time: .omitted) + (priorities.isEmpty ? "" : "、優先度\(priorities)のToDoあり")
    }

    private var privacyNote: some View {
        Label("登録時にのみiOSカレンダーへアクセスします。MeetingFlow AIから外部サーバーへ予定を送信することはありません。", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(MFColor.secondaryText)
            .mfCard()
    }

    @MainActor
    private func add(_ todo: TodoItem) async {
        guard let date = todo.dueDate else { errorMessage = "期限が設定されていません。"; return }
        do {
            _ = try await EventKitCalendarService().add(title: todo.title, date: date, notes: "MeetingFlow AI\n担当：\(todo.assignee)")
            confirmation = "「\(todo.title)」を追加しました。"
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func syncAll() async {
        let targets = todos.filter { !$0.isCompleted && $0.dueDate != nil }
        guard !targets.isEmpty else { errorMessage = "期限付きの未完了ToDoがありません。"; return }
        isSyncing = true
        defer { isSyncing = false }
        var count = 0
        do {
            for todo in targets {
                guard let date = todo.dueDate else { continue }
                _ = try await EventKitCalendarService().add(title: todo.title, date: date, notes: "MeetingFlow AI\n担当：\(todo.assignee)")
                count += 1
            }
            confirmation = "\(count)件をiOSカレンダーへ登録しました。"
        } catch { errorMessage = error.localizedDescription }
    }
}
