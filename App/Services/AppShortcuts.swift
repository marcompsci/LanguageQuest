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

/// v1.4: "Quick 3 in Language Quest" for busy days.
struct QuickThreeIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick 3"
    static let description = IntentDescription("Opens Language Quest on a 3-question check.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingShortcut.value = .quickThree
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
        AppShortcut(intent: QuickThreeIntent(),
                    phrases: ["Quick 3 in \(.applicationName)", "Quick quiz in \(.applicationName)"],
                    shortTitle: "Quick 3", systemImageName: "hare.fill")
    }
}

enum PendingShortcut {
    enum Action { case memoryCheck, continueLearning, quickThree }
    @MainActor static var value: Action?
}
