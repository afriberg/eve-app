import Foundation
import Observation

/// Drives the pairing UI in Settings. Owns the bounded poll loop for step 3
/// of the flow (`DevicePairingService.claim`) — an unattended loop must not
/// run forever if the owner never approves (brief: "must not get stuck").
/// `@MainActor` because every `state` mutation drives SwiftUI directly.
@MainActor
@Observable
final class PairingViewModel {
    enum State: Equatable {
        case idle
        case requesting
        case waitingForApproval(requestId: String)
        case paired
        case failed(String)
    }

    private(set) var state: State

    private let pairingService: DevicePairingService
    private var pollTask: Task<Void, Never>?

    /// How many times to poll claim() before giving up and asking the user
    /// to retry explicitly. 40 attempts * 3s ≈ 2 minutes.
    private let maxPollAttempts = 40
    private let pollInterval: Duration = .seconds(3)

    init(pairingService: DevicePairingService) {
        self.pairingService = pairingService
        self.state = pairingService.hasStoredCredential ? .paired : .idle
    }

    func startPairing(deviceName: String, deviceModel: String) {
        pollTask?.cancel()
        state = .requesting
        pollTask = Task { [pairingService] in
            do {
                let requestId = try await pairingService.requestPairing(
                    deviceName: deviceName, deviceModel: deviceModel
                )
                self.state = .waitingForApproval(requestId: requestId)
                await self.pollForApproval(requestId: requestId)
            } catch {
                self.state = .failed(String(describing: error))
            }
        }
    }

    private func pollForApproval(requestId: String) async {
        for _ in 0..<maxPollAttempts {
            if Task.isCancelled { return }
            do {
                try await pairingService.claim(requestId: requestId)
                state = .paired
                return
            } catch DevicePairingService.PairingError.notYetApproved {
                try? await Task.sleep(for: pollInterval)
            } catch {
                state = .failed(String(describing: error))
                return
            }
        }
        state = .failed("Godkännande tog för lång tid. Försök igen när det är godkänt.")
    }

    func cancelPairing() {
        pollTask?.cancel()
        state = .idle
    }

    func forget() {
        pollTask?.cancel()
        try? pairingService.forget()
        state = .idle
    }
}
