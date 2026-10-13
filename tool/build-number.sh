#!/usr/bin/env bash
# Bumps build_number.txt by 1 and prints the new value.
#
# Single source of truth for BOTH platforms — Android versionCode and iOS
# CFBundleVersion come from the same number, so they never drift apart:
#
#   flutter build appbundle   --build-number=$(tool/build-number.sh)
#   flutter build ipa         --build-number=$(tool/build-number.sh)
#   shorebird release android --build-number=$(tool/build-number.sh)
#
# Both stores require this to be strictly GREATER than the last accepted
# upload (Apple rejects a duplicate CFBundleVersion, Play a duplicate
# versionCode). +1 each time satisfies that. Gaps are legal too, so if a number
# ever gets burned by a rejected upload, just run this again.
#
# Commit build_number.txt after a store upload, so the counter does not reset
# or collide when building from another machine.
set -euo pipefail

file="$(dirname "$0")/../build_number.txt"

current=$(tr -cd '0-9' < "$file" 2>/dev/null || echo "")
current=${current:-0}

next=$(( current + 1 ))
echo "$next" > "$file"
echo "$next"
