import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject private var recorder: AudioRecordingService
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @Query private var todos: [TodoItem]

    private var openTodos: [TodoItem] { todos.filter { !$0.isCompleted } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                greeting
                startCard
                overviewGrid
                recentMeetings
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .navigationBarHidden(true)
        .mfScreenBackground()
    }

    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image("MimiFlowLogo")
                    .resizable().scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                Text("MeetingFlow AI")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MFColor.primaryDark)
            }
            Spacer()
            NavigationLink(destination: NotificationCenterView()) {
                Image(systemName: "bell")
                    .font(.title3)
                    .foregroundStyle(MFColor.text)
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("お知らせ")
        }
        .padding(.top, 10)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("おはようございます 👋")
                .font(.subheadline)
                .foregroundStyle(MFColor.secondaryText)
            Text("今日も良い一日に\nしていきましょう。")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(MFColor.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startCard: some View {
        NavigationLink(destination: RecordingView()) {
            HStack(spacing: 17) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.18))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(recorder.state == .idle ? "新しい会議を開始" : "録音中の会議へ戻る")
                        .font(.title3.weight(.bold))
                    Text(recorder.state == .idle ? "録音から会議整理まで、ひとつの流れで" : "録音はバックグラウンドで継続中です")
                        .font(.subheadline)
                        .opacity(0.88)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(.white)
                    .foregroundStyle(MFColor.primary)
                    .clipShape(Circle())
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 98)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [Color(hex: "7664F4"), MFColor.primary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: MFColor.primary.opacity(0.22), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavigationLink(destination: MeetingListView()) {
                DashboardMetric(icon: "calendar.badge.clock", title: "会議一覧", value: "\(meetings.count) 件の会議", color: MFColor.primary)
            }
            NavigationLink(destination: AnalyticsView()) {
                DashboardMetric(icon: "chart.line.uptrend.xyaxis", title: "分析", value: "\(meetings.count) 件の会議を集計", color: MFColor.accent)
            }
            NavigationLink(destination: TodoListView()) {
                DashboardMetric(icon: "checklist", title: "ToDo", value: "\(openTodos.count) 件のタスク", color: MFColor.accent)
            }
            NavigationLink(destination: CalendarIntegrationView()) {
                DashboardMetric(icon: "calendar", title: "カレンダー", value: nearestTodoText, color: MFColor.danger)
            }
        }
        .buttonStyle(.plain)
    }

    private var recentMeetings: some View {
        VStack(spacing: 12) {
            MFSectionHeader(title: "最近の会議")
            if meetings.isEmpty {
                EmptyStateView(icon: "waveform", title: "会議はまだありません", message: "録音を開始すると、ここに会議が表示されます。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(meetings.prefix(4).enumerated()), id: \.element.id) { index, meeting in
                        Button {
                            router.openMeetingFromHome(meeting)
                        } label: {
                            MeetingRow(meeting: meeting)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if index < min(meetings.count, 4) - 1 { Divider().padding(.leading, 50) }
                    }
                }
                .padding(.horizontal, 14)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var nearestTodoText: String {
        guard let date = openTodos.compactMap(\.dueDate).min() else { return "予定を追加" }
        return "次の予定: \(date.formatted(.dateTime.month().day().hour().minute()))"
    }
}

private struct DashboardMetric: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(MFColor.text)
                Text(value).font(.caption2).foregroundStyle(MFColor.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .mfCard(padding: 13)
    }
}

private struct NotificationCenterView: View {
    @Query(sort: \TodoItem.dueDate) private var todos: [TodoItem]
    @State private var statusText = "確認中…"
    @State private var confirmation: String?
    @State private var errorMessage: String?

    private var upcoming: [TodoItem] {
        todos.filter { !$0.isCompleted && ($0.dueDate ?? .distantPast) > .now }.prefix(10).map { $0 }
    }

    var body: some View {
        List {
            Section("通知の状態") {
                LabeledContent("期限通知", value: statusText)
                Button("通知を有効にする", systemImage: "bell.badge") {
                    Task { await enableNotifications() }
                }
                Button("5秒後にテスト通知", systemImage: "speaker.wave.2") {
                    Task { await testNotification() }
                }
            }
            Section("期限の近いToDo") {
                if upcoming.isEmpty {
                    Text("通知予定のToDoはありません。")
                        .foregroundStyle(MFColor.secondaryText)
                } else {
                    ForEach(upcoming) { todo in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(todo.title).font(.subheadline.weight(.semibold))
                            Text(todo.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                .font(.caption).foregroundStyle(MFColor.secondaryText)
                        }
                    }
                }
            }
            Section {
                Label("ToDoの期限を保存すると、許可済みの場合は通知音付きで予約されます。", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(MFColor.secondaryText)
            }
        }
        .navigationTitle("お知らせ")
        .task { await refreshStatus() }
        .alert("完了", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(confirmation ?? "") }
        .alert("通知を設定できません", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor private func refreshStatus() async {
        let status = await TodoNotificationService().authorizationStatus()
        statusText = switch status {
        case .authorized, .provisional, .ephemeral: "有効"
        case .denied: "無効"
        case .notDetermined: "未設定"
        @unknown default: "不明"
        }
    }

    @MainActor private func enableNotifications() async {
        do {
            _ = try await TodoNotificationService().requestAuthorization()
            for todo in upcoming { try? await TodoNotificationService().schedule(for: todo) }
            await refreshStatus()
            confirmation = "通知を有効にしました。"
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func testNotification() async {
        do {
            try await TodoNotificationService().scheduleTest()
            await refreshStatus()
            confirmation = "5秒後に通知音付きのバナーを表示します。"
        } catch { errorMessage = error.localizedDescription }
    }
}
