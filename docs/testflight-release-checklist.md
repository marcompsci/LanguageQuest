# TestFlight release checklist: Language Quest

Run this before **every** TestFlight upload. A failing or skipped item means the build does not go out.

## A. Automated (must all pass)

```bash
scripts/release-check.sh          # on the Mac: compliance gate, unit tests, Release build, UI tests
```

GitHub Actions runs the same gates on every push (**Release gate** workflow):

| Job | What it checks |
|---|---|
| Compliance checks (static) | Privacy manifest, required-reason APIs, permission strings, export compliance key, no ATS exceptions or HTTP, secrets scan, dependencies, version/build format and sync, bundle/team/signing, entitlements, app icon, purchases off, privacy policy parity, no placeholder text, test hooks are Debug-only |
| LQCore unit tests + content checks | All unit tests (content validation for 13 courses, compliance regressions) and generated content matching the authoring scripts |
| iOS build, analyze, UI tests | Unsigned Release build for device, Clang static analyzer, all UI tests on an iPhone simulator (one retry for simulator start-up failures only) |

- [ ] `scripts/release-check.sh` ends with "Automated release checks passed"
- [ ] The latest **Release gate** run on the commit you are uploading is green

## B. Before each upload (manual)

- [ ] Increase `CURRENT_PROJECT_VERSION` in `project.yml` (and `MARKETING_VERSION` for a new version), then run `xcodegen generate` (XcodeGen 2.42.0) and commit
- [ ] Xcode: **Any iOS Device** › Product › **Archive** › Organizer › **Validate App** passes with no errors
- [ ] Smoke test the archived build on a real iPhone: create an explorer, finish Luna's quest, open each ☰ screen, Write Out in landscape, Parents gate
- [ ] One pass on an **iPad** simulator or device (layout, rotation, Write Out)
- [ ] `docs/app-review-notes.md` lists every new feature in this build (guideline 2.3.1(a), so nothing is hidden or undocumented under 2.5.19)
- [ ] "What to Test" text updated in `docs/external-tester-guide.md`

## C. One-time App Store Connect setup (manual)

- [ ] Privacy policy hosted at a public HTTPS URL; URL entered in App Information and TestFlight Test Information; `PrivacyNotice.hostedPolicyURL` set
- [ ] App Privacy: **Data Not Collected**
- [ ] Age rating questionnaire completed (including the content descriptors added November 16, 2026)
- [ ] TestFlight Test Information: beta description, feedback email, Beta App Review contact, sign-in **not required**, Review Notes
- [ ] No in-app purchase products created (purchases are off in this version)

## D. If something changed, re-check

| You changed… | Also do |
|---|---|
| Added a network call, SDK or package | Privacy label, policy, manifest, gate check 7, ATS |
| Used UserDefaults / file dates / disk space | Declare the reason in `PrivacyInfo.xcprivacy` (the gate fails until you do) |
| Asked for a new permission | Purpose string in `project.yml` (the gate checks it); request it only after the parental gate |
| Turned on purchases | Follow the §4 payments checklist in `apple-compliance-report.md` |
| Added text players see | No "coming soon" or placeholder text (the gate scans for it) |

---

## Release-readiness result (audit of November 12, 2026)

**Result: CONDITIONAL.** Every automated check passes. What remains can only be done by a person in Xcode and App Store Connect, and then Apple's own TestFlight App Review. External TestFlight approval is **not** App Store approval.

What passed:
- Static compliance gate (`scripts/compliance-check.py`): 17 pass, 0 fail, 0 warn, 7 manual.
- 141 LQCore unit tests (Linux and CI), plus the check that generated content matches the authoring scripts.
- GitHub Actions "Release gate" (macOS 15): unsigned Release build, Clang static analysis, and all 11 UI tests on an iPhone simulator, including the accessibility audits (contrast, Dynamic Type, clipped text) in Light and Dark Mode.
- Privacy policy hosted at a public HTTPS URL (GitHub, HTTP 200) and bundled in the app for offline reading.
- A Debug build installed and ran on the owner's iPhone (Xcode, Nov 12).

What a person still has to do before external testers can get a build (sections B and C above):
1. Xcode Release **Archive** and **Validate App** with your signing.
2. App Store Connect: privacy policy URL, App Privacy answer "Data Not Collected", age rating questionnaire, TestFlight Test Information (description, feedback email, review notes from `app-review-notes.md`).
3. One pass on an iPad, and an Instruments memory check on a long session.
4. Upload the build and submit it for TestFlight review. This was deliberately not done: it needs your go-ahead.

Accessibility audit exceptions (logged as `AUDIT-IGNORED` in the test output, never hidden):
- Done/Close buttons in navigation bars for Dynamic Type: iOS shows these through the Large Content Viewer.
- Flag emoji for contrast and clipped text: they are decorative pictures (hidden from VoiceOver), not text.
