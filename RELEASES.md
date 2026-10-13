# Releases and patches — the ledger

The one place that says which builds exist, what they were built from, and
what has been patched onto them. **Read it before cutting a release or a
patch; add to it right after.** See `CLAUDE.md` for the rules that keep it
honest.

Ground truth, when this file and reality disagree:

| Question | Ask |
|---|---|
| Which releases can be patched | `shorebird releases list` |
| What iOS buyers are getting | `python tool/asc-versions.py` (follows each ASC label to the binary's real version) |
| Which Xcode an iOS build used | ASC `buildBundles.sdkBuild` for that build — see "Xcode" below |
| What a patch will carry | `git log <release tag>..HEAD` |

If you find a release or patch that is missing here, add it — and say where
the facts came from.

## Current (newest first)

| Release (Shorebird) | Platform | Built from | Built | Xcode / SDK | Store state | Patches |
|---|---|---|---|---|---|---|
| `1.0.8+20` | Android | `dde6556` on `design/living-sky-home`, whose app code is `b94052c`'s (only `RELEASES.md` and `codemagic.yaml` differ): `1.0.8+19`'s code + the save fix for 3 and 4 GB phones `4a2bba3` + `2c3fcaf` + the Report button `c8aa7ed` + the version bump, i.e. `1350bb2` (+19 Patch 1) + the bump. Built by the user running `shorebird release android --build-number=20` on the PC, Shorebird 1.6.123, Flutter 3.47.5; "Published Release 1.0.8+20". Tests not rerun for this build (code same as Patch 1's, whose dry run was clean). Codemagic can also build store releases since 2026-10-04: the upload keystore is stored there as `ayahreel_upload` (Personal Account → Code signing identities; CN AyahReel, expires 2053-12-09, the `C2:C9:DA:6D…` key) for `android-release` on a tag `arelease-<build>`. A first `arelease-20` (on `0fedadb`, 2026-10-04 19:33 UTC) was cancelled at the user's word before any build or Shorebird release, and the tag deleted. Now that Shorebird has `1.0.8+20` from the PC, don't tag `arelease-20` again: a Codemagic-built store release would be `+21` | 2026-10-04 (~19:36 UTC) | — | **not uploaded**. `1.0.8+19` Patch 1 already carries the same fixes, so uploading is optional and the user's call; if it goes to Play production, use the same release notes as 19 (Play's "copy from previous release"; en-US "Bug fixes, smoother editing and new features. …", 6 languages). AAB copy at `D:\Downloads\ayahreel-1.0.8+20.aab`, 127,753,383 bytes; versionCode 20, versionName 1.0.8 (bundletool), signed with the upload key — SHA-1 `C2:C9:DA:6D…`, SHA-256 `CA:9D:DD:CF…`, same as `+19`; feed `android.latest` not raised. Built on the PC's CRLF checkout, so like `+19` its patches are cut on the PC, not Codemagic | none |
| `1.0.8+19` | Android | `6dc8fe1` on `design/living-sky-home` (`+18`'s code + the recitation download fix `c280376`, merged as `c60abaf`, + the version bump), `shorebird release android --build-number=19` on this machine, Shorebird's Flutter 3.47.5 | 2026-10-03 | — | Play: **production** — Play Console on 2026-10-04 shows the track's latest release as 19 (1.0.8) in 178 countries / regions, app last updated 2026-10-03 (when it was uploaded and rolled out is not recorded; this row said not uploaded). AAB copy at `D:\Downloads\ayahreel-1.0.8+19.aab`, 127,716,191 bytes; versionCode 19, versionName 1.0.8, signed with the upload key — SHA-1 `C2:C9:DA:6D…`, SHA-256 `CA:9D:DD:CF…`, same as `+18`); feed `android.latest` not raised. On this PC 799 tests pass and 12 fail, all Windows only — `+18`'s five, and seven in `download_test.dart` that compare a `/`-built path with Windows's `\` | Patch 1, the save fix for 3 and 4 GB phones (`4a2bba3` + `2c3fcaf`, 2026-10-04), plus the Report button on failed saves (`c8aa7ed`): **published to stable 2026-10-04 ~16:55 UTC** from this PC on `1350bb2` (release commit + the fix + `c8aa7ed` + ledger and CI-only commits). Built deliberately from `1350bb2` and not origin's head, since `b94052c` bumps `pubspec.yaml` to +20; the build printed "AyahReel version: 1.0.8+19". Dart only since `6dc8fe1`, icon set the same by grep; dry run "No issues detected" with no warning (no Kotlin, Java or asset diff). Codemagic's `android-patch` had built it four times earlier that day (tags `apatch-dry-1.0.8+19`, `--2`, `--3` and `apatch-1.0.8+19`) and published nothing, because of the PC-checkout asset differences (see "Android patches from Codemagic"); next is Patch 2 |
| `1.0.8+18` | Android | `4daca10` on `design/living-sky-home` (`d517db2` + the version bump; same code as the `4953e87` it was built from before a rebase), `shorebird release android --build-number=18` on this machine, Shorebird's Flutter 3.47.5 | 2026-10-02 | — | Play: **superseded by `+19`, never to be uploaded** (copy at `D:\Downloads\ayahreel-1.0.8+18.aab`; versionCode 18, signed with the upload key `C2:C9:DA:6D…`); feed `android.latest` not raised. 784 of 789 tests pass on this PC; the five failures are Windows or timezone only (a symlink needing privilege, `/` vs `\` in a path compare, reminders read in UTC on a UTC+4 machine). Built before the recitation download fix `c280376` (merged as `c60abaf`), so it does not have it | none |
| `1.0.7+9` | iOS | tag `v1.0.7` = `f3d72b3`, Codemagic | 2026-09-25 | sdkBuild `23F81a` (= the 26.6 pin) | App Store: WAITING_FOR_REVIEW (2026-09-25) | `patch-1.0.7+9` on `218b7c1` (greeting on the badge's line), tag pushed 2026-09-26 — Codemagic build result not recorded; `patch-1.0.7+9--2` on `5ed7add` (greeting + verse numbers, branch `patch/1.0.7-verse-numbers` = `218b7c1` + cherry-pick of `e9ea60f`), tag pushed 2026-09-28 — **Codemagic build failed**, nothing shipped: asset change in `MaterialIcons-Regular.otf` (the new `format_list_numbered_rtl_rounded` icon; see "Icons" below); `patch-1.0.7+9--3` on `a359b7e` (same, with the row's icon swapped for `tag_rounded`, already in 1.0.7), tag pushed 2026-09-28 — Codemagic build result not recorded, but expect the same refusal: the Android dry run of `a359b7e` found `more_horiz` added to the font (case 2 under "Icons"); `patch-1.0.7+9--4` on `0a702b1` (same, the menu opened with `showMenu`; Android dry run clean, font byte-identical to the release's), tag pushed 2026-09-28 — Codemagic build result not recorded; `patch-1.0.7+9--5` on `0aebd8c` (same, the Verse numbers row moved from beside Verse translation to directly above Daily streak nudge; Android dry run clean), tag pushed 2026-09-28 — Codemagic build result not recorded; `patch-1.0.7+9--6` on `1684297` (on top of `--5`: 109 reciters with search and surahs a voice lacks greyed out, the surah-file and Fares Abbad recitation fixes, preview errors that say what failed, compact font cards, and one notification a day — Quran quizzes and reels with pictures; branch `patch/1.0.7-reciters-quizzes` = `0aebd8c` + cherry-picks of `b481863`…`5d60727`, leaving out `35048bf` (its Dart calls a native picker 1.0.7 doesn't have) and `94bd7a4` (an asset)); icon set checked against `v1.0.7` by grep — **no Android dry run**, this machine no longer has Shorebird or the Android SDK; 753 tests pass on the branch; tag pushed 2026-09-30 — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `1684297`); `patch-1.0.7+9--7` on `7ebf4ea` (on top of `--6`: each part of the day has three or four endings taken in turn, so no two nights end alike — at nine every night it had said "before you sleep"; three templates rewritten in all five languages where an ending doubled a word, the tea line with them; a window laid in older words is laid again at the next launch (`ReminderCopy.version`), so phones on `--6` drop its fortnight of identical endings; cherry-pick of `49740c1`); no icon, native or asset change; 756 tests pass on the branch; tag pushed 2026-09-30 — **Codemagic build succeeded** (2026-09-30 05:30 UTC); `patch-1.0.7+9--8` on `d308c56` (on top of `--7`, two cherry-picks: `25b8a4a` of `fa05401`, 2026-10-01 — saves that failed at their last step on phones short of storage, renders and gallery-named copies never deleted from the cache; and `d308c56` of `d82163d`, 2026-10-02 — FFmpeg's log and statistics events switched off and save progress read from FFmpeg's `-progress` file, for Play's 1.0.7 ANR in `StandardMessageCodec` during an export; a failed encode's log fetched once; the `-benchmark` diagnostic removed); Dart only, no icon, native, asset or `codemagic.yaml` change since `--7`, icon set same as `v1.0.7` by grep, Xcode pin 26.6 = `23F81a`, 773 tests pass on the branch; Android dry run of the same commit clean on 2026-10-02 (Android Patch 5, from the user's Windows PC, which does have Shorebird and the SDK); tag pushed by the user 2026-10-02 — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `d308c56`, 2026-10-02 17:35 UTC); `patch-1.0.7+9--9` on `e49297c` (on top of `--8`, cherry-pick `-x` of `c280376`: recitations that a slow or broken connection used to lose now finish. Per-ayah files get 30 s without a byte instead of 30 s for the whole file, and are streamed to disk; requests that don't answer are aborted instead of left running; surah slices resume from the byte reached and keep what came across fetches; tries are 1/2/4 s apart and a try that brought bytes doesn't count; the surah text is retried; the preview retries when the app comes back to a connection error. Reproduced first through the real `RecitationService` behind a bad-network proxy: 600 kbps, a drop every 2.5 MB and a 40 s stall each failed with "offline" before, and finished after); Dart only, no icon, native, asset or `codemagic.yaml` change since `--8`, icon set same as `v1.0.7` by grep (the one extra hit, `Icons.adaptive`, is a doc comment in `settings_screen.dart`), Xcode pin 26.6 = `23F81a`, `flutter analyze` clean and 795 tests pass on the branch; **no Android dry run before the tag**: the PC session was cutting Android Patch 6 from the same change (patch-id `08393732ee0c`) and had not reported 40 minutes after the fix reached GitHub; tag pushed 2026-10-02 21:21 UTC on the user's go-ahead — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `e49297c`, 2026-10-02 21:34 UTC); `patch-1.0.7+9--10` on `7d74ff1` (on top of `--9`: the save fix for small phones, `be724a0` = cherry-pick `-x` of `4a2bba3` — exports planned to the phone's memory, one decoder thread per verse card, a lost export remembered, loop-aware pass cuts, hardware-encoder timeouts, an `export` line in feedback notes — and `1778d5a`, the 32-bit check without dart:ffi; the other four commits since `--9` are `codemagic.yaml` only, adding `android-patch` and leaving `ios-patch` as it was); Dart only, no icon, native or asset change, icon set same as `--9` by grep (the extra `Icons.adaptive` is the known doc comment), Xcode pin 26.6 = `23F81a`, `flutter analyze` clean and 814 tests pass on the branch. **No clean Android dry run before the tag**: Codemagic's Android checks of this commit found only the PC-checkout asset differences (NOTICES, a JSON or README; no icon font, shader or Kotlin change), and the PC wasn't reachable. Tag pushed 2026-10-04 15:21 UTC on the user's standing go-ahead ("ota to the users … don't ask") — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `7d74ff1`, 2026-10-04 16:07 UTC); next is `--11`, which would carry `48a0836` (the Report button on failed saves and the next-launch notice after a lost one; Dart only, icon set unchanged) — not tagged, waiting on the user |
| `1.0.7+17` | Android | `v1.0.7` line, built locally (exact commit not recorded; its icon font matches `v1.0.7`'s) | 2026-09-25 | — | Play: not recorded | Patch 1: not recorded (this row said `218b7c1` was unpublished, but Shorebird numbered the next one 2); **Patch 2** on `0a702b1` (greeting + verse numbers, branch `patch/1.0.7-verse-numbers`), published to stable from this machine 2026-09-28 after a clean dry run; **Patch 3** on `0aebd8c` (same, the Verse numbers row moved to directly above Daily streak nudge), published to stable 2026-09-28 after a clean dry run; **Patch 4**: on stable per `shorebird patches list` (id 684445), though this row had it as not made — who cut it, from which commit and when is not recorded; **Patch 5** on `d308c56` (branch `patch/1.0.7-reciters-quizzes`: everything in iOS `--7` — the reciters, preview errors, one notification a day with its endings — plus the storage fix `25b8a4a` and the FFmpeg main-thread fix for this release's ANR and `writeBytes` OOM on Play), published to stable 2026-10-02 from the `C:\Users\dell\ayah_patch_android` worktree after a clean dry run (no icon, native or asset diff); **Patch 6** (id 691513), the recitation download fix = iOS `--9`: built from `03ac5cb`, a cherry-pick of `c280376` onto `d308c56` whose tree is identical to the branch head `e49297c` (patch-id `08393732ee0c`), published to stable 2026-10-03 from the same worktree after a clean dry run (no icon, native or asset diff; built with the release's Flutter 3.47.1). The first dry run hung overnight with nothing built, the PC most likely asleep; the second took about 5 minutes. On this PC 783 tests pass and 12 fail, all Windows only — the usual five, and seven in the new `download_test.dart` that compare a `/`-built path with Windows's `\` (all 13 pass with a separator-proof compare); **Patch 7**, the save fix for 3 and 4 GB phones plus the Report button on failed saves and the next-launch notice after a lost one: **published to stable 2026-10-04 ~16:50 UTC** from the `C:\Users\dell\ayah_patch_android` worktree on `48a0836` (`origin/patch/1.0.7-reciters-quizzes`: `e49297c`, whose tree is Patch 6's, + `be724a0` + `1778d5a` + `48a0836` + CI-only commits). Dart only, icon set the same as Patch 6 by grep; dry run "No issues detected" with no warning. Codemagic's `android-patch` had built it earlier that day (tags `apatch-dry-1.0.7+17`, `apatch-1.0.7+17`, `apatch-dry-1.0.7+17--2`) and published nothing, because of the PC-checkout asset differences. Android now has the Report button and iOS doesn't, until `patch-1.0.7+9--11` is tagged; next is Patch 8 |
| `1.0.6+8` | iOS | tag `v1.0.6` = `39ff928` | 2026-09-12 | sdkBuild `23F81a` (Xcode 26.6) | App Store: READY_FOR_SALE | tags `patch-1.0.6+8`, `--2`, `--3`; next is `--4` |
| `1.0.6+16` | Android | `1.0.6` line | not recorded (`v1.0.6` is 2026-09-12) | — | Play: not recorded | not recorded |
| `1.0.5+7` | iOS | tag `v1.0.5` = `0c43be9` | 2026-09-06 | Xcode 26.4.1 | READY_FOR_SALE | `patch-1.0.5+7` … `--5`, from branch `patch/1.0.5-b7-meta-app-id` |
| `1.0.5+15` | Android | `fb33c84` | 2026-09-06 | — | Play production | patches 1–3 from branch `patch/1.0.5-b15-series-settings` |

Older releases (1.0.4 and below, 0.1.x) are still listed by Shorebird and
were back-patched with the update checker in August 2026; the history lives
in `LAUNCH.md`.

## What each release actually contains

A patch only fixes a release that has the bug. Check with
`git show <release tag>:<file>` before patching an older release.

- **Home header** — 1.0.7 puts the rewards cartouche on its own line under
  the greeting. 1.0.6 and older have greeting, wordmark and cartouche in one
  row, so a fix to the 1.0.7 layout is for 1.0.7 only.

## Android patches from Codemagic

Since 2026-10-04 an Android patch no longer needs the PC. The
`android-patch` workflow in `codemagic.yaml` builds it on a Codemagic Mac
with the `shorebird` group's token; a patch needs no keystore.

- `git tag apatch-dry-<release>`: analyze, test and
  `shorebird patch android --dry-run`. Nothing is uploaded.
- `git tag apatch-<release>`: the same, then it publishes to stable, but
  only if the dry run printed "No issues detected" and no warning. A
  later patch of the same release is `apatch-<release>--2`.
- `<release>` is Shorebird's Android string (`1.0.8+19`, `1.0.7+17`),
  never the iOS one. `apatch-`, because `ios-patch` takes every
  `patch-*` tag.
- The result is the GitHub check "Android - Shorebird OTA patch" on the
  tagged commit from app `6a63ba37…`
  (`gh api repos/Mulhimfy/ayahReel/commits/<sha>/check-runs`). The log
  needs a Codemagic login, and this app sends no success emails, so the
  check spells the verdict out: one "Verdict: …" step per fact (Shorebird
  finished, Gradle built, release found, no Kotlin or Java change, no
  asset change, "No issues detected", clean), each a tick or a cross, and
  a last step "Published", red when a publishing tag shipped nothing. A second Codemagic app
  (`6a9d08ca…`) runs every tag too and fails at once: it has no Shorebird
  token (for Android) and no "AyahReel ASC key" (for iOS, the failure
  emails), so it can never publish anything.
- **A release built on the PC can't be patched from here** (found
  2026-10-04 on both `1.0.8+19` and `1.0.7+17`). Kotlin and Java come out
  the same (JDK 21 here). But NOTICES and a bundled JSON or README differ,
  because the PC's checkout writes some text files with CRLF and the
  release carries those bytes. `--allow-asset-diffs` is never the answer,
  so those patches are cut on the PC. A release built on Codemagic, or on
  a checkout with the same line endings as Codemagic's, could be patched
  here.
- If the dry run reports Kotlin or Java changes because Codemagic's JDK
  compiles them differently from the PC's, the patch goes back to the PC.

## Icons

Flutter tree-shakes `MaterialIcons-Regular.otf` down to the glyphs the
compiled app can reach, and Shorebird refuses a patch whose font differs from
the release's. Two ways a Dart-only change moves the font:

1. **A new `Icons.*` in our code** (or one no longer used). Quick check:
   ```bash
   git grep -h -oE '\bIcons\.[a-zA-Z0-9_]+' <release tag> -- lib | sort -u > /tmp/rel
   grep -rhoE '\bIcons\.[a-zA-Z0-9_]+' lib | sort -u | diff /tmp/rel -
   ```
   `patch-1.0.7+9--2` failed on this (`format_list_numbered_rtl_rounded`).
2. **A framework fallback icon coming back to life.** The grep above can't
   see these. Every `PopupMenuButton` in 1.0.7 passes `icon:`, so the
   compiler drops `widget.icon ?? Icon(Icons.adaptive.more)` and its glyph;
   one `PopupMenuButton(child: …)` revives it and adds `more_horiz`. That
   was the second failure (`--3`). Use `showMenu` from an `InkWell` instead.

The real check is the font itself. The Android dry run does it for you (a
`[WARN] … asset changes` line naming the `.otf`). To see which glyphs, pull
the font out of the release's AAB and a fresh build and diff code points
(fontTools; map them to names with Flutter's `material/icons.dart`):

```bash
unzip -j <aab> base/assets/flutter_assets/fonts/MaterialIcons-Regular.otf -d <dir>
python -c "from fontTools.ttLib import TTFont as F; import sys; a,b=(set(F(p).getBestCmap()) for p in sys.argv[1:]); print([hex(c) for c in a^b])" rel.otf patch.otf
```

An empty list means the same font. iOS has no local dry run (no Mac), so
check Android first: the glyph set is decided in Dart, the same way on both.

## Xcode for iOS patches

`codemagic.yaml` builds store releases on `xcode: latest` but pins the
`ios-patch` workflow to one version, because a different asset compiler
re-authors `Assets.car` and Shorebird refuses the patch as an asset change.
The pin has to equal what the **release being patched** was built with.

After every iOS store build, compare its `sdkBuild` with the release the pin
was set for. Same `sdkBuild` means same Xcode, and the pin stands. A new one
means the new release needs the pin moved, and older releases then need
their own pin, on a branch. Read `sdkBuild` with the ASC API (read-only):

```
GET /v1/builds?filter[app]=6794389870&filter[preReleaseVersion.version]=<train>&include=buildBundles
```

using `_token()` and `_get()` from `tool/asc-versions.py`.

| sdkBuild | Xcode | Releases |
|---|---|---|
| `23F81a` | 26.6 (17F113) | `1.0.6+8`, `1.0.7+9` — checked 2026-09-25 |
