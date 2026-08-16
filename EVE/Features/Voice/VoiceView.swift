import SwiftUI

/// The app's main screen. Deliberately as simple as the brief demands (§5):
/// a name, a single control, and one line of state.
struct VoiceView: View {
    @State private var viewModel = VoiceViewModel()

    var body: some View {
        VStack(spacing: 32) {
            Text("EVE")
                .font(.largeTitle.bold())

            Button(action: viewModel.toggleListening) {
                Circle()
                    .fill(viewModel.state.accentColor)
                    .frame(width: 120, height: 120)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.state.label)

            Text(viewModel.state.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    VoiceView()
}
