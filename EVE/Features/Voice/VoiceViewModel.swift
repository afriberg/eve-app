import Foundation
import Observation

/// Drives EVE/Features/Voice/VoiceView — push-to-talk (GW-M3, `eve-ios-app`
/// Milestone 3, `docs/roadmap.md`). Mic capture and on-device STT
/// (Architecture B, `docs/voice-architecture.md`) both happen entirely on
/// this phone; only the final transcript is ever sent to the Gateway, over
/// the same `conversation.message`/`conversation.response` WS exchange
/// GW-M2's `ConversationViewModel` already uses (eve-os
/// `docs/voice-gateway.md`). A returned `audio` field (eve-os
/// `eve/gateway/tts.py`, GW-M3) is played back locally; its absence (TTS
/// disabled, or synthesis failed on the Gateway) is not an error — the turn
/// still completes as a silent, text-only success, mirroring the Gateway's
/// own graceful degradation.
@MainActor
@Observable
final class VoiceViewModel {
    private(set) var state: VoiceSessionState = .idle
    private(set) var lastTranscript: String?
    private(set) var lastResponseText: String?

    private let apiClient: GatewayAPIClient
    private let transport: ConversationTransport
    private let speech: SpeechCapturing
    private let audioSession: AudioSessionActivating
    private let playback: AudioPlaying

    private var isConnected = false

    init(
        apiClient: GatewayAPIClient,
        transport: ConversationTransport,
        speech: SpeechCapturing,
        audioSession: AudioSessionActivating,
        playback: AudioPlaying
    ) {
        self.apiClient = apiClient
        self.transport = transport
        self.speech = speech
        self.audioSession = audioSession
        self.playback = playback
    }

    /// One tap starts listening; the next stops it and sends whatever was
    /// transcribed. Taps mid-turn (`.processing`/`.speaking`) are ignored —
    /// there is no cancel-in-flight path yet (barge-in is Milestone 6, not
    /// this one). A thin, synchronous wrapper around `startListening()`/
    /// `finishListeningAndRespond()` so `VoiceView`'s `Button` action
    /// doesn't need to be async — those two do the real work and are what
    /// tests call directly, to await completion without racing a detached
    /// `Task`.
    func toggleListening() {
        switch state {
        case .idle, .interrupted, .disconnected, .error:
            Task { await startListening() }
        case .listening:
            Task { await finishListeningAndRespond() }
        case .processing, .speaking:
            return
        }
    }

    /// Two automatic retries (three attempts total): a real, physically-
    /// observed failure mode is a transient WS connection failure
    /// (`NSPOSIXErrorDomain Code=57 "Socket is not connected"`) on a
    /// reconnect attempt after a previous session ended — confirmed via
    /// Gateway logs to never even reach the server (no `/v1/ws` line for
    /// the failing ticket), so this is a local/network-level connection-
    /// establishment hiccup, not a backend bug. One retry was not always
    /// enough — physically observed to fail twice in a row on the same
    /// hiccup — so this backs off longer between attempts (300ms, then
    /// 800ms) with a fresh ticket each time (the failed one is already
    /// burned, single-use), to make the transient case invisible instead
    /// of forcing the user to notice an error and tap again themselves.
    private func ensureConnected() async -> Bool {
        if isConnected { return true }
        guard let baseURL = await apiClient.currentBaseURL else {
            state = .error("Ingen EVE-server konfigurerad. Ställ in den under Inställningar.")
            return false
        }
        let backoffs: [Duration] = [.milliseconds(300), .milliseconds(800)]
        for attempt in 0...backoffs.count {
            do {
                let ticket = try await apiClient.createSession()
                try await transport.connect(baseURL: baseURL, ticket: ticket.ticket)
                let started = try await transport.receiveConversationEvent()
                guard case .sessionStarted = started else {
                    state = .error("Oväntat svar från EVE Voice Gateway.")
                    return false
                }
                isConnected = true
                return true
            } catch {
                if attempt < backoffs.count {
                    try? await Task.sleep(for: backoffs[attempt])
                    continue
                }
                state = .error(String(describing: error))
                return false
            }
        }
        return false
    }

    func startListening() async {
        guard await ensureConnected() else { return }

        guard await speech.requestAuthorization() else {
            state = .error("EVE behöver tillgång till mikrofonen och taligenkänning under Inställningar.")
            return
        }

        do {
            try audioSession.activateForConversation()
            try speech.startRecognition()
            state = .listening
        } catch {
            state = .error("Kunde inte starta mikrofonen.")
        }
    }

    func finishListeningAndRespond() async {
        let transcript = speech.stopRecognition().trimmingCharacters(in: .whitespacesAndNewlines)
        // Deliberately NOT deactivating the audio session here anymore — a
        // real bug, reported after physical testing: toggling the session
        // off then back on (`startListening()`) on every single turn,
        // rather than only at the end of a conversation, correlated
        // exactly with the WS dying between a turn and its follow-up
        // (NSPOSIXErrorDomain Code=57 "Socket is not connected" on the very
        // next send, every time — not an occasional idle-timeout drop).
        // `.voiceChat` mode's voice-processing I/O reconfiguration on
        // deactivate/reactivate is a plausible culprit, though not proven
        // from a client-side stack trace alone. Apple's own guidance is to
        // avoid unnecessary session reconfiguration during a continuous
        // interaction anyway, so the session now stays active for the
        // whole conversation and is only torn down in disconnect().

        guard !transcript.isEmpty else {
            state = .idle
            return
        }

        lastTranscript = transcript
        state = .processing

        do {
            try await transport.sendConversationMessage(transcript)
            let event = try await transport.receiveConversationEvent()
            switch event {
            case .response(let text, let audio):
                lastResponseText = text
                if let audio {
                    state = .speaking
                    await playback.play(dataURL: audio.dataURL)
                }
                state = .idle
            case .error(_, let message):
                state = .error(message)
            case .sessionStarted, .sessionClosed, .unknown:
                state = .error("Oväntat svar från EVE Voice Gateway.")
            }
        } catch {
            // A real bug, found on a physical device: `isConnected` is only
            // ever set on a successful connect, never cleared on a
            // transport-level failure. If the WS silently drops (e.g. an
            // idle timeout between turns), every subsequent tap kept
            // reusing the same dead `URLSessionWebSocketTask` and failing
            // with the same `NSPOSIXErrorDomain Code=57 "Socket is not
            // connected"` forever — the app had to be force-quit to
            // recover. Clearing it here means the next tap's
            // `ensureConnected()` establishes a fresh session/socket
            // instead of trusting a stale one.
            isConnected = false
            state = .error(String(describing: error))
        }
    }

    func disconnect() async {
        speech.stopRecognition()
        playback.stop()
        audioSession.deactivate()
        try? await transport.sendClose()
        await transport.close()
        isConnected = false
        state = .disconnected
    }
}
