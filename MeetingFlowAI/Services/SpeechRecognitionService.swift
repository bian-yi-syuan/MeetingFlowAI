import Foundation
import Speech
import AVFoundation

final class SpeechRecognitionService: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var state: SpeechRecognitionState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedLanguage: SubtitleLanguage = .japanese
    @Published private(set) var isUsingSimulatorMock = false
    @Published private(set) var receivedAudioBufferCount = 0
    @Published private(set) var receivedResultCount = 0
    @Published private(set) var debugStatus = "待機中"

    private let lock = NSLock()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var mockTask: Task<Void, Never>?
    private var activeRecognitionID: UUID?
    private var mockLineIndex = 0
    private var appendedBufferCount = 0

    func requestPermissions() async -> Bool {
        debugLog("requestPermissions started; current=\(SFSpeechRecognizer.authorizationStatus().rawValue)")
        await publish(state: .requestingPermission, error: nil)
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            debugLog("requestPermissions denied/restricted; result=\(status.rawValue)")
            await publish(state: .permissionDenied, error: "マイクと音声認識の使用を許可してください。")
            return false
        }
        debugLog("requestPermissions authorized")
        await publish(state: .ready, error: nil)
        return true
    }

    func startRecognition(
        language: SubtitleLanguage,
        isConnected: Bool,
        mode: SubtitleRecognitionMode = .real
    ) async {
        stopRecognition()
        debugLog("startRecognition started; mode=\(mode.rawValue), language=\(language.displayName)")
        #if targetEnvironment(simulator)
        if mode == .simulatorMock {
            await startSimulatorMock(language: language)
            return
        }
        #endif
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            guard await requestPermissions() else { return }
        }

        lock.withLock { appendedBufferCount = 0 }
        await MainActor.run {
            receivedAudioBufferCount = 0
            receivedResultCount = 0
            debugStatus = "Apple Speechを初期化しています"
            isUsingSimulatorMock = false
        }

        let locale = Locale(identifier: language.localeIdentifier)
        let supported = SFSpeechRecognizer.supportedLocales().contains { candidate in
            normalized(candidate.identifier) == normalized(locale.identifier)
        }
        logDiagnostics(language: language, locale: locale, isSupported: supported, isConnected: isConnected)

        guard supported else {
            await handleRecognizerFailure(
                message: "この環境では\(language.displayName)の音声認識を利用できません（\(language.localeIdentifier)）。"
            )
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            await handleRecognizerFailure(
                message: "Failed to initialize recognizer for \(language.localeIdentifier)"
            )
            return
        }
        debugLog("recognizer.isAvailable=\(recognizer.isAvailable), supportsOnDeviceRecognition=\(recognizer.supportsOnDeviceRecognition)")
        guard recognizer.isAvailable else {
            await handleRecognizerFailure(message: "音声認識サービスは現在利用できません。")
            return
        }
        if !isConnected && !recognizer.supportsOnDeviceRecognition {
            await publish(
                state: .unavailable,
                error: "オフライン字幕に対応していないため、現在利用できません。ネットワーク接続後に再度お試しください。"
            )
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if !isConnected && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        let existingText = await MainActor.run { transcript }
        let recognitionID = UUID()
        activeRecognitionID = recognitionID

        lock.withLock { recognitionRequest = request }
        debugLog("recognitionRequest created; partialResults=true, onDevice=\(request.requiresOnDeviceRecognition)")
        await MainActor.run {
            selectedLanguage = language
            state = .recognizing
            errorMessage = nil
            isUsingSimulatorMock = false
            debugStatus = "音声入力を待っています"
        }
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.activeRecognitionID == recognitionID else { return }
                if let partial = result?.bestTranscription.formattedString, !partial.isEmpty {
                    self.transcript = existingText.isEmpty ? partial : existingText + "\n" + partial
                    self.receivedResultCount += 1
                    self.debugStatus = result?.isFinal == true ? "最終認識結果を受信しました" : "リアルタイム認識中"
                    self.debugLog("result received; isFinal=\(result?.isFinal == true), text=\(partial)")
                }
                if let error {
                    self.debugLog("recognition error=\(error.localizedDescription)")
                    self.state = .error
                    self.errorMessage = "音声認識エラー：\(error.localizedDescription)"
                    self.debugStatus = "Apple Speechエラー"
                }
            }
        }
        debugLog("recognitionTask created successfully")
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let (request, count) = lock.withLock {
            appendedBufferCount += 1
            return (recognitionRequest, appendedBufferCount)
        }
        request?.append(buffer)
        if count == 1 || count.isMultiple(of: 50) {
            let requestExists = request != nil
            let frameLength = buffer.frameLength
            DispatchQueue.main.async {
                self.receivedAudioBufferCount = count
                self.debugStatus = requestExists
                    ? "音声buffer受信済み・Apple Speech応答待ち"
                    : "音声buffer受信済み・認識requestなし"
                self.debugLog("audio buffer appended; count=\(count), requestExists=\(requestExists), frames=\(frameLength)")
            }
        }
    }

    func stopRecognition() {
        mockTask?.cancel()
        mockTask = nil
        activeRecognitionID = nil
        let request = lock.withLock {
            let activeRequest = recognitionRequest
            recognitionRequest = nil
            return activeRequest
        }
        request?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
    }

    func resetTranscript() {
        mockLineIndex = 0
        lock.withLock { appendedBufferCount = 0 }
        DispatchQueue.main.async {
            self.transcript = ""
            self.state = .idle
            self.errorMessage = nil
            self.isUsingSimulatorMock = false
            self.receivedAudioBufferCount = 0
            self.receivedResultCount = 0
            self.debugStatus = "待機中"
        }
    }

    func setMicrophonePermissionDenied() async {
        await publish(state: .permissionDenied, error: "マイクと音声認識の使用を許可してください。")
    }

    private func publish(state: SpeechRecognitionState, error: String?) async {
        await MainActor.run {
            self.state = state
            self.errorMessage = error
        }
    }

    private func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private func handleRecognizerFailure(message: String) async {
        debugLog(message)
        await MainActor.run {
            state = .error
            errorMessage = message
            debugStatus = "Apple Speechを開始できませんでした"
        }
    }

    private func startSimulatorMock(language: SubtitleLanguage) async {
        #if targetEnvironment(simulator)
        activeRecognitionID = nil
        let request = lock.withLock {
            let activeRequest = recognitionRequest
            recognitionRequest = nil
            return activeRequest
        }
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        mockTask?.cancel()

        let previousLanguage = await MainActor.run { selectedLanguage }
        if previousLanguage != language { mockLineIndex = 0 }
        await MainActor.run {
            selectedLanguage = language
            state = .recognizing
            errorMessage = nil
            isUsingSimulatorMock = true
            debugStatus = "Simulator Mockを実行中"
        }
        let lines = language == .japanese ? Self.japaneseMockLines : Self.englishMockLines
        let startIndex = min(mockLineIndex, lines.count)
        mockTask = Task { [weak self] in
            for index in startIndex..<lines.count {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    let line = lines[index]
                    self.transcript += self.transcript.isEmpty ? line : "\n" + line
                    self.mockLineIndex = index + 1
                    self.receivedResultCount += 1
                }
            }
        }
        #endif
    }

    private func logDiagnostics(
        language: SubtitleLanguage,
        locale: Locale,
        isSupported: Bool,
        isConnected: Bool
    ) {
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        let microphone = AVAudioApplication.shared.recordPermission.rawValue
        debugLog(
            "selectedLanguage=\(language.displayName), locale=\(locale.identifier), " +
            "supported=\(isSupported), speechAuthorization=\(SFSpeechRecognizer.authorizationStatus().rawValue), " +
            "microphonePermission=\(microphone), networkConnected=\(isConnected), simulator=\(simulator)"
        )
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[MeetingFlow Speech] \(message)")
        #endif
    }

    private static let japaneseMockLines = [
        "こんにちは。本日の会議では新しいプロジェクトについて確認します。",
        "次に、デザイン案と開発スケジュールを共有します。",
        "田中さんは来週までに資料を準備してください。",
        "次回の会議で進捗を確認します。",
        "本日の決定事項を会議一覧に保存します。"
    ]

    private static let englishMockLines = [
        "Hello, this is a speech recognition test.",
        "Today we will discuss the new project schedule.",
        "Please prepare the design materials by next week.",
        "We will confirm progress at the next meeting.",
        "The decisions will be saved with this meeting."
    ]
}

struct RecognizedTranscriptSegment: Equatable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

protocol SpeechTranscribing {
    func transcribe(audioURL: URL) async throws -> [RecognizedTranscriptSegment]
}

enum SpeechTranscriptionError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable(String)
    case unsupportedLocale(String)
    case onDeviceUnavailable
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "音声認識が許可されていません。設定アプリで許可してください。"
        case .recognizerUnavailable(let language): "\(language)の音声認識サービスを現在利用できません。"
        case .unsupportedLocale(let locale): "この環境は音声認識言語 \(locale) に対応していません。"
        case .onDeviceUnavailable: "この端末は選択言語のオフライン文字起こしに対応していません。ネットワーク接続後に再度お試しください。"
        case .noSpeech: "音声から文字を認識できませんでした。手動で文字起こしを追加できます。"
        }
    }
}

/// 録音ファイルをApple Speechで再解析します。オンライン時はApple Speech、
/// オフライン時は対応端末のon-device recognitionだけを使用します。
@MainActor
final class AppleSpeechFileRecognitionService: SpeechTranscribing {
    private var activeTask: SFSpeechRecognitionTask?

    func transcribe(audioURL: URL) async throws -> [RecognizedTranscriptSegment] {
        try await transcribe(audioURL: audioURL, language: .japanese, isConnected: false)
    }

    func transcribe(
        audioURL: URL,
        language: SubtitleLanguage,
        isConnected: Bool
    ) async throws -> [RecognizedTranscriptSegment] {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else { throw SpeechTranscriptionError.permissionDenied }
        let locale = Locale(identifier: language.localeIdentifier)
        let supported = SFSpeechRecognizer.supportedLocales().contains {
            $0.identifier.replacingOccurrences(of: "_", with: "-").lowercased() ==
            locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        }
        guard supported else { throw SpeechTranscriptionError.unsupportedLocale(language.localeIdentifier) }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable(language.displayName)
        }
        if !isConnected && !recognizer.supportsOnDeviceRecognition {
            throw SpeechTranscriptionError.onDeviceUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        if !isConnected && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.contextualStrings = ["MeetingFlow AI", "議事録", "進捗", "決定事項", "次回アクション"]

        #if DEBUG
        print(
            "[MeetingFlow Speech File] start; locale=\(language.localeIdentifier), " +
            "online=\(isConnected), onDevice=\(request.requiresOnDeviceRecognition), file=\(audioURL.lastPathComponent)"
        )
        #endif

        let transcription: SFTranscription = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFTranscription, Error>) in
            var didResume = false
            activeTask = recognizer.recognitionTask(with: request) { result, error in
                if let error, !didResume {
                    #if DEBUG
                    print("[MeetingFlow Speech File] error=\(error.localizedDescription)")
                    #endif
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal, !didResume else { return }
                #if DEBUG
                print("[MeetingFlow Speech File] final result=\(result.bestTranscription.formattedString)")
                #endif
                didResume = true
                continuation.resume(returning: result.bestTranscription)
            }
        }
        activeTask = nil
        let segments = group(transcription.segments)
        guard !segments.isEmpty else { throw SpeechTranscriptionError.noSpeech }
        return segments
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
    }

    private func group(_ source: [SFTranscriptionSegment]) -> [RecognizedTranscriptSegment] {
        guard !source.isEmpty else { return [] }
        var result: [RecognizedTranscriptSegment] = []
        var words: [String] = []
        var start = source[0].timestamp
        var end = start

        for segment in source {
            if words.isEmpty { start = segment.timestamp }
            words.append(segment.substring)
            end = segment.timestamp + segment.duration
            let reachedPause = end - start >= 15
            let reachedPunctuation = segment.substring.last.map { "。！？.!?".contains($0) } ?? false
            if reachedPause || reachedPunctuation {
                append(words: &words, start: start, end: end, into: &result)
            }
        }
        append(words: &words, start: start, end: end, into: &result)
        return result
    }

    private func append(words: inout [String], start: TimeInterval, end: TimeInterval, into result: inout [RecognizedTranscriptSegment]) {
        let text = words.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { result.append(RecognizedTranscriptSegment(text: text, startTime: start, endTime: end)) }
        words.removeAll(keepingCapacity: true)
    }
}
