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
# snapshot. This machine's committer email (git config user.email) is
# replaced wherever the tree has it. The private history and its author
# emails stay private. The message ends with the private commit it
# mirrors, so RELEASES.md can name both.
set -euo pipefail

REF=${1:?ref}
BRANCH=${2:?public branch}
TAG=${3:-}
REMOTE=${PUBLIC_REMOTE:-public}
NOREPLY='244372596+Mulhimfy@users.noreply.github.com'

SRC=$(git rev-parse --verify "$REF^{commit}")
ME=$(git config user.email || true)

export GIT_INDEX_FILE
GIT_INDEX_FILE=$(mktemp)
trap 'rm -f "$GIT_INDEX_FILE"' EXIT
git read-tree "$SRC"
if [ -n "$ME" ]; then
  git grep -lF "$ME" "$SRC" -- . 2>/dev/null | sed "s/^$SRC://" |
    while IFS= read -r path; do
      mode=$(git ls-tree "$SRC" -- "$path" | cut -d' ' -f1)
      blob=$(git cat-file blob "$SRC:$path" |
        ME="$ME" NOREPLY="$NOREPLY" perl -pe 's/\Q$ENV{ME}\E/$ENV{NOREPLY}/g' |
        git hash-object -w --stdin)
      git update-index --cacheinfo "$mode,$blob,$path"
    done
fi
TREE=$(git write-tree)

PARENT=""
if git ls-remote --exit-code "$REMOTE" "refs/heads/$BRANCH" >/dev/null 2>&1; then
  git fetch -q "$REMOTE" "refs/heads/$BRANCH"
  PARENT=$(git rev-parse FETCH_HEAD)
fi

if [ -n "$PARENT" ] && [ "$(git rev-parse "$PARENT^{tree}")" = "$TREE" ]; then
  NEW=$PARENT
  echo "public/$BRANCH already has this tree: $NEW"
else
  MSG=$(git log -1 --format=%B "$SRC" |
    ME="$ME" NOREPLY="$NOREPLY" perl -pe 's/\Q$ENV{ME}\E/$ENV{NOREPLY}/g if $ENV{ME}')
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
