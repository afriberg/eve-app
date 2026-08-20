import AVFoundation
import Foundation

/// Plays a GW-M3 `conversation.response` audio field — a base64 data URL
/// synthesized by eve-os's local, offline Piper TTS (see eve-os
/// docs/voice-gateway.md, "GW-M3 — Voice"). One utterance at a time.
@MainActor
protocol AudioPlaying: AnyObject {
    /// Decodes and plays `dataURL` (e.g. "data:audio/wav;base64,...."),
    /// suspending until playback finishes. A malformed data URL or playback
    /// failure resolves silently rather than throwing — a broken spoken
    /// reply must never fail the turn, mirroring the Gateway's own
    /// text-first, audio-is-an-enhancement design (eve/gateway/api.py).
    func play(dataURL: String) async
    func stop()
}

@MainActor
final class AudioPlaybackService: NSObject, AudioPlaying, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    func play(dataURL: String) async {
        stop()

        guard
            let commaIndex = dataURL.firstIndex(of: ","),
            let audioData = Data(base64Encoded: String(dataURL[dataURL.index(after: commaIndex)...]))
        else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
            do {
                let player = try AVAudioPlayer(data: audioData)
                player.delegate = self
                self.player = player
                if !player.play() {
                    finish()
                }
            } catch {
                finish()
            }
        }
    }

    func stop() {
        player?.stop()
        finish()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        player = nil
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
