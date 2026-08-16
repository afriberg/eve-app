import Foundation

/// A single turn in a conversation. The EVE/Hermes backend is the source of
/// truth for conversation history (docs/security.md, "Conversation history") —
/// this type exists only to move data through the client, never to persist a
/// parallel copy of EVE's memory.
struct ConversationTurn: Identifiable, Codable, Equatable {
    enum Speaker: String, Codable {
        case user
        case eve
    }

    let id: UUID
    let speaker: Speaker
    let text: String
    let timestamp: Date
}
