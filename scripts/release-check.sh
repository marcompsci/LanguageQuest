#!/usr/bin/env bash
# Run before every TestFlight upload. Exits non-zero unless every automated gate passes.
# Manual items are printed and must be confirmed in docs/testflight-release-checklist.md.
set -uo pipefail
cd "$(dirname "$0")/.."
status=0

step() { printf '\n== %s ==\n' "$1"; }

step "1/4 Compliance gate (static)"
python3 scripts/compliance-check.py --strict; rc=$?
if [ $rc -eq 1 ]; then echo "FAIL: compliance gate"; status=1; fi
if [ $rc -eq 2 ]; then echo "MANUAL items remain (see list above)"; fi

step "2/4 LQCore unit tests"
if command -v swift >/dev/null || [ -x /opt/swift/usr/bin/swift ]; then
  if [ -x scripts/test-core.sh ]; then scripts/test-core.sh || { echo "FAIL: unit tests"; status=1; }
  else (cd Packages/LQCore && swift test) || { echo "FAIL: unit tests"; status=1; }; fi
else
  echo "FAIL: Swift toolchain not found, so unit tests did not run"; status=1
fi

step "3/4 Xcode Release build + UI tests (macOS only)"
if command -v xcodebuild >/dev/null; then
  xcodebuild -project LanguageQuest.xcodeproj -scheme LanguageQuest -configuration Release \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet || { echo "FAIL: Release build"; status=1; }
  SIM=$(xcrun simctl list devices available | grep -m1 -o 'iPhone [^(]*' | sed 's/ *$//')
  xcodebuild -project LanguageQuest.xcodeproj -scheme LanguageQuest -destination "platform=iOS Simulator,name=$SIM" test -quiet \
    || { echo "FAIL: UI tests"; status=1; }
else
  echo "NOT RUN: xcodebuild unavailable on this machine. Run this script on a Mac before uploading."; status=1
fi

step "4/4 Archive"
echo "MANUAL: In Xcode choose Any iOS Device, Product > Archive, then Validate App in the Organizer."

echo
if [ $status -eq 0 ]; then echo "Automated release checks passed. Finish the manual items in docs/testflight-release-checklist.md."
else echo "Release checks FAILED or did not all run. Do not upload."; fi
exit $status
