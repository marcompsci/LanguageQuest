# Language Quest: Product Requirements

**Status:** Vertical slice (v0.1). Not production-ready; see "Release blockers".
**Owner:** Phoronomics · **Platform:** iOS / iPadOS 17+ first

## 1. Vision

Language Quest is a 2D pixel-art adventure game in which children and teenagers learn a language by **using it**. Players explore a village, talk with characters, finish quests, and practise listening, reading, writing and speaking. Spaced review brings words back at the right time. It should feel like a game you want to play, not a worksheet.

Launch course: **Spanish, taught in English**, with a switchable regional variety (Latin America general, Mexico, Spain, Argentina, Colombia, Caribbean/Puerto Rico).

## 2. Who it's for

Age sets **presentation**, never level. Every player can take the placement test, and skills are tracked separately.

**Minimum age: 10.** (Changed from 7+ in v0.2.)

| Band | Presentation | Default theme |
|---|---|---|
| 11–12 | Quests, sentence building, listening and speaking; read-aloud available | Playful |
| 13–15 | Contextual dialogue, more independent practice, school alignment | Explorer |
| 16+ | Practical situations, denser UI, (later) complex grammar | Explorer |

There is no birthdate. Onboarding asks for an age band with **no option pre-selected** (neutral age screening).

## 3. Problems we solve (from competitor research)

- **Punishing mechanics.** Energy and hearts systems, mistake counters, and streak anxiety. We use none of them: mistakes bring feedback and retries.
- **Flashcard drills with no context.** Here every word arrives through a conversation with a character, in a place.
- **Kids' apps stop at age 8; teen apps aren't made for younger players.** One curriculum spans ages 11 to 16+, with two themes (Explorer is the default since v0.6).
- **Material tested before it is taught.** Units have can-do goals, guided practice before independent practice, then a mastery check.
- **Opaque progress.** The parent dashboard separates *activity* (time, XP) from *demonstrated mastery*. Mastery means remembered across days, and producing language is tracked separately from understanding it.
- **Subscription traps.** Apple billing only, prices configurable, and essential learning always free.

## 4. Scope of the v0.1 vertical slice (built)

| Area | Requirement | Status |
|---|---|---|
| Onboarding | Age band (no default) → language → Spanish variant → avatar → optional nickname → optional placement | Built |
| Avatar | Original pixel avatar: 6 skin tones, 5 hair styles, 6 hair colours, 8 outfits, plus equippable reward cosmetics | Built |
| World | Explorable Starter Village (32×24 tiles): touch D-pad, tap-to-walk (A*), collision, NPCs, signs, locked exit to the next world, saved position | Built |
| Accessible navigation | "Go to" list walks to any person or place; VoiceOver labels on controls | Built |
| NPC dialogue | Authored, deterministic dialogue trees. A wrong reply stays on the line with gentle feedback. Hints are pre-written (Coco the parrot). Replay audio. `{name}` personalisation | Built |
| Curriculum | 3 authored Spanish units, 15 quests, 68 quest activities in 8 activity types, 15 mastery-check items, 94 words and phrases, 10 cultural notes, 6 regional variants | Built, **pending linguist review** |
| Exercises | Listen, read, match, build a sentence, fill the blank, write, speak, reply | Built |
| Speaking | No-microphone self-check by default; on-device recognition only if a grown-up enables it | Built (recognition needs on-device testing) |
| Spaced review | SM-2 variant using accuracy, attempts, response time, hints, and actual elapsed time; comprehension and production tracked separately | Built and tested |
| Assessment | Baseline placement, weekly retention check, unit mastery checks | Built and tested |
| Rewards | XP, 15 free cosmetics, 6 badges; no streaks, loot boxes, or paid advantages | Built |
| Parent area | Parental gate; progress by skill; understood vs can-use words; review due; retention; activity kept separate; settings (variant, theme, motion, subtitles, read-aloud, voice volume and speed, text size, break reminder); speech consent; family profiles; export; delete; Family Plus panel | Built (prototype) |
| Monetisation | StoreKit 2 code paths, entitlement validation, restore, Family Sharing flag, parental gate. **Paid plans disabled** | Built, off |
| Persistence | Local-first versioned JSON with backup and migration; works fully offline | Built and tested |

## 5. Explicitly out of the slice (see ROADMAP.md)

Conversation Town and the later worlds; Word Battles; Puzzle Academy; mini-games (soccer, cooking, treasure hunt, shopping, travel, racing); family and classroom co-op with preset messages; French and Japanese; native-speaker audio recordings; Declared Age Range API integration; iCloud sync.

## 6. Monetisation (proposed, not enabled)

- **Free Explorer:** no ads; Units 1–3 (the whole Starter Village); unlimited review; hints; correction feedback; placement and retention checks; parent dashboard; export and delete; all accessibility settings. Up to 2 explorer profiles.
- **Family Plus (proposed):** $3.99/month or $29.99/year; up to 4 profiles; advanced worlds; extra cosmetics. Prices come from App Store Connect, not code (`StoreConfig` holds only product IDs and limits).
- Before enabling (`StoreConfig.paidPlansEnabled = true`): legal review (COPPA, state laws, Apple Schedule 2), technical review (sandbox and TestFlight purchase testing, refunds, Family Sharing revocation), and a unit-economics review (content cost per unit, audio recording cost, expected conversion).
- **Never paid:** correction, hints, review, the starter curriculum, and safety or privacy controls (enforced by `Feature.isEssential` and tested).

## 7. Success measures (to validate with families, on device only)

- **Learning:** share of learned items marked "understands" after 2 weeks; delayed-retention percentage on weekly checks; mastery-check pass rate.
- **Experience:** quest completion; sessions per week the child starts (not prompted by notifications); parent-reported enjoyment.
- **Trust:** zero data leaves the device; parent comprehension of the dashboard (usability test).
- **No dark-pattern KPIs.** We don't optimise streaks, daily logins, or session length.

## 8. Non-negotiables

- No ads, third-party analytics, tracking, open chat, stranger matching, public profiles, or unrestricted AI dialogue.
- No cloud storage of voice. On-device recognition only, off by default.
- Every error leads to feedback and a path forward, never punishment.
- XP never equals proficiency.
- No claims of school credit, guaranteed fluency, COPPA compliance, or App Store approval without independent validation.

## 9. Release blockers (must clear before any public release)

1. Native-speaker linguist review of all text, per variant. The validator rejects unreleased content in release builds.
2. Native-quality audio recordings replacing text-to-speech.
3. Children's privacy legal review (COPPA as amended in 2025, state laws, Apple 5.1.4) and a published privacy policy.
4. Decision on Kids Category versus a general listing (see APP_STORE_CHECKLIST.md §1).
5. On-device QA of speech recognition per Spanish locale; UI tests passing on device and simulator; accessibility audit fixes.
6. Kid usability testing in two age bands.
