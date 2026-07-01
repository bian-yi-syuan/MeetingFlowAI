import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case home, meetings, record, todos, settings
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selection: AppTab = .home
    @Published var selectedMeeting: Meeting?

    func openMeetingFromHome(_ meeting: Meeting) {
        selectedMeeting = meeting
        selection = .meetings
    }

    func resetNavigation() {
        selectedMeeting = nil
    }
}

extension Notification.Name {
    static let meetingFlowLocalDataDidReset = Notification.Name("meetingFlowLocalDataDidReset")
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var meetings: [Meeting]
    @StateObject private var router = AppRouter()

    var body: some View {
        TabView(selection: $router.selection) {
            NavigationStack { HomeView() }
                .tabItem { Label("ホーム", systemImage: "house") }
                .tag(AppTab.home)

            NavigationStack {
                MeetingListView()
                    .navigationDestination(isPresented: Binding(
                        get: { router.selectedMeeting != nil },
                        set: { if !$0 { router.selectedMeeting = nil } }
                    )) {
                        if let meeting = router.selectedMeeting {
                            MeetingDetailView(meeting: meeting)
                        }
                    }
            }
                .tabItem { Label("会議一覧", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.meetings)

            NavigationStack { RecordingView() }
                .tabItem { Label("録音", systemImage: "mic.circle.fill") }
                .tag(AppTab.record)

            NavigationStack { TodoListView() }
                .tabItem { Label("ToDo", systemImage: "checkmark.square") }
                .tag(AppTab.todos)

            NavigationStack { SettingsView() }
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .environmentObject(router)
        .task {
            removeLegacyDemoMeetingsOnce()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingFlowLocalDataDidReset)) { _ in
            router.resetNavigation()
        }
    }

    private func removeLegacyDemoMeetingsOnce() {
        let key = "didRemoveBundledDemoMeetingsV2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let demoTitles = Set(["プロジェクト定例ミーティング", "新商品企画レビュー"])
        meetings.filter { demoTitles.contains($0.title) && $0.audioFileName == nil }.forEach(modelContext.delete)
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
