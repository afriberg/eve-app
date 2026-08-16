import Foundation
import Speech

/// Wraps on-device speech recognition (Architecture B — see
/// docs/voice-architecture.md). Targets `SFSpeechRecognizer` for broad OS
/// support today; migrating to `SpeechAnalyzer`/`SpeechTranscriber`
/// (iOS 26+, see docs/ios-integrations.md) is an open decision, not made yet.
final class SpeechRecognitionService {
    enum SpeechError: Error {
        case authorizationDenied
        case recognizerUnavailable
        case localeNotSupported(Locale)
    }

    private let locale: Locale

    init(locale: Locale = Locale(identifier: "sv-SE")) {
        self.locale = locale
    }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Must be checked at runtime, not assumed — see docs/ios-integrations.md,
    /// "Speech framework (on-device STT)". Apple does not publish a stable
    /// locale table for on-device support.
    func isOnDeviceRecognitionAvailable() -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.supportsOnDeviceRecognition
    }
}
