import SwiftUI

/// The app's main screen — push-to-talk (GW-M3, Milestone 3). A name, a
/// single control, and one line of state, as the brief demands (§5).
struct VoiceView: View {
    @Environment(GatewayEnvironment.self) private var gatewayEnvironment
    @State private var viewModel: VoiceViewModel?

    var body: some View {
        VStack(spacing: 32) {
            Text("EVE")
                .font(.largeTitle.bold())

            Button {
                viewModel?.toggleListening()
            } label: {
                Circle()
                    .fill((viewModel?.state ?? .idle).accentColor)
                    .frame(width: 120, height: 120)
            }
            .buttonStyle(.plain)
            .accessibilityLabel((viewModel?.state ?? .idle).label)
            .disabled(viewModel == nil)

            Text((viewModel?.state ?? .idle).label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let transcript = viewModel?.lastTranscript {
                Text("Du: \(transcript)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let response = viewModel?.lastResponseText {
                Text("EVE: \(response)")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .task {
            guard viewModel == nil else { return }
            viewModel = VoiceViewModel(
                apiClient: gatewayEnvironment.apiClient,
                transport: gatewayEnvironment.makeWebSocketClient(),
                speech: SpeechRecognitionService(),
                audioSession: AudioSessionManager(),
                playback: AudioPlaybackService()
            )
        }
        .onDisappear {
            guard let viewModel else { return }
            Task { await viewModel.disconnect() }
        }
    }
}

#Preview {
    VoiceView()
        .environment(GatewayEnvironment())
}
