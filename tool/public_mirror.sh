#!/usr/bin/env bash
# Mirrors a commit of this private repo to the public CI repo,
# Mulhimfy/ayahReel-ci, where GitHub Actions minutes are free. Since
# 2026-10-13 the private repo's jobs don't start ("recent account
# payments have failed"), so tests, preview APKs and Shorebird patches
# run there instead, from the same workflow files.
#
#   tool/public_mirror.sh <ref> <public-branch>          push a snapshot of <ref>
#   tool/public_mirror.sh <ref> <public-branch> <tag>    ... and tag the snapshot
#
# A gpatch-*/gipatch-* tag SHIPS a patch, exactly as it did on the
# private repo: the user's call, one tag per run (at most three per
# push, or GitHub sends no event).
#
# The public repo gets snapshots, not history: each mirrored commit
# becomes one commit with the same tree and message, authored by the
# GitHub noreply address, its parent the public branch's previous
# snapshot. Every private address — this machine's committer email, and
# every address that authored or committed in the private history, the
# owner's among them, whoever runs this — is replaced wherever the tree
# or the message has it, and the push is refused if one is left. The
# private history and its author emails stay private. The message ends with the private commit it
# mirrors, so RELEASES.md can name both.
set -euo pipefail

REF=${1:?ref}
BRANCH=${2:?public branch}
TAG=${3:-}
REMOTE=${PUBLIC_REMOTE:-public}
NOREPLY='244372596+Mulhimfy@users.noreply.github.com'

SRC=$(git rev-parse --verify "$REF^{commit}")

# The addresses that must not reach the public tree. Not only this
# machine's: on 2026-10-22 a session whose own address was a noreply one
# mirrored the owner's (in tool/harvest_scenes.py) because only the
# runner's was replaced. So every address in the private history goes
# too. Public noreply addresses stay as they are.
SCRUB=$(
  { git config user.email || true
    git log --format='%ae%n%ce' "$SRC" 2>/dev/null || true
  } | grep -v -i -e '^$' -e 'noreply' | sort -u || true
)
SCRUB_ARGS=()
while IFS= read -r e; do
  [ -n "$e" ] && SCRUB_ARGS+=(-e "$e")
done <<<"$SCRUB"
scrub() {
  SCRUB="$SCRUB" NOREPLY="$NOREPLY" perl -pe '
    BEGIN { @addr = grep { length } split /\n/, $ENV{SCRUB} }
    for my $a (@addr) { s/\Q$a\E/$ENV{NOREPLY}/g }'
}

# The mirror's artifacts are public, and GitHub masks secrets only in a
# job's own log, never in a file the job uploads: on 2026-10-13 an iOS
# patch log carried three secrets that way. A workflow that uploads logs
# must pass them through tool/redact_logs.py first. A branch cut from an
# older release tag needs that commit cherry-picked before it's mirrored.
for wf in $(git ls-tree --name-only "$SRC" .github/workflows/); do
  body=$(git cat-file blob "$SRC:$wf")
  if grep -q 'upload-artifact' <<<"$body" && grep -qE '\.log\b' <<<"$body" &&
     ! grep -q 'tool/redact_logs.py' <<<"$body"; then
    echo "$wf uploads logs without tool/redact_logs.py: not mirrored." >&2
    exit 1
  fi
done

export GIT_INDEX_FILE
GIT_INDEX_FILE=$(mktemp)
trap 'rm -f "$GIT_INDEX_FILE"' EXIT
git read-tree "$SRC"
if [ ${#SCRUB_ARGS[@]} -gt 0 ]; then
  # git grep answers 1 when nothing matches, which under pipefail would
  # end the script here, silently, with nothing pushed.
  { git grep -lF "${SCRUB_ARGS[@]}" "$SRC" -- . 2>/dev/null || true; } |
    sed "s/^$SRC://" |
    while IFS= read -r path; do
      mode=$(git ls-tree "$SRC" -- "$path" | cut -d' ' -f1)
      blob=$(git cat-file blob "$SRC:$path" | scrub | git hash-object -w --stdin)
      git update-index --cacheinfo "$mode,$blob,$path"
    done
fi
TREE=$(git write-tree)
if [ ${#SCRUB_ARGS[@]} -gt 0 ] &&
   git grep -qF "${SCRUB_ARGS[@]}" "$TREE" -- . 2>/dev/null; then
  echo "A private address is still in the tree: not mirrored." >&2
  exit 1
fi

PARENT=""
if git ls-remote --exit-code "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1; then
  git fetch -q "$REMOTE" "refs/heads/$BRANCH"
  PARENT=$(git rev-parse FETCH_HEAD)
fi

if [ -n "$PARENT" ] && [ "$(git rev-parse "$PARENT^{tree}")" = "$TREE" ]; then
  NEW=$PARENT
  echo "public/$BRANCH already has this tree: $NEW"
else
  MSG=$(git log -1 --format=%B "$SRC" | scrub)
  NEW=$(printf '%s\n\nMirrors %s of the private repo.\n' "$MSG" "$SRC" |
    GIT_AUTHOR_NAME=Mulhimfy GIT_AUTHOR_EMAIL="$NOREPLY" \
    GIT_AUTHOR_DATE="$(git log -1 --format=%aI "$SRC")" \
    GIT_COMMITTER_NAME=Mulhimfy GIT_COMMITTER_EMAIL="$NOREPLY" \
    git commit-tree "$TREE" ${PARENT:+-p "$PARENT"})
  git push -q "$REMOTE" "$NEW:refs/heads/$BRANCH"
  echo "public/$BRANCH = $NEW (mirrors $SRC)"
fi

if [ -n "$TAG" ]; then
  git push -q "$REMOTE" "$NEW:refs/tags/$TAG"
  echo "tag $TAG -> $NEW"
fi
