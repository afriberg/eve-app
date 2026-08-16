import AppIntents

/// "Siri, prata med EVE" — see docs/ios-integrations.md, "Siri / App Intents".
/// This intent only ever opens the app into voice mode; per the brief (§11)
/// Siri must never itself decide what EVE's answer is.
struct TalkToEVEIntent: AppIntent {
    static var title: LocalizedStringResource = "Prata med EVE"
    static var description = IntentDescription("Öppnar EVE och börjar lyssna.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eveStartListeningRequested, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let eveStartListeningRequested = Notification.Name("eveStartListeningRequested")
}
