import SwiftUI

/// See docs/roadmap.md, "Latency metrics" — this view is where those numbers
/// surface once there is a live session to measure. Today it only reflects
/// what is actually knowable client-side; nothing here is faked.
struct DiagnosticsView: View {
    @Environment(GatewayEnvironment.self) private var gatewayEnvironment
    @State private var serverURLText = "-"
    @State private var isPaired = false

    var body: some View {
        Form {
            LabeledContent("Server-URL (aktiv anslutning)", value: serverURLText)
            // Separate from the line above on purpose: this reads the raw
            // UserDefaults value directly, bypassing the actor entirely, to
            // tell apart "never persisted to disk" from "persisted fine, but
            // Settings' own text field isn't picking it up" when debugging
            // the field-appears-empty report.
            LabeledContent("Server-URL (sparat på disk)", value: GatewayEnvironment.persistedServerURLString() ?? "(inget sparat)")
            LabeledContent(
                "TLS-förtroende",
                value: gatewayEnvironment.trustConfigurationError == nil ? "EVE-rot-CA laddad" : "Saknas"
            )
            LabeledContent("Parkopplad", value: isPaired ? "Ja" : "Nej")
            LabeledContent("Voice WebSocket", value: "Ej implementerad (GW-M2+)")
            LabeledContent("Mikrofon", value: "Ej begärt")
            LabeledContent("Ljudväg", value: "-")
            LabeledContent("Session", value: "Ingen")
        }
        .navigationTitle("Diagnostik")
        .task {
            serverURLText = await gatewayEnvironment.apiClient.currentBaseURL?.absoluteString ?? "-"
            isPaired = gatewayEnvironment.makePairingService().hasStoredCredential
        }
    }
}

#Preview {
    NavigationStack { DiagnosticsView() }
        .environment(GatewayEnvironment())
}
