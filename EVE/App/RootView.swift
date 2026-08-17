import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            VoiceView()
                .toolbar {
                    // GW-M2 (text conversation) is real; voice (Milestone 3,
                    // VoiceView) is still a state-machine placeholder — this
                    // is the only way to reach a working conversation today.
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            ConversationView()
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
    }
}

#Preview {
    RootView()
}
