# Test Plan

## 1. Automated: LQCore unit tests (75 tests; all pass)

Run with `./scripts/test-core.sh`, or `cd Packages/LQCore && swift test` (macOS or Linux).

| Suite | What it proves |
|---|---|
| `ContentTests` (15) | 3 units and 15 quests load; the validator finds no errors; ≥3 activity types per quest; every unit covers 4 skills × 3 modes × guided and independent; content is marked unreviewed, so **release validation fails** (honesty gate); every dialogue plays to an end and starts its quest; wrong replies stay put with feedback; variants resolve (plátano/banana/banano/guineo, jugo/zumo, voseo); currency follows the variant; every picture has alt text; every listening item has text; **every answer key passes its own checker in all 6 variants**; no duplicate choices in any variant; the validator catches broken content; variant text decodes both JSON shapes |
| `AnswerCheckerTests` (7) | Punctuation and case insensitivity; missing accents are correct with a note; another region's form is correct with a note; one typo counts as "almost" (and short words get no leeway); tiles; feedback is never punitive |
| `SchedulerTests` (10) | Grades; intervals grow; misses return in 10 minutes; effortful answers grow less; delayed retention counts only after ≥1 day; interval and ease bounds; **comprehension and production stay separate**; **cramming doesn't count as mastery**; track classification; deterministic due queue and retention candidates |
| `AssessmentFlowTests` (8) | Placement for beginners, partial knowledge, and full knowledge; placement skips and never uses speaking; mastery-check grading and badge; retention check becomes due after a week; **the parent report separates activity from mastery** |
| `SaveLoadTests` (8) | File and memory round trips; a corrupt main file falls back to the backup; corrupt with no backup throws; future versions aren't silently discarded; v1 → v2 migration; delete everything; saves contain no birthdate, email, phone, location, or device-ID fields |
| `ProgressionTests` (9) | Unlock order; quest completion and one-time rewards; replay XP; mistakes never remove XP or progress; unit and exit unlocks; free units are available without purchase; rewards exist in the catalog; activity-log pruning; nickname sanitising; age band sets presentation, not progress |
| `PurchaseGatingTests` (5) | Paid plans off by default; **essential learning is never gated**; profile slots by plan; entitlement validation (expired, revoked, upgraded, and unknown products are rejected; offline cache honoured until expiry); purchases need a fresh parental gate plus parent permission; a future-dated gate is rejected |
| `ParentalGateTests` (3) | Number words; 500 seeded challenges are correct and show no digits; lockout after 3 misses |
| `WorldTests` (5) | Map parses and is enclosed; every NPC, sign and exit is reachable from spawn; every quest NPC exists; A* avoids walls and NPCs and is deterministic; the mover collides |
| `AccessibilityAndPrivacyTests` (5) | **WCAG AA contrast (4.5:1)** for every text pair in both themes; export is valid JSON; privacy defaults (microphone, sync and purchases off); **no networking, tracking, or location APIs in the core**; content loads from the local bundle (offline) |

## 2. Automated: UI tests (`UITests/LanguageQuestUITests.swift`)

Run in Xcode (⌘U) or with `xcodebuild test -scheme LanguageQuest -destination 'platform=iOS Simulator,name=iPhone 16'`. Launch arguments: `-uiTesting` (in-memory save) and `-seedProfile`.

| Test | Flow |
|---|---|
| `testOnboardingCreatesExplorerAndSkipsPlacement` | Age has no default; variant must be chosen; nickname; skip placement; arrive in the village |
| `testParentGateBlocksWrongAnswer` | A wrong answer shows a message, and the dashboard stays hidden |
| `testParentGateOpensDashboard` | Solves the written-out question and the dashboard appears |
| `testFirstQuestFromDialogueToReward` | Go to → Luna → dialogue → quest → 4 activities (listen, match, reply, speak self-check) → "¡Misión cumplida!" |
| `testWrongAnswerGivesFeedbackAndRetryNotPunishment` | A wrong reply stays on the line; a wrong choice shows "Try again"; the right answer continues |
| `testAccessibilityAuditOnboardingAndGate` | `performAccessibilityAudit()` (iOS 17) on onboarding and the parent gate |

**Status: written, not yet run.** The authoring environment had no iOS simulator. Expect to adjust identifiers or timing on the first run. The accessibility audit may flag material-background contrast or clipped text, which should be fixed rather than suppressed.

## 3. Offline tests

- Automated: the core has no networking APIs (source scan); content loads from a file URL inside the bundle.
- Manual: in Airplane Mode, do a fresh install → onboarding → a quest → review → parent dashboard → export. Everything must work. With paid plans off, nothing ever needs the network.
- Manual: on-device speech with Airplane Mode on (see §4).

## 4. Manual QA: speech and audio (on real devices)

| Check | Expected |
|---|---|
| Speech checking off (default) | Speak activities show "I said it!"; the microphone permission is never requested |
| Parent turns speech checking on | Speech and microphone permission prompts appear, from the parent area only |
| Each variant's speech locale on recent iPhones and iPads | If `supportsOnDeviceRecognition` is false → falls back to self-check with an explanation, never to server recognition |
| Airplane Mode with recognition on | Still works for supported locales (on-device) |
| TTS voice per variant | Best available voice for the locale; record which voices each test device has (shown in the parent area in a future build) |
| Volume 0 | No speech output |

## 5. Device matrix

- iPhone SE (3rd gen, small screen), iPhone 15, iPhone 16 Pro Max
- iPad (10th gen), iPad Pro 13"
- iOS 17.x and 18.x / 26.x
- VoiceOver on; Dynamic Type at AX3; Reduce Motion; Bold Text; Increase Contrast; Voice Control; Switch Control (D-pad and "Go to")

## 6. Accessibility checklist

- [ ] Every control has a label (D-pad: "Walk up", etc.; the A button announces "Talk to Luna")
- [ ] The map is usable without seeing it: "Go to" list → auto-walk → auto-talk
- [ ] Right and wrong feedback uses shape (✓ / ↺) plus words plus colour
- [ ] Listening items offer "Show the words", for deaf and hard-of-hearing learners
- [ ] Read-aloud for instructions (default on for ages 7–9)
- [ ] Reduced motion stops NPC bobbing, water animation, hop and camera easing
- [ ] Tap targets ≥ 44 pt (main buttons 54 pt; the A button 84 pt)
- [ ] Text contrast passes (automated) and is re-checked on device

## 7. Learning-quality validation (with families)

- Pilot with 6–10 children per age band for 2 weeks. Measure the delayed-retention percentage, the "understands" counts, and mastery-check pass rates.
- Linguist review per variant (see CURRICULUM.md).
- Teacher review of ACTFL alignment claims.

## 8. Purchase testing (only when enabled)

Use the Xcode StoreKit configuration, then sandbox, then TestFlight:
- purchase (monthly and yearly);
- Ask to Buy (pending);
- restore;
- renewal and expiry (accelerated);
- refund and revocation;
- Family Sharing (`familyShared`);
- the parental gate expires after 2 minutes;
- "Allow purchases" off blocks the flow.
