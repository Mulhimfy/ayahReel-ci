#!/usr/bin/env bash
# One Flutter for everything: the store builds (Shorebird), the preview
# APKs the user tries on a phone, the desk previews, the CI tests and
# Codemagic. Prints that version, or fails naming each place that would
# build or test on another one, so what is tested is what ships.
#
#   bash tool/check_flutter_version.sh
#
# The version lives in flutter_version.txt. GitHub workflows read the file
# themselves; codemagic.yaml's `flutter:` pins can't, so they are compared
# here. Every `shorebird release` has to name the version too: without
# --flutter-version, Shorebird builds with its newest Flutter.
#
# flutter-test.yml runs this on every push, and both release workflows
# run it before they build. 1.0.9 shipped on 3.47.5 while the previews
# had been built on 3.44.6 since 1.0.8; this is what stops that.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

want=$(tr -d '[:space:]' < flutter_version.txt)
if ! printf '%s' "$want" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "flutter_version.txt says '$want', not a version like 3.47.5." >&2
  exit 1
fi

files=(.github/workflows/*.yml codemagic.yaml)
bad=0
complain() {
  echo "$1" >&2
  bad=1
}

# A version written out anywhere a build or a test is set up.
ver='[0-9]+\.[0-9]+\.[0-9]+'
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  where=$(printf '%s' "$hit" | cut -d: -f1,2)
  got=$(printf '%s' "${hit#*:*:}" | grep -oE "$ver" | head -1)
  [ "$got" = "$want" ] ||
    complain "$where pins Flutter $got; flutter_version.txt says $want."
done < <(grep -nHE "(flutter-version|FLUTTER_VERSION)[\"']?[[:space:]]*[:=][[:space:]]*[\"']?$ver|^[[:space:]]*flutter:[[:space:]]*[\"']?$ver" \
  "${files[@]}" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)

# subosito/flutter-action with no version installs the newest stable.
for f in .github/workflows/*.yml; do
  uses=$(grep -cE '^[^#]*uses:[[:space:]]*subosito/flutter-action' "$f" || true)
  reads=$(grep -cE '^[^#]*flutter-version:[[:space:]]*\$\{\{[[:space:]]*steps\.flutter\.outputs\.version[[:space:]]*\}\}' "$f" || true)
  [ "$uses" = "$reads" ] ||
    complain "$f: $uses subosito/flutter-action step(s), $reads reading flutter_version.txt (steps.flutter.outputs.version)."
done

# A Shorebird release names its Flutter on the line that runs it.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  printf '%s' "$hit" | grep -q -- '--flutter-version' ||
    complain "$(printf '%s' "$hit" | cut -d: -f1,2): shorebird release without --flutter-version (it would take Shorebird's newest Flutter)."
done < <(grep -nHE '^[^#]*shorebird release (android|ios)' "${files[@]}" || true)

if [ "$bad" != 0 ]; then
  echo "Make them all $want, or change flutter_version.txt." >&2
  exit 1
fi
echo "$want"
