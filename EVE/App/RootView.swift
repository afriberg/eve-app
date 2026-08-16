import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            VoiceView()
                .toolbar {
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
