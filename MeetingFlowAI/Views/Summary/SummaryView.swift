import SwiftUI
import SwiftData
import UIKit

struct SummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting
    @StateObject private var viewModel = MeetingWorkflowViewModel()
    @State private var isEditing = false
    @State private var errorMessage: String?
    @State private var confirmation: String?
    @State private var isGenerating = false
    @State private var generationProgress = 0.0
    @State private var generationStage = "文字起こしを準備しています"

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summarySection(icon: "scope", title: "会議の目的", color: MFColor.accent, generated: meeting.purpose, notes: $meeting.purposeUserNotes)
                summarySection(icon: "checkmark.seal.fill", title: "決定事項", color: MFColor.mint, generated: meeting.decisions, notes: $meeting.decisionsUserNotes)
                summarySection(icon: "bubble.left.and.text.bubble.right", title: "議論内容", color: MFColor.primary, generated: meeting.discussion, notes: $meeting.discussionUserNotes)
                summarySection(icon: "exclamationmark.triangle.fill", title: "課題", color: MFColor.warning, generated: meeting.issues, notes: $meeting.issuesUserNotes)
                summarySection(icon: "figure.walk.motion", title: "次回アクション", color: MFColor.danger, generated: meeting.nextActions, notes: $meeting.nextActionsUserNotes)
                summarySection(icon: "number", title: "重要キーワード", color: MFColor.primaryDark, generated: meeting.keywordsText, notes: $meeting.keywordsUserNotes)
                summarySection(icon: "exclamationmark.shield.fill", title: "リスク", color: MFColor.danger, generated: meeting.riskAnalysis, notes: $meeting.riskUserNotes)
                summarySection(icon: "checklist", title: "フォローアップ", color: MFColor.mint, generated: meeting.followUp, notes: $meeting.followUpUserNotes)

                if meeting.transcript.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(MFColor.warning)
                        Text("要約を作るには、先に文字起こしを1件以上追加してください。")
                            .font(.caption).foregroundStyle(MFColor.secondaryText)
                    }
                    .mfCard()
                }
            }
            .padding(18)
        }
        .navigationTitle("AI 要約")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isEditing.toggle()
                    if !isEditing { save() }
                } label: { Image(systemName: isEditing ? "checkmark" : "pencil") }
                .disabled(isGenerating)
                Menu {
                    Button("要約を再生成", systemImage: "arrow.clockwise", action: beginGeneration)
                    Button("クリップボードへコピー", systemImage: "doc.on.doc", action: copySummary)
                    ShareLink(item: summaryText) { Label("共有", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isGenerating {
                    generationProgressView
                } else {
                    MFPrimaryButton(
                        title: "AIで要約を生成",
                        icon: "sparkles",
                        disabled: meeting.transcript.isEmpty,
                        action: beginGeneration
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .alert("要約を作成できません", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "不明なエラー") }
        .alert("完了", isPresented: Binding(
            get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(confirmation ?? "") }
        .mfScreenBackground()
    }

    private func summarySection(icon: String, title: String, color: Color, generated: String, notes: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            if isEditing {
                if !generated.isEmpty {
                    Text(generated)
                        .font(.subheadline)
                        .foregroundStyle(MFColor.secondaryText)
                        .lineSpacing(4)
                }
                TextEditor(text: notes)
                    .font(.subheadline)
                    .frame(minHeight: title == "議論内容" ? 110 : 80)
                    .padding(8)
                    .background(MFColor.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("\(title)の追記")
            } else {
                let combined = meeting.combined(generated, notes: notes.wrappedValue)
                Text(combined.isEmpty ? "未作成" : combined)
                    .font(.subheadline)
                    .foregroundStyle(combined.isEmpty ? MFColor.secondaryText : MFColor.text)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .mfCard()
    }

    private var generationProgressView: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(MFColor.accent)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(generationStage).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text("\(Int(generationProgress * 100))%")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(MFColor.primary)
                }
                ProgressView(value: generationProgress)
                    .tint(MFColor.primary)
            }
        }
        .padding(14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: MFColor.primary.opacity(0.12), radius: 14, y: 5)
        .accessibilityElement(children: .combine)
    }

    private func beginGeneration() {
        guard !isGenerating, !meeting.transcript.isEmpty else { return }
        isGenerating = true
        generationProgress = 0.04
        generationStage = "保存済み字幕を読み込んでいます"

        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
                let draft = try viewModel.summaryDraft(for: meeting)
                let stages = [
                    "会議の目的を整理中", "決定事項を確認中", "議論内容を構造化中", "課題を抽出中",
                    "次回アクションを整理中", "キーワードを選定中", "リスクを分析中", "フォローアップを作成中"
                ]
                for index in stages.indices {
                    generationStage = stages[index]
                    withAnimation(.easeInOut(duration: 0.2)) {
                        generationProgress = Double(index + 1) / Double(stages.count)
                    }
                    apply(draft, at: index)
                    try await Task.sleep(for: .milliseconds(180))
                }
                meeting.status = .completed
                meeting.updatedAt = .now
                save()
                confirmation = "保存済み字幕から8項目の要約を作成しました。"
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func apply(_ draft: SummaryDraft, at index: Int) {
        switch index {
        case 0: meeting.purpose = draft.purpose
        case 1: meeting.decisions = draft.decisions
        case 2: meeting.discussion = draft.discussion
        case 3: meeting.issues = draft.issues
        case 4: meeting.nextActions = draft.nextActions
        case 5: meeting.keywordsText = draft.keywords
        case 6: meeting.riskAnalysis = draft.risks
        case 7: meeting.followUp = draft.followUp
        default: break
        }
    }

    private var summaryText: String {
        """
        【会議の目的】
        \(meeting.combined(meeting.purpose, notes: meeting.purposeUserNotes))

        【決定事項】
        \(meeting.combined(meeting.decisions, notes: meeting.decisionsUserNotes))

        【議論内容】
        \(meeting.combined(meeting.discussion, notes: meeting.discussionUserNotes))

        【課題】
        \(meeting.combined(meeting.issues, notes: meeting.issuesUserNotes))

        【次回アクション】
        \(meeting.combined(meeting.nextActions, notes: meeting.nextActionsUserNotes))

        【重要キーワード】
        \(meeting.combined(meeting.keywordsText, notes: meeting.keywordsUserNotes))

        【リスク】
        \(meeting.combined(meeting.riskAnalysis, notes: meeting.riskUserNotes))

        【フォローアップ】
        \(meeting.combined(meeting.followUp, notes: meeting.followUpUserNotes))
        """
    }

    private func copySummary() {
        UIPasteboard.general.string = summaryText
        confirmation = "要約をコピーしました。"
    }

    private func save() { try? modelContext.save() }
}
