import SwiftUI
import SwiftData
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

@main
struct MeetingFlowAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recorder = AudioRecordingService()
    @StateObject private var recordingDraft = RecordingDraftViewModel()
    @StateObject private var networkMonitor = NetworkMonitorService()
    @AppStorage("hasCompletedOnboardingV1") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            hasCompletedOnboarding = true
                        }
                    }
                }
            }
                .environmentObject(recorder)
                .environmentObject(recordingDraft)
                .environmentObject(networkMonitor)
                .tint(MFColor.primary)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [Meeting.self, TranscriptSegment.self, Speaker.self, TodoItem.self, Participant.self])
    }
}
