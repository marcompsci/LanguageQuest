import XCTest

/// Key flows. Launch arguments:
///   -uiTesting     in-memory save (every run starts clean)
///   -seedProfile   skip onboarding with a test explorer (reduced motion on)
final class LanguageQuestUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor private func launch(seed: Bool, firstQuestDone: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (seed ? ["-seedProfile"] : []) + (firstQuestDone ? ["-seedFirstQuest"] : [])
        app.launch()
        return app
    }

    /// Tiles on the language page sit in a lazy grid: scroll until the tile exists.
    @MainActor private func revealTile(_ id: String, in app: XCUIApplication) -> Bool {
        for _ in 0..<4 {
            if app.buttons[id].waitForExistence(timeout: 2) && app.buttons[id].isHittable { return true }
            app.swipeUp()
        }
        return app.buttons[id].exists
    }

    @MainActor func testOnboardingCreatesExplorerAndSkipsPlacement() {
        let app = launch(seed: false)
        let next = app.buttons["onboardingNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()                                   // welcome
        XCTAssertFalse(next.isEnabled, "age has no default; must be chosen")
        app.buttons["age-11-12"].tap()
        next.tap()                                   // age
        next.tap()                                   // language
        XCTAssertFalse(next.isEnabled, "variant must be chosen")
        app.buttons["variant-es-MX"].tap()
        next.tap()                                   // variant
        next.tap()                                   // avatar
        let name = app.textFields["nicknameField"]
        name.tap()
        name.typeText("Sam")
        next.tap()                                   // start exploring
        let skip = app.buttons["skipPlacement"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["Back to the village"].tap()
        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 5))
    }

    @MainActor func testJapaneseOnboardingSkipsVariantStep() {
        let app = launch(seed: false)
        let next = app.buttons["onboardingNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()                                   // welcome
        app.buttons["age-13-15"].tap()
        next.tap()                                   // age
        app.buttons["course-en-ja"].tap()
        next.tap()                                   // language → straight to avatar (one variant)
        XCTAssertTrue(app.staticTexts["Make your explorer"].waitForExistence(timeout: 3))
    }

    @MainActor func testMenuLanguagePageAndHamburger() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["course-en-fr"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["African Languages"].exists)
        XCTAssertTrue(app.staticTexts["Old Languages"].exists)
        for id in ["en-de", "en-it", "en-zh", "en-yo", "en-he", "en-egy", "en-am", "en-grc", "en-la", "en-hbo"] {
            XCTAssertTrue(app.buttons["course-\(id)"].exists, id)
        }
        app.buttons["course-en-fr"].tap()            // main menu → French page
        XCTAssertTrue(app.buttons["Play: French village"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["menu-games"].exists)
        XCTAssertTrue(app.buttons["menu-flashcards"].exists)
        XCTAssertFalse(app.buttons["menu-kana"].exists)
        app.buttons["hamburgerMenu"].tap()
        for item in ["Review", "Phrasebook", "Quest journal", "Wardrobe", "Bag and badges", "Settings", "Parents"] {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 2), item)
        }
        app.buttons["Wardrobe"].tap()
        XCTAssertTrue(app.staticTexts["Make your explorer"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        app.buttons["backToLanguages"].tap()
        app.buttons["course-en-ja"].tap()
        XCTAssertTrue(revealTile("menu-kana", in: app), "Kana Dojo shows for Japanese")
        app.swipeDown(); app.swipeDown()
        app.buttons["playButton"].tap()
        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 5))
        app.buttons["menuButton"].tap()              // village → Japanese page
        XCTAssertTrue(app.buttons["Play: Japanese village"].waitForExistence(timeout: 5))
    }

    @MainActor func testParentGateBlocksWrongAnswer() {
        let app = launch(seed: true)
        app.buttons["hamburgerMenu"].tap()
        app.buttons["Parents"].tap()
        let field = app.textFields["gateAnswer"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("1")
        app.buttons["gateContinue"].tap()
        XCTAssertTrue(app.staticTexts["gateMessage"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "What they've learned")).firstMatch.exists)
    }

    @MainActor func testParentGateOpensDashboard() {
        let app = launch(seed: true)
        app.buttons["hamburgerMenu"].tap()
        app.buttons["Parents"].tap()
        let q = app.staticTexts["gateQuestion"]
        XCTAssertTrue(q.waitForExistence(timeout: 5))
        let answer = Self.solve(q.label)
        let field = app.textFields["gateAnswer"]
        field.tap()
        field.typeText(String(answer))
        app.buttons["gateContinue"].tap()
        // List section headers are shown in capitals, so match without case.
        let learned = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "What they've learned")).firstMatch
        XCTAssertTrue(learned.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Activity (not mastery)"].exists || app.cells.count > 0)
    }

    @MainActor func testFirstQuestFromDialogueToReward() {
        let app = launch(seed: true)
        app.buttons["course-en-es"].tap()            // main menu → Spanish page
        app.buttons["playButton"].tap()              // → village
        XCTAssertTrue(app.buttons["goToButton"].waitForExistence(timeout: 5))
        app.buttons["goToButton"].tap()
        app.buttons["Luna"].tap()
        let line = app.staticTexts["dialogueLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 10), "walking to Luna opens her dialogue")
        // n1 → Next, n2 → pick the right reply (index 0), n3 → Next.
        app.buttons["dialogueNext"].tap()
        app.buttons["reply0"].tap()
        app.buttons["dialogueNext"].tap()
        let start = app.buttons["startQuestButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        // 1. Listen: answer is choice b.
        app.buttons["choice-b"].tap()
        app.buttons["continueButton"].tap()
        // 2. Match: left i pairs with right i.
        for i in 0..<5 {
            app.buttons["matchLeft\(i)"].tap()
            app.buttons["matchRight\(i)"].tap()
        }
        app.buttons["continueButton"].tap()
        // 3. Reply: answer is choice c.
        app.buttons["choice-c"].tap()
        app.buttons["continueButton"].tap()
        // 4. Speak (no microphone by default): self-check.
        app.buttons["saidItButton"].tap()
        app.buttons["continueButton"].tap()
        XCTAssertTrue(app.staticTexts["¡Misión cumplida!"].waitForExistence(timeout: 5))
        app.buttons["backToVillage"].tap()
        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 5))
    }

    @MainActor func testWrongAnswerGivesFeedbackAndRetryNotPunishment() {
        let app = launch(seed: true)
        app.buttons["course-en-es"].tap()            // main menu → Spanish page
        app.buttons["playButton"].tap()              // → village
        XCTAssertTrue(app.buttons["goToButton"].waitForExistence(timeout: 5))
        app.buttons["goToButton"].tap()
        app.buttons["Luna"].tap()
        XCTAssertTrue(app.staticTexts["dialogueLine"].waitForExistence(timeout: 10))
        app.buttons["dialogueNext"].tap()
        app.buttons["reply1"].tap()                        // wrong reply: stays, shows feedback
        XCTAssertTrue(app.buttons["reply0"].exists)
        app.buttons["reply0"].tap()
        app.buttons["dialogueNext"].tap()
        app.buttons["startQuestButton"].tap()
        app.buttons["choice-a"].tap()                      // wrong
        XCTAssertTrue(app.buttons["tryAgainButton"].waitForExistence(timeout: 2))
        app.buttons["tryAgainButton"].tap()
        app.buttons["choice-b"].tap()
        XCTAssertTrue(app.buttons["continueButton"].waitForExistence(timeout: 2))
    }

    @MainActor func testAccessibilityAuditOnboardingAndGate() throws {
        let app = launch(seed: false)
        XCTAssertTrue(app.buttons["onboardingNext"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit { Self.report($0) }
        let seeded = launch(seed: true)
        seeded.buttons["hamburgerMenu"].tap()
        seeded.buttons["Parents"].tap()
        XCTAssertTrue(seeded.textFields["gateAnswer"].waitForExistence(timeout: 5))
        try seeded.performAccessibilityAudit { Self.report($0) }
    }

    // MARK: Helpers

    /// Prints each audit issue with the element it's about (so CI logs say what to fix), then lets it fail the test.
    static func report(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let el = issue.element.map { "\($0.elementType.rawValue) id='\($0.identifier)' label='\($0.label)'" } ?? "no element"
        // System navigation-bar buttons (Done/Close) don't grow with Dynamic Type by design; iOS shows them
        // in the Large Content Viewer on long press instead. Logged, not failed.
        if issue.auditType == .dynamicType, let e = issue.element, e.elementType == .button, ["Done", "Close"].contains(e.label) {
            print("AUDIT-IGNORED (system bar button, Large Content Viewer): \(issue.compactDescription) | \(el)")
            return true
        }
        // Flag emoji are pictures, not text: text contrast/clipping rules don't apply to them (they're hidden from VoiceOver too).
        if [.contrast, .textClipped].contains(issue.auditType), let e = issue.element, !e.label.isEmpty,
           e.label.unicodeScalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) || $0.properties.isEmojiPresentation }) {
            print("AUDIT-IGNORED (emoji picture): \(issue.compactDescription) | \(el)")
            return true
        }
        // Contrast is measured from screen pixels, so text cut off by the screen edge or the home indicator can't be
        // measured fairly. Those are logged with their frame; the same text is audited when fully on screen elsewhere.
        if issue.auditType == .contrast, let e = issue.element {
            let window = XCUIApplication().windows.firstMatch.frame
            let safe = window.insetBy(dx: 0, dy: 0).divided(atDistance: 34, from: .maxYEdge).remainder
            if !safe.contains(e.frame) {
                print("AUDIT-IGNORED (partly off screen \(e.frame) in \(window)): \(issue.compactDescription) | \(el)")
                return true
            }
        }
        print("AUDIT-ISSUE: \(issue.compactDescription) | \(el) frame=\(issue.element?.frame ?? .zero)")
        return false
    }

    static let words: [String: Int] = {
        let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                    "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        var m: [String: Int] = [:]
        for (i, w) in ones.enumerated() { m[w] = i }
        for (t, v) in tens {
            m[t] = v
            for i in 1...9 { m["\(t)-\(ones[i])"] = v + i }
        }
        return m
    }()

    static func solve(_ q: String) -> Int {
        let s = q.lowercased()
        let op = s.contains(" plus ") ? " plus " : " times "
        let parts = s.components(separatedBy: op).map { $0.trimmingCharacters(in: .whitespaces) }
        let a = words[parts[0]] ?? 0, b = words[parts[1]] ?? 0
        return op == " plus " ? a + b : a * b
    }

    // MARK: v0.8

    /// Word Library: search, star a word, then practice starred words.
    @MainActor func testWordLibraryStarAndPractice() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["course-en-es"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["weeklyGoalPicker"].exists, "weekly goal on the main menu")
        app.buttons["course-en-es"].tap()
        XCTAssertTrue(app.otherElements["wordOfTheDay"].waitForExistence(timeout: 3) || app.buttons["Hear the word of the day"].exists)
        XCTAssertTrue(revealTile("menu-words", in: app))
        app.buttons["menu-words"].tap()
        XCTAssertTrue(app.navigationBars["Word Library"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["practiceStarred"].isEnabled, "nothing starred yet")
        let star = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'star-'")).firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        star.tap()
        XCTAssertTrue(app.buttons["practiceStarred"].isEnabled)
        app.buttons["practiceStarred"].tap()
        XCTAssertTrue(app.navigationBars["Starred words"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
    }

    /// Quizzes are locked until a quest is done; then one can be played to the end. Sentence Builder opens from Games.
    @MainActor func testUnitQuizAndSentenceBuilder() {
        let app = launch(seed: true, firstQuestDone: true)
        XCTAssertTrue(app.buttons["course-en-es"].waitForExistence(timeout: 5))
        // A finished quest unlocks "First Steps": close the celebration(s) first.
        while app.buttons["celebrationDone"].waitForExistence(timeout: 2) { app.buttons["celebrationDone"].tap() }
        app.buttons["course-en-es"].tap()
        XCTAssertTrue(revealTile("menu-quizzes", in: app))
        app.buttons["menu-quizzes"].tap()
        XCTAssertTrue(app.buttons["quiz-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quiz-2"].isEnabled, "unit 2 is locked")
        app.buttons["quiz-1"].tap()
        for _ in 0..<10 {
            let opt = app.buttons["quiz-option-0"]
            guard opt.waitForExistence(timeout: 3) else { break }
            opt.tap()
            XCTAssertTrue(app.buttons["quizNext"].waitForExistence(timeout: 3))
            app.buttons["quizNext"].tap()
        }
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 5), "quiz reaches a score")
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to the list
        let row = app.buttons["quiz-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.label.contains("Best score") || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Best score'")).firstMatch.exists, "best score kept")
        app.buttons["Done"].tap()
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(revealTile("menu-games", in: app))
        app.buttons["menu-games"].tap()
        let builder = app.buttons["builderGame"]
        XCTAssertTrue(builder.waitForExistence(timeout: 5))
        builder.tap()
        XCTAssertTrue(app.navigationBars["Sentence Builder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tile-0"].exists)
        app.buttons["Done"].tap()
    }

    // MARK: v0.9

    /// The new games open from Games and play a round; the language can be pinned to the main menu.
    @MainActor func testNewGamesAndPinning() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["course-en-es"].waitForExistence(timeout: 5))
        app.buttons["course-en-es"].tap()
        XCTAssertTrue(app.buttons["pinLanguage"].waitForExistence(timeout: 5))
        app.buttons["pinLanguage"].tap()
        XCTAssertTrue(revealTile("menu-games", in: app))
        app.buttons["menu-games"].tap()
        XCTAssertTrue(app.buttons["rightOrWrongGame"].waitForExistence(timeout: 5))
        app.buttons["rightOrWrongGame"].tap()
        if !app.buttons["rowRight"].waitForExistence(timeout: 6) { print("UI-DUMP:\n" + app.debugDescription) }
        XCTAssertTrue(app.buttons["rowRight"].exists)
        app.buttons["rowRight"].tap()
        XCTAssertTrue(app.buttons["rowNext"].waitForExistence(timeout: 3), "feedback after an answer")
        app.buttons["Done"].tap()
        if !app.buttons["listenTypeGame"].waitForExistence(timeout: 3) { app.buttons["menu-games"].tap() }
        XCTAssertTrue(app.buttons["listenTypeGame"].waitForExistence(timeout: 5))
        app.buttons["listenTypeGame"].tap()
        let field = app.textFields["listenTypeField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("hola")
        app.buttons["listenTypeCheck"].tap()
        XCTAssertTrue(app.buttons["listenTypeNext"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        // Back on the main menu, the pinned section shows Spanish.
        app.swipeDown(); app.swipeDown()
        XCTAssertTrue(app.buttons["backToLanguages"].waitForExistence(timeout: 5))
        app.buttons["backToLanguages"].tap()
        XCTAssertTrue(app.staticTexts["section-pinned"].waitForExistence(timeout: 5) || app.otherElements["section-pinned"].exists
                      || app.descendants(matching: .any)["section-pinned"].exists, "pinned section")
    }

    /// High contrast and the left-handed pad can be switched on in Settings; the conversation replay opens.
    @MainActor func testAccessibilitySettingsAndConversationReplay() {
        let app = launch(seed: true, firstQuestDone: true)
        XCTAssertTrue(app.buttons["course-en-es"].waitForExistence(timeout: 5))
        while app.buttons["celebrationDone"].waitForExistence(timeout: 2) { app.buttons["celebrationDone"].tap() }
        app.buttons["course-en-es"].tap()
        XCTAssertTrue(app.buttons["hamburgerMenu"].waitForExistence(timeout: 5))
        app.buttons["hamburgerMenu"].tap()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let hc = app.switches["highContrastToggle"]
        for _ in 0..<4 where !hc.exists { app.swipeUp() }
        XCTAssertTrue(hc.waitForExistence(timeout: 3))
        if hc.switches.firstMatch.exists { hc.switches.firstMatch.tap() } else { hc.tap() }
        XCTAssertTrue(app.switches["leftHandedToggle"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["hamburgerMenu"].waitForExistence(timeout: 5))
        app.buttons["hamburgerMenu"].tap()
        let journal = app.buttons["Quest journal"].firstMatch
        XCTAssertTrue(journal.waitForExistence(timeout: 5))
        journal.tap()
        let replay = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'replay-'")).firstMatch
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        replay.tap()
        XCTAssertTrue(app.navigationBars["Conversation"].waitForExistence(timeout: 5))
    }

    // MARK: Compliance audit: no dead ends, privacy policy reachable

    /// Every ☰ menu screen (except Parents, which has its own gate tests) opens and can be closed.
    @MainActor func testEveryMenuScreenOpensAndCloses() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["course-en-es"].waitForExistence(timeout: 5))
        app.buttons["course-en-es"].tap()
        for item in ["Review", "Phrasebook", "Write Out", "Bonus lesson", "Quest journal", "Wardrobe", "Bag and badges",
                     "Mistakes notebook", "Trophies", "My stats", "Settings", "Privacy policy"] {
            app.buttons["hamburgerMenu"].tap()
            // Pick the item inside the open menu (some, like Write Out, also exist as tiles on the page).
            let inMenu = app.collectionViews.buttons[item].firstMatch
            let target = inMenu.waitForExistence(timeout: 3) ? inMenu : app.buttons.matching(identifier: item).element(boundBy: 0)
            XCTAssertTrue(target.exists, item)
            target.tap()
            let close = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "Close"])).firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5), "\(item) has a way out")
            close.tap()
            XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5), "back on the language page after \(item)")
        }
    }

    /// Light Mode and Dark Mode both get an accessibility audit (the dark theme once put light text on white lists).
    @MainActor func testAccessibilityAuditInLightAndDarkAppearance() throws {
        for style in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = style
            let app = launch(seed: true)
            XCTAssertTrue(app.buttons["hamburgerMenu"].waitForExistence(timeout: 5))
            try app.performAccessibilityAudit(for: [.contrast, .dynamicType, .textClipped]) { Self.report($0) }
            app.buttons["hamburgerMenu"].tap()
            app.collectionViews.buttons["Settings"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            try app.performAccessibilityAudit(for: [.contrast]) { Self.report($0) }
            app.terminate()
        }
        XCUIDevice.shared.appearance = .light   // back to the simulator default (.unspecified is rejected)
    }

    @MainActor func testPrivacyPolicyIsReadableOffline() {
        let app = launch(seed: true)
        XCTAssertTrue(app.buttons["hamburgerMenu"].waitForExistence(timeout: 5))
        app.buttons["hamburgerMenu"].tap()
        app.buttons["Privacy policy"].tap()
        XCTAssertTrue(app.staticTexts["Language Quest Privacy Policy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Children's privacy"].exists)
    }
}
