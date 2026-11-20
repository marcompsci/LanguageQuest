import AppIntents

/// v1.1: "Hey Siri, start a memory check in Language Quest". Opens the app on the memory check.
/// Nothing is sent anywhere: the intent only opens the app.
struct StartMemoryCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a memory check"
    static let description = IntentDescription("Opens Language Quest on a 5-question memory check.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingShortcut.value = .memoryCheck
        return .result()
    }
}

struct OpenTodaysPathIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue learning"
    static let description = IntentDescription("Opens Language Quest on your language page.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingShortcut.value = .continueLearning
        return .result()
    }
}

struct LanguageQuestShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartMemoryCheckIntent(),
                    phrases: ["Start a memory check in \(.applicationName)", "Quiz me in \(.applicationName)"],
                    shortTitle: "Memory check", systemImageName: "brain.head.profile")
        AppShortcut(intent: OpenTodaysPathIntent(),
                    phrases: ["Continue learning in \(.applicationName)", "Open \(.applicationName)"],
                    shortTitle: "Continue learning", systemImageName: "play.fill")
    }
}

enum PendingShortcut {
    enum Action { case memoryCheck, continueLearning }
    @MainActor static var value: Action?
}
