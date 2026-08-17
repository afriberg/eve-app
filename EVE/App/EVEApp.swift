import SwiftUI

@main
struct EVEApp: App {
    @State private var gatewayEnvironment = GatewayEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(gatewayEnvironment)
                .task {
                    await gatewayEnvironment.restoreStoredServerURL()
                    await gatewayEnvironment.restoreStoredCredential()
                }
        }
    }
}
