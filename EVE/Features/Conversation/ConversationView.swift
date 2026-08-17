import SwiftUI

/// Turn history + text input (GW-M2 — `eve-ios-app` Milestone 2). EVE/Hermes
/// is the source of truth for conversation content (docs/security.md,
/// "Conversation history") — this view only ever renders what
/// `ConversationViewModel` hands it; it does not compute, cache beyond UX
/// needs, or persist history itself.
struct ConversationView: View {
    @Environment(GatewayEnvironment.self) private var gatewayEnvironment
    @State private var viewModel: ConversationViewModel?
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if let viewModel {
                List(viewModel.turns) { turn in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(turn.speaker == .user ? "Du" : "EVE")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(turn.text)
                    }
                }
                .overlay {
                    if viewModel.turns.isEmpty {
                        ContentUnavailableView(
                            "Inga meddelanden än",
                            systemImage: "bubble.left.and.bubble.right"
                        )
                    }
                }

                statusBanner(for: viewModel.connectionState)
                inputBar(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Samtal")
        .task {
            guard viewModel == nil else { return }
            let model = ConversationViewModel(
                apiClient: gatewayEnvironment.apiClient,
                transport: gatewayEnvironment.makeWebSocketClient()
            )
            viewModel = model
            await model.connect()
        }
        .onDisappear {
            guard let viewModel else { return }
            Task { await viewModel.disconnect() }
        }
    }

    @ViewBuilder
    private func statusBanner(for state: ConversationViewModel.ConnectionState) -> some View {
        switch state {
        case .idle, .connected:
            EmptyView()
        case .connecting:
            HStack {
                ProgressView()
                Text("Ansluter...")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        case .sending:
            HStack {
                ProgressView()
                Text("EVE svarar...")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.horizontal)
        }
    }

    private func inputBar(viewModel: ConversationViewModel) -> some View {
        HStack {
            TextField("Skriv ett meddelande...", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { sendDraft(viewModel: viewModel) }
            Button {
                sendDraft(viewModel: viewModel)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func sendDraft(viewModel: ConversationViewModel) {
        let text = draft
        draft = ""
        Task { await viewModel.send(text: text) }
    }
}

#Preview {
    NavigationStack { ConversationView() }
        .environment(GatewayEnvironment())
}
