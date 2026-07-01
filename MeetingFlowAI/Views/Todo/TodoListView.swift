import SwiftUI
import SwiftData

private enum TodoFilter: String, CaseIterable {
    case open = "未完了"
    case done = "完了済み"
    case all = "すべて"
}

private struct TodoMeetingGroup: Identifiable {
    let id: String
    let title: String
    let date: Date?
    let todos: [TodoItem]
}

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allTodos: [TodoItem]
    @StateObject private var viewModel = MeetingWorkflowViewModel()
    var meeting: Meeting?
    @State private var filter: TodoFilter = .open
    @State private var editingTodo: TodoItem?
    @State private var showNewTodo = false
    @State private var confirmation: String?
    @State private var errorMessage: String?
    @State private var actionTodo: TodoItem?
    @State private var showTodoActions = false

    init(meeting: Meeting? = nil) {
        self.meeting = meeting
    }

    private var scopedTodos: [TodoItem] {
        allTodos.filter { todo in
            guard let meeting else { return true }
            return todo.meeting?.id == meeting.id
        }
    }

    private var displayedTodos: [TodoItem] {
        scopedTodos.filter { todo in
            switch filter { case .open: !todo.isCompleted; case .done: todo.isCompleted; case .all: true }
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var groupedTodos: [TodoMeetingGroup] {
        Dictionary(grouping: displayedTodos) { todo in
            todo.meeting?.id.uuidString ?? "unassigned"
        }
        .map { id, todos in
            let relatedMeeting = todos.first?.meeting
            return TodoMeetingGroup(
                id: id,
                title: relatedMeeting?.title ?? "会議未設定",
                date: relatedMeeting?.startedAt,
                todos: todos
            )
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $filter) {
                ForEach(TodoFilter.allCases, id: \.self) { item in
                    Text("\(item.rawValue) \(count(for: item))").tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(18)

            if displayedTodos.isEmpty {
                Spacer()
                EmptyStateView(icon: "checkmark.square", title: "ToDoはありません", message: emptyMessage)
                    .padding(.horizontal, 18)
                Spacer()
            } else {
                List {
                    ForEach(groupedTodos) { group in
                        Section {
                            ForEach(group.todos) { todo in
                                TodoRow(todo: todo) {
                                    actionTodo = todo
                                    showTodoActions = true
                                } onEdit: {
                                    editingTodo = todo
                                } onCalendar: {
                                    addToCalendar(todo)
                                }
                                .listRowBackground(Color.white)
                                .swipeActions(edge: .trailing) {
                                    Button { actionTodo = todo; showTodoActions = true } label: { Label("操作", systemImage: "ellipsis.circle") }
                                        .tint(MFColor.primary)
                                }
                            }
                        } header: {
                            TodoMeetingSectionHeader(title: group.title, date: group.date)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(meeting == nil ? "ToDo" : "会議のToDo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if meeting != nil {
                    Button { extractTodos() } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("文字起こしからToDoを抽出")
                }
                Button { showNewTodo = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("ToDoを追加")
            }
        }
        .sheet(item: $editingTodo) { todo in TodoEditorSheet(todo: todo, meeting: meeting) }
        .sheet(isPresented: $showNewTodo) { TodoEditorSheet(todo: nil, meeting: meeting) }
        .confirmationDialog(
            actionTodo?.title ?? "ToDoの操作",
            isPresented: $showTodoActions,
            titleVisibility: .visible
        ) {
            if let todo = actionTodo {
                Button(todo.isCompleted ? "未完了に戻す" : "完了にする") { changeCompletion(todo) }
                Button("編集") { editingTodo = todo }
                Button("削除", role: .destructive) { deleteTodo(todo) }
                Button("キャンセル", role: .cancel) {}
            }
        } message: {
            Text(actionTodo?.isCompleted == true ? "このToDoを未完了へ戻すか、編集・削除できます。" : "完了へ移動する前に確認してください。")
        }
        .alert("完了", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(confirmation ?? "") }
        .alert("操作できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .mfScreenBackground()
    }

    private var emptyMessage: String {
        if filter == .done { return "完了したタスクはまだありません。" }
        return meeting == nil ? "会議から抽出するか、＋ボタンで追加できます。" : "右上のキラキラボタンで文字起こしから抽出できます。"
    }

    private func count(for filter: TodoFilter) -> Int {
        switch filter { case .open: scopedTodos.filter { !$0.isCompleted }.count; case .done: scopedTodos.filter(\.isCompleted).count; case .all: scopedTodos.count }
    }

    private func extractTodos() {
        guard let meeting else { return }
        let drafts = viewModel.todoDrafts(for: meeting)
        let existingSources = Set(meeting.todos.map(\.sourceText))
        let newDrafts = drafts.filter { !existingSources.contains($0.sourceText) }
        for draft in newDrafts {
            let todo = TodoItem(
                title: draft.title,
                assignee: draft.assignee,
                dueDate: draft.dueDate,
                sourceText: draft.sourceText,
                meeting: meeting
            )
            modelContext.insert(todo)
            if todo.dueDate != nil { Task { try? await TodoNotificationService().schedule(for: todo) } }
        }
        save()
        confirmation = newDrafts.isEmpty ? "新しく抽出できるToDoはありませんでした。" : "\(newDrafts.count)件のToDoを端末内で抽出しました。"
    }

    private func addToCalendar(_ todo: TodoItem) {
        guard let date = todo.dueDate else {
            editingTodo = todo
            errorMessage = "先に期限を設定してください。"
            return
        }
        Task {
            do {
                _ = try await EventKitCalendarService().add(title: todo.title, date: date, notes: "MeetingFlow AIから追加\n担当：\(todo.assignee)")
                confirmation = "カレンダーに追加しました。"
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() { try? modelContext.save() }

    private func changeCompletion(_ todo: TodoItem) {
        todo.isCompleted.toggle()
        save()
        if todo.isCompleted {
            TodoNotificationService().cancel(todoID: todo.id)
        } else {
            Task { try? await TodoNotificationService().schedule(for: todo) }
        }
        actionTodo = nil
    }

    private func deleteTodo(_ todo: TodoItem) {
        TodoNotificationService().cancel(todoID: todo.id)
        modelContext.delete(todo)
        save()
        actionTodo = nil
    }
}

private struct TodoMeetingSectionHeader: View {
    let title: String
    let date: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MFColor.primary)
                .frame(width: 28, height: 28)
                .background(MFColor.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MFColor.text)
                    .lineLimit(1)
                if let date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(MFColor.secondaryText)
                }
            }
        }
        .padding(.top, 8)
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

private struct TodoRow: View {
    @Bindable var todo: TodoItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onCalendar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isCompleted ? MFColor.mint : MFColor.secondaryText.opacity(0.45))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
                Text(todo.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(todo.isCompleted)
                    .foregroundStyle(todo.isCompleted ? MFColor.secondaryText : MFColor.text)
                HStack(spacing: 8) {
                    if !todo.assignee.isEmpty { Label(todo.assignee, systemImage: "person").lineLimit(1) }
                    if let date = todo.dueDate { Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar") }
                }
                .font(.caption2)
                .foregroundStyle(isOverdue ? MFColor.danger : MFColor.secondaryText)
            }
            Spacer()
            Menu {
                Button("編集", systemImage: "pencil", action: onEdit)
                Button("カレンダーに追加", systemImage: "calendar.badge.plus", action: onCalendar)
            } label: {
                StatusPill(text: todo.priority.title, color: priorityColor)
            }
        }
        .padding(.vertical, 6)
    }

    private var isOverdue: Bool { todo.dueDate.map { $0 < Calendar.current.startOfDay(for: .now) && !todo.isCompleted } ?? false }
    private var priorityColor: Color { switch todo.priority { case .high: MFColor.danger; case .medium: MFColor.warning; case .low: MFColor.mint } }
}

struct TodoEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    let todo: TodoItem?
    let meeting: Meeting?
    @State private var title: String
    @State private var assignee: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: TodoPriority
    @State private var selectedMeetingID: UUID?

    init(todo: TodoItem?, meeting: Meeting?) {
        self.todo = todo
        self.meeting = meeting
        _title = State(initialValue: todo?.title ?? "")
        _assignee = State(initialValue: todo?.assignee ?? "")
        _hasDueDate = State(initialValue: todo?.dueDate != nil)
        _dueDate = State(initialValue: todo?.dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        _priority = State(initialValue: todo?.priority ?? .medium)
        _selectedMeetingID = State(initialValue: meeting?.id ?? todo?.meeting?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("関連する会議") {
                    if let meeting {
                        LabeledContent("会議", value: meeting.title)
                        Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(MFColor.secondaryText)
                    } else if meetings.isEmpty {
                        Label("先に会議を1件作成してください。", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(MFColor.secondaryText)
                    } else {
                        Picker("会議を選択", selection: $selectedMeetingID) {
                            Text("選択してください").tag(Optional<UUID>.none)
                            ForEach(meetings) { item in
                                Text("\(item.title) ・ \(item.startedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .tag(Optional(item.id))
                            }
                        }
                        .pickerStyle(.menu)
                        if let selectedMeeting {
                            Label(
                                selectedMeeting.startedAt.formatted(date: .long, time: .shortened),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(MFColor.primary)
                        }
                    }
                }
                Section("タスク") {
                    TextField("例：見積書を確認", text: $title)
                    TextField("担当者", text: $assignee)
                }
                Section("期限") {
                    Toggle("期限を設定", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("日時", selection: $dueDate) }
                }
                Section("優先度") {
                    Picker("優先度", selection: $priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(todo == nil ? "ToDoを追加" : "ToDoを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let targetMeeting = meeting ?? selectedMeeting else { return }
        let savedTodo: TodoItem
        if let todo {
            todo.title = title; todo.assignee = assignee; todo.dueDate = hasDueDate ? dueDate : nil; todo.priority = priority
            todo.meeting = targetMeeting
            savedTodo = todo
        } else {
            let newTodo = TodoItem(title: title, assignee: assignee, dueDate: hasDueDate ? dueDate : nil, priority: priority, meeting: targetMeeting)
            modelContext.insert(newTodo)
            savedTodo = newTodo
        }
        try? modelContext.save()
        if savedTodo.dueDate != nil {
            Task { try? await TodoNotificationService().schedule(for: savedTodo) }
        } else {
            TodoNotificationService().cancel(todoID: savedTodo.id)
        }
        dismiss()
    }

    private var selectedMeeting: Meeting? {
        meetings.first { $0.id == selectedMeetingID }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (meeting != nil || selectedMeeting != nil)
    }
}
