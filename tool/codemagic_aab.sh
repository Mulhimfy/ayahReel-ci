#!/usr/bin/env bash
# Waits for Codemagic's android-release build of an `arelease-<n>` tag and
# downloads its .aab. Used by .github/workflows/play-upload.yml.
#
#   CODEMAGIC_TOKEN=<api token> tool/codemagic_aab.sh arelease-22 out.aab
set -euo pipefail

TAG=$1
OUT=$2
APP=6a63ba37239456f26d0fe4ca   # ayahReel on Codemagic
AUTH="x-auth-token: ${CODEMAGIC_TOKEN:?CODEMAGIC_TOKEN is not set}"
deadline=$((SECONDS + 170 * 60))

while :; do
  json=$(curl -fsS -H "$AUTH" \
    "https://api.codemagic.io/builds?appId=$APP&workflowId=android-release&tag=$TAG") || json='{}'
  build=$(TAG="$TAG" jq -c '[.builds[]? | select(.tag == env.TAG)] | sort_by(.index) | last // empty' <<<"$json")
  [ -n "$build" ] || build='{}'
  status=$(jq -r '.status // "not started yet"' <<<"$build")
  echo "$(date -u +%H:%M:%S) $TAG: $status"
  case $status in
    finished) break ;;
    failed | canceled | timeout | skipped)
      echo "::error::Codemagic's build of $TAG ended $status; nothing was uploaded."
      exit 1 ;;
  esac
  if ((SECONDS > deadline)); then
    echo "::error::Gave up waiting for Codemagic's build of $TAG."
    exit 1
  fi
  sleep 60
done

echo "Codemagic build $(jq -r ._id <<<"$build") finished."
url=$(jq -r '[.artefacts[]? | select(.name | endswith(".aab"))][0].url // empty' <<<"$build")
if [ -n "$url" ]; then
  curl -fsSL -H "$AUTH" -o "$OUT" "$url"
else
  # Several artefacts come as one zip.
  zip=$(jq -r '[.artefacts[]? | select(.name | endswith(".zip"))][0].url // empty' <<<"$build")
  [ -n "$zip" ] || { echo "::error::The build has no .aab artefact."; exit 1; }
  dir=$(mktemp -d)
  curl -fsSL -H "$AUTH" -o "$dir/a.zip" "$zip"
  unzip -q "$dir/a.zip" -d "$dir"
  found=$(find "$dir" -name '*.aab' | head -1)
  [ -n "$found" ] || { echo "::error::No .aab inside the build's artefacts."; exit 1; }
  mv "$found" "$OUT"
fi
ls -l "$OUT"
