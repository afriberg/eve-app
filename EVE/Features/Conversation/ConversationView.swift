import SwiftUI

/// Turn history view. EVE/Hermes is the source of truth for conversation
/// content (docs/security.md, "Conversation history") — this view only
/// ever renders what a view model hands it; it does not compute, cache
/// beyond UX needs, or persist history itself.
struct ConversationView: View {
    let turns: [ConversationTurn]

    var body: some View {
        List(turns) { turn in
            VStack(alignment: .leading, spacing: 4) {
                Text(turn.speaker == .user ? "Du" : "EVE")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(turn.text)
            }
        }
        .overlay {
            if turns.isEmpty {
                ContentUnavailableView(
                    "Inga meddelanden än",
                    systemImage: "bubble.left.and.bubble.right"
                )
            }
        }
        .navigationTitle("Samtal")
    }
}

#Preview {
    NavigationStack { ConversationView(turns: []) }
}
