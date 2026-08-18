import AVFoundation
import Foundation
import Speech

/// The subset of `SpeechRecognitionService` `VoiceViewModel` needs — exists
/// so it can be unit tested against a fake instead of touching the real
/// `AVAudioEngine`/`SFSpeechRecognizer` (same reasoning as
/// `ConversationTransport`). `@MainActor`-isolated to match the one real
/// implementation below, whose recognition callback mutates state that must
/// only ever be touched from the main actor `VoiceViewModel` also runs on.
@MainActor
protocol SpeechCapturing: AnyObject {
    func requestAuthorization() async -> Bool
    func startRecognition() throws
    func stopRecognition() -> String
}

/// Wraps on-device speech recognition (Architecture B — see
/// docs/voice-architecture.md): capture and transcription both happen on
/// this phone; only the final transcript text ever leaves it, over the same
/// `conversation.message` GW-M2 already uses. Targets `SFSpeechRecognizer`
/// for broad OS support today; migrating to `SpeechAnalyzer`/
/// `SpeechTranscriber` (iOS 26+, see docs/ios-integrations.md) is an open
/// decision, not made yet.
@MainActor
final class SpeechRecognitionService: SpeechCapturing {
    enum SpeechError: Error {
        case authorizationDenied
        case recognizerUnavailable
        case localeNotSupported(Locale)
    }

    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""

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

    /// Requests both speech-recognition and microphone authorization —
    /// `startRecognition()` needs both, and iOS gates them as two separate
    /// prompts (`NSSpeechRecognitionUsageDescription`,
    /// `NSMicrophoneUsageDescription`; see project.yml).
    func requestAuthorization() async -> Bool {
        let speechStatus = await Self.requestAuthorization()
        guard speechStatus == .authorized else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
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

    /// Starts microphone capture and streams it into a live recognition
    /// task. Non-blocking — the caller (`VoiceViewModel`) reads whatever was
    /// transcribed so far via `stopRecognition()` once the user releases the
    /// push-to-talk button; there is no "wait for a final result" here by
    /// design, since push-to-talk has an explicit end-of-turn signal the
    /// recognizer itself doesn't need to guess at (no silence-timeout logic).
    func startRecognition() throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechError.localeNotSupported(locale)
        }
        guard recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request
        latestTranscript = ""

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let transcript = result.bestTranscription.formattedString
            Task { @MainActor [weak self] in
                self?.latestTranscript = transcript
            }
        }
    }

    /// Stops capture and returns whatever has been transcribed so far. Safe
    /// to call even if `startRecognition()` was never called or already
    /// failed — always returns cleanly rather than throwing, since this is
    /// also the cleanup path `VoiceViewModel` calls on disconnect/error.
    @discardableResult
    func stopRecognition() -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        return latestTranscript
    }
}
