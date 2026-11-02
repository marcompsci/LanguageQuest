# Architecture

## 1. Repository inspection (starting point)

The repository was new and empty, apart from a README, when this work began. There was no existing architecture to preserve. Your other repos (HopQuest and the 2023 Spanish-Vocab-Calender) were looked at for context only; no code was copied.

## 2. Stack decision: SwiftUI + SpriteKit (native)

| Option | For | Against |
|---|---|---|
| **SwiftUI + SpriteKit** ✅ | No runtime to ship; small app size; first-class VoiceOver and Dynamic Type for all menus and lessons; native StoreKit 2, Speech, and AVSpeechSynthesizer; crisp pixel art with nearest-neighbour textures; one language (Swift) for game and logic; Swift Playgrounds and Xcode friendly | iOS only; SpriteKit is a 2D engine with a small ecosystem; Android later means a port |
| Unity | Cross-platform; big asset ecosystem | Large binary; accessibility of game UI is weak without extra work; per-seat licensing; StoreKit and Speech need plugins; third-party SDKs are a risk for kids' privacy |
| Godot 4 | Free, cross-platform, good 2D | iOS export, accessibility, and StoreKit integration need custom native plugins; smaller iOS track record |
| React Native or Flutter + game canvas | Shared UI code with Android | Game loop and pixel rendering are second-class; more bridging for Speech and StoreKit |

**Decision.** The game is tile-based 2D with modest animation, and most screens are lessons, menus and dashboards, where SwiftUI's accessibility shines. SpriteKit covers smooth 60 fps pixel movement. This is the simplest architecture that does the job. Every learning rule lives in a platform-independent Swift package (`LQCore`) that builds and tests on macOS, iOS and Linux. That keeps it testable, and it can be reused if an Android port (for example via Swift on Android, or a rewrite against the same JSON content and test vectors) is ever needed.

## 3. Layout

```
LanguageQuest/
├── project.yml                     XcodeGen spec (app + UI tests)
├── App/                            iOS app (SwiftUI + SpriteKit)
│   ├── LanguageQuestApp.swift      entry point, RootView
│   ├── AppModel.swift              app state, persistence, services
│   ├── Theme.swift                 colours from LQCore palettes, button styles
│   ├── Game/
│   │   ├── PixelArt.swift          original pixel art drawn in code (characters, tiles)
│   │   └── VillageScene.swift      SpriteKit scene: tiles, NPCs, movement, camera
│   ├── Views/                      onboarding, world HUD, dialogue, quest player,
│   │   │                           journal, bag, review, placement, mastery, parent area
│   │   └── Activities/             ActivityHost + the eight exercise views
│   ├── Services/                   SpeechService (TTS), SpeechRecognitionService
│   │                               (on-device only), StoreService (StoreKit 2)
│   └── Resources/                  asset catalog, StoreKit test config, privacy manifest
├── Packages/LQCore/                platform-independent logic + content (unit-tested)
│   └── Sources/LQCore/
│       ├── Content/                models, variant text, loader, validator
│       ├── Assessment/             answer checking, placement, mastery, retention, parent report
│       ├── Review/                 spaced scheduler, learner model, review planner
│       ├── Progress/               profile, saves + migration, progression, reward catalog
│       ├── Dialogue/               deterministic dialogue runner
│       ├── Entitlements/           plans, feature gate, entitlement resolver, purchase gate
│       ├── Privacy/                parental gate, data export/delete, privacy notice
│       ├── World/                  tile map, A*, grid movement, Starter Village data
│       ├── Theme/                  palettes + WCAG contrast
│       └── Resources/Content/en-es course JSON
├── UITests/                        XCUITest key flows + accessibility audits
├── tools/                          content authoring scripts, icon generator
└── docs/
```

## 4. Modules (the spec's list → where it lives)

| Module | Implementation | Tests |
|---|---|---|
| Game world and scene engine | `World/TileMap`, `GridMover`, `StarterVillage` (data, collision, A*); `App/Game/VillageScene` (rendering, input, camera) | `WorldTests` |
| Curriculum and content management | `Content/*` with JSON course packs and a validator | `ContentTests` |
| Dialogue engine | `Dialogue/DialogueRunner`: authored trees only, no free text | `ContentTests` |
| Assessment and spaced review | `Assessment/*`, `Review/*` | `AnswerCheckerTests`, `SchedulerTests`, `AssessmentFlowTests` |
| Audio and speech | `App/Services/SpeechService` (TTS per variant), `SpeechRecognitionService` (on-device only) | Manual device QA (TEST_PLAN §4) |
| Player progress and saves | `Progress/Profile`, `SaveStore` (versioned, atomic, backup, migration), `Progression` | `SaveLoadTests`, `ProgressionTests` |
| Parent dashboard | `Assessment/ParentReport` (data); `App/Views/ParentAreaView` | `AssessmentFlowTests`, UI tests |
| Accessibility and localisation | `Theme/Palette` (contrast-tested); VoiceOver labels; Dynamic Type; reduced motion; "Go to" navigation; course packs are per language | `AccessibilityAndPrivacyTests`, UI accessibility audit |
| Subscription entitlement | `Entitlements/*` (pure logic); `App/Services/StoreService` (StoreKit 2) | `PurchaseGatingTests` |
| Privacy and consent | `Privacy/*`, `ParentSettings` (speech consent, purchases allowed), no-network scan | `AccessibilityAndPrivacyTests`, `SaveLoadTests` |
| Testing and observability | XCTest + XCUITest. Observability is deliberately **on-device only**: errors surface as on-screen notices, and there is no telemetry SDK | All |

## 5. Data flow

1. **Launch.** `AppModel` loads the bundled course (`ContentLibrary.bundledSpanish()`), validates it, and loads `FamilySave` from Application Support. With no profile, the app shows onboarding.
2. **World.** `VillageScene` asks `GridMover` and `TileMap` whether each step is legal. Tap-to-walk and "Go to" use `TileMap.path` (deterministic A*). Talking to an NPC → `Progression.quest(offeredBy:)` → `DialogueRunner` → quest sheet.
3. **Activities.** `ActivityHost` checks answers with `AnswerChecker`, gives feedback, and reports a `ReviewOutcome`. `Progression.complete` updates both learner-model tracks for every item, awards XP and rewards once, and logs the day's activity.
4. **Saves.** Every change persists through `FileSaveStore`: atomic write, the previous file kept as a backup, and iOS file protection.
5. **Parent area.** `ParentGateView` → `ParentReport.build` (pure) → dashboard.

## 6. Persistence and offline

- Local-first: a single `family.json` (`FamilySave`, schema v2) plus `family.backup.json`.
- `SaveMigrator` upgrades v1 saves. Unknown future versions throw rather than being overwritten.
- If the main file is corrupt, the backup is used. If both are bad, the app starts fresh in memory **without** overwriting the files, and tells the user.
- All content ships in the bundle. Core gameplay needs no network: the core package has no networking APIs, which a test checks.
- Network-dependent features are optional: the App Store (only if paid plans are ever enabled) and on-device speech model downloads handled by iOS.
- No API keys exist, and none may be added to the client.

## 7. Security

- File protection: `.completeFileProtectionUntilFirstUserAuthentication` on iOS.
- No accounts. If adult accounts are ever added (for example cloud sync), use Sign in with Apple, store tokens in the Keychain, use TLS only, and authorise access by role (parent versus child profile), as PRIVACY_AND_CHILD_SAFETY.md specifies.
- StoreKit: only `VerificationResult.verified` transactions are mapped to entitlements. Revoked, expired and upgraded transactions are ignored (tested).

## 8. Performance notes

- The village is about 770 tile sprites with cached textures and `ignoresSiblingOrder`. The ambient animation is disabled under reduced motion.
- Pixel textures are generated once at launch from small character maps. They could be moved to an asset catalog later without changing game logic.

## 9. Known limitations (honest)

- The app target was written without access to an iOS SDK in the authoring environment. It parses cleanly and was independently reviewed, but **the first Xcode build may surface compiler errors** to fix. LQCore itself is compiled and tested (75 tests).
- One world (Starter Village). Conversation Town and the later worlds are data and roadmap only.
- There is no sound-effects engine yet. Feedback uses haptics (`sensoryFeedback`), and voice uses text-to-speech.
