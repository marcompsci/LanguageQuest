# App Store Checklist

> Nothing here guarantees approval. Re-read the current guidelines before submitting: https://developer.apple.com/app-store/review/guidelines/

## 1. Category decision: one mixed-age app, or separate apps?

The facts:
- Kids Category age bands are **5 and under, 6–8, and 9–11**. There is no band above 11.
- Once an app is held to Kids Category rules, it stays bound by them in later updates.
- Outside the Kids Category, an app may not use "For Kids" or "For Children" in its metadata, or imply that children are its main audience (5.1.4).
- Apple's age ratings are now 4+, 9+, 13+, 16+ and 18+ (2025 update).

| Option | For | Against |
|---|---|---|
| **A. One app, Education category, rated 4+, kids-grade privacy everywhere** (recommended for the slice) | Matches the 7–16+ product and the shared curriculum; one codebase and store page; teens aren't put off by a "kids" badge | No Kids Category shelf; can't market "for kids" in metadata; COPPA still applies (mixed audience) |
| B. One app in the Kids Category, band 9–11 | Kids shelf, parent trust | Teens (13+) are a poor fit; Kids rules bind every future update, including teen features |
| C. Two apps: "Language Quest Kids" (Kids Category, 6–8 or 9–11) and "Language Quest" (13+) sharing LQCore and content | Best fit for each audience | Two listings, double maintenance, and families split across apps |

**Update (v0.2): the app now targets ages 10+**, which makes option A the clear fit. Age rating: 9+ is the closest Apple tier below 10 (content would qualify for 4+, but 9+ signals the intended audience); a 9–11 Kids Category listing would exclude most of the audience.

**Recommendation:** start with **A**, keeping Kids-Category-grade privacy (no third-party SDKs, parental gates, no external links). Revisit C after kid and teen usability testing. **This decision needs legal review** together with the COPPA analysis.

## 2. Build and project

- [ ] Set `DEVELOPMENT_TEAM` in `project.yml`; run `xcodegen generate`
- [ ] Bundle id `com.phoronomics.languagequest` registered in App Store Connect
- [ ] Version and build numbers set (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`)
- [ ] App icon (1024 px, no alpha): included (`tools/art/make_icon.py`); consider a commissioned final icon
- [ ] Launch screen: generated (plain). Optional branded launch screen
- [ ] `PrivacyInfo.xcprivacy` included: no tracking, no collected data, no required-reason APIs. Re-check whenever dependencies change
- [ ] Usage descriptions present: microphone and speech recognition (requested only after a parent turns on speech checking)
- [ ] Release build passes `ContentValidator.validate(lib, releaseBuild: true)` **(currently fails on purpose: content not yet linguist-reviewed)**
- [ ] Unit tests (`swift test`) and UI tests (`xcodebuild test`) are green

## 3. Metadata

- [ ] Name: Language Quest (check availability and trademark)
- [ ] Subtitle (no "for kids" wording if listed outside the Kids Category): e.g. "Learn Spanish in an adventure"
- [ ] Description: accurate, with **no** claims of fluency, school credit, or COPPA certification
- [ ] Keywords
- [ ] Screenshots: 6.9" and 6.5" iPhone, 13" iPad
- [ ] Support URL and **privacy policy URL** (required)
- [ ] Age rating questionnaire, answered honestly:
  - no user-generated content, chat, web access, ads, gambling, or mature themes;
  - mention educational content and in-app purchases (if enabled);
  - expected rating 4+.
- [ ] Category: Education (secondary: Games > Adventure or Educational)

## 4. App Privacy ("nutrition label")

- [ ] "Data Not Collected": accurate for v0.1 (all data stays on the device, no SDKs). Re-evaluate if paid plans, sync, or analytics are added. Purchase data handled by Apple doesn't count as collected by you.

## 5. Kids and family requirements (apply even outside the Kids Category, by policy)

- [ ] Parental gate before purchases, settings, and any external link: ✅ `ParentGateView`
- [ ] No third-party ads or analytics: ✅
- [ ] No data sent to third parties: ✅
- [ ] Gate explains itself to pre-readers ("Kids: please ask a grown-up"): ✅ (also spoken with read-aloud on)

## 6. In-app purchase (only when `paidPlansEnabled` is turned on)

- [ ] Subscription group "familyplus" with monthly and yearly products (IDs in `StoreConfig.default`)
- [ ] Prices set in App Store Connect (proposed: $3.99/mo, $29.99/yr). **Never hard-coded**
- [ ] Family Sharing enabled on both. This **can't be turned off later**, so decide deliberately
- [ ] Optional introductory offer (one per person per subscription group)
- [ ] Paywall shows the title, length, and price of each plan, what's included, and links to the privacy policy and terms (Schedule 2 §3.8(b), Guideline 3.1.2)
- [ ] Restore Purchases button: ✅
- [ ] Cancellation guidance: ✅ (Settings > name > Subscriptions); consider adding `showManageSubscriptions`
- [ ] Tested in Xcode with `App/Resources/LanguageQuest.storekit`, then in sandbox and TestFlight: purchase, renew, expire, refund or revoke, Ask to Buy (pending), Family Sharing
- [ ] App Review notes: "Paid features are extras; all learning essentials are free"

## 7. Review notes template

> Language Quest is an offline Spanish-learning adventure for ages 10 and up. It has no accounts, ads, analytics, chat, or network features, and all data stays on the device. The Grown-ups area (lock icon, top right) is behind a parental gate: type the answer to the written-out sum in digits. Speech checking is off by default; a grown-up can enable on-device recognition in the Grown-ups area. Audio never leaves the device. To test quickly: tap "Go to" → Luna, talk to her, and complete the first quest.

## 8. Before you press Submit

- [ ] Legal sign-off (privacy, COPPA, state laws)
- [ ] Linguist sign-off per variant; audio recorded; units marked `released`
- [ ] Accessibility: VoiceOver walk-through of onboarding, a quest, and the parent area; Dynamic Type at AX3; Reduce Motion; Voice Control
- [ ] Device matrix tested (see TEST_PLAN.md §5)
