import SwiftUI
import SwiftData

private enum TranscriptTab: String, CaseIterable {
    case all = "全文"
    case summary = "要約"
    case marks = "マーク"
}

struct TranscriptView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var networkMonitor: NetworkMonitorService
    @Bindable var meeting: Meeting
    @AppStorage("subtitleLanguage") private var subtitleLanguageRaw = SubtitleLanguage.japanese.rawValue
    @State private var selectedTab: TranscriptTab = .all
    @State private var query = ""
    @State private var editingSegment: TranscriptSegment?
    @State private var showAddSegment = false
    @State private var showSpeakers = false
    @State private var isTranscribing = false
    @State private var errorMessage: String?
    @State private var confirmation: String?

    private var displayedSegments: [TranscriptSegment] {
        meeting.sortedTranscript.filter { segment in
            let matchesTab = selectedTab != .marks || segment.isMarked
            let matchesQuery = query.isEmpty || segment.text.localizedCaseInsensitiveContains(query) || segment.speakerName.localizedCaseInsensitiveContains(query)
            return matchesTab && matchesQuery
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $selectedTab) {
                ForEach(TranscriptTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if selectedTab == .summary {
                SummaryPreview(meeting: meeting)
            } else {
                searchField
                if displayedSegments.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: selectedTab == .marks ? "bookmark" : "text.quote",
                        title: selectedTab == .marks ? "マークはありません" : "文字起こしはありません",
                        message: "＋ボタンから発言内容を追加し、話者と時刻を整理できます。"
                    )
                    .padding(18)
                    Spacer()
                } else {
                    List {
                        ForEach(displayedSegments) { segment in
                            TranscriptSegmentRow(
                                segment: segment,
                                speakers: meeting.speakers,
                                onEdit: { editingSegment = segment },
                                onSpeaker: { speaker in
                                    segment.speakerName = speaker.name
                                    segment.speakerColorHex = speaker.colorHex
                                    save()
                                },
                                onMark: { segment.isMarked.toggle(); save() },
                                onSplit: { split(segment) },
                                onMerge: { mergeWithNext(segment) }
                            )
                            .listRowInsets(EdgeInsets(top: 11, leading: 18, bottom: 11, trailing: 18))
                            .listRowBackground(Color.white)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("文字起こし")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if meeting.audioFileName != nil && meeting.transcript.allSatisfy(\.isMarked) {
                    Button { Task { await transcribeAudio() } } label: {
                        if isTranscribing { ProgressView() } else { Image(systemName: "waveform.badge.mic") }
                    }
                    .disabled(isTranscribing)
                    .accessibilityLabel("録音ファイルから文字起こし")
                }
                Button { showSpeakers = true } label: { Image(systemName: "person.2.badge.gearshape") }
                    .accessibilityLabel("発言者を管理")
                Button { showAddSegment = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("発言を追加")
            }
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEditorSheet(segment: segment, speakers: meeting.speakers) { save() }
        }
        .sheet(isPresented: $showAddSegment) {
            NewSegmentSheet(meeting: meeting) { save() }
        }
        .sheet(isPresented: $showSpeakers) {
            SpeakerManagerView(meeting: meeting)
        }
        .alert("文字起こしできませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .alert("完了", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(confirmation ?? "") }
        .mfScreenBackground()
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(MFColor.secondaryText)
            TextField("文字起こしを検索", text: $query)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(Color(hex: "EDEFF4"))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func split(_ segment: TranscriptSegment) {
        let text = segment.text
        guard text.count > 1 else { return }
        let midpoint = text.index(text.startIndex, offsetBy: text.count / 2)
        let splitIndex = text[midpoint...].firstIndex(where: { "。、！？\n".contains($0) }) ?? midpoint
        let first = String(text[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let second = String(text[splitIndex...]).trimmingCharacters(in: CharacterSet(charactersIn: "。、！？ \n"))
        guard !first.isEmpty, !second.isEmpty else { return }
        segment.text = first
        let newSegment = TranscriptSegment(
            speakerName: segment.speakerName,
            speakerColorHex: segment.speakerColorHex,
            text: second,
            startTime: (segment.startTime + segment.endTime) / 2,
            endTime: segment.endTime,
            orderIndex: segment.orderIndex + 1,
            meeting: meeting
        )
        segment.endTime = newSegment.startTime
        meeting.transcript.filter { $0.orderIndex > segment.orderIndex }.forEach { $0.orderIndex += 1 }
        modelContext.insert(newSegment)
        save()
    }

    private func mergeWithNext(_ segment: TranscriptSegment) {
        let sorted = meeting.sortedTranscript
        guard let index = sorted.firstIndex(where: { $0.id == segment.id }), index + 1 < sorted.count else { return }
        let next = sorted[index + 1]
        segment.text += "\n" + next.text
        segment.endTime = next.endTime
        modelContext.delete(next)
        normalizeOrder()
        save()
    }

    private func delete(at offsets: IndexSet) {
        offsets.map { displayedSegments[$0] }.forEach(modelContext.delete)
        normalizeOrder()
        save()
    }

    private func normalizeOrder() {
        meeting.sortedTranscript.enumerated().forEach { $0.element.orderIndex = $0.offset }
    }

    private func save() {
        meeting.updatedAt = .now
        try? modelContext.save()
    }

    @MainActor
    private func transcribeAudio() async {
        guard let fileName = meeting.audioFileName else { return }
        isTranscribing = true
        defer { isTranscribing = false }
        do {
            let url = try LocalAudioFileService().url(for: fileName)
            let language = SubtitleLanguage(rawValue: subtitleLanguageRaw) ?? .japanese
            let recognized = try await AppleSpeechFileRecognitionService().transcribe(
                audioURL: url,
                language: language,
                isConnected: networkMonitor.isConnected
            )
            let startIndex = meeting.transcript.count
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
            save()
            confirmation = "録音ファイルから文字起こししました。発言者は手動で設定してください。"
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let speakers: [Speaker]
    let onEdit: () -> Void
    let onSpeaker: (Speaker) -> Void
    let onMark: () -> Void
    let onSplit: () -> Void
    let onMerge: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(String(segment.speakerName.prefix(1)))
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(Color(hex: segment.speakerColorHex))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Menu {
                        ForEach(speakers) { speaker in
                            Button(speaker.name) { onSpeaker(speaker) }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(segment.speakerName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MFColor.text)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundStyle(MFColor.primary)
                            if segment.isLive { StatusPill(text: "LIVE", color: MFColor.danger) }
                        }
                    }
                    Spacer()
                    Text(ReportBuilder.formatDuration(segment.startTime))
                        .font(.caption2)
                        .foregroundStyle(MFColor.secondaryText)
                }
                Text(segment.text)
                    .font(.subheadline)
                    .foregroundStyle(MFColor.text)
                    .lineSpacing(4)
                    .onTapGesture(perform: onEdit)
                HStack {
                    Button(action: onMark) {
                        Image(systemName: segment.isMarked ? "bookmark.fill" : "bookmark")
                    }
                    Spacer()
                    Menu {
                        Button("編集", systemImage: "pencil", action: onEdit)
                        Button("この位置で分割", systemImage: "scissors", action: onSplit)
                        Button("次の発言と結合", systemImage: "arrow.triangle.merge", action: onMerge)
                    } label: { Image(systemName: "ellipsis") }
                }
                .font(.caption)
                .foregroundStyle(MFColor.primary)
            }
        }
    }
}

private struct SegmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var segment: TranscriptSegment
    let speakers: [Speaker]
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("発言者", selection: $segment.speakerName) {
                    ForEach(speakers) { Text($0.name).tag($0.name) }
                }
                TextEditor(text: $segment.text).frame(minHeight: 180)
                DatePicker("開始時刻", selection: timeBinding, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("発言を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let speaker = speakers.first(where: { $0.name == segment.speakerName }) { segment.speakerColorHex = speaker.colorHex }
                        onSave(); dismiss()
                    }
                }
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: segment.startTime) },
            set: { segment.startTime = $0.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400) }
        )
    }
}

private struct NewSegmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let meeting: Meeting
    let onSave: () -> Void
    @State private var text = ""
    @State private var speakerName = "発言者 A"
    @State private var startTime: TimeInterval = 0

    var body: some View {
        NavigationStack {
            Form {
                Picker("発言者", selection: $speakerName) {
                    ForEach(meeting.speakers) { Text($0.name).tag($0.name) }
                }
                Section("発言内容") { TextEditor(text: $text).frame(minHeight: 180) }
                Section("開始（秒）") {
                    TextField("0", value: $startTime, format: .number).keyboardType(.numberPad)
                }
            }
            .navigationTitle("発言を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        let speaker = meeting.speakers.first(where: { $0.name == speakerName })
                        modelContext.insert(TranscriptSegment(
                            speakerName: speakerName,
                            speakerColorHex: speaker?.colorHex ?? "517CF6",
                            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                            startTime: startTime,
                            endTime: startTime + 5,
                            orderIndex: meeting.transcript.count,
                            meeting: meeting
                        ))
                        onSave(); dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { speakerName = meeting.speakers.first?.name ?? "発言者 A" }
    }
}

struct SpeakerManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting
    @State private var newName = ""

    private let colors = ["517CF6", "3FB98A", "6C63F2", "E55757", "F3A52B", "2E9AB8"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(meeting.speakers) { speaker in
                        SpeakerEditorRow(
                            speaker: speaker,
                            segmentCount: meeting.transcript.filter { $0.speakerName == speaker.name }.count,
                            onRename: { oldName, newName in
                                meeting.participantRecords.filter { $0.name == oldName }.forEach { $0.name = newName }
                                meeting.transcript.filter { $0.speakerName == oldName }.forEach { $0.speakerName = newName }
                                meeting.participantsText = meeting.participantRecords.sorted { $0.orderIndex < $1.orderIndex }.map(\.name).joined(separator: "、")
                                try? modelContext.save()
                            }
                        )
                    }
                    .onDelete(perform: delete)
                } header: { Text("発言者") }

                Section("発言者を追加") {
                    HStack {
                        TextField("例：山田部長", text: $newName)
                        Button("追加") { addSpeaker() }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    Label("MVPでは手動で発言者を設定します。将来は話者分離サービスへ差し替えられる設計です。", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(MFColor.secondaryText)
                }
            }
            .navigationTitle("発言者ラベル")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { try? modelContext.save(); dismiss() } } }
        }
    }

    private func addSpeaker() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(Speaker(name: name, colorHex: colors[meeting.speakers.count % colors.count], meeting: meeting))
        newName = ""
        try? modelContext.save()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let speaker = meeting.speakers[index]
            meeting.transcript.filter { $0.speakerName == speaker.name }.forEach {
                $0.speakerName = "発言者 A"; $0.speakerColorHex = "517CF6"
            }
            modelContext.delete(speaker)
        }
        try? modelContext.save()
    }
}

private struct SpeakerEditorRow: View {
    @Bindable var speaker: Speaker
    let segmentCount: Int
    let onRename: (String, String) -> Void

    var body: some View {
        HStack {
            Circle().fill(Color(hex: speaker.colorHex)).frame(width: 12, height: 12)
            TextField("発言者名", text: $speaker.name)
            Text("\(segmentCount)件").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: speaker.name) { oldName, newName in
            let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned != oldName else { return }
            onRename(oldName, cleaned)
        }
    }
}

private struct SummaryPreview: View {
    let meeting: Meeting

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if meeting.hasSummary {
                    Text("会議の目的").font(.headline)
                    Text(meeting.purpose)
                    Text("決定事項").font(.headline)
                    Text(meeting.decisions)
                    NavigationLink("要約を開く", destination: SummaryView(meeting: meeting))
                } else {
                    EmptyStateView(icon: "sparkles", title: "要約はまだありません", message: "文字起こしを追加して要約を作成できます。")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }
}
