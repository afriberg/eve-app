import AppIntents

/// Registers the built-in Siri phrase the moment the app is installed —
/// zero user setup required, and the same declaration makes the intent
/// available to Spotlight, the Shortcuts app, and the Action Button
/// (see docs/ios-integrations.md).
struct EVEShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TalkToEVEIntent(),
            phrases: [
                "Prata med \(.applicationName)",
                "Starta \(.applicationName)",
            ],
            shortTitle: "Prata med EVE",
            systemImageName: "waveform"
        )
    }
}
