# Language Quest

An iOS-first pixel-art adventure game that teaches Spanish to players aged **10 and up**. Explore Starter Village, talk with its people, finish quests, and practise listening, reading, writing and speaking, with spaced review and a parent dashboard. It has no ads, no energy or hearts, no streaks, and works offline.

**Status: vertical slice v0.1. Not production-ready.** See [What works vs. what's planned](#what-works-vs-whats-planned).

## What's here

- `Packages/LQCore`: all learning and game logic, plus the Spanish course content. Platform-independent; **95 unit tests, all passing**.
- `App/`: SwiftUI + SpriteKit app: onboarding, avatar, explorable village, NPC dialogue, 8 exercise types, journal, bag, review, placement, mastery checks, parent area, StoreKit 2 (disabled).
- `UITests/`: key-flow UI tests and accessibility audits.
- `docs/`: [PRD](docs/PRD.md) · [Competitor research](docs/COMPETITOR_RESEARCH.md) · [Curriculum](docs/CURRICULUM.md) · [Architecture](docs/ARCHITECTURE.md) · [Privacy & child safety](docs/PRIVACY_AND_CHILD_SAFETY.md) · [App Store checklist](docs/APP_STORE_CHECKLIST.md) · [Test plan](docs/TEST_PLAN.md) · [Roadmap & milestones](docs/ROADMAP.md)

## Build and run

Requirements: macOS with **Xcode 16+** (iOS 17 SDK or later) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/marcompsci/LanguageQuest.git
cd LanguageQuest
./scripts/test-core.sh          # 95 logic tests (also: cd Packages/LQCore && swift test)
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
