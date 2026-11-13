#!/usr/bin/env python3
"""Language Quest App Store / TestFlight compliance gate (static checks).

Runs on macOS or Linux with only the Python standard library.

    python3 scripts/compliance-check.py            # report; exit 1 on any FAIL
    python3 scripts/compliance-check.py --strict   # also exit 1 while MANUAL items remain (use before a release)

Statuses: PASS (checked and fine), FAIL (blocks), WARN (risk to review), MANUAL (cannot be
checked from the repo; a person must confirm). A check that could not run is reported as
FAIL or MANUAL, never as PASS.
"""
import os, re, sys, plistlib, struct, zlib, subprocess, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRICT = "--strict" in sys.argv
results = []

def add(status, check, detail=""):
    results.append((status, check, detail))

def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()

def swift_files(*dirs):
    for d in dirs:
        for root, _, files in os.walk(os.path.join(ROOT, d)):
            if "/.build" in root:
                continue
            for f in files:
                if f.endswith(".swift"):
                    yield os.path.join(root, f)

APP_SWIFT = list(swift_files("App", "Packages/LQCore/Sources"))
ALL_SRC = {p: open(p, encoding="utf-8").read() for p in APP_SWIFT}
PROJECT_YML = read("project.yml")

def yml_value(key):
    m = re.search(rf"^\s*{re.escape(key)}:\s*\"?([^\"\n]*)\"?\s*$", PROJECT_YML, re.M)
    return m.group(1).strip() if m else None

def uses(pattern):
    rx = re.compile(pattern)
    return sorted({os.path.relpath(p, ROOT) for p, s in ALL_SRC.items() if rx.search(s)})

# 1. Privacy manifest -------------------------------------------------------
manifest_path = os.path.join(ROOT, "App/Resources/PrivacyInfo.xcprivacy")
declared_reasons = set()
try:
    with open(manifest_path, "rb") as f:
        pm = plistlib.load(f)
    if pm.get("NSPrivacyTracking") is not False:
        add("FAIL", "Privacy manifest: NSPrivacyTracking", "must be false (the app does no tracking)")
    elif pm.get("NSPrivacyTrackingDomains"):
        add("FAIL", "Privacy manifest: tracking domains", "must be empty")
    else:
        add("PASS", "Privacy manifest present and valid", "no tracking, no tracking domains")
    declared_reasons = {t.get("NSPrivacyAccessedAPIType") for t in pm.get("NSPrivacyAccessedAPITypes", [])}
    if pm.get("NSPrivacyCollectedDataTypes"):
        add("WARN", "Privacy manifest: collected data types", "declares collected data; App Privacy label must match")
except Exception as e:  # noqa: BLE001
    add("FAIL", "Privacy manifest", f"missing or unreadable: {e}")

# 2. Required-reason APIs must be declared ----------------------------------
REQUIRED_REASON = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage",
    "NSPrivacyAccessedAPICategoryFileTimestamp": r"\.creationDate\b|\.modificationDate\b|contentModificationDate|attributesOfItem|getattrlist|\bstat\(",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time",
    "NSPrivacyAccessedAPICategoryDiskSpace": r"volumeAvailableCapacity|systemFreeSize|systemSize\b|statfs",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}
missing = []
for cat, rx in REQUIRED_REASON.items():
    hits = uses(rx)
    if hits and cat not in declared_reasons:
        missing.append(f"{cat} used in {', '.join(hits)}")
add("FAIL" if missing else "PASS", "Required-reason APIs declared", "; ".join(missing) or "none used without a declared reason")

# 3. Permission purpose strings ----------------------------------------------
PERMS = {
    "NSMicrophoneUsageDescription": r"AVAudioApplication\.requestRecordPermission|requestRecordPermission|AVAudioEngine\(\)\.inputNode|\.inputNode\b",
    "NSSpeechRecognitionUsageDescription": r"SFSpeechRecognizer\.requestAuthorization",
    "NSCameraUsageDescription": r"AVCaptureDevice|UIImagePickerController\b.*camera",
    "NSPhotoLibraryUsageDescription": r"PHPhotoLibrary|PhotosPicker",
    "NSLocationWhenInUseUsageDescription": r"CLLocationManager",
    "NSContactsUsageDescription": r"CNContactStore",
    "NSUserTrackingUsageDescription": r"ATTrackingManager",
    "NSFaceIDUsageDescription": r"LAContext\(\)",
}
bad = []
for key, rx in PERMS.items():
    hits = uses(rx)
    has = f"INFOPLIST_KEY_{key}" in PROJECT_YML
    if hits and not has:
        bad.append(f"{key} missing (used in {', '.join(hits)})")
    if has:
        text = yml_value(f"INFOPLIST_KEY_{key}") or ""
        if len(text) < 25:
            bad.append(f"{key} is too vague: '{text}'")
if uses(r"ATTrackingManager"):
    bad.append("App Tracking Transparency is used, but the app must not track")
add("FAIL" if bad else "PASS", "Permission purpose strings", "; ".join(bad) or "every permission API has a specific purpose string")

# 4. Export compliance --------------------------------------------------------
enc = yml_value("INFOPLIST_KEY_ITSAppUsesNonExemptEncryption")
if enc is None:
    add("FAIL", "Export compliance key", "ITSAppUsesNonExemptEncryption not set; every upload will ask")
elif enc.upper() in ("NO", "FALSE"):
    risky = uses(r"CCCrypt|SecKeyCreateEncryptedData|AES\.GCM|ChaChaPoly|import\s+OpenSSL|import\s+CryptoSwift")
    add("FAIL" if risky else "PASS", "Export compliance: exempt (NO)",
        f"encryption APIs found that may not be exempt: {risky}" if risky else "only hashing / OS-provided crypto found")
else:
    add("MANUAL", "Export compliance", "app declares non-exempt encryption: documentation required in App Store Connect")

# 5. Transport security -------------------------------------------------------
ats = [p for p in ("project.yml",) if "NSAllowsArbitraryLoads" in read(p) or "NSExceptionDomains" in read(p)]
http = [f"{os.path.relpath(p, ROOT)}" for p, s in ALL_SRC.items()
        if re.search(r"\"http://(?!www\.apple\.com/DTDs)", s)]
add("FAIL" if (ats or http) else "PASS", "No ATS exceptions or plain-HTTP URLs",
    "; ".join(ats + http) or "no exceptions")

# 5b. No networking: the privacy policy and the Data Not Collected label depend on it.
net = uses(r"\bURLSession\b|\bURLRequest\b|NWConnection|NWPathMonitor|WKWebView|SFSafariViewController|CFSocket|import\s+Network\b|Data\(contentsOf:\s*URL\(string")
add("FAIL" if net else "PASS", "No network code (policy says nothing leaves the device)",
    f"network APIs in {', '.join(net)}: update the privacy policy and App Privacy label, then this check" if net else "no URLSession, sockets or web views")

# 6. Secrets ------------------------------------------------------------------
SECRET_RX = [
    (r"AKIA[0-9A-Z]{16}", "AWS access key"), (r"sk_live_[0-9a-zA-Z]{10,}", "Stripe live key"),
    (r"-----BEGIN (RSA |EC |)PRIVATE KEY-----", "private key"), (r"ghp_[0-9A-Za-z]{30,}", "GitHub token"),
    (r"xox[baprs]-[0-9A-Za-z-]{10,}", "Slack token"), (r"AIza[0-9A-Za-z_\-]{35}", "Google API key"),
    (r"eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{10,}", "JWT (e.g. Supabase key)"),
    (r"(?i)(api[_-]?key|secret|password)\s*[:=]\s*\"[^\"]{12,}\"", "hard-coded credential"),
]
try:
    tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.split()
except Exception as e:  # noqa: BLE001
    tracked = []
    add("FAIL", "Secrets scan", f"could not list files with git: {e}")
found = []
for rel in tracked:
    if rel.endswith((".p8", ".p12", ".mobileprovision", ".cer", ".pem", ".keystore")) or os.path.basename(rel) in (".env", "AuthKey.p8"):
        found.append(f"{rel} (credential file)")
        continue
    if rel.endswith((".png", ".jpg", ".pbxproj")) or "/Resources/Content/" in rel:
        continue
    try:
        text = open(os.path.join(ROOT, rel), encoding="utf-8", errors="ignore").read()
    except OSError:
        continue
    for rx, name in SECRET_RX:
        if re.search(rx, text):
            found.append(f"{rel}: {name}")
if tracked:
    add("FAIL" if found else "PASS", "No secrets or credential files in git", "; ".join(found) or f"{len(tracked)} tracked files scanned")

# 7. Dependencies -------------------------------------------------------------
remote = re.findall(r"\.package\(\s*url:", read("Packages/LQCore/Package.swift")) + \
         (["project.yml remote package"] if re.search(r"^\s*url:\s*https?://", PROJECT_YML, re.M) else [])
add("WARN" if remote else "PASS", "Third-party dependencies",
    "remote packages found: check them for advisories and privacy manifests" if remote else "none (first-party code only; nothing to audit for advisories)")

# 8. Version and build --------------------------------------------------------
mv, bv = yml_value("MARKETING_VERSION"), yml_value("CURRENT_PROJECT_VERSION")
ok = bool(mv and re.fullmatch(r"\d+\.\d+(\.\d+)?", mv)) and bool(bv and re.fullmatch(r"\d+(\.\d+){0,2}", bv))
pbx = read("LanguageQuest.xcodeproj/project.pbxproj")
in_sync = f"MARKETING_VERSION = {mv};" in pbx and f"CURRENT_PROJECT_VERSION = {bv};" in pbx
add("PASS" if ok and in_sync else "FAIL", "Version and build number",
    f"{mv} ({bv})" + ("" if in_sync else ": project.yml and LanguageQuest.xcodeproj disagree; run xcodegen generate"))
add("MANUAL", "Build number is higher than the last upload", f"App Store Connect must not already have {mv} ({bv})")

# 9. Bundle, team, signing, deployment ---------------------------------------
bid = yml_value("PRODUCT_BUNDLE_IDENTIFIER")
team = yml_value("DEVELOPMENT_TEAM")
dep = re.search(r"iOS:\s*\"?([\d.]+)", PROJECT_YML)
problems = []
if not bid or not re.fullmatch(r"[A-Za-z0-9.\-]+", bid): problems.append("bundle id")
if not team or not re.fullmatch(r"[A-Z0-9]{10}", team): problems.append("development team")
if "CODE_SIGN_STYLE: Automatic" not in PROJECT_YML: problems.append("signing style is not Automatic (check provisioning)")
add("FAIL" if problems else "PASS", "Bundle id, team, signing", ", ".join(problems) or f"{bid}, team {team}, automatic signing, iOS {dep.group(1) if dep else '?'}+")

# 10. Entitlements ------------------------------------------------------------
ents = [r for r in tracked if r.endswith(".entitlements")]
add("PASS" if not ents else "WARN", "Entitlements",
    "none (no capabilities that need provisioning)" if not ents else f"review capabilities in {ents}")

# 11. App icon ----------------------------------------------------------------
def png_info(path):
    with open(path, "rb") as f:
        data = f.read(33)
    w, h, depth, color = struct.unpack(">IIBB", data[16:26])
    return w, h, color

try:
    icon_dir = os.path.join(ROOT, "App/Resources/Assets.xcassets/AppIcon.appiconset")
    contents = json.load(open(os.path.join(icon_dir, "Contents.json")))
    fn = [i.get("filename") for i in contents["images"] if i.get("filename")]
    w, h, color = png_info(os.path.join(icon_dir, fn[0]))
    alpha = color in (4, 6)
    add("PASS" if (w, h) == (1024, 1024) and not alpha else "FAIL", "App icon 1024×1024, no transparency",
        f"{w}×{h}, {'has alpha' if alpha else 'opaque'}")
except Exception as e:  # noqa: BLE001
    add("FAIL", "App icon", f"could not check: {e}")

# 12. Purchases ---------------------------------------------------------------
ent = read("Packages/LQCore/Sources/LQCore/Entitlements/Entitlements.swift")
paid = re.search(r"paidPlansEnabled:\s*true", ent) is not None
if paid:
    add("FAIL", "Paid plans enabled", "complete the 3.1 checklist in docs/apple-compliance-report.md (Terms/EULA + privacy links in the purchase UI, IAP products in App Store Connect, restore tested) and then update this check")
else:
    add("PASS", "Purchases off in this build", "StoreConfig.default.paidPlansEnabled == false; no purchase UI reachable")

# 13. Privacy policy ----------------------------------------------------------
try:
    in_app = read("Packages/LQCore/Sources/LQCore/Resources/Content/legal/privacy-policy.md")
    docs = read("docs/privacy-policy.md")
    add("PASS" if in_app == docs else "FAIL", "Privacy policy in app = docs/privacy-policy.md",
        "identical" if in_app == docs else "copies differ: update both")
except OSError as e:
    add("FAIL", "Privacy policy", f"missing: {e}")
hosted = re.search(r"hostedPolicyURL:\s*String\?\s*=\s*\"(https://[^\"]+)\"",
                   read("Packages/LQCore/Sources/LQCore/Privacy/DataRights.swift"))
if not hosted:
    add("MANUAL", "Hosted privacy policy URL", "not set: host docs/privacy-policy.md, put the URL in PrivacyNotice.hostedPolicyURL and in App Store Connect")
else:
    # Check it really loads without a login; if this machine is offline, a person must check (never a silent pass).
    import urllib.request
    try:
        with urllib.request.urlopen(urllib.request.Request(hosted.group(1), method="GET", headers={"User-Agent": "compliance-check"}), timeout=15) as r:
            ok = r.status == 200
        add("PASS" if ok else "FAIL", "Hosted privacy policy URL loads publicly", f"{hosted.group(1)} → HTTP {r.status}")
    except Exception as e:  # noqa: BLE001
        add("MANUAL", "Hosted privacy policy URL loads publicly", f"could not reach {hosted.group(1)} from here ({e.__class__.__name__}); open it in a private browser window")

# 14. Placeholder / unfinished text in shipped strings -------------------------
# Phrases are matched in any case; TODO/FIXME only in capitals (Spanish "todo" means "everything").
PLACE = re.compile(r"\"[^\"\n]*((?i:coming soon|lorem ipsum|placeholder text|future update)|TODO|FIXME)[^\"\n]*\"")
hits = [f"{os.path.relpath(p, ROOT)}" for p, s in ALL_SRC.items()
        if PLACE.search(s) and not p.endswith("ContentValidator.swift")]
add("FAIL" if hits else "PASS", "No 'coming soon' or placeholder text in the app", ", ".join(sorted(set(hits))) or "none found")

# 15. Test hooks are Debug-only ----------------------------------------------
model = read("App/AppModel.swift")
add("PASS" if re.search(r"#if DEBUG\s*\n\s*ProcessInfo\.processInfo\.arguments\.contains\(\"-uiTesting\"\)", model) else "FAIL",
    "UI-test launch hooks compiled out of Release", "guideline 2.5.19: no hidden modes in shipped builds")

# Things only a person / App Store Connect can confirm -------------------------
for item in [
    "Release archive builds and validates in Xcode (Product > Archive > Validate App)",
    "UI tests pass on an iPhone simulator and on iPad (xcodebuild test)",
    "App Privacy label in App Store Connect = Data Not Collected",
    "Age rating questionnaire answered (including the Nov 16, 2026 content descriptors)",
    "TestFlight Test Information complete: beta description, feedback email, privacy policy URL, contact, review notes",
    "Native-speaker review status of course content noted in Review Notes",
]:
    add("MANUAL", item)

# Report ----------------------------------------------------------------------
order = {"FAIL": 0, "WARN": 1, "MANUAL": 2, "PASS": 3}
width = max(len(c) for _, c, _ in results)
for status, check, detail in sorted(results, key=lambda r: order[r[0]]):
    print(f"[{status:6}] {check:<{width}}  {detail}")
counts = {s: sum(1 for r in results if r[0] == s) for s in order}
print(f"\n{counts['PASS']} pass · {counts['FAIL']} fail · {counts['WARN']} warn · {counts['MANUAL']} manual")
if counts["FAIL"]:
    print("RESULT: FAIL")
    sys.exit(1)
if STRICT and counts["MANUAL"]:
    print("RESULT: CONDITIONAL (manual items remain; --strict)")
    sys.exit(2)
print("RESULT: automated gates pass" + (" (manual items listed above still need a person)" if counts["MANUAL"] else ""))
