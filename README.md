# Language Quest

An iOS-first pixel-art adventure game that teaches Spanish to kids (7+) and teens. Explore Starter Village, talk with its people, finish quests, and practise listening, reading, writing and speaking, with spaced review and a parent dashboard. It has no ads, no energy or hearts, no streaks, and works offline.

**Status: vertical slice v0.1. Not production-ready.** See [What works vs. what's planned](#what-works-vs-whats-planned).

## What's here

- `Packages/LQCore`: all learning and game logic, plus the Spanish course content. Platform-independent; **75 unit tests, all passing**.
- `App/`: SwiftUI + SpriteKit app: onboarding, avatar, explorable village, NPC dialogue, 8 exercise types, journal, bag, review, placement, mastery checks, parent area, StoreKit 2 (disabled).
- `UITests/`: key-flow UI tests and accessibility audits.
- `docs/`: [PRD](docs/PRD.md) · [Competitor research](docs/COMPETITOR_RESEARCH.md) · [Curriculum](docs/CURRICULUM.md) · [Architecture](docs/ARCHITECTURE.md) · [Privacy & child safety](docs/PRIVACY_AND_CHILD_SAFETY.md) · [App Store checklist](docs/APP_STORE_CHECKLIST.md) · [Test plan](docs/TEST_PLAN.md) · [Roadmap & milestones](docs/ROADMAP.md)

## Build and run

Requirements: macOS with **Xcode 16+** (iOS 17 SDK or later) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/marcompsci/LanguageQuest.git
cd LanguageQuest
./scripts/test-core.sh          # 75 logic tests (also: cd Packages/LQCore && swift test)
xcodegen generate               # creates LanguageQuest.xcodeproj
open LanguageQuest.xcodeproj
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

> **First build:** the app target was written in an environment without the iOS SDK. It parses cleanly and was independently reviewed, but it has not been compiled yet. If Xcode reports errors, they should be small type or API fixes. `LQCore` is fully compiled and tested.

### Real device

1. Put your Team ID in `project.yml` → `settings.base.DEVELOPMENT_TEAM`, then run `xcodegen generate`.
2. Select your iPhone and press ⌘R. Signing is automatic.

### TestFlight

1. In App Store Connect, create the app with bundle id `com.phoronomics.languagequest`, category Education.
2. Bump `CURRENT_PROJECT_VERSION` in `project.yml` for each upload, then run `xcodegen generate`.
3. In Xcode, choose Product → Archive (destination "Any iOS Device") → Distribute App → App Store Connect → Upload.
4. In App Store Connect, open TestFlight and add internal testers. For external testers, fill in the test information and use the review notes in [APP_STORE_CHECKLIST.md §7](docs/APP_STORE_CHECKLIST.md).
5. Before any external build: content is marked `authored` (not linguist-reviewed), and text-to-speech stands in for native audio. Label the build "Pilot".

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
