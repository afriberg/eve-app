import SwiftUI

/// Simple connection indicator per the brief's §27 example ("EVE ● Connected").
/// Detailed diagnostics live in Features/Settings/DiagnosticsView.
struct ConnectionStatusView: View {
    let state: ConnectionState

    var body: some View {
        Label(state.label, systemImage: state.symbolName)
            .foregroundStyle(state.tintColor)
            .font(.subheadline)
    }
}

private extension ConnectionState {
    var label: String {
        switch self {
        case .unknown: return "Okänd"
        case .connected: return "Ansluten"
        case .offline: return "Frånkopplad"
        case .unauthenticated: return "Ej parkopplad"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .connected: return "circle.fill"
        case .offline: return "circle"
        case .unauthenticated: return "exclamationmark.triangle"
        }
    }

    var tintColor: Color {
        switch self {
        case .unknown: return .secondary
        case .connected: return .green
        case .offline: return .secondary
        case .unauthenticated: return .orange
        }
    }
}

#Preview {
    ConnectionStatusView(state: .connected)
}
