import Foundation
import Observation

/// Drives EVE/Features/Voice/VoiceView. See docs/architecture.md,
/// "State machine". Milestone 3 (docs/roadmap.md) wires this into
/// AudioSessionManager, SpeechRecognitionService and EVEAPIClient once the
/// backend voice session exists (docs/backend-api.md) — today it only
/// exercises the state transitions themselves.
@Observable
final class VoiceViewModel {
    private(set) var state: VoiceSessionState = .idle

    func toggleListening() {
        switch state {
        case .idle, .interrupted, .disconnected, .error:
            state = .listening
        case .listening:
            state = .processing
        case .processing, .speaking:
            state = .idle
        }
    }
}
