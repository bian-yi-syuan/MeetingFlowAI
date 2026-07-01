import SwiftUI
import SwiftData
import UIKit
import MessageUI

private enum EmailTemplate: String, CaseIterable {
    case share = "会議内容の共有"
    case followUp = "フォローアップ"
    case request = "対応のお願い"
}

struct EmailDraftView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting
    let attachmentURL: URL?
    @StateObject private var viewModel = MeetingWorkflowViewModel()
    @State private var template: EmailTemplate = .share
    @State private var confirmation: String?
    @State private var errorMessage: String?
    @State private var showMailComposer = false

    init(meeting: Meeting, attachmentURL: URL? = nil) {
        self.meeting = meeting
        self.attachmentURL = attachmentURL
    }

    var body: some View {
        Form {
            Section("テンプレート") {
                Picker("種類", selection: $template) {
                    ForEach(EmailTemplate.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button("このテンプレートで生成", systemImage: "sparkles", action: generate)
            }
            Section("宛先") {
                TextField("複数の場合はカンマ区切り", text: $meeting.emailTo, axis: .vertical)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("件名") { TextField("件名", text: $meeting.emailSubject) }
            Section("メールプレビュー") {
                TextEditor(text: $meeting.emailBody)
                    .frame(minHeight: 330)
            }
            if let attachmentURL {
                Section("添付ファイル") {
                    Label(attachmentURL.lastPathComponent, systemImage: "waveform.badge.plus")
                        .font(.subheadline)
                        .foregroundStyle(MFColor.secondaryText)
                }
            }
            Section {
                Label("送信ボタンでiOS標準メール画面を開きます。宛先、敬称、機密情報を確認してから最終送信してください。", systemImage: "exclamationmark.shield")
                    .font(.caption).foregroundStyle(MFColor.secondaryText)
            }
        }
        .navigationTitle("メール草稿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { copy() } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("コピー")
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("共有")
                Button("保存") { save(); confirmation = "草稿を保存しました。" }
            }
        }
        .safeAreaInset(edge: .bottom) {
            MFPrimaryButton(title: "参加者へメールを送信", icon: "paperplane.fill", action: openMailComposer)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .alert("完了", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(confirmation ?? "") }
        .alert("メールを開けません", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showMailComposer) {
            MailComposeView(
                recipients: recipients,
                subject: meeting.emailSubject,
                body: meeting.emailBody,
                attachmentURL: attachmentURL
            ) { result in
                showMailComposer = false
                if case .sent = result { confirmation = "メールを送信しました。" }
            }
        }
        .onAppear(perform: prepareDraft)
        .onDisappear(perform: save)
    }

    private var shareText: String {
        "件名：\(meeting.emailSubject)\n\n\(meeting.emailBody)"
    }

    private func generate() {
        let base = viewModel.emailBody(for: meeting)
        switch template {
        case .share:
            meeting.emailSubject = "本日の\(meeting.title)内容のご共有"
            meeting.emailBody = base
        case .followUp:
            meeting.emailSubject = "【ご確認】\(meeting.title)のフォローアップ"
            meeting.emailBody = base.replacingOccurrences(of: "本日の", with: "先日の") + "\n\n進捗についてご確認いただけますと幸いです。"
        case .request:
            meeting.emailSubject = "【ご対応のお願い】\(meeting.title)"
            meeting.emailBody = base + "\n\n恐れ入りますが、ご対応のほどお願いいたします。"
        }
        save()
        confirmation = "草稿を生成しました。送信前に内容をご確認ください。"
    }

    private func copy() {
        UIPasteboard.general.string = shareText
        confirmation = "メール草稿をコピーしました。"
    }

    private func save() {
        meeting.updatedAt = .now
        try? modelContext.save()
    }

    private var recipients: [String] {
        EmailAddressParser.parse(meeting.emailTo)
    }

    private func importParticipantEmails() {
        let merged = Array(Set(recipients + meeting.participantEmails)).sorted()
        if !merged.isEmpty { meeting.emailTo = merged.joined(separator: ", ") }
    }

    private func prepareDraft() {
        importParticipantEmails()
        if meeting.emailSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meeting.emailSubject = "本日の(meeting.title)内容のご共有"
        }
        if meeting.emailBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meeting.emailBody.contains("□") {
            meeting.emailBody = viewModel.emailBody(for: meeting)
        }
        save()
    }

    private func openMailComposer() {
        save()
        guard !recipients.isEmpty else {
            errorMessage = "宛先欄に有効なメールアドレスを1件以上入力してください。"
            return
        }
        guard MFMailComposeViewController.canSendMail() else {
            errorMessage = "この端末にメールアカウントが設定されていません。実機の設定を確認してください。"
            return
        }
        showMailComposer = true
    }
}

enum EmailAddressParser {
    static func parse(_ text: String) -> [String] {
        let values = text.components(separatedBy: CharacterSet(charactersIn: ",;、\n \t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return Array(Set(values.filter { value in
            let range = NSRange(value.startIndex..., in: value)
            return regex?.firstMatch(in: value, range: range)?.range == range
        })).sorted()
    }
}

private struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachmentURL: URL?
    let completion: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(recipients)
        controller.setSubject(subject)
        controller.setMessageBody(EmailHTMLFormatter.html(from: body), isHTML: true)
        if let attachmentURL, let data = try? Data(contentsOf: attachmentURL) {
            let mimeType = attachmentURL.pathExtension.lowercased() == "m4a" ? "audio/mp4" : "audio/x-caf"
            controller.addAttachmentData(data, mimeType: mimeType, fileName: attachmentURL.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: (MFMailComposeResult) -> Void
        init(completion: @escaping (MFMailComposeResult) -> Void) { self.completion = completion }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            completion(result)
        }
    }
}

private enum EmailHTMLFormatter {
    static func html(from plainText: String) -> String {
        let lines = plainText.components(separatedBy: .newlines)
        let content = lines.map { line -> String in
            let escaped = escape(line)
            if line.hasPrefix("【"), line.hasSuffix("】") {
                return "<p style=\"margin:24px 0 8px;font-weight:700;\">\(escaped)</p>"
            }
            if line.isEmpty { return "<div style=\"height:10px\"></div>" }
            return "<div style=\"margin:3px 0;\">\(escaped)</div>"
        }.joined()
        return """
        <html><body style="font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif;font-size:16px;line-height:1.65;color:#171A21;">
        \(content)
        </body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
