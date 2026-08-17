import SwiftUI
import UIKit

/// Deliberately small — this app is built specifically for EVE, not as a
/// general-purpose AI client (brief §28). Server URL / pairing /
/// permissions / diagnostics only.
struct SettingsView: View {
    @Environment(GatewayEnvironment.self) private var gatewayEnvironment
    @State private var serverURLText: String = ""
    @State private var pairingViewModel: PairingViewModel?
    @State private var connectionMonitor: ConnectionMonitor?

    var body: some View {
        Form {
            Section("EVE Server") {
                TextField("Server-URL (t.ex. https://10.13.13.1:8443)", text: $serverURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(applyServerURL)
                if let connectionMonitor {
                    ConnectionStatusView(state: connectionMonitor.state)
                }
                if gatewayEnvironment.trustConfigurationError != nil {
                    Label(
                        "EVE-rotcertifikatet saknas i appen — anslutning kan aldrig lyckas förrän det läggs till.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.red)
                }
            }

            Section("Ihopparkoppling") {
                pairingSection
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
        .onAppear {
            // Deliberately not part of the `.task` below or the `@State`
            // initial-value expression — both were tried and, on a real
            // device, still left this field empty on repeated visits.
            // `.onAppear` runs synchronously, every time this view appears
            // (including revisiting after popping back from Diagnostics),
            // so there is no async gap for a stale/empty value to show
            // through, regardless of exactly when NavigationStack
            // reinitializes this view's state.
            serverURLText = GatewayEnvironment.persistedServerURLString() ?? ""
        }
        .task {
            let monitor = ConnectionMonitor(client: gatewayEnvironment.apiClient)
            connectionMonitor = monitor
            pairingViewModel = PairingViewModel(pairingService: gatewayEnvironment.makePairingService())
            await monitor.refresh()
        }
        .onDisappear {
            // Saves even if the user never pressed Return on the keyboard —
            // navigating away was silently discarding the typed URL before.
            applyServerURL()
            pairingViewModel?.cancelPairing()
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
        switch pairingViewModel?.state {
        case .none, .idle:
            Button("Parkoppla den här telefonen") {
                pairingViewModel?.startPairing(deviceName: UIDevice.current.name, deviceModel: deviceModelIdentifier())
            }
        case .requesting:
            HStack {
                ProgressView()
                Text("Skickar parkopplingsförfrågan...")
            }
        case .waitingForApproval:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView()
                    Text("Väntar på godkännande från EVE-ägaren...")
                }
                Button("Avbryt", role: .cancel) {
                    pairingViewModel?.cancelPairing()
                }
            }
        case .paired:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Den här telefonen är parkopplad.")
                Spacer()
                Button("Glöm", role: .destructive) {
                    pairingViewModel?.forget()
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.red)
                Button("Försök igen") {
                    pairingViewModel?.startPairing(deviceName: UIDevice.current.name, deviceModel: deviceModelIdentifier())
                }
            }
        }
    }

    private func applyServerURL() {
        guard let url = URL(string: serverURLText) else { return }
        // Written synchronously so it's on disk before this function returns
        // — not deferred into the Task below, which the app has no
        // guarantee will finish before this view is torn down (a fresh
        // instance is pushed each time Settings is opened, reading this
        // same persisted value back at init time; see `serverURLText`'s
        // initial value above).
        GatewayEnvironment.persistServerURLString(url.absoluteString)
        Task {
            await gatewayEnvironment.configureServer(baseURL: url, persistToDisk: false)
            await connectionMonitor?.refresh()
        }
    }

    /// Standard `utsname`-based device identifier (e.g. "iPhone16,2") — used
    /// only as a human-readable label at pairing time, sent to the Gateway
    /// so the owner can tell devices apart in `GET /v1/devices`.
    private func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier += String(UnicodeScalar(UInt8(value)))
        }
    }
}

private extension Bundle {
    var eveAppVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(GatewayEnvironment())
}
