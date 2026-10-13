# AyahReel — notes for AI sessions

## Releases and patches

`RELEASES.md` is the ledger of every store build and every Shorebird patch.
Read it before building or patching anything.

**Keep it current. This is a requirement, not a courtesy.** Whenever you
build a release (`v*` tag, `shorebird release …`) or publish or queue a patch
(`patch-*` tag, `shorebird patch …`), add the row or the patch to
`RELEASES.md` in the same session, before you report the work as done. Record
the release string, platform, commit, date, Xcode/`sdkBuild` for iOS, store
state and tag. Do the same when you notice something the ledger is missing,
such as a release in `shorebird releases list` or a tag in `git tag` with no
row. Write "not recorded" rather than guess.

Rules that each cost a failed build or a wrong patch once:

- **Shipping is the user's call.** A pushed `patch-*` tag, or a
  `shorebird patch` without `--dry-run`, reaches installed apps on their
  next launch. There is no review and no undo, only a later patch. A `v*` tag
  builds and submits to App Review. Say plainly that it ships, and wait for
  an explicit yes to that step alone.
- **The patch target is the exact Shorebird release string**,
  `<version>+<build>`, taken from `shorebird releases list`. iOS and Android
  build numbers differ (`1.0.7+9` vs `1.0.7+17`). Never take it from
  `pubspec.yaml` or from the App Store label, which has drifted from the
  binary's version before (see `tool/asc-versions.py`).
- **A patch carries everything since the release commit.** Before tagging,
  `git log <release tag>..HEAD` should show only the fix. If the branch has
  moved on, branch from the release tag and cherry-pick the fix.
- **Patch only the releases that have the bug.** Check the code at each
  release tag (`git show v1.0.6:<file>`); layouts differ between versions.
- **iOS patch Xcode must match the release's Xcode.** See "Xcode for iOS
  patches" in `RELEASES.md`. Compare `sdkBuild` after every iOS store build.
- **Android: dry-run first.** `shorebird patch android
  --release-version=<v+b> --dry-run` should say "No issues detected".
- **Never pass `--allow-native-diffs` or `--allow-asset-diffs`.** A diff means
  the change needs a store build.
- **A patch can't change the icon font.** Flutter subsets it to the glyphs
  the compiled app can reach, so a new `Icons.*`, or a widget use that
  revives a framework fallback icon (`PopupMenuButton(child:)` does), is an
  asset change. See "Icons" in `RELEASES.md`; dry-run Android before
  tagging iOS, since iOS can't be checked locally.
- **At most three tags per `git push`.** GitHub sends no webhook for more,
  and Codemagic never builds them. Tag names can't be reused; a later patch
  of the same release takes a suffix: `patch-1.0.6+8--4`.
- **Android back-patch to an older release:** run
  `./tool/sync-version.ps1 <version>` first so `kAppVersion` names the
  release being patched (see `LAUNCH.md`).
- **`pubspec.lock` with five packages downgraded is SDK noise on this
  machine.** `git checkout -- pubspec.lock`; never commit it.
- **Line endings:** `.gitattributes` pins bundled READMEs and JSON to LF.
  A CRLF checkout of them shows up as an asset diff and blocks the patch.

## Saves on small phones

Before changing the export for a "can't save" or "the app closed"
report, read `EXPORT_MEMORY.md`: what a save costs, what each budget
does, how to read a note's `export` field, and the next levers in order.
