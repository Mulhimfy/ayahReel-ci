#!/usr/bin/env bash
# Rewrites kAppVersion in lib/data/app_version.dart, and prints it.
#
# The marketing version has to exist in two places at once: pubspec.yaml,
# because that is what gets baked into the binary the stores display, and
# lib/data/app_version.dart, because UpdateService compares against a Dart
# constant rather than a native package read (see the notes in that file for
# why). Two copies of one number is a drift waiting to happen — a release
# where they disagree either nags users who are already current or stays
# silent for users who are behind, and neither shows up in testing.
#
# So nobody edits the Dart constant by hand. This does it:
#
#   tool/sync-version.sh            # takes the version from pubspec.yaml
#   tool/sync-version.sh 1.0.1      # takes the version given
#   tool/sync-version.sh 1.0.1+12   # same — anything after '+' is dropped
#
# The argument form is for OTA patches. A patch belongs to one release, and
# the release being patched is named by the tag (patch-1.0.1+12), not by
# whatever pubspec says on the commit the fix happens to sit on. Pushing the
# checker back to users still on 1.0.1 means their copy must say '1.0.1',
# or it reads itself as current and never prompts — the exact failure this
# whole feature exists to avoid.
#
# test/version_sync_test.dart fails the build if the two ever disagree, so a
# forgotten run is caught by CI rather than by users.
set -euo pipefail

root="$(dirname "$0")/.."
dart="$root/lib/data/app_version.dart"

version="${1:-}"
if [ -z "$version" ]; then
  version=$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' "$root/pubspec.yaml" | head -1)
fi

# A release version is <marketing>+<build>; only the marketing half is what
# the stores show and what the feed publishes.
version="${version%%+*}"

if ! printf '%s' "$version" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
  echo "sync-version: '$version' is not a dotted version." >&2
  exit 1
fi

if ! grep -q "^const kAppVersion = '" "$dart"; then
  echo "sync-version: no 'const kAppVersion = ...' line in $dart." >&2
  exit 1
fi

# Written through a temp file rather than `sed -i`: the in-place flag takes
# an argument on BSD sed and not on GNU sed, and this runs on both.
tmp="$dart.sync.tmp"
sed "s/^const kAppVersion = '.*';\$/const kAppVersion = '$version';/" \
  "$dart" > "$tmp"
mv "$tmp" "$dart"

echo "$version"
