import AVFoundation
import Foundation

/// Owns the app's single AVAudioSession configuration. See
/// docs/ios-integrations.md, "Bluetooth / AirPods" — this type is the source
/// of the interruption/route-change signals that drive VoiceSessionState
/// transitions in EVE/Features/Voice, and must never assume iPhone-speaker
/// output.
final class AudioSessionManager {
    enum AudioSessionError: Error {
        case activationFailed(Error)
    }

    private let session = AVAudioSession.sharedInstance()

    var onInterruption: ((AVAudioSession.InterruptionType) -> Void)?
    var onRouteChange: ((AVAudioSession.RouteChangeReason) -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Configures playAndRecord for a conversational turn. `.voiceChat` vs.
    /// `.spokenAudio` is an open decision pending on-device validation —
    /// see docs/ios-integrations.md.
    func activateForConversation() throws {
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioSessionError.activationFailed(error)
        }
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    var currentRouteDescription: String {
        session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        onInterruption?(type)
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }
        onRouteChange?(reason)
    }
}
