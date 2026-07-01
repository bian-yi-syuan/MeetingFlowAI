import SwiftUI
import SwiftData

struct MeetingDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting
    @StateObject private var player = AudioPlaybackService()
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showParticipantEditor = false
    @State private var showRecordingShare = false
    @State private var showRecordingExport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overviewCard
                if meeting.audioFileName != nil { playbackCard }
                workflowGrid
                progressCard
                exportCard
            }
            .padding(18)
        }
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: ReportBuilder.text(for: meeting)) { Label("レポートを共有", systemImage: "square.and.arrow.up") }
                    Button("会議を削除", systemImage: "trash", role: .destructive) { showDeleteConfirmation = true }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .mfScreenBackground()
        .alert("この会議を削除しますか？", isPresented: $showDeleteConfirmation) {
            Button("削除", role: .destructive) { deleteMeeting() }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("録音・文字起こし・要約・ToDoを端末から削除します。この操作は取り消せません。") }
        .alert("操作できませんでした", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "不明なエラー") }
        .onDisappear { player.pause() }
        .sheet(isPresented: $showParticipantEditor) {
            ParticipantEditorView(meeting: meeting)
        }
        .sheet(isPresented: $showRecordingShare) {
            if let recordingURL { ActivityShareSheet(items: [recordingURL]) }
        }
        .sheet(isPresented: $showRecordingExport) {
            if let recordingURL { DocumentExportSheet(fileURL: recordingURL) }
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(meeting.startedAt.formatted(date: .long, time: .shortened), systemImage: "calendar")
                Spacer()
                StatusPill(text: meeting.status.title)
            }
            .font(.subheadline)
            HStack(alignment: .top) {
                Label(meeting.participants.isEmpty ? "参加者未設定" : meeting.participants.joined(separator: "、"), systemImage: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(MFColor.secondaryText)
                Spacer()
                Button("編集") { showParticipantEditor = true }
                    .font(.caption.weight(.semibold))
            }
        }
        .mfCard()
    }

    private var playbackCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("録音ファイル").font(.headline)
                    Label("端末内に保存済み", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(MFColor.mint)
                }
                Spacer()
                Text(ReportBuilder.formatDuration(meeting.duration)).font(.caption).foregroundStyle(MFColor.secondaryText)
            }
            Slider(value: Binding(get: { player.progress }, set: { player.seek(to: $0) }), in: 0...1)
            Button {
                do {
                    if let fileName = meeting.audioFileName { try player.toggle(fileName: fileName) }
                } catch { errorMessage = error.localizedDescription }
            } label: {
                Label(player.isPlaying ? "一時停止" : "録音を再生", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)

            Divider()
            HStack(spacing: 8) {
                recordingAction(title: "共有", icon: "square.and.arrow.up") {
                    guard recordingURL != nil else { return showMissingRecordingError() }
                    showRecordingShare = true
                }
                NavigationLink(destination: EmailDraftView(meeting: meeting, attachmentURL: recordingURL)) {
                    recordingActionLabel(title: "メール", icon: "envelope")
                }
                recordingAction(title: "ファイル保存", icon: "folder.badge.plus") {
                    guard recordingURL != nil else { return showMissingRecordingError() }
                    showRecordingExport = true
                }
            }
        }
        .mfCard()
    }

    private func recordingAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            recordingActionLabel(title: title, icon: icon)
        }
        .buttonStyle(.plain)
    }

    private func recordingActionLabel(title: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.headline)
            Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(MFColor.primary)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(MFColor.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }

    private var workflowGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("会議ワークフロー").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink(destination: TranscriptView(meeting: meeting)) {
                    WorkflowTile(icon: "text.quote", title: "文字起こし", subtitle: "\(meeting.transcript.count) セグメント", color: MFColor.primary)
                }
                NavigationLink(destination: SummaryView(meeting: meeting)) {
                    WorkflowTile(icon: "sparkles", title: "AI 要約", subtitle: meeting.hasSummary ? "作成済み" : "未作成", color: MFColor.accent)
                }
                NavigationLink(destination: TodoListView(meeting: meeting)) {
                    WorkflowTile(icon: "checkmark.square", title: "ToDo", subtitle: "\(meeting.todos.filter { !$0.isCompleted }.count) 件未完了", color: MFColor.mint)
                }
                NavigationLink(destination: CalendarIntegrationView(meeting: meeting)) {
                    WorkflowTile(icon: "calendar", title: "カレンダー", subtitle: "予定を登録", color: MFColor.danger)
                }
                NavigationLink(destination: EmailDraftView(meeting: meeting)) {
                    WorkflowTile(icon: "envelope", title: "メール草稿", subtitle: meeting.emailBody.isEmpty ? "未作成" : "編集できます", color: MFColor.warning)
                }
                ShareLink(item: ReportBuilder.text(for: meeting)) {
                    WorkflowTile(icon: "square.and.arrow.up", title: "レポート共有", subtitle: "共有前に確認", color: MFColor.primaryDark)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("整理の進捗").font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.headline)
                    .foregroundStyle(MFColor.primary)
            }
            ProgressView(value: progress).tint(MFColor.primary)
            Text("文字起こし・要約・ToDo・メール草稿がそろうと完了です。")
                .font(.caption)
                .foregroundStyle(MFColor.secondaryText)
        }
        .mfCard()
    }

    private var exportCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(MFColor.warning)
            Text("共有する前に、社外秘情報・個人情報・宛先を必ず確認してください。")
                .font(.caption)
                .foregroundStyle(MFColor.secondaryText)
        }
        .mfCard()
    }

    private var progress: Double {
        let values = [!meeting.transcript.isEmpty, meeting.hasSummary, !meeting.todos.isEmpty, !meeting.emailBody.isEmpty]
        return Double(values.filter { $0 }.count) / Double(values.count)
    }

    private var recordingURL: URL? {
        guard let fileName = meeting.audioFileName else { return nil }
        return try? LocalAudioFileService().url(for: fileName)
    }

    private func showMissingRecordingError() {
        errorMessage = "録音ファイルが見つかりません。"
    }

    private func deleteMeeting() {
        meeting.todos.forEach { TodoNotificationService().cancel(todoID: $0.id) }
        if let fileName = meeting.audioFileName { try? LocalAudioFileService().delete(fileName: fileName) }
        modelContext.delete(meeting)
        try? modelContext.save()
    }
}

private struct WorkflowTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(MFColor.text)
            Text(subtitle).font(.caption).foregroundStyle(MFColor.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mfCard(padding: 13)
    }
}
