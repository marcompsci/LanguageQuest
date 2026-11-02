# Privacy and Child Safety

> **Not legal advice, and not a compliance claim.** This document describes how the app is designed and what still needs review. Language Quest has **not** been reviewed by a privacy lawyer and must not be described as "COPPA compliant" until it has been. Facts are current as of November 2026; laws are changing quickly, so re-check before release.

## 1. Design stance: collect almost nothing

The v0.1 app:
- has **no accounts, no network calls, no analytics, no ads, no tracking, no chat, and no public profiles**;
- stores everything on the device;
- includes no third-party SDKs.

| Data | Why | Where | Retention | Leaves device? |
|---|---|---|---|---|
| Nickname (optional, sanitised to letters, 16 characters max) | Personalised dialogue | Device | Until the profile is deleted | No (only inside a parent-initiated export) |
| Age band (not a birthdate) | Presentation and theme | Device | Until the profile is deleted | No |
| Avatar, Spanish variant, settings | Gameplay | Device | Until the profile is deleted | No |
| Progress, learner model, assessment results | Learning | Device | Until the profile is deleted | No |
| Minutes and activities per day | Parent dashboard, break reminder | Device | **60 days**, then pruned automatically | No |
| Cached plan and expiry (only if paid plans are enabled) | Offline entitlement | Device; Apple holds the receipt | Until it expires or is deleted | Apple handles purchases |
| Microphone audio (only if a parent enables speech checking) | Check pronunciation | **Processed in memory by on-device recognition** | **Never stored** | No |

**Never collected:** birthdate, real full name, email, phone number, location, photos, contacts, device advertising ID (IDFA), voiceprints or other biometric templates.

The save file is checked by tests to contain no birthdate, email, phone, location, or device-ID fields.

## 2. COPPA

What the research found (law-firm summaries; the FTC FAQ couldn't be fetched, so verify there):
- The FTC's amended COPPA Rule was published 22 April 2025, took effect in June 2025, and requires **full compliance by 22 April 2026**.
- Key changes:
  - **separate verifiable parental consent** before sharing children's data with third parties;
  - a **written data-retention policy** in the privacy notice (no indefinite retention);
  - a **written information-security program**;
  - "personal information" now includes **biometric identifiers** such as voiceprints;
  - mixed-audience services must use **neutral age screening**.
- A recording of a child's voice is personal information. A narrow exception allows audio collected only to respond to the child's request, deleted immediately, and disclosed in the notice.

How the design maps to this:

| Requirement area | Language Quest design |
|---|---|
| Collection of personal information from children under 13 | v0.1 collects nothing off-device. The operator receives no personal information. **Lawyer to confirm** whether purely on-device storage keeps COPPA's notice and consent duties from applying, and what changes if accounts or sync are added. |
| Verifiable parental consent (VPC) | Not needed today because nothing is collected by the operator (to be confirmed). Any future collection (cloud sync, accounts, server-side speech) must be preceded by VPC using an FTC-approved method, with **separate** consent for any third-party disclosure (there is none planned). A parental gate is **not** VPC (Apple 5.1.4). |
| Neutral age screening | Age band picker with no default; the app works fully for every band; no birthdate. |
| Voice | On-device recognition only (`requiresOnDeviceRecognition = true`), off by default, enabled only by an adult behind the gate. Audio is streamed in memory and never written or sent. If the device can't recognise offline, speaking falls back to the no-microphone self-check (no server fallback). |
| Retention policy | Activity log pruned at 60 days; everything else kept until the parent deletes it; documented in-app (`PrivacyNotice.dataInventory`). |
| Security program | Required before any data collection. Today: iOS file protection, no network surface. |
| Parent rights | In-app export (JSON) and deletion of one profile or all data. |

## 3. State laws (US), status as researched

- **Texas App Store Accountability Act (SB 2420):** blocked in December 2025, then in effect after the Fifth Circuit stayed the injunction (June 2026); the Supreme Court declined to block it (July 2026); litigation continues. App stores must verify age and get parental consent, and developers must use the store's age and consent signals.
- **Utah:** compliance deadline moved to 6 May 2027; enforced only through private lawsuits.
- **Louisiana:** 1 July 2027.
- **Alabama:** 1 January 2027.
- **California Age-Appropriate Design Code:** partly enforceable after the Ninth Circuit's March 2026 ruling. Enforceable now: high-privacy defaults, child-appropriate notices, privacy-rights tools. Language Quest's defaults already meet the spirit of these.

**Engineering plan.** Integrate Apple's **Declared Age Range API** (iOS 26+) to receive age-range and consent signals without a birthdate, with a fallback to the in-app age band on older iOS. Handle "significant change" consent flows if a future update changes data practices.

## 4. Apple requirements

| Guideline | How we meet it |
|---|---|
| 1.3 / 5.1.4 Kids: no third-party analytics or ads; no personal data to third parties | None included. `PrivacyInfo.xcprivacy` declares no tracking and no collected data. |
| Parental gate before purchases, external links, and settings | `ParentGateView`: a question written in words, answered in digits; locks for 60 s after 3 misses. Purchases need a fresh gate (valid 2 minutes) **and** a parent "Allow purchases" toggle. There are no external links. |
| 5.1.1(v) account deletion | No accounts. In-app deletion of all data is available anyway. |
| 3.1.2 subscriptions | Disclosure text, restore button, Settings cancellation guidance, and App Store prices only. Paid plans are off. |
| Age rating honesty (2.3.6) | No user-generated content, chat, web access, or ads; expected rating 4+ (see APP_STORE_CHECKLIST). |

**Limitation of the knowledge gate.** Teens can solve it. For the teen bands, the gate protects settings from younger siblings, not from the teen. Purchases additionally go through Apple's own confirmation, and Ask to Buy for Family Sharing children. **Roadmap:** an optional parent PIN stored in the Keychain.

## 5. Child-safety design rules

- No open chat, stranger matching, public profiles, user-generated text visible to others, or web views.
- Planned family and classroom co-op will use **preset messages only**, local or within the family, with no stranger matching.
- **No generative AI dialogue.** All NPC lines and hints are authored and deterministic. Typed answers are only compared against answer keys and are never stored as free text beyond the in-memory check.
- No manipulative design: no streaks, energy, loot boxes, countdown pressure, push notifications, or characters asking for money.
- Break reminders are gentle and optional. Nothing locks the child out.
- Mistakes always lead to feedback, never loss of progress or XP.

## 6. If data collection is ever added (future requirements)

1. Privacy policy (child-readable version plus the full version) with a data-lifecycle table, retention periods, named third parties (if any), and contact details.
2. Verifiable parental consent before collection; separate consent for any disclosure; a way to revoke consent and delete.
3. Adult accounts via Sign in with Apple. Tokens in the Keychain; TLS only; server-side role-based authorisation (parent can read and delete child profiles; child sessions cannot change settings).
4. Encryption in transit (TLS 1.2+) and at rest; least-privilege access; audit logs; an incident-response plan.
5. Written security program, annual risk assessment, and vendor assurances.
6. No default cloud storage of microphone recordings. Any server-side speech processing requires separate VPC, immediate deletion, and a published notice.

## 7. Before release: review checklist

- [ ] Children's privacy lawyer reviews this document, the app, and the App Store privacy answers
- [ ] Privacy policy URL published (required for Kids and for all apps)
- [ ] Confirm the App Privacy label: "Data Not Collected"
- [ ] Decide on the Declared Age Range API integration and its fallback
- [ ] Re-check the status of Texas, Utah, Louisiana, Alabama and California
- [ ] Security review of the save format and export flow

## Sources

- FTC COPPA FAQ: https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions
- COPPA amendments: https://hunton.com/privacy-and-information-security-law/ftc-publishes-final-coppa-rule-amendments · https://natlawreview.com/article/amendments-ftc-coppa-rule-now-effect
- State app-store acts: https://www.mondaq.com/unitedstates/privacy-protection/1799524/key-developments-with-state-app-store-accountability-acts-as-texas-act-takes-effect · https://fpf.org/blog/comparing-enacted-app-store-accountability-acts/ · https://shuftipro.com/news/supreme-court-texas-app-store-age-verification-law/
- California AADC: https://www.cooley.com/news/insight/2026/2026-03-30-netchoice-v-bonta-ninth-circuit-narrows-injunction-against-californias-ageappropriate-design-code-act
- Apple Kids: https://developer.apple.com/kids/ · App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Declared Age Range: https://developer.apple.com/documentation/declaredagerange/agerangeservice
- On-device speech: https://developer.apple.com/documentation/speech/sfspeechrecognizer
