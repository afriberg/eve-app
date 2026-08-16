import SwiftUI

/// See docs/roadmap.md, "Latency metrics" — this view is where those numbers
/// surface once there is a live session to measure. Today it only reflects
/// what is actually knowable client-side; nothing here is faked.
struct DiagnosticsView: View {
    var body: some View {
        Form {
            LabeledContent("Backend", value: "Okänt")
            LabeledContent("Voice WebSocket", value: "Ej implementerad")
            LabeledContent("Mikrofon", value: "Ej begärt")
            LabeledContent("Ljudväg", value: "-")
            LabeledContent("Session", value: "Ingen")
        }
        .navigationTitle("Diagnostik")
    }
}

#Preview {
    NavigationStack { DiagnosticsView() }
}
