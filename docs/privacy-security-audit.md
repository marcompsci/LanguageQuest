# Privacy and security audit: Language Quest

Audit date: November 12, 2026 · Version 0.7.0 (1)

## Summary

Language Quest collects no data. It has no network code, accounts, backend, analytics, ads, or third-party SDKs. Everything is stored on the device. The App Store privacy label should be **Data Not Collected**.

## Checklist (Phase 4)

| Item | Status | Evidence |
|---|---|---|
| HTTPS/TLS network transport | N/A: the app makes no network requests (StoreKit is the only Apple service, and it's off) | Gate check 5b fails on any URLSession, socket or web view; check 5 fails on plain HTTP or ATS exceptions |
| Secure token storage | No tokens exist. The parent PIN is a salted SHA-256 hash in the Keychain (`ParentPINStore`, this device only). Resetting it uses LocalAuthentication; the app only receives yes or no | Code review |
| No production secrets in the bundle | ✅ None | Gate secrets scan of every tracked file (keys, tokens, JWTs, `.p8/.p12/.mobileprovision`) |
| Server-side authorization, Supabase RLS, Firebase rules | N/A: no backend | Code search |
| Unauthorized database access | N/A: local file only. iOS sandbox plus `completeFileProtectionUntilFirstUserAuthentication` | `FileSaveStore.save` |
| Session handling | N/A: no sessions | — |
| Input validation and safe output | Typed answers are compared on-device and never executed or sent. The nickname is local only and is not rendered as Markdown or HTML. Export is JSON produced by `JSONEncoder` | Code review |
| Permission purpose strings | ✅ Microphone, Speech Recognition and Face ID (PIN reset), all specific and accurate. Mic and speech are requested only after a parent turns on speech practice behind the gate | `project.yml`; gate check 3 (now also covers `LAContext`) |
| Privacy policy access | ✅ In the app (☰ › Privacy policy, and Parents) and online at the public GitHub URL | `docs/privacy-policy.md`; `PrivacyPolicyTests`; gate URL check |
| In-app account deletion | N/A: no accounts. Local "Delete this explorer" and "Delete all data" are behind the parental gate | `ParentAreaView` |
| Data deletion and retention | ✅ Daily activity log pruned after `ActivityLog.retentionDays` for every explorer at launch. Delete-all removes all save files, backups, quarantined copies, exports and the PIN. Deleting an explorer purges the backup. Unreadable saves are kept aside until delete-all | `DeletionTests`, `ComplianceTests` |
| App privacy disclosure inventory | ✅ The in-app inventory (`PrivacyNotice.dataInventory`, version 2) matches the policy | `ComplianceTests.testPrivacyInventoryCoversEveryOnDeviceDataType` |
| Privacy manifest | ✅ `App/Resources/PrivacyInfo.xcprivacy`: no tracking, no domains, no collected data | Gate check 1 |
| Required-reason APIs | ✅ None used (no UserDefaults, file timestamps, boot time, disk space, keyboards) | Gate check 2 (fails if one is added without a declared reason) |
| Third-party SDK privacy | N/A: no third-party packages | Gate check 7 |
| Encryption export classification | ✅ No encryption: only a SHA-256 hash of the PIN. `ITSAppUsesNonExemptEncryption = NO` | Gate check 4 |
| Tracking / ATT | ✅ None. The gate fails if `ATTrackingManager` appears | Gate check 3 |

## App Store Connect "App Privacy" answers

- Do you or your third-party partners collect data from this app? **No.**
  (Speech audio and handwriting are processed only on the device and are never sent or stored. Apple counts data as "collected" only when it is sent off the device.)

## Children (ages 11–12 are in the audience)

- No personal information is collected, so COPPA's notice and consent duties for collecting data are not triggered. Keep it that way: any future analytics, crash reporting, cloud sync, or AI service needs a new review, parental consent, and an updated privacy label.
- Speech, deletion, export, purchases, and break reminders are behind a parental gate plus an optional PIN.
- Not in the Kids Category. Don't use "for kids" or "for children" in App Store metadata (that wording is reserved for the Kids Category).
- Guideline 5.1.2(i) (2025–26) requires clear disclosure and consent before sharing personal data with third-party AI. The app uses no third-party AI. Speech and handwriting use Apple's on-device frameworks.

## Watch list for future changes

1. Adding any network call → add ATS-safe HTTPS only, update the privacy label and policy, and re-run the gate.
2. Adding UserDefaults/@AppStorage → declare `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (the gate fails until you do).
3. Turning on purchases → follow the §4 checklist in `apple-compliance-report.md`.
4. iCloud or cloud sync (`allowCloudSync` exists but must stay false) → this is a new data flow and needs parental consent.
