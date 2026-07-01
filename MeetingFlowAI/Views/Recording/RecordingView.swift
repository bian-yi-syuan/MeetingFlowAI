import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var recorder: AudioRecordingService
    @EnvironmentObject private var draft: RecordingDraftViewModel
    @EnvironmentObject private var networkMonitor: NetworkMonitorService
    @State private var completedMeeting: Meeting?
    @State private var showCompleted = false
    @State private var showCancelConfirmation = false
    @State private var errorMessage: String?
    @State private var editingRecordingTodo: TodoItem?
    @State private var deletingRecordingTodo: TodoItem?
    @AppStorage("onDeviceTranscription") private var onDeviceTranscription = true
    @AppStorage("keepAudio") private var keepAudio = true
    @AppStorage("subtitleLanguage") private var subtitleLanguageRaw = SubtitleLanguage.japanese.rawValue
    @AppStorage("subtitleRecognitionMode") private var subtitleRecognitionModeRaw = SubtitleRecognitionMode.real.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusHeader
                elapsedTime
                WaveformView(level: recorder.level, isActive: recorder.state == .recording)
                    .frame(height: 72)
                meetingFields
                privacyCard
                controls
                liveTranscriptCard
                if recorder.state != .idle { recordingTodoSection }
            }
            .padding(20)
        }
        .navigationTitle(recorder.state == .idle ? "新しい会議" : "録音中")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if recorder.state != .idle {
                    Button("キャンセル", role: .destructive) { showCancelConfirmation = true }
                }
            }
        }
        .mfScreenBackground()
        .alert("録音を破棄しますか？", isPresented: $showCancelConfirmation) {
            Button("破棄", role: .destructive) { cancelRecording() }
            Button("続ける", role: .cancel) {}
        } message: { Text("録音中の音声は端末から削除されます。") }
        .alert("操作できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "不明なエラー") }
        .alert("ToDoを削除しますか？", isPresented: Binding(
            get: { deletingRecordingTodo != nil },
            set: { if !$0 { deletingRecordingTodo = nil } }
        )) {
            Button("削除", role: .destructive) { deleteRecordingTodo() }
            Button("キャンセル", role: .cancel) { deletingRecordingTodo = nil }
        } message: {
            Text("「\(deletingRecordingTodo?.title ?? "")」を削除します。この操作は取り消せません。")
        }
        .sheet(item: $editingRecordingTodo) { todo in
            TodoEditorSheet(todo: todo, meeting: draft.currentMeeting)
        }
        .navigationDestination(isPresented: $showCompleted) {
            if let completedMeeting { MeetingDetailView(meeting: completedMeeting) }
        }
        .onChange(of: recorder.liveTranscript) { _, text in updateLiveTranscript(text) }
        .onChange(of: draft.participants) { _, _ in updateActiveMeetingDetails() }
        .onChange(of: draft.title) { _, _ in updateActiveMeetingDetails() }
        .onChange(of: subtitleLanguageRaw) { _, _ in restartLiveRecognitionIfNeeded() }
        .onChange(of: subtitleRecognitionModeRaw) { _, _ in restartLiveRecognitionIfNeeded() }
        .onChange(of: networkMonitor.isConnected) { _, _ in restartLiveRecognitionIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .meetingFlowLocalDataDidReset)) { _ in
            recorder.cancel()
            draft.reset()
            completedMeeting = nil
            showCompleted = false
            editingRecordingTodo = nil
            deletingRecordingTodo = nil
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MFColor.secondaryText)
        }
    }

    private var elapsedTime: some View {
        Text(formatElapsed(recorder.elapsed))
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(MFColor.text)
            .contentTransition(.numericText())
    }

    private var meetingFields: some View {
        VStack(spacing: 14) {
            LabeledContent {
                TextField("例：プロジェクト定例", text: $draft.title)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("会議名", systemImage: "text.cursor")
            }
            Divider()
            LabeledContent {
                TextField("例：佐藤さん、田中さん", text: $draft.participants)
                    .multilineTextAlignment(.trailing)
            } label: {
                Label("参加者", systemImage: "person.2")
            }
        }
        .font(.subheadline)
        .mfCard()
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(MFColor.mint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("ローカル録音").font(.subheadline.weight(.semibold))
                Text("録音ファイルは端末内に保存します。字幕はオンライン時にApple音声認識、オフライン時は対応端末の端末内認識を使用します。")
                    .font(.caption)
                    .foregroundStyle(MFColor.secondaryText)
            }
        }
        .mfCard()
    }

    private var liveTranscriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI リアルタイム字幕", systemImage: "captions.bubble.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: networkMonitor.isConnected ? "wifi" : "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(networkMonitor.isConnected ? MFColor.mint : MFColor.secondaryText)
                    .accessibilityLabel(networkMonitor.isConnected ? "オンライン" : "オフライン")
                StatusPill(text: subtitleStatusText, color: subtitleStatusColor)
            }

            Picker("字幕言語", selection: $subtitleLanguageRaw) {
                ForEach(SubtitleLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .disabled(recorder.speechState == .requestingPermission)

            #if targetEnvironment(simulator)
            Picker("字幕モード", selection: $subtitleRecognitionModeRaw) {
                ForEach(SubtitleRecognitionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .disabled(recorder.speechState == .requestingPermission)
            #endif

            Text(subtitleMessage)
                .font(.subheadline)
                .foregroundStyle(recorder.liveTranscript.isEmpty ? MFColor.secondaryText : MFColor.text)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                .lineLimit(6)
                .animation(.easeOut(duration: 0.2), value: recorder.liveTranscript)

            #if DEBUG
            if recorder.state != .idle, !recorder.isUsingSimulatorMock {
                Label(
                    "\(recorder.speechDebugStatus) ・ buffer \(recorder.speechBufferCount) ・ result \(recorder.speechResultCount)",
                    systemImage: "waveform.badge.magnifyingglass"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(MFColor.secondaryText)
            }
            #endif
        }
        .mfCard()
    }

    private var recordingTodoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("会議中のToDo").font(.headline)
                Spacer()
                Text("追加するとToDoタブにも即時反映")
                    .font(.caption2).foregroundStyle(MFColor.secondaryText)
            }
            HStack(spacing: 10) {
                TextField("例：明日までに資料を共有", text: $draft.quickTodoTitle)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(MFColor.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .submitLabel(.done)
                    .onSubmit(addQuickTodo)
                Button(action: addQuickTodo) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(MFColor.primary)
                        .clipShape(Circle())
                }
                .disabled(draft.quickTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let meeting = draft.currentMeeting {
                let openTodos = meeting.sortedTodos.filter { !$0.isCompleted }
                if openTodos.isEmpty {
                    Text("まだToDoはありません。会議中に気づいた項目を追加できます。")
                        .font(.caption).foregroundStyle(MFColor.secondaryText)
                } else {
                    ForEach(openTodos) { todo in
                        HStack(spacing: 10) {
                            Circle().stroke(MFColor.primary.opacity(0.35), lineWidth: 1.5).frame(width: 18, height: 18)
                            Text(todo.title).font(.subheadline)
                            Spacer()
                            StatusPill(text: todo.priority.title, color: MFColor.warning)
                            Menu {
                                Button("編集", systemImage: "pencil") { editingRecordingTodo = todo }
                                Button("削除", systemImage: "trash", role: .destructive) { deletingRecordingTodo = todo }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundStyle(MFColor.primary)
                            }
                            .accessibilityLabel("\(todo.title)を編集または削除")
                        }
                        if todo.id != openTodos.last?.id { Divider() }
                    }
                }
            }
        }
        .mfCard()
    }

    private var controls: some View {
        Group {
            if recorder.state == .idle {
                MFPrimaryButton(title: "録音を開始", icon: "mic.fill") {
                    Task { await startRecording() }
                }
            } else {
                HStack(spacing: 28) {
                    circleControl(icon: "bookmark", label: "マーク") { draft.addMark(at: recorder.elapsed) }
                    circleControl(
                        icon: recorder.state == .paused ? "play.fill" : "pause.fill",
                        label: recorder.state == .paused ? "再開" : "一時停止",
                        prominent: true
                    ) { recorder.pauseOrResume() }
                    circleControl(icon: "stop.fill", label: "停止") { Task { await finishRecording() } }
                }
                if !draft.marks.isEmpty {
                    Text("重要マーク \(draft.marks.count) 件")
                        .font(.caption)
                        .foregroundStyle(MFColor.primary)
                }
            }
        }
    }

    private func circleControl(icon: String, label: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(prominent ? .white : MFColor.text)
                    .frame(width: 58, height: 58)
                    .background(prominent ? AnyShapeStyle(MFColor.primary) : AnyShapeStyle(.white))
                    .clipShape(Circle())
                    .overlay { if !prominent { Circle().stroke(MFColor.border) } }
                    .shadow(color: prominent ? MFColor.primary.opacity(0.25) : .clear, radius: 12, y: 5)
                Text(label).font(.caption).foregroundStyle(MFColor.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        switch recorder.state { case .idle: "録音準備完了"; case .recording: "録音中"; case .paused: "一時停止中" }
    }

    private var statusColor: Color {
        switch recorder.state { case .idle: MFColor.secondaryText; case .recording: MFColor.mint; case .paused: MFColor.warning }
    }

    private var selectedSubtitleLanguage: SubtitleLanguage {
        SubtitleLanguage(rawValue: subtitleLanguageRaw) ?? .japanese
    }

    private var selectedRecognitionMode: SubtitleRecognitionMode {
        SubtitleRecognitionMode(rawValue: subtitleRecognitionModeRaw) ?? .real
    }

    private var subtitleStatusText: String {
        guard onDeviceTranscription else { return "OFF" }
        if recorder.isUsingSimulatorMock { return "Simulator Mock" }
        switch recorder.speechState {
        case .idle: return "待機中"
        case .requestingPermission: return "準備中"
        case .ready: return recorder.state == .paused ? "一時停止" : "準備完了"
        case .recognizing:
            if recorder.speechResultCount > 0 { return "LIVE" }
            return recorder.speechBufferCount > 0 ? "応答待ち" : "音声待ち"
        case .unavailable: return "利用不可"
        case .permissionDenied: return "権限必要"
        case .error: return "エラー"
        }
    }

    private var subtitleStatusColor: Color {
        if recorder.isUsingSimulatorMock { return MFColor.accent }
        return switch recorder.speechState {
        case .recognizing: recorder.speechResultCount > 0 ? MFColor.danger : MFColor.warning
        case .ready: MFColor.mint
        case .permissionDenied, .error: MFColor.danger
        default: MFColor.secondaryText
        }
    }

    private var subtitleMessage: String {
        guard onDeviceTranscription else { return "設定でリアルタイム字幕がオフになっています。" }
        if !recorder.liveTranscript.isEmpty { return recorder.liveTranscript }
        switch recorder.speechState {
        case .idle:
            return "録音を開始すると字幕が表示されます。"
        case .requestingPermission:
            return "音声認識の準備をしています。"
        case .ready:
            return recorder.state == .paused ? "字幕を一時停止しています。再開すると認識を続けます。" : "録音を開始すると字幕が表示されます。"
        case .recognizing:
            if recorder.isUsingSimulatorMock { return "Simulator用のテスト字幕を生成しています。" }
            return recorder.speechBufferCount == 0
                ? "マイク音声を待っています..."
                : "音声入力を受信しました。Apple Speechの応答を待っています..."
        case .unavailable:
            return "オフライン字幕に対応していないため、現在利用できません。\nネットワーク接続後に再度お試しください。"
        case .permissionDenied:
            return "権限が必要です\nマイクと音声認識の使用を許可してください。"
        case .error:
            return recorder.speechErrorMessage ?? "音声認識でエラーが発生しました。"
        }
    }

    private func startRecording() async {
        do {
            try await recorder.start(
                liveTranscription: onDeviceTranscription,
                language: selectedSubtitleLanguage,
                networkConnected: networkMonitor.isConnected,
                recognitionMode: selectedRecognitionMode,
                recordingName: draft.title
            )
            let meeting = Meeting(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新しい会議" : draft.title,
                participantsText: draft.participants,
                status: .draft
            )
            modelContext.insert(meeting)
            ParticipantSyncService.syncNames(from: draft.participants, meeting: meeting, context: modelContext)
            if meeting.speakers.isEmpty {
                modelContext.insert(Speaker(name: "発言者 A", colorHex: "517CF6", meeting: meeting))
            }
            draft.currentMeeting = meeting
            try modelContext.save()
        }
        catch {
            recorder.cancel()
            if let meeting = draft.currentMeeting { modelContext.delete(meeting) }
            draft.reset()
            errorMessage = error.localizedDescription
        }
    }

    private func finishRecording() async {
        do {
            let language = selectedSubtitleLanguage
            let connected = networkMonitor.isConnected
            let usedSimulatorMock = recorder.isUsingSimulatorMock
            let fileName = try await recorder.stop()
            let duration = recorder.elapsed
            guard let meeting = draft.currentMeeting else { throw AudioServiceError.noRecording }
            meeting.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新しい会議" : draft.title
            meeting.duration = duration
            meeting.audioFileName = (keepAudio || onDeviceTranscription) ? fileName : nil
            meeting.status = onDeviceTranscription && !usedSimulatorMock ? .processing : .draft
            ParticipantSyncService.syncNames(from: draft.participants, meeting: meeting, context: modelContext)
            if !keepAudio && !onDeviceTranscription {
                try? LocalAudioFileService().delete(fileName: fileName)
            }
            for (index, time) in draft.marks.enumerated() {
                modelContext.insert(TranscriptSegment(
                    speakerName: "重要マーク",
                    speakerColorHex: "F3A52B",
                    text: "録音中に登録した重要ポイントです。文字起こし後に内容を追記してください。",
                    startTime: time,
                    endTime: time,
                    orderIndex: meeting.transcript.count + index,
                    isMarked: true,
                    meeting: meeting
                ))
            }
            try modelContext.save()
            completedMeeting = meeting
            showCompleted = true
            draft.reset()
            if onDeviceTranscription && !usedSimulatorMock {
                Task {
                    await transcribe(
                        meeting: meeting,
                        fileName: fileName,
                        language: language,
                        isConnected: connected
                    )
                }
            } else if usedSimulatorMock {
                meeting.status = .completed
                try? modelContext.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addQuickTodo() {
        let title = draft.quickTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let meeting = draft.currentMeeting else { return }
        modelContext.insert(TodoItem(title: title, priority: .medium, meeting: meeting))
        draft.quickTodoTitle = ""
        try? modelContext.save()
    }

    private func deleteRecordingTodo() {
        guard let todo = deletingRecordingTodo else { return }
        TodoNotificationService().cancel(todoID: todo.id)
        modelContext.delete(todo)
        try? modelContext.save()
        deletingRecordingTodo = nil
    }

    private func restartLiveRecognitionIfNeeded() {
        guard recorder.state == .recording, onDeviceTranscription else { return }
        Task {
            await recorder.restartLiveRecognition(
                language: selectedSubtitleLanguage,
                networkConnected: networkMonitor.isConnected,
                mode: selectedRecognitionMode
            )
        }
    }

    private func updateActiveMeetingDetails() {
        guard recorder.state != .idle, let meeting = draft.currentMeeting else { return }
        meeting.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新しい会議" : draft.title
        ParticipantSyncService.syncNames(from: draft.participants, meeting: meeting, context: modelContext)
        try? modelContext.save()
    }

    private func updateLiveTranscript(_ text: String) {
        guard recorder.state != .idle, !text.isEmpty, let meeting = draft.currentMeeting else { return }
        if let live = meeting.transcript.first(where: \.isLive) {
            live.text = text
            live.endTime = recorder.elapsed
        } else {
            let speaker = meeting.speakers.first
            modelContext.insert(TranscriptSegment(
                speakerName: speaker?.name ?? "発言者 A",
                speakerColorHex: speaker?.colorHex ?? "517CF6",
                text: text,
                startTime: 0,
                endTime: recorder.elapsed,
                orderIndex: 0,
                isLive: true,
                meeting: meeting
            ))
        }
        try? modelContext.save()
    }

    private func cancelRecording() {
        recorder.cancel()
        if let meeting = draft.currentMeeting { modelContext.delete(meeting) }
        try? modelContext.save()
        draft.reset()
    }

    private func formatElapsed(_ value: TimeInterval) -> String {
        let total = Int(value)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    @MainActor
    private func transcribe(
        meeting: Meeting,
        fileName: String,
        language: SubtitleLanguage,
        isConnected: Bool
    ) async {
        do {
            let url = try LocalAudioFileService().url(for: fileName)
            let recognized = try await AppleSpeechFileRecognitionService().transcribe(
                audioURL: url,
                language: language,
                isConnected: isConnected
            )
            let liveSegments = meeting.transcript.filter(\.isLive)
            liveSegments.forEach(modelContext.delete)
            let startIndex = meeting.transcript.filter { !$0.isLive }.map(\.orderIndex).max().map { $0 + 1 } ?? 0
            for (index, item) in recognized.enumerated() {
                modelContext.insert(TranscriptSegment(
                    speakerName: meeting.speakers.first?.name ?? "発言者 A",
                    speakerColorHex: meeting.speakers.first?.colorHex ?? "517CF6",
                    text: item.text,
                    startTime: item.startTime,
                    endTime: item.endTime,
                    orderIndex: startIndex + index,
                    meeting: meeting
                ))
            }
            meeting.status = .completed
            if !keepAudio {
                try LocalAudioFileService().delete(fileName: fileName)
                meeting.audioFileName = nil
            }
            try modelContext.save()
        } catch {
            // ファイル再解析に失敗しても、録音中に取得した実字幕は保持します。
            let hasActualTranscript = meeting.transcript.contains { !$0.isMarked && !$0.text.isEmpty }
            meeting.status = hasActualTranscript ? .completed : .draft
            try? modelContext.save()
        }
    }
}
