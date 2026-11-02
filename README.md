# Language Quest

An iOS-first pixel-art adventure game that teaches **Spanish, French and Japanese** to players aged **10 and up**. Explore Starter Village, talk with its people, finish quests, and practise listening, reading, writing and speaking, with spaced review and a parent dashboard. It has no ads, no energy or hearts, no streaks, and works offline.

**Status: vertical slice v0.1. Not production-ready.** See [What works vs. what's planned](#what-works-vs-whats-planned).

## What's here

- `Packages/LQCore`: all learning and game logic, plus the Spanish, French and Japanese courses. Platform-independent; **106 unit tests, all passing**.
- `App/`: SwiftUI + SpriteKit app: onboarding, avatar, explorable village, NPC dialogue, 8 exercise types, journal, bag, review, placement, mastery checks, parent area, StoreKit 2 (disabled).
- `UITests/`: key-flow UI tests and accessibility audits.
- `docs/`: [PRD](docs/PRD.md) · [Competitor research](docs/COMPETITOR_RESEARCH.md) · [Curriculum](docs/CURRICULUM.md) · [Architecture](docs/ARCHITECTURE.md) · [Privacy & child safety](docs/PRIVACY_AND_CHILD_SAFETY.md) · [App Store checklist](docs/APP_STORE_CHECKLIST.md) · [Test plan](docs/TEST_PLAN.md) · [Roadmap & milestones](docs/ROADMAP.md)

## Build and run

Requirements: macOS with **Xcode 16+** (iOS 17 SDK or later) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/marcompsci/LanguageQuest.git
cd LanguageQuest
./scripts/test-core.sh          # 106 logic tests (also: cd Packages/LQCore && swift test)
open LanguageQuest.xcodeproj    # committed; regenerate with `xcodegen generate` after editing project.yml
```

### Simulator

1. In Xcode, choose the **LanguageQuest** scheme and an iPhone simulator (e.g. iPhone 16).
2. Press ⌘R. A first launch shows onboarding.
3. To test purchases locally (only after enabling paid plans), the scheme already points at `App/Resources/LanguageQuest.storekit`.
4. Press ⌘U to run the UI tests. They use `-uiTesting` (in-memory save) and `-seedProfile`.

Command line:

```bash
xcodebuild -project LanguageQuest.xcodeproj -scheme LanguageQuest \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project LanguageQuest.xcodeproj -scheme LanguageQuest \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

> **Build status:** v0.2 builds in Xcode and runs on a physical iPhone (2 Nov 2026). `LQCore` is fully compiled and tested. The project is preset to Apple team X6LZQ3FS36.

### Real device

1. Put your Team ID in `project.yml` → `settings.base.DEVELOPMENT_TEAM`, then run `xcodegen generate`.
2. Select your iPhone and press ⌘R. Signing is automatic.

### TestFlight

1. In App Store Connect, create the app with bundle id `com.phoronomics.languagequest`, category Education.
2. Bump `CURRENT_PROJECT_VERSION` in `project.yml` for each upload, then run `xcodegen generate`.
3. In Xcode, choose Product → Archive (destination "Any iOS Device") → Distribute App → App Store Connect → Upload.
4. In App Store Connect, open TestFlight and add internal testers. For external testers, fill in the test information and use the review notes in [APP_STORE_CHECKLIST.md §7](docs/APP_STORE_CHECKLIST.md).
5. Before any external build: content is marked `authored` (not linguist-reviewed), and text-to-speech stands in for native audio. Label the build "Pilot".

## What's new in v0.2 (10+ update)

1. **Ages 10+.** The 7–9 band is gone. Old saves with "7-9" load as 10–12. Theme: Playful for 10–12, Explorer for 13+.
2. **Chiptune sound and music.** Original tunes and effects synthesized on device, with separate music and sound settings.
3. **Livelier village.** Walking animation, shadows, dust puffs, villagers who glance around, bouncing quest markers. All of it turns off with Reduce Motion.
4. **Word Battles.** Friendly duels against Mateo, Nico, Don Pepe and Profe Sol. Answers charge a spark meter, and every mistake gets a coaching tip instead of a penalty.
5. **Word Scramble.** Puzzle Academy spelling game built from the words you've met.
6. **Market Rush.** Read a Spanish shopping list, pick the items, pay the exact amount in your variant's currency.
7. **Lost words.** 10 hidden word treasures with fun facts, collected in a treasure book.
8. **Quest tracker.** An arrow and step count point to the next quest; tap it to walk there.
9. **Phrasebook.** Every word you've met, searchable in Spanish (any region's form) or English, with audio, mastery level, and how other regions say it.
10. **Parent PIN.** Optional; a salted hash is stored in the Keychain. Teens can solve the math gate, so this keeps parent settings for parents. Forgot your PIN? The device passcode resets it.

## v0.7: levels, challenges and word games

1. **Explorer levels.** XP turns into levels (100 XP, then +50 more per level) with titles from Newcomer to Legend, and a celebration on level-up.
2. **Daily challenges.** Three small goals a day (same all day), +15 XP each. Nothing is lost if you skip a day.
3. **Achievements.** Ten trophies (First Steps, World Traveler, Scribe, Speedster, Treasure Hunter, Card Shark…) in a Trophies screen.
4. **Echo.** Hear a word, pick how it's written.
5. **Memory Match.** Pair six words with their meanings; stars for fewer moves.
6. **Spelling Bee.** Hear a word, type it (Latin spelling works for other scripts; missing accents get a gentle note).
7. **Mistakes notebook.** Your most-missed words in the current language, with a multiple-choice retry.
8. **My stats.** Activities over the last 7 days and words per language by mastery level.
9. **Juice.** Vibration on right and wrong answers (follows the sound-effects setting) and confetti for celebrations (off with Reduce Motion).
10. **Easy-read text.** An optional setting with wider letter and line spacing and no faded grey text.

## v0.6: ages 11+, writing, bonus lessons

- **Ages 11+.** Bands are now 11–12, 13–15 and 16+; older saves ("7-9", "10-12") load as 11–12. Everyone starts with the sleeker Explorer look.
- **Smoother voices.** The app picks the most natural voice installed (Premium, then Enhanced), avoids robotic novelty voices, and speaks sentence by sentence with short pauses. Settings shows which voice is used and how to download a better one (Apple's free Enhanced/Premium voices).
- **Multiple-choice flashcards.** Every flashcard (deck and the menu's quick card) asks you to pick the meaning from four choices; you can still tap to peek.
- **Bonus lesson.** A daily 6-activity lesson on the main menu: finished-quest practice (due words first) plus a sneak peek at the next quest's words. +25 XP once a day per language.
- **Write Out.** Trace, copy, then write words from memory on a canvas, with pen, eraser (scribble out), undo and clear. The screen can turn to landscape for more room. Latin-alphabet languages have a Print/Cursive switch, and every language has a Letters row (alphabet, kana, Greek, Hebrew, Fidel). Handwriting is checked on-device with Vision where it supports the language (Spanish, French, German, Italian, Latin, Chinese, Japanese, plus Latin-letter spellings); otherwise you compare with the example.
- **Better village.** Richer tiles with variation, tree shadows, glinting water, a soft vignette, petals by day and fireflies at night, lit windows and a lantern glow after dark (particles off with Reduce Motion).
- **Speed duels.** An opt-in Word Battle mode with a 5-second bonus window and a tougher rival. Running out of time never costs points; Classic stays timer-free.

## v0.4: menu and languages

The app now opens on a **main menu**: Play, your three languages with flags and progress (tap one to switch), a Today card, and buttons for Games, Flashcards, Review, Phrasebook, Kana Dojo (Japanese), Quest journal, Wardrobe, Bag, Settings and Parents. In the village, the house button goes back to the menu and the flag button switches language. Also new: flashcards, the Kana Dojo, a day/night tint, a lesson theme for each language (reggaeton, a Paris waltz, Tokyo pop) and badges per language.

## Languages (v0.5)

The main menu lists languages in three sections. Pick one to open its page; your progress in each is kept.

| Section | Course | Size | Notes |
|---|---|---|---|
| Choose a language | Spanish (6 regional varieties) | 3 units · 15 quests | |
| | French (France, Québec) | 3 units · 15 quests | |
| | Japanese | 3 units · 15 quests | Kana with romaji; Kana Dojo |
| | German | Starter: 1 unit · 5 quests | |
| | Italian | Starter | |
| | Chinese (Mandarin, simplified) | Starter | Characters with pinyin; type either |
| African Languages | Yoruba | Starter | Tone marks optional when typing; no iOS voice, so audio reads the spelling with an English voice |
| | Hebrew (modern) | Starter | Right to left, Latin spelling underneath |
| | Ancient Egyptian (Middle Egyptian) | Starter | Egyptologists' pronunciation (em hotep, nefer); read with an English voice |
| | Amharic | Starter | Ge'ez (Fidel) script with Latin spelling; no iOS voice, so audio reads the spelling |
| Old Languages | Ancient Greek (Attic) | Starter | Read aloud with a modern Greek voice |
| | Latin (Classical) | Starter | Read aloud with an Italian voice |
| | Biblical Hebrew | Starter | Vowel points; read aloud with a modern Hebrew voice |

Starter units cover greetings, names, how are you, polite words and numbers 1–10, with a mastery check. Hebrew appears twice on purpose: modern Hebrew under African Languages (as requested) and Biblical Hebrew under Old Languages. Every non-Latin string has an authored Latin spelling (tested). **All courses are authored by the dev team and not yet reviewed by native speakers or specialists; the ancient languages especially need a specialist's check.**

The main menu also shows a **Recent lesson** card: the last quest you practiced, a Continue button, and a quick flashcard from words you've already met (it records into the right language even if you've switched).

## Editing content

The Spanish course is generated from `tools/content-authoring/*.py`:

```bash
./tools/content-authoring/build.sh   # regenerates JSON and runs the content tests
```

The validator rejects broken content: missing answers, unreachable dialogue, placeholder text, fewer than 3 activity types per quest, missing alt text, and so on. See [CURRICULUM.md](docs/CURRICULUM.md).

## What works vs. what's planned

| Works (tested in LQCore) | Built, needs validation | Planned / not done |
|---|---|---|
| Content loading and validation, 6 Spanish variants | iOS app UI (not yet compiled) | Native audio recordings |
| Answer checking (accents, regional forms, typos) | UI tests (not yet run) | Linguist review |
| Spaced review with comprehension and production tracked separately | On-device speech recognition | Conversation Town and later worlds |
| Placement, retention, and mastery checks | Text-to-speech voices per variant | Word Battles, Puzzle Academy, mini-games |
| Progression, XP, cosmetics, badges (no streaks) | | Family and classroom co-op (preset messages) |
| Versioned offline saves, backup, migration | | Parent PIN, Declared Age Range API |
| Parental gate, purchase gating, entitlements (paid plans off) | | Legal review (COPPA, state laws) |
| Village map, collision, A* pathfinding | | French and Japanese |

Language Quest makes no claims of App Store approval, COPPA compliance, language proficiency, or production readiness. Those require the validation steps in [ROADMAP.md](docs/ROADMAP.md).
