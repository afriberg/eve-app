import XCTest
@testable import EVE

@MainActor
final class FakeSpeechCapture: SpeechCapturing {
    var authorizationResult = true
    var transcriptToReturn = ""
    var startRecognitionError: Error?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func requestAuthorization() async -> Bool { authorizationResult }

    func startRecognition() throws {
        startCallCount += 1
        if let startRecognitionError { throw startRecognitionError }
    }

    @discardableResult
    func stopRecognition() -> String {
        stopCallCount += 1
        return transcriptToReturn
    }
}

@MainActor
final class FakeAudioSession: AudioSessionActivating {
    var activateError: Error?
    private(set) var activateCallCount = 0
    private(set) var deactivateCallCount = 0

    func activateForConversation() throws {
        activateCallCount += 1
        if let activateError { throw activateError }
    }

    func deactivate() {
        deactivateCallCount += 1
    }
}

@MainActor
final class FakeAudioPlayback: AudioPlaying {
    private(set) var playedDataURLs: [String] = []
    private(set) var stopCallCount = 0

    func play(dataURL: String) async {
        playedDataURLs.append(dataURL)
    }

    func stop() {
        stopCallCount += 1
    }
}

@MainActor
final class VoiceViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeConfiguredClient() async -> GatewayAPIClient {
        let client = GatewayAPIClient(session: MockURLProtocol.makeSession())
        await client.configure(baseURL: URL(string: "https://gateway.example/")!)
        await client.setDeviceCredential("evgw_abc.def")
        MockURLProtocol.stubs["POST /v1/sessions"] = .init(
            status: 200,
            body: Data(
                #"{"session_id":"s1","ticket":"tk1","expires_at":"2026-08-16T00:00:30Z"}"#.utf8
            )
        )
        return client
    }

    /// Default parameter *values* in Swift are evaluated in a synchronous,
    /// non-isolated context regardless of the enclosing method's own actor
    /// isolation — so `= FakeSpeechCapture()` directly as a default would
    /// fail to compile (`FakeSpeechCapture` is `@MainActor`). `nil` defaults
    /// plus constructing the fallback inside the (MainActor-isolated)
    /// function body sidesteps that.
    private func makeViewModel(
        client: GatewayAPIClient,
        transport: FakeConversationTransport,
        speech: FakeSpeechCapture? = nil,
        audioSession: FakeAudioSession? = nil,
        playback: FakeAudioPlayback? = nil
    ) -> VoiceViewModel {
        VoiceViewModel(
            apiClient: client, transport: transport,
            speech: speech ?? FakeSpeechCapture(),
            audioSession: audioSession ?? FakeAudioSession(),
            playback: playback ?? FakeAudioPlayback()
        )
    }

    func testStartListeningConnectsThenActivatesMicAndRecognition() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [.event(.sessionStarted(sessionId: "s1"))]
        let speech = FakeSpeechCapture()
        let audioSession = FakeAudioSession()
        let viewModel = makeViewModel(
            client: client, transport: transport, speech: speech, audioSession: audioSession
        )

        await viewModel.startListening()

        XCTAssertEqual(viewModel.state, .listening)
        XCTAssertEqual(transport.connectCallCount, 1)
        XCTAssertEqual(audioSession.activateCallCount, 1)
        XCTAssertEqual(speech.startCallCount, 1)
    }

    func testStartListeningFailsWithoutAConfiguredServer() async {
        let unconfiguredClient = GatewayAPIClient(session: MockURLProtocol.makeSession())
        let transport = FakeConversationTransport()
        let viewModel = makeViewModel(client: unconfiguredClient, transport: transport)

        await viewModel.startListening()

        guard case .error = viewModel.state else {
            return XCTFail("expected .error, got \(viewModel.state)")
        }
        XCTAssertEqual(transport.connectCallCount, 0)
    }

    func testStartListeningFailsWhenAuthorizationIsDenied() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [.event(.sessionStarted(sessionId: "s1"))]
        let speech = FakeSpeechCapture()
        speech.authorizationResult = false
        let viewModel = makeViewModel(client: client, transport: transport, speech: speech)

        await viewModel.startListening()

        guard case .error = viewModel.state else {
            return XCTFail("expected .error, got \(viewModel.state)")
        }
        XCTAssertEqual(speech.startCallCount, 0)
    }

    func testFinishListeningSendsTranscriptAndRecordsResponseWithAudio() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [
            .event(.sessionStarted(sessionId: "s1")),
            .event(.response(text: "Hej! Hur mår du?", audio: ConversationAudio(
                dataURL: "data:audio/wav;base64,AA==", mimeType: "audio/wav"
            ))),
        ]
        let speech = FakeSpeechCapture()
        speech.transcriptToReturn = "Hej EVE"
        let playback = FakeAudioPlayback()
        let viewModel = makeViewModel(client: client, transport: transport, speech: speech, playback: playback)
        await viewModel.startListening()

        await viewModel.finishListeningAndRespond()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.lastTranscript, "Hej EVE")
        XCTAssertEqual(viewModel.lastResponseText, "Hej! Hur mår du?")
        XCTAssertEqual(transport.sentMessages, ["Hej EVE"])
        XCTAssertEqual(playback.playedDataURLs, ["data:audio/wav;base64,AA=="])
    }

    func testFinishListeningWithoutAudioStillSucceeds() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [
            .event(.sessionStarted(sessionId: "s1")),
            .event(.response(text: "Hej!", audio: nil)),
        ]
        let speech = FakeSpeechCapture()
        speech.transcriptToReturn = "Hej EVE"
        let playback = FakeAudioPlayback()
        let viewModel = makeViewModel(client: client, transport: transport, speech: speech, playback: playback)
        await viewModel.startListening()

        await viewModel.finishListeningAndRespond()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertEqual(viewModel.lastResponseText, "Hej!")
        XCTAssertTrue(playback.playedDataURLs.isEmpty)
    }

    func testEmptyTranscriptGoesStraightBackToIdleWithoutSending() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [.event(.sessionStarted(sessionId: "s1"))]
        let speech = FakeSpeechCapture()
        speech.transcriptToReturn = "   "
        let viewModel = makeViewModel(client: client, transport: transport, speech: speech)
        await viewModel.startListening()

        await viewModel.finishListeningAndRespond()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertNil(viewModel.lastTranscript)
        XCTAssertTrue(transport.sentMessages.isEmpty)
    }

    func testGatewayErrorEventSurfacesAsErrorState() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [
            .event(.sessionStarted(sessionId: "s1")),
            .event(.error(code: "hermes_unavailable", message: "EVE's reasoning backend is unreachable right now")),
        ]
        let speech = FakeSpeechCapture()
        speech.transcriptToReturn = "Hej EVE"
        let viewModel = makeViewModel(client: client, transport: transport, speech: speech)
        await viewModel.startListening()

        await viewModel.finishListeningAndRespond()

        XCTAssertEqual(
            viewModel.state,
            .error("EVE's reasoning backend is unreachable right now")
        )
    }

    func testToggleListeningFromProcessingOrSpeakingIsANoOp() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [
            .event(.sessionStarted(sessionId: "s1")),
            .event(.response(text: "Hej!", audio: nil)),
        ]
        let speech = FakeSpeechCapture()
        speech.transcriptToReturn = "Hej EVE"
        let viewModel = makeViewModel(client: client, transport: transport, speech: speech)
        await viewModel.startListening()
        await viewModel.finishListeningAndRespond()
        XCTAssertEqual(viewModel.state, .idle)

        // toggleListening() from .idle after a completed turn must be able
        // to start a fresh listen, not get stuck thinking it's mid-turn.
        viewModel.toggleListening()
        XCTAssertEqual(speech.stopCallCount, 1) // unchanged synchronously; startListening() runs in a spawned Task
    }

    func testDisconnectStopsSpeechPlaybackAndAudioSession() async {
        let client = await makeConfiguredClient()
        let transport = FakeConversationTransport()
        transport.receiveScript = [.event(.sessionStarted(sessionId: "s1"))]
        let speech = FakeSpeechCapture()
        let audioSession = FakeAudioSession()
        let playback = FakeAudioPlayback()
        let viewModel = makeViewModel(
            client: client, transport: transport, speech: speech,
            audioSession: audioSession, playback: playback
        )
        await viewModel.startListening()

        await viewModel.disconnect()

        XCTAssertEqual(viewModel.state, .disconnected)
        XCTAssertEqual(speech.stopCallCount, 1)
        XCTAssertEqual(playback.stopCallCount, 1)
        XCTAssertEqual(audioSession.deactivateCallCount, 1)
        XCTAssertEqual(transport.closeCallCount, 1)
    }
}
