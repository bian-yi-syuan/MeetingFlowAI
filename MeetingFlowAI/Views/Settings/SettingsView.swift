import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recorder: AudioRecordingService
    @EnvironmentObject private var recordingDraft: RecordingDraftViewModel
    @Query private var meetings: [Meeting]
    @Query private var todos: [TodoItem]
    @AppStorage("onDeviceTranscription") private var onDeviceTranscription = true
    @AppStorage("keepAudio") private var keepAudio = true
    @State private var showDeleteConfirmation = false
    @State private var confirmation: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 13) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 45)).foregroundStyle(MFColor.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ゲストユーザー").font(.headline)
                        Text("Local-first モード").font(.caption).foregroundStyle(MFColor.secondaryText)
                        StatusPill(text: "無料MVP")
                    }
                }
                .padding(.vertical, 5)
            }

            Section("AI・録音") {
                Toggle(isOn: $onDeviceTranscription) {
                    SettingsLabel(icon: "captions.bubble", title: "リアルタイム字幕", color: MFColor.primary)
                }
                Toggle(isOn: $keepAudio) {
                    SettingsLabel(icon: "externaldrive", title: "録音を保存", color: MFColor.mint)
                }
            }

            Section("データ") {
                LabeledContent("保存中の会議", value: "\(meetings.count)件")
                LabeledContent("保存中のToDo", value: "\(todos.count)件")
                ShareLink(item: ReportBuilder.backupJSON(meetings: meetings)) {
                    SettingsLabel(icon: "square.and.arrow.up", title: "バックアップを書き出す", color: MFColor.primary)
                }
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    SettingsLabel(icon: "trash", title: "すべてのローカルデータを削除", color: MFColor.danger)
                }
            }

            Section("プライバシーとサポート") {
                NavigationLink(destination: PrivacyPolicyView()) {
                    SettingsLabel(icon: "hand.raised", title: "プライバシーポリシー", color: MFColor.accent)
                }
                NavigationLink(destination: SecurityGuideView()) {
                    SettingsLabel(icon: "lock.shield", title: "セキュリティガイド", color: MFColor.mint)
                }
                NavigationLink(destination: AboutView()) {
                    SettingsLabel(icon: "info.circle", title: "MeetingFlow AIについて", color: MFColor.primary)
                }
            }

            Section {
                Text("Version 1.0.0")
                    .font(.caption).foregroundStyle(MFColor.secondaryText).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("設定")
        .alert("すべて削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("完全に削除", role: .destructive, action: deleteAll)
            Button("キャンセル", role: .cancel) {}
        } message: { Text("会議、録音、文字起こし、要約、ToDoを端末から削除します。この操作は取り消せません。") }
        .alert("完了", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(confirmation ?? "") }
        .alert("削除できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func deleteAll() {
        do {
            recorder.cancel()
            recordingDraft.reset()
            TodoNotificationService().cancelAll()
            try LocalAudioFileService().deleteAllAudio()
            try modelContext.delete(model: Meeting.self)
            try modelContext.delete(model: TranscriptSegment.self)
            try modelContext.delete(model: Speaker.self)
            try modelContext.delete(model: TodoItem.self)
            try modelContext.delete(model: Participant.self)
            try modelContext.save()
            NotificationCenter.default.post(name: .meetingFlowLocalDataDidReset, object: nil)
            confirmation = "端末内データを削除しました。"
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct SettingsLabel: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        Label {
            Text(title).foregroundStyle(MFColor.text)
        } icon: {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
        }
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("保存場所") {
                Text("会議音声、文字起こし、要約、ToDoはアプリのサンドボックス内に保存します。音声ファイルにはiOSのData Protectionを設定します。")
            }
            Section("外部送信") {
                Text("独自AI APIは使用しません。オンライン字幕はAppleのSpeech機能を使用し、オフライン時は対応端末で端末内認識へ切り替えます。共有とカレンダー登録は、利用者が操作した時だけ実行します。")
            }
            Section("利用者の管理") {
                Text("設定からすべてのデータを削除できます。録音前に参加者へ目的を説明し、同意を得てください。")
            }
        }
        .navigationTitle("プライバシー")
    }
}

private struct SecurityGuideView: View {
    var body: some View {
        List {
            Section("現在の安全設計") {
                Label("Local-first：独自サーバーへの自動送信なし", systemImage: "iphone.gen3")
                Label("音声ファイルの完全保護", systemImage: "lock.doc")
                Label("ファイル名の検証", systemImage: "checkmark.shield")
                Label("共有前の機密情報確認", systemImage: "eye")
            }
        }
        .navigationTitle("セキュリティガイド")
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.and.mic").font(.system(size: 58)).foregroundStyle(MFColor.primary)
            Text("MeetingFlow AI").font(.title.bold())
            Text("Record Once. AI Handles The Rest.").font(.subheadline).foregroundStyle(MFColor.secondaryText)
            Text("日本のビジネスシーン向けに、会議後の整理を一つの流れで支援するLocal-first iOSアプリです。")
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            Spacer()
        }
        .padding(.top, 50)
        .navigationTitle("このアプリについて")
    }
}
