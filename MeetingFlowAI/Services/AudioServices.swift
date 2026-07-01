import AVFoundation
import Combine
import Foundation

enum RecordingState: Equatable {
    case idle, recording, paused
}

enum AudioServiceError: LocalizedError {
    case permissionDenied
    case speechPermissionDenied
    case noRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "マイクの利用が許可されていません。設定アプリでマイクを許可してください。"
        case .speechPermissionDenied: "音声認識が許可されていません。設定アプリで音声認識を許可してください。"
        case .noRecording: "録音データが見つかりません。"
        }
    }
}

@MainActor
final class AudioRecordingService: NSObject, ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var liveTranscript = ""
    @Published private(set) var speechState: SpeechRecognitionState = .idle
    @Published private(set) var speechErrorMessage: String?
    @Published private(set) var isUsingSimulatorMock = false
    @Published private(set) var speechBufferCount = 0
    @Published private(set) var speechResultCount = 0
    @Published private(set) var speechDebugStatus = "待機中"

    let speechRecognition = SpeechRecognitionService()

    private let files: AudioFileStoring
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var hasInputTap = false
    private var liveTranscriptionEnabled = true
    private var liveLanguage: SubtitleLanguage = .japanese
    private var networkConnected = true
    private var recognitionMode: SubtitleRecognitionMode = .real
    private var cancellables = Set<AnyCancellable>()

    init(files: AudioFileStoring = LocalAudioFileService()) {
        self.files = files
        super.init()
        speechRecognition.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.liveTranscript = $0 }
            .store(in: &cancellables)
        speechRecognition.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.speechState = $0 }
            .store(in: &cancellables)
        speechRecognition.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.speechErrorMessage = $0 }
            .store(in: &cancellables)
        speechRecognition.$isUsingSimulatorMock
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isUsingSimulatorMock = $0 }
            .store(in: &cancellables)
        speechRecognition.$receivedAudioBufferCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.speechBufferCount = $0 }
            .store(in: &cancellables)
        speechRecognition.$receivedResultCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.speechResultCount = $0 }
            .store(in: &cancellables)
        speechRecognition.$debugStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.speechDebugStatus = $0 }
            .store(in: &cancellables)
    }

    func start(
        liveTranscription: Bool = true,
        language: SubtitleLanguage = .japanese,
        networkConnected: Bool = true,
        recognitionMode: SubtitleRecognitionMode = .real,
        recordingName: String = "MeetingFlow"
    ) async throws {
        guard await requestPermission() else {
            await speechRecognition.setMicrophonePermissionDenied()
            throw AudioServiceError.permissionDenied
        }
        liveTranscriptionEnabled = liveTranscription
        liveLanguage = language
        self.networkConnected = networkConnected
        self.recognitionMode = recognitionMode
        speechRecognition.resetTranscript()
        if liveTranscription, recognitionMode == .real,
           !(await speechRecognition.requestPermissions()) {
            throw AudioServiceError.speechPermissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        debugLog("AVAudioSession active; category=record, mode=measurement")

        let url = try files.newRecordingURL(baseName: recordingName)
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioServiceError.noRecording }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        audioEngine = engine
        audioFile = file
        currentURL = url
        if liveTranscription {
            await speechRecognition.startRecognition(
                language: language,
                isConnected: networkConnected,
                mode: recognitionMode
            )
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            try? file.write(from: buffer)
            self?.speechRecognition.append(buffer)
            let meter = Self.normalizedLevel(buffer)
            let duration = Double(file.length) / format.sampleRate
            Task { @MainActor [weak self] in
                self?.level = meter
                self?.elapsed = duration
            }
        }
        hasInputTap = true
        debugLog("inputNode.installTap succeeded; sampleRate=\(format.sampleRate), channels=\(format.channelCount)")
        engine.prepare()
        try engine.start()
        debugLog("audioEngine.prepare/start succeeded; recognitionTaskState=\(speechRecognition.state)")
        state = .recording
    }

    func pauseOrResume() {
        guard let audioEngine else { return }
        if state == .recording {
            audioEngine.pause()
            speechRecognition.stopRecognition()
            state = .paused
        } else if state == .paused {
            do {
                try audioEngine.start()
                state = .recording
                if liveTranscriptionEnabled {
                    Task { [weak self] in
                        guard let self else { return }
                        await self.speechRecognition.startRecognition(
                            language: self.liveLanguage,
                            isConnected: self.networkConnected,
                            mode: self.recognitionMode
                        )
                    }
                }
            } catch { return }
        }
    }

    func restartLiveRecognition(
        language: SubtitleLanguage,
        networkConnected: Bool,
        mode: SubtitleRecognitionMode
    ) async {
        liveLanguage = language
        self.networkConnected = networkConnected
        recognitionMode = mode
        guard liveTranscriptionEnabled, state == .recording else { return }
        await speechRecognition.startRecognition(language: language, isConnected: networkConnected, mode: mode)
    }

    func stop() async throws -> String {
        guard let audioEngine, let currentURL else { throw AudioServiceError.noRecording }
        if let audioFile, audioFile.fileFormat.sampleRate > 0 {
            elapsed = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        }
        if hasInputTap { audioEngine.inputNode.removeTap(onBus: 0); hasInputTap = false }
        audioEngine.stop()
        speechRecognition.stopRecognition()
        finishSession()
        let finalizedURL = try await files.finalizeRecording(at: currentURL)
        return finalizedURL.lastPathComponent
    }

    func cancel() {
        if hasInputTap { audioEngine?.inputNode.removeTap(onBus: 0); hasInputTap = false }
        audioEngine?.stop()
        if let currentURL { try? FileManager.default.removeItem(at: currentURL) }
        speechRecognition.stopRecognition()
        finishSession()
        elapsed = 0
        speechRecognition.resetTranscript()
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0.03 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0.03 }
        var sum: Float = 0
        for index in 0..<count { sum += data[index] * data[index] }
        return max(0.03, min(1, sqrt(sum / Float(count)) * 8))
    }

    private func finishSession() {
        audioFile = nil
        audioEngine = nil
        currentURL = nil
        level = 0
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[MeetingFlow Audio] \(message)")
        #endif
    }
}

@MainActor
final class AudioPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(fileName: String) throws {
        if isPlaying {
            pause()
            return
        }
        if player == nil {
            let url = try LocalAudioFileService().url(for: fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { throw AudioServiceError.noRecording }
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
        }
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func seek(to fraction: Double) {
        guard let player else { return }
        player.currentTime = min(max(0, fraction), 1) * player.duration
        progress = fraction
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.progress = 0
            self?.player = nil
            self?.timer?.invalidate()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player, player.duration > 0 else { return }
                self.progress = player.currentTime / player.duration
            }
        }
    }
}
