import Foundation

/// Drives every voice-related UI surface. See docs/architecture.md, "State machine".
/// Deliberately framework-free (no SwiftUI import) — presentation mapping lives in
/// EVE/UI/VoiceSessionState+Presentation.swift.
enum VoiceSessionState: Equatable {
    case idle
    case listening
    case processing
    case speaking
    case interrupted
    case disconnected
    case error(String)
}
