enum SpeechRecognitionState: Equatable {
    case idle
    case requestingPermission
    case ready
    case recognizing
    case unavailable
    case permissionDenied
    case error
}
