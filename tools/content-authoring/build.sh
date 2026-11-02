#!/usr/bin/env bash
# Regenerates every bundled course's JSON from these authoring scripts, then runs
# the content tests. The scripts are the source of truth for content.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
content="$here/../../Packages/LQCore/Sources/LQCore/Resources/Content"
for s in course unit1 unit2 unit3; do python3 "$here/$s.py" "$content/en-es"; done
python3 "$here/fr.py" "$content/en-fr"
python3 "$here/ja.py" "$content/en-ja"
python3 "$here/starter.py" "$content" "$here/../../Packages/LQCore/Sources/LQCore/World/VillageWords+Generated.swift"
"$here/../../scripts/test-core.sh" --filter "ContentTests|MultiCourseTests"
