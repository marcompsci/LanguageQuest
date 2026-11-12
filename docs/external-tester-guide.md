# External TestFlight guide: Language Quest

This covers getting Language Quest to testers outside your App Store Connect team. It requires a one-time **TestFlight App Review** of the first build.

> **TestFlight approval is not App Store approval.** Passing TestFlight App Review only lets external testers install the beta. A full App Review still happens when you submit for the App Store, and it can reject things TestFlight allowed.

## 1. Beta App Description (App Store Connect › TestFlight › Test Information)

> Language Quest is a pixel-art adventure for ages 11 and up where you learn languages by talking to the people of a small village. Pick Spanish, French or Japanese (full courses), or try starter lessons in German, Italian, Chinese, Yoruba, Hebrew, Ancient Egyptian, Amharic, Ancient Greek, Latin and Biblical Hebrew. Play word duels, memory games and a spelling bee, write words out by hand, and earn levels and trophies. No ads, no accounts, works offline. Lesson text is still being reviewed by native speakers.

## 2. What to Test (per build)

> Thanks for testing! Please try:
> 1. Create an explorer and finish the first quest with Luna (Spanish).
> 2. Switch to another language from the main menu and play a quest there.
> 3. Games: Echo, Memory Match, Spelling Bee and a Speed duel.
> 4. Write Out: write a word, turn the phone sideways, and tap Check.
> 5. The Bonus lesson and Daily challenges on the main menu.
> Tell us about anything confusing, any wrong translations, sounds that are too loud, or crashes. Use the TestFlight app to send a screenshot with feedback.

## 3. Review notes and reviewer navigation

Use `docs/app-review-notes.md` (Review Notes section and the 2-minute path).

## 4. Demo account

None needed: the app has no sign-in. Leave "Sign-in required" **off**.

## 5. Privacy policy checklist

- [ ] Host `docs/privacy-policy.md` at a public HTTPS address (for example GitHub Pages or your Phoronomics website). It must load without a login.
- [ ] Put the URL in **App Information › Privacy Policy URL** and **TestFlight › Test Information › Privacy Policy URL**.
- [ ] Put the same URL in `PrivacyNotice.hostedPolicyURL` (`Packages/LQCore/Sources/LQCore/Privacy/DataRights.swift`) so the Parents area links to it, then rebuild.
- [ ] App Privacy label: **Data Not Collected**.

## 6. Support and feedback contact

- [ ] **Feedback email** (required for external testing): an inbox you check.
- [ ] **Beta App Review contact**: first and last name, phone and email (only Apple sees these).
- [ ] **Support URL** (required later for the App Store): a page with a way to contact you.

## 7. Encryption / export compliance

- [ ] The build includes `ITSAppUsesNonExemptEncryption = NO`, so App Store Connect should not ask. If it does, answer that the app uses only exempt encryption (Apple OS hashing; no HTTPS of its own).
- [ ] With exempt encryption there is no documentation to upload.

## 8. Tester compatibility

- iPhone or iPad on **iOS / iPadOS 17.0 or later**, with the free **TestFlight** app installed.
- Works offline after installing. Check the install size in App Store Connect after upload.
- The read-aloud voice uses the device's built-in voices. For the best sound, testers can download Enhanced or Premium voices in Settings › Accessibility › Spoken Content › Voices (on newer iOS: Read & Speak). Amharic, Yoruba and Ancient Egyptian have no iPhone voice, so they're read from their Latin spelling.
- Age: TestFlight testers must meet Apple's account age rules. Children test with a parent's invitation or through Family Sharing; consider an adults-and-teens-first beta.

## 9. Steps in App Store Connect

**Before you start:** the Apple Developer Program agreements (including the Paid/Free Apps agreement) are active, and the app record exists with bundle id `com.phoronomics.languagequest`.

1. **Upload a build:** on the Mac, run `scripts/release-check.sh` (it must end with "passed"). In Xcode choose **Any iOS Device (arm64)**, then **Product › Archive** › Organizer › **Validate App** › **Distribute App › App Store Connect › Upload**. Each upload needs a higher build number (`CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate`).
2. **Wait for processing** (usually 10–30 minutes). The build appears under TestFlight › iOS Builds.
3. **Internal group** (no review): TestFlight › Internal Testing › **+** › name it "Team" › add App Store Connect users › add the build. Use this group to smoke-test on real devices first.
4. **Test Information:** TestFlight › Test Information › fill in the description, feedback email, privacy policy URL, marketing URL (optional), Beta App Review contact, sign-in (off) and Review Notes.
5. **External group:** TestFlight › External Testing › **+** › name it, for example "Families beta".
6. **Assign the build:** open the group › Builds › **+** › pick the build › fill in What to Test › **Submit for Review**. The first build always goes to TestFlight App Review; later builds of the same version may skip it.
7. **Confirm approval:** the build status changes from "Waiting for Review" / "In Review" to **"Ready to Test"**, and Apple emails the account holder. If it's rejected, read the message in App Store Connect › TestFlight, fix the issue, increase the build number and resubmit.
8. **Public link (optional):** in the external group › **Public Link** › **Enable Public Link** › set a tester limit (for example 100) and, optionally, criteria such as device and OS. Copy the `https://testflight.apple.com/join/…` link. You can only enable this after the build is approved.
9. **Verify with an outside Apple Account:** on a device signed in to an Apple Account that is **not** on your team, install TestFlight, open the public link (or the email invite), tap **Accept** › **Install**, and launch the app. Check that the build number matches and that "What to Test" shows.

## 10. After each new build

Run `scripts/release-check.sh`, update Review Notes if features changed (guideline 2.3.1(a)), increase the build number, and upload.
