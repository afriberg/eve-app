import SwiftUI

/// Presentation-layer mapping for `VoiceSessionState`. Kept out of Models/
/// since Models must stay UI-framework-free (docs/architecture.md).
///
/// `label` is looked up from EVE/Resources/{sv,en}.lproj/Localizable.strings —
/// sv is the app's default/development region, en demonstrates the
/// localization path the architecture is required to support even though
/// the UI ships Swedish-only today. Other screens in this initial scaffold
/// still use hardcoded Swedish literals directly (acceptable for a
/// skeleton); extending this pattern to them is follow-up work, not done
/// silently as if it were already complete.
extension VoiceSessionState {
    var label: String {
        switch self {
        case .idle:
            return NSLocalizedString("voice.state.idle", comment: "Voice screen idle label")
        case .listening:
            return NSLocalizedString("voice.state.listening", comment: "Voice screen listening label")
        case .processing:
            return NSLocalizedString("voice.state.processing", comment: "Voice screen processing label")
        case .speaking:
            return NSLocalizedString("voice.state.speaking", comment: "Voice screen speaking label")
        case .interrupted:
            return NSLocalizedString("voice.state.interrupted", comment: "Voice screen interrupted label")
        case .disconnected:
            return NSLocalizedString("voice.state.disconnected", comment: "Voice screen disconnected label")
        case .error(let message):
            return message
        }
    }

    var accentColor: Color {
        switch self {
        case .idle: return .accentColor
        case .listening: return .green
        case .processing: return .orange
        case .speaking: return .blue
        case .interrupted: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}
