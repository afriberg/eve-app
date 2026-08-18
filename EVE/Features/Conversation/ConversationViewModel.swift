import Foundation
import Observation

/// Drives EVE/Features/Conversation/ConversationView (GW-M2 — text
/// conversation, `eve-ios-app` Milestone 2, `docs/roadmap.md`). One
/// synchronous turn per `send(text:)` call: the Gateway's
/// `conversation.message` always gets exactly one `conversation.response`
/// or `error` back, never a partial stream (eve-os
/// `eve/gateway/hermes_client.py` — non-streaming by design at this
/// milestone), so there is no need for a continuous background receive
/// loop here.
@MainActor
@Observable
final class ConversationViewModel {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case sending
        case failed(String)
    }

    private(set) var connectionState: ConnectionState = .idle
    private(set) var turns: [ConversationTurn] = []

    private let apiClient: GatewayAPIClient
    private let transport: ConversationTransport

    init(apiClient: GatewayAPIClient, transport: ConversationTransport) {
        self.apiClient = apiClient
        self.transport = transport
    }

    func connect() async {
        guard connectionState != .connecting, connectionState != .connected else { return }
        connectionState = .connecting
        guard let baseURL = await apiClient.currentBaseURL else {
            connectionState = .failed("Ingen EVE-server konfigurerad. Ställ in den under Inställningar.")
            return
        }
        do {
            let ticket = try await apiClient.createSession()
            try await transport.connect(baseURL: baseURL, ticket: ticket.ticket)
            let started = try await transport.receiveConversationEvent()
            guard case .sessionStarted = started else {
                connectionState = .failed("Oväntat svar från EVE Voice Gateway.")
                return
            }
            connectionState = .connected
        } catch {
            connectionState = .failed(String(describing: error))
        }
    }

    func send(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard connectionState == .connected else { return }

        turns.append(ConversationTurn(id: UUID(), speaker: .user, text: trimmed, timestamp: Date()))
        connectionState = .sending
        do {
            try await transport.sendConversationMessage(trimmed)
            let event = try await transport.receiveConversationEvent()
            switch event {
            case .response(let responseText, _):
                // GW-M3's optional audio field is Voice's concern
                // (VoiceViewModel) — this text-only view never plays it.
                turns.append(
                    ConversationTurn(id: UUID(), speaker: .eve, text: responseText, timestamp: Date())
                )
                connectionState = .connected
            case .error(_, let message):
                connectionState = .failed(message)
            case .sessionStarted, .sessionClosed, .unknown:
                connectionState = .failed("Oväntat svar från EVE Voice Gateway.")
            }
        } catch {
            connectionState = .failed(String(describing: error))
        }
    }

    func disconnect() async {
        try? await transport.sendClose()
        await transport.close()
        connectionState = .idle
    }
}
