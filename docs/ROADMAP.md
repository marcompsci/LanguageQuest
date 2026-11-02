# Roadmap and Milestone Plan

Status key: ✅ done and tested · 🟡 built, needs device or expert validation · ⬜ planned

## Milestone 0: Foundations ✅
- New repo, XcodeGen project, `LQCore` Swift package, test script.
- **Acceptance:** `swift test` runs on macOS and Linux; `xcodegen generate` produces a project with app and UI-test targets.

## Milestone 1: Core engine ✅
- Content models with regional variants; validator; answer checker; spaced scheduler with comprehension and production tracks; progression and rewards; saves with backup and migration; entitlement logic; parental gate; tile map with A*.
- **Acceptance:** every rule in CURRICULUM.md and PRIVACY_AND_CHILD_SAFETY.md that can be expressed in logic has a unit test; 75 tests green.

## Milestone 2: Spanish content, Units 1–3 🟡
- 15 quests and 68 activities across 8 types; mastery checks; cultural notes; 6 variants.
- **Acceptance:** the validator passes; every answer key passes in every variant (✅).
- **Still needed:** native-speaker linguist sign-off per variant, and native audio recordings.

## Milestone 3: Playable vertical slice 🟡
- Onboarding, avatar, Starter Village (SpriteKit), NPC dialogue, quest player, eight exercise views, journal, bag, review, placement, mastery check, parent area, StoreKit service (off).
- **Acceptance:**
  - (a) builds in Xcode 16 for iOS 17;
  - (b) the 6 UI tests pass on the iPhone 16 simulator;
  - (c) a child can finish Unit 1 without adult help;
  - (d) VoiceOver can complete quest 1 using "Go to".
- **Status:** builds in Xcode and runs on a physical iPhone (v0.2, 2 Nov 2026). **Next action:** run the UI tests and play-test on device.

## Milestone 4: Polish and accessibility pass ⬜
- Fix accessibility-audit findings; Dynamic Type at AX3 layouts; landscape layout on iPad; original sound effects (synthesised, no licensed audio); NPC walking animation frames; parent PIN in the Keychain; a "voices on this device" readout for parents.
- **Acceptance:** zero audit issues on onboarding, quest, review, and parent screens; manual VoiceOver walk-through passes.

## Milestone 5: Content release readiness ⬜
- Linguist review per variant; record native audio (`audioFile` per item and dialogue line); mark units `released`.
- **Acceptance:** `ContentValidator.validate(_, releaseBuild: true)` passes; an audio file exists for every item and line, in every variant offered.

## Milestone 6: Legal and store readiness ⬜
- Children's privacy legal review; privacy policy; category decision (APP_STORE_CHECKLIST §1); Declared Age Range API integration (iOS 26) with fallback; age rating questionnaire.
- **Acceptance:** written legal sign-off; TestFlight external review passes; App Privacy label is "Data Not Collected".

## Milestone 7: TestFlight family pilot ⬜
- 2-week pilot across age bands, measuring retention, mastery-check pass rate, and parent dashboard comprehension.
- **Acceptance:** pilot report; top issues fixed.

## Milestone 3b: v0.2 "10+ update", 10 phases 🟡
| # | Phase | Acceptance | Status |
|---|---|---|---|
| 1 | Retarget to ages 10+ | No 7–9 band; old saves migrate; tests | ✅ tested |
| 2 | Chiptune music and sound effects | Every effect is audible and ends; music loops in sync; separate settings | ✅ core tested · 🟡 device audio |
| 3 | Walk cycle, shadows, ambient life | Off under Reduce Motion | 🟡 device check |
| 4 | Word Battles | Questions well formed for every opponent and seed; mistakes never cost points; 4 in a row wins | ✅ core tested |
| 5 | Word Scramble | Every puzzle solvable and actually scrambled, in every variant | ✅ core tested |
| 6 | Market Rush | Every order payable with coins; basket and payment checks | ✅ core tested |
| 7 | Hidden word treasures | 10 unique, reachable spots; saved in the treasure book | ✅ core tested |
| 8 | Quest tracker | Correct 8-way headings; tap walks there | ✅ core tested |
| 9 | Phrasebook | Accent-insensitive search across all regions' forms and English | ✅ core tested |
| 10 | Parent PIN | SHA-256 vectors; trivial PINs rejected; lockout | ✅ core tested |

## Milestone 3c: v0.4 "menu and languages", 10 phases 🟡
| # | Phase | Acceptance | Status |
|---|---|---|---|
| 1 | Main menu | Launch opens a menu when an explorer exists; Play goes to the village; house button returns | ✅ builds and runs on iPhone · 🟡 UI test written |
| 2 | One-tap language switching | Flags with progress on the menu, a flag button in the village HUD, and Settings; progress kept per language | ✅ core tested (parked progress shown) · 🟡 UI test written |
| 3 | Today card | Activities today, words due for review; never mentions streaks or losing | ✅ core tested |
| 4 | Explorer settings | Sound, text, romaji, variety, look without the parent gate; data, money, permissions and break reminders stay behind it | 🟡 device check |
| 5 | Wardrobe | Avatar editor and earned items in one place | 🟡 device check |
| 6 | Flashcards | Due words first; new learners still get a deck; feeds spaced review | ✅ core tested |
| 7 | Kana Dojo (Japanese) | 4 distinct options every question, hiragana and katakana; best stars saved | ✅ core tested |
| 8 | Day and night | Village tint follows the device clock; night stays readable | ✅ core tested · 🟡 device look |
| 9 | Lesson music per language | Reggaeton (Spanish), Paris waltz (French), Tokyo pop (Japanese); tracks loop in sync | ✅ core tested · 🟡 heard on device |
| 10 | Per-language badges | Unit and mastery badges are earned once per language and named for it | ✅ core tested |

## Later: game and curriculum expansion ⬜
- **Conversation Town** (Units 4–6: school, home, hobbies), then Adventure City, Explorer Academy, Quest Kingdom, Mastery Realm. Worlds are data: a new map plus NPC files.
- **Word Battles 2:** listening and speaking rounds, plus new opponents per world.
- **Puzzle Academy 2:** grammar and sentence-ordering puzzles (Word Scramble shipped in v0.2).
- **Mini-games in Spanish:** soccer (commands and numbers), cooking (food and imperatives), treasure hunt (directions), shopping (money), travel (transport), racing (left/right and fast/slow).
- **Family and classroom co-op:** same device, or family-only via Game Center friends; **preset messages only**; no stranger matching.
- **More variants:** vosotros unit for Spain; Chile and Peru variants after linguist review.
- **French and Japanese:** authored in v0.3 (3 units each). Next: linguist review, native audio, and kanji with furigana for older learners (kana-reading Kana Dojo shipped in v0.4).
- **Monetisation:** turn on Family Plus only after legal, technical, and unit-economics review (PRD §6).
- **Android:** reuse the JSON content and the LQCore test vectors.

## What is mocked, unfinished, or legally unreviewed (as of this build)

| Item | State |
|---|---|
| iOS app target | Builds and runs on iPhone (v0.2); needs device play-testing |
| UI tests | Written (menu and language-switch test added in v0.4), not yet run |
| Spanish content | Authored by the dev team; **not linguist-reviewed** (marked `authored`) |
| Audio | **Text-to-speech placeholder**; no native recordings |
| Speech recognition | Implemented (on-device only), **untested on device**; locale support varies by device |
| Paid plans / StoreKit | Implemented and **disabled**; StoreKit config for local testing only; not legally or economically reviewed |
| COPPA, state-law, and Apple Kids analysis | Design-level only; **no legal review** |
| Declared Age Range API | Not implemented (parent PIN shipped in v0.2) |
| Sound effects and music | Synthesized chiptune (v0.2); not yet heard on device |
| Conversation Town and later worlds, more mini-games (soccer, cooking, travel, racing), co-op | Not implemented (Word Battles, Word Scramble and Market Rush shipped in v0.2) |
| French and Japanese | Authored (v0.3), tested, running on device; **not linguist-reviewed** |
