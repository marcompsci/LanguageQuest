#!/usr/bin/env bash
# Regenerates the bundled Spanish course JSON from these authoring scripts,
# then runs the content tests. The scripts are the source of truth for content.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../../Packages/LQCore/Sources/LQCore/Resources/Content/en-es"
for s in course unit1 unit2 unit3; do python3 "$here/$s.py" "$out"; done
"$here/../../scripts/test-core.sh" --filter ContentTests
