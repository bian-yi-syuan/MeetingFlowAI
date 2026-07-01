import Foundation
@preconcurrency import AVFoundation

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

protocol AudioFileStoring {
    func newRecordingURL(baseName: String) throws -> URL
    func finalizeRecording(at sourceURL: URL) async throws -> URL
    func url(for fileName: String) throws -> URL
    func delete(fileName: String) throws
    func deleteAllAudio() throws
}

struct LocalAudioFileService: AudioFileStoring {
    private var directory: URL {
        get throws {
            let root = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = root.appendingPathComponent("Recordings", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            return directory
        }
    }

    private var legacyDirectory: URL {
        get throws {
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return root.appendingPathComponent("MeetingFlowAI/Audio", isDirectory: true)
        }
    }

    func newRecordingURL(baseName: String = "MeetingFlow") throws -> URL {
        let sanitized = sanitize(baseName)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: .now)
        return try directory.appendingPathComponent("\(sanitized)_\(stamp).caf")
    }

    func finalizeRecording(at sourceURL: URL) async throws -> URL {
        let safeDirectory = try directory.standardizedFileURL
        let source = sourceURL.standardizedFileURL
        guard source.deletingLastPathComponent() == safeDirectory else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let destination = source.deletingPathExtension().appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let asset = AVURLAsset(url: source)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            try protect(source)
            return source
        }
        exporter.shouldOptimizeForNetworkUse = true
        do {
            if #available(iOS 18.0, *) {
                try await exporter.export(to: destination, as: .m4a)
            } else {
                exporter.outputURL = destination
                exporter.outputFileType = .m4a
                let box = ExportSessionBox(exporter)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    box.session.exportAsynchronously {
                        switch box.session.status {
                        case .completed:
                            continuation.resume()
                        case .failed, .cancelled:
                            continuation.resume(throwing: box.session.error ?? CocoaError(.fileWriteUnknown))
                        default:
                            continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                        }
                    }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try protect(source)
            return source
        }
        try protect(destination)
        try? FileManager.default.removeItem(at: source)
        return destination
    }

    func url(for fileName: String) throws -> URL {
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        guard safeName == fileName else { throw CocoaError(.fileReadInvalidFileName) }
        let current = try directory.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: current.path) { return current }
        let legacy = try legacyDirectory.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return current
    }

    func delete(fileName: String) throws {
        let location = try url(for: fileName)
        guard FileManager.default.fileExists(atPath: location.path) else { return }
        try FileManager.default.removeItem(at: location)
    }

    func deleteAllAudio() throws {
        for location in [try directory, try legacyDirectory] {
            if FileManager.default.fileExists(atPath: location.path) {
                try FileManager.default.removeItem(at: location)
            }
        }
    }

    private func sanitize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? "MeetingFlow" : trimmed
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\0\n\r")
        let safe = source.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
        return String((safe.isEmpty ? "MeetingFlow" : safe).prefix(48))
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }
}
