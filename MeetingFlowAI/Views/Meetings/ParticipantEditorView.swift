import SwiftUI
import SwiftData

private struct ParticipantDraft: Identifiable {
    var id: UUID
    var persistedID: UUID?
    var name: String
    var email: String

    init(participant: Participant) {
        id = participant.id
        persistedID = participant.id
        name = participant.name
        email = participant.email
    }

    init(name: String = "", email: String = "") {
        id = UUID()
        persistedID = nil
        self.name = name
        self.email = email
    }
}

struct ParticipantEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting
    @State private var drafts: [ParticipantDraft] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($drafts) { $participant in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("氏名（例：田中さん）", text: $participant.name)
                                .font(.headline)
                        }
                        .padding(.vertical, 5)
                    }
                    .onDelete { drafts.remove(atOffsets: $0) }
                    Button("参加者を追加", systemImage: "person.badge.plus") {
                        drafts.append(ParticipantDraft())
                    }
                } header: {
                    Text("会議参加者")
                } footer: {
                    Text("氏名は文字起こしの発言者選択と連動します。")
                }
            }
            .navigationTitle("参加者を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let records = meeting.participantRecords.sorted { $0.orderIndex < $1.orderIndex }
        if records.isEmpty {
            drafts = meeting.participants.map { ParticipantDraft(name: $0) }
        } else {
            drafts = records.map(ParticipantDraft.init)
        }
    }

    private func save() {
        let cleaned = drafts.compactMap { draft -> ParticipantDraft? in
            var value = draft
            value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
            value.email = value.email.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.name.isEmpty ? nil : value
        }
        let existing = Dictionary(uniqueKeysWithValues: meeting.participantRecords.map { ($0.id, $0) })
        let retainedIDs = Set(cleaned.compactMap(\.persistedID))

        for participant in meeting.participantRecords where !retainedIDs.contains(participant.id) {
            if !meeting.transcript.contains(where: { $0.speakerName == participant.name }) {
                meeting.speakers.filter { $0.name == participant.name }.forEach(modelContext.delete)
            }
            modelContext.delete(participant)
        }
        for (index, draft) in cleaned.enumerated() {
            if let id = draft.persistedID, let participant = existing[id] {
                if participant.name != draft.name {
                    ParticipantSyncService.renameSpeaker(from: participant.name, to: draft.name, meeting: meeting)
                }
                participant.name = draft.name
                participant.email = draft.email
                participant.orderIndex = index
            } else {
                modelContext.insert(Participant(name: draft.name, email: draft.email, orderIndex: index, meeting: meeting))
                if !meeting.speakers.contains(where: { $0.name == draft.name }) {
                    modelContext.insert(Speaker(name: draft.name, colorHex: ParticipantSyncService.colors[index % ParticipantSyncService.colors.count], meeting: meeting))
                }
            }
        }
        meeting.participantsText = cleaned.map(\.name).joined(separator: "、")
        meeting.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}
