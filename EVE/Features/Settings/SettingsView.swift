import SwiftUI

/// Deliberately small — this app is built specifically for EVE, not as a
/// general-purpose AI client (brief §28). Server URL / pairing /
/// permissions / diagnostics only.
struct SettingsView: View {
    @State private var serverURL: String = ""

    var body: some View {
        Form {
            Section("EVE Server") {
                TextField("Server-URL", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ConnectionStatusView(state: .unknown)
            }

            Section("Röst") {
                LabeledContent("Mikrofon", value: "Ej begärt")
                LabeledContent("Taligenkänning", value: "Ej begärt")
            }

            Section("Siri / Genvägar") {
                Text("Lägg till \u{201C}Prata med EVE\u{201D} i Genvägar-appen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostik") {
                NavigationLink("Diagnostik") {
                    DiagnosticsView()
                }
            }

            Section("Om") {
                LabeledContent("Version", value: Bundle.main.eveAppVersion)
            }
        }
        .navigationTitle("Inställningar")
    }
}

private extension Bundle {
    var eveAppVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
