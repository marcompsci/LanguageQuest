#!/usr/bin/env bash
# Runs the LQCore unit tests (content, assessment, review, save/load, progression,
# purchase gating, parental gate, world, accessibility, offline/privacy checks).
# Works on macOS (Xcode command line tools) and Linux (Swift 5.9+).
set -euo pipefail
cd "$(dirname "$0")/../Packages/LQCore"
if [ -d /opt/swift/usr/libexec/swift/bin ] && ! command -v swift >/dev/null; then
  export PATH=/opt/swift/usr/libexec/swift/bin:$PATH
  export LD_LIBRARY_PATH=/opt/swift/usr/lib/x86_64-linux-gnu:/opt/swift/usr/libexec/swift/lib/swift/linux:${LD_LIBRARY_PATH:-}
fi
swift test "$@"
