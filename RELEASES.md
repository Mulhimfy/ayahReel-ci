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
| `1.0.9+11` | iOS | `2c015f8` on `main` = the app code of `8e4b5fc` (the same as Android `1.0.9+23`) + `2c015f8` (the release jobs' fix, no app code). Tag `girelease-1.0.9--2`, GitHub run 38209584875 (`ios-release.yml`): Xcode 26.6, Shorebird 1.6.128, Flutter 3.47.5 (`ff900e7fba`); build number from Apple (TestFlight's newest was 9), passing over 10, which Shorebird had from the failed first run; "Published Release 1.0.9+11" (Shorebird release id 891550). IPA `com.ayahReel.app` 1.0.9 (11), `DTSDKBuild` `23F81a`, 74,903,081 bytes, kept 30 days as the run's `ipa` artifact; uploaded by altool 26.40.1 ~05:55 UTC (delivery `f9cf3315…`), processed VALID, no non-exempt encryption | 2026-10-12 (~05:54 UTC) | sdkBuild `23F81a` (Xcode 26.6, the `ios-patch.yml` pin) | App Store: **READY_FOR_SALE** (ASC API, checked 2026-10-13 ~18:10 UTC). Before that **WAITING_FOR_REVIEW**: version 1.0.9 (`c54be1ce…`) submitted 2026-10-12 05:59:37 UTC (review submission `1ac02a03-6fbf-4044-8aa0-661d29c135de`), release type `AFTER_APPROVAL` (on sale by itself once approved), no phased release, copyright "2026 AyahReel", What's New from `docs/store/release-notes/1.0.9/app-store.json` (en-US). iOS buyers go from 1.0.7 straight to this; there was never an iOS 1.0.8. Feed `ios.latest` not raised yet (only once the App Store serves it) | **Patch 1** (id 716474): **published to stable 2026-10-13** by `gipatch-1.0.9+11` on the public mirror (run 38448437728; Xcode 26.6, SDK `23F81a`): the same three fixes as Android `1.0.9+23` Patch 1, from `patch/1.0.9` = `d7e28c9`. See "Android patches from GitHub Actions", 2026-10-13. **Patch 2**: **published to stable 2026-10-14** by `gipatch-1.0.9+11--2` on the mirror (run 38606136390; Xcode 26.6): the same code as Android `1.0.9+23` Patch 2, `690ad56` (mirror `b0332ca`). Next: `gipatch-1.0.9+11--3` |
| `1.0.9+23` | Android | `8e4b5fc` on `main` (2026-10-12): `main`'s `f81f0d8` + the merge of `feat/live-recitation` at `e6cf90d` (`ff5d388`: live recitation in the verse picker, Instagram Story, Your verses / My works, the Tanafus card, share notifications, frames and kept colours, the `:render` save process, `BootReceiver`, and the 2026-10-11 save and crash fixes) + `a97738f` (version 1.0.9+23, `kAppVersion` 1.0.9, `build_number.txt` 23, the GitHub release jobs) + `8e4b5fc` (release notes). Tag `garelease-23`, GitHub run 38208595778 (`android-release.yml`): `shorebird release android --build-number=23 --flutter-version=3.47.5`, Shorebird 1.6.128, Flutter 3.47.5 (`ff900e7fba`); Gradle printed "AyahReel version: 1.0.9+23"; "Published Release 1.0.9+23" (Shorebird release id 891549). Before it: `flutter analyze` clean and 936 tests passed, 143 skipped (run 38208119290, on `a97738f`, whose app code is the tag's) | 2026-10-12 (~05:50 UTC) | — | Play: **production, status completed (everyone, no staged rollout), sent for review** 2026-10-12 ~05:52 UTC by the same run's Play job (`tool/play_upload.mjs release`), replacing 22 (1.0.8); notes from `docs/store/release-notes/1.0.9/play.json` in en-US, ar, fr-FR, hi-IN, id, ru-RU. Bundle: `com.ayahreel.app`, versionCode 23, versionName 1.0.9 (bundletool), signed with the upload key `C2:C9:DA:6D…` (keytool), 128,505,829 bytes, SHA-256 `9a0986ff…`; kept 30 days as the run's `aab` artifact. Built on GitHub's Linux runner, so its patches need no asset exception. Feed `android.latest` not raised yet (only once Play serves it) | **Patch 1** (id 716426): **published to stable 2026-10-13** by `gpatch-1.0.9+23` on the public mirror (run 38448430138, after the clean `gpatch-dry-1.0.9+23`, run 38446960751: "No issues detected", no native or asset diff): saves that play, reminders at 30 days, pictures that wait for a drawn frame; from `patch/1.0.9` = `d7e28c9` (mirror `4756e5d`). See "Android patches from GitHub Actions", 2026-10-13. **Patch 2**: **published to stable 2026-10-14** by `gpatch-1.0.9+23--2` on the mirror (run 38606132844): saves reclaimed in the background run again, and the Telegram invitation; from `patch/1.0.9` = `690ad56` (mirror `b0332ca`). See 2026-10-14 below the table. Next: `gpatch-1.0.9+23--3` |
| `1.0.9+10` | iOS | `8e4b5fc` on `main`, tag `girelease-1.0.9`, GitHub run 38208596040 (`ios-release.yml`): Xcode 26.6, SDK `23F81a`, Shorebird 1.6.128, Flutter 3.47.5 (`ff900e7fba`) | 2026-10-12 (~05:40 UTC) | sdkBuild `23F81a` | **Never reached Apple. Do not patch it.** "Published Release 1.0.9+10" (Shorebird release id 891532), then the job's IPA check died on macOS's `unzip`, which has no `-W`, before the IPA was kept or uploaded. Shorebird makes one version+build once, so the release went out as `1.0.9+11` below; the job now keeps the IPA first and passes over numbers Shorebird has (`2c015f8`) | none |
| `1.0.8+22` | Android | `2a1b5be` on `design/living-sky-home` = `17dd5b0` (origin's `21bb1c2` merged into the local `+21` commits on 2026-10-07) + the version bump: `1.0.8+21`'s code + `b96ee14` (photos FFmpeg's image reader can't open, such as the Galaxy S24 Ultra's HEIC, converted to PNG first; the encode's `.part` made in the render folder, so a cache sweep can't delete it mid-encode). `shorebird release android --build-number=22` on the PC's `C:\Users\dell\ayah_reels` checkout, Shorebird 1.6.123, Flutter 3.47.5; Gradle printed "AyahReel version: 1.0.8+22"; "Published Release 1.0.8+22" (Shorebird release id 881270). Before the build: `flutter analyze` clean; 849 tests pass, 142 skipped, 12 fail, the same Windows-only ones as `+21` | 2026-10-07 (~07:21 UTC) | — | Play: **production**, status completed, found by the Play check of 2026-10-12 ~05:21 UTC (run 38207576906; when it was rolled out is not recorded), until `1.0.9+23` passes review and takes over. Before that, in the bundle library, on no track — the Play check run of 2026-10-07 ~11:33 UTC (GitHub run 37614813659) lists bundles 11, 12, 16, 17, 19, 20, 21, 22; production holds 21 (completed) and an empty draft. When it was uploaded is not recorded. Play then refused a second upload of the same file ("Version code 22 has already been used"): an uploaded code is spent, so it is added to a release with "Add from library", not uploaded again. Rollout is the user's call. AAB copy at `D:\Downloads\ayahreel-1.0.8+22.aab`, 127,836,334 bytes; versionCode 22, versionName 1.0.8 (Gradle's merged manifest), signed with the upload key — SHA-1 `C2:C9:DA:6D…`, SHA-256 `CA:9D:DD:CF…`, same as `+21`; feed `android.latest` not raised. Built on the PC's CRLF checkout, so its patches are cut on the PC, or on Codemagic only under the two-asset exception | **Patch 1** (id 705044): **published to stable 2026-10-08 ~14:10 UTC** — the "None" verse translation (`75ffe97`) and, for the smallest phones, lean x264 plus a note that says where a lost save died (`4ade252`, see `EXPORT_MEMORY.md`); feedback code date `2026-10-08`. Dart only, no icon change — from `246325c` on `design/living-sky-home` (`git log 2a1b5be..` adds only these, ledger and CI commits), tag `gpatch-1.0.8+22--2`, by GitHub Actions `android-patch.yml` (Shorebird 1.6.124 on ubuntu-latest): dry run "No issues detected", no native change, only the two PC assets (`NOTICES.Z`, `quran_verses.json`), matched by `tool/verify_asset_diffs.py`, so published with the approved exception. Before it: `gpatch-dry-1.0.8+22` (Shorebird not on PATH), `gpatch-dry-1.0.8+22--2` (clean) and `gpatch-1.0.8+22` (runner out of disk; Shorebird showed no patch afterwards) |
| `1.0.8+21` | Android | `532c86c` on `design/living-sky-home` = `cdb23ba` (origin's head after a pull on 2026-10-05) + the version bump: `1.0.8+20`'s code + both code reviews' Dart fixes (`e17c800`, `a00abff`, `fd1285f`), the native fix for replayed launch links on Android (`4fe79c6`, `MainActivity.kt`, the reason this needs a store build and not only a patch), saves that survive a vanished backdrop (`069bee5`), rendering from a folder the system doesn't empty (`cccba8f`) and the image cache's memory given to the encode on small phones (`3927308`). `shorebird release android --build-number=21` on the PC's `C:\Users\dell\ayah_reels` checkout, Shorebird 1.6.123, Flutter 3.47.5; Gradle printed "AyahReel version: 1.0.8+21"; "Published Release 1.0.8+21" (Shorebird release id 876952). Before the build: `flutter analyze` clean; 845 tests pass, 142 skipped, 12 fail, all the known Windows-only ones (seven `/` vs `\` compares in `download_test.dart`, the symlink needing privilege, one path compare, three reminders read in UTC on a UTC+4 machine) | 2026-10-05 (~16:12 UTC) | — | Play: **production** — found 2026-10-07 by the Play upload workflow's check run (GitHub run 37587396899): the production track holds "21 (1.0.8)", status completed (when it was uploaded and rolled out is not recorded; this row said not uploaded). It lacks `b96ee14`, which `+22` has and a `+21` patch could carry. AAB copy at `D:\Downloads\ayahreel-1.0.8+21.aab`, 127,827,828 bytes; versionCode 21, versionName 1.0.8 (Gradle's merged manifest; no bundletool on the PC), signed with the upload key — SHA-1 `C2:C9:DA:6D…`, SHA-256 `CA:9D:DD:CF…`, same as `+20`; feed `android.latest` not raised. Built on the PC's CRLF checkout like `+19` and `+20`, so its patches are cut on the PC, or on Codemagic only under the two-asset exception (see "Android patches from Codemagic") | **Patch 1** (id 701633): **published to stable 2026-10-07 ~08:14 UTC from this PC** (the `ayah_patch_108_21` worktree; "Published Patch 1!", arm32 1.20 MB, arm64 1.12 MB, x86_64 1.12 MB, no `[WARN]`), at the user's word after Codemagic could not build it. Three earlier PC tries published nothing: one stalled at 60% of the release AAB download and two failed with "Connection closed while receiving data" (the PC's internet dropping; Shorebird links its Windows download issue #2532); the fourth went through. Branch `patch/1.0.8-21` at `e387e72` = `532c86c` + cherry-pick `-x` of `b96ee14` (photos FFmpeg can't open converted to PNG; the encode's `.part` kept in the render folder), Dart only, no icon change, lib identical to `+22`'s (whose 849 tests pass). The other session's 05:24 UTC patches (`+20` #4, `+19` #5, `1.0.7+17` #11) skipped `+21` because its commits were not pushed yet. Tag `apatch-1.0.8+21` pushed ~07:33 UTC: the second Codemagic app failed as always, and the working app started nothing; the API answers 402 `BILLING_NOT_ENABLED` ("Please enable billing to continue building"), so Codemagic builds nothing until billing is on. PC dry run in the `ayah_patch_108_21` worktree ~07:45 UTC: "No issues detected", no `[WARN]`, "AyahReel version: 1.0.8+21". **Do not re-run the `apatch-1.0.8+21` tag on Codemagic**: it would publish the same code again as Patch 2. Next is Patch 2. **Patch 2** (id 705047): **published to stable 2026-10-08 ~14:10 UTC** — the "None" verse translation (`75ffe97`) and, for the smallest phones, lean x264 plus a note that says where a lost save died (`4ade252`, see `EXPORT_MEMORY.md`); feedback code date `2026-10-08`. Dart only, no icon change — from `5eb18c1` on `patch/1.0.8-21` (`e387e72` + cherry-picks of `75ffe97`, `4ade252` and the workflow file; `lib/` identical to `+22` Patch 1's), tag `gpatch-1.0.8+21--2`, by GitHub Actions `android-patch.yml` (Shorebird 1.6.124 on ubuntu-latest): dry run "No issues detected", no native change, only the two PC assets (`NOTICES.Z`, `quran_verses.json`), matched by `tool/verify_asset_diffs.py`, so published with the approved exception. `gpatch-1.0.8+21` before it ran out of disk and published nothing |
| `1.0.8+20` | Android | `dde6556` on `design/living-sky-home`, whose app code is `b94052c`'s (only `RELEASES.md` and `codemagic.yaml` differ): `1.0.8+19`'s code + the save fix for 3 and 4 GB phones `4a2bba3` + `2c3fcaf` + the Report button `c8aa7ed` + the version bump, i.e. `1350bb2` (+19 Patch 1) + the bump. Built by the user running `shorebird release android --build-number=20` on the PC, Shorebird 1.6.123, Flutter 3.47.5; "Published Release 1.0.8+20". Tests not rerun for this build (code same as Patch 1's, whose dry run was clean). Codemagic can also build store releases since 2026-10-04: the upload keystore is stored there as `ayahreel_upload` (Personal Account → Code signing identities; CN AyahReel, expires 2053-12-09, the `C2:C9:DA:6D…` key) for `android-release` on a tag `arelease-<build>`. A first `arelease-20` (on `0fedadb`, 2026-10-04 19:33 UTC) was cancelled at the user's word before any build or Shorebird release, and the tag deleted. Now that Shorebird has `1.0.8+20` from the PC, don't tag `arelease-20` again: a Codemagic-built store release would be `+21` | 2026-10-04 (~19:36 UTC) | — | Play: **production**. Found 2026-10-04 ~22:40 UTC: Play Console's Android vitals list the production track's release as "20 (1.0.8)" (when it was uploaded and rolled out is not recorded; this row said not uploaded, and before that: `1.0.8+19` Patch 1 already carries the same fixes, so uploading is optional and the user's call; if it goes to Play production, use the same release notes as 19 (Play's "copy from previous release"; en-US "Bug fixes, smoother editing and new features. …", 6 languages). AAB copy at `D:\Downloads\ayahreel-1.0.8+20.aab`, 127,753,383 bytes; versionCode 20, versionName 1.0.8 (bundletool), signed with the upload key — SHA-1 `C2:C9:DA:6D…`, SHA-256 `CA:9D:DD:CF…`, same as `+19`; feed `android.latest` not raised. Built on the PC's CRLF checkout, so like `+19` its patches are cut on the PC, not Codemagic | **Patch 1** (id 694317): **published to stable 2026-10-05 ~02:25 UTC** from this PC's `C:\Users\dell\ayah_reels` checkout (the one `+20` was released from), branch `patch/1.0.8-20` at `a012c13` = `e17c800` (the code review's fixes, Dart only, on top of `dde6556`'s app code; only `RELEASES.md` and `codemagic.yaml` commits between) + `a012c13` (GitHub Actions CI, not app code). Same Dart as `+19` Patch 2 below, whose checks it shares: GitHub Actions analyze clean and every test passing on `fix/review-2026-10-04`, and Codemagic's Android dry runs of the same Dart (`apatch-dry-1.0.8+19--4` on `7105f63` and `apatch-dry-1.0.7+17--3` on `40c690f`, both pushed 2026-10-04 22:28 UTC): analyze and test pass, Gradle built, release found, no Kotlin or Java change, icon font, shaders, manifests, other fonts and pictures the same; only NOTICES and json/README differ, the PC checkout's CRLF bytes, so the publish is the PC's. PC dry run 2026-10-05 02:11 UTC: "No issues detected", no `[WARN]`; the build printed "AyahReel version: 1.0.8+20" (Shorebird 1.6.123, Flutter 3.47.5); **Patch 2 published to stable 2026-10-05 ~12:00 UTC from Codemagic** (tag `apatch-1.0.8+20` on `1a03771` = `b0b397e` + the exception workflow, no app code; build `6ac376002e8bb15cf38dcf0b`, "✅ Published Patch 2!"; arm32 1.62 MB, arm64 1.50 MB, x86_64 1.52 MB; only `NOTICES.Z` and `quran_verses.json` differed, verified and allowed). **Patch 3 published to stable 2026-10-05 ~13:20 UTC from Codemagic**: tag `apatch-1.0.8+20--2` on `0f09258` = `1a03771` + `0f09258` (cherry-pick of `3927308`: the image cache capped at 48 MB on phones that aren't roomy, and emptied when a foreground save starts) — "✅ Published", with only the two verified assets allowed. Patch 2 was prepared as branch `patch/1.0.8-20` at `b0b397e` (= `1948838` + the render-folder fix `cccba8f` + Codemagic-only commits); before that at `1948838` = Patch 1's `a012c13` + `acc51b9` + `1948838` (cherry-pick of `069bee5`: a flattened backdrop that vanished before the encode — the Galaxy M13 feedback of 2026-10-04, `ayah_bgflat_….png: No such file or directory` — is made atomically, and a save whose own input vanished renders once more); `acc51b9` is the cherry-pick `-x` of the 2026-10-05 second review's fixes (`fd1285f` on `design/living-sky-home`, Dart only: verse-card memo keyed on the voice's timings, word-highlight holes, square-pixel scenes, hardware-probe freeze/sharing/retirement, render pictures written whole, upload silence detection via `ametadata`, recitation caches cleared with storage, atomic joins/conversions, quiz drag-to-answer and double filing, identical challenge rounds, reminder window kept through a past day / re-laid on language or zone change, single-read rewards init, My Reels kept through one bad entry, player/reopen/picker/onboarding fixes, l10n and RTL fixes). Its native half `4fe79c6` (Android launch-link replay, iOS widget noon) is store-build only and not on the branch. Icon set the same as the release by grep. GitHub Actions on the branch (at its head): analyze clean, every test passing. Codemagic Android dry run `apatch-dry-1.0.8+20` on `acc51b9` pushed 2026-10-05 03:57 UTC: the working Codemagic app (`6a63ba37…`) started no build for it in the 12 minutes watched (cause not known: queue or build minutes; its log needs a login), and the second app (`6a9d08ca…`) failed at once as it always does. No assets, pubspec, `codemagic.yaml` or native files differ from the branch's last patch, and the diff adds no widget that brings back a framework fallback icon. To be cut on the PC: `shorebird patch android --release-version=1.0.8+20 --dry-run`, then publish. **Patch 4** queued 2026-10-07 05:24 UTC on Codemagic: tag `apatch-1.0.8+20--3` on `61fd6ef` = Patch 3's `0f09258` + `61fd6ef` (cherry-pick `-x` of `b96ee14`: photos FFmpeg can't open (a Galaxy S24 Ultra's HEIC, 2026-10-06: "Option loop not found") made into a PNG through Flutter's decoder by `StillSource`; the encode's `.part`, passes and progress file made in the render folder instead of the cache folder Android empties (a 3.6 GB phone, 2026-10-06: "the rendered reel has no picture"); an output gone after a successful encode reported as "No such file or directory", so the save renders once more; feedback notes carry `code: 2026-10-07`. Dart only, no icon, asset, pubspec or native change. GitHub Actions on the branch: analyze clean, 845 tests passed). **Published to stable 2026-10-07 ~06:12 UTC** (Codemagic build `6ac5d7832e8bb15cf3976058`: analyze, test, patch passed; no Kotlin or Java change; icon font, shaders, manifests, other fonts and pictures the same; only `NOTICES` and json/README differed, the approved two-asset exception). Next is Patch 5; **Patch 5** (id 705000): **published to stable 2026-10-08 ~13:40 UTC** — the "None" verse translation (`75ffe97`) and, for the smallest phones, lean x264 plus a note that says where a lost save died (`4ade252`, see `EXPORT_MEMORY.md`); feedback code date `2026-10-08`. Dart only, no icon change — from `6858862` on `patch/1.0.8-20` (`61fd6ef` + cherry-picks of `75ffe97`, `4ade252` and the workflow file), tag `gpatch-1.0.8+20`, by GitHub Actions `android-patch.yml` (Shorebird 1.6.124 on ubuntu-latest): dry run "No issues detected", no native change, only the two PC assets (`NOTICES.Z`, `quran_verses.json`), matched by `tool/verify_asset_diffs.py`, so published with the approved exception |
| `1.0.8+19` | Android | `6dc8fe1` on `design/living-sky-home` (`+18`'s code + the recitation download fix `c280376`, merged as `c60abaf`, + the version bump), `shorebird release android --build-number=19` on this machine, Shorebird's Flutter 3.47.5 | 2026-10-03 | — | Play: **production** — Play Console on 2026-10-04 shows the track's latest release as 19 (1.0.8) in 178 countries / regions, app last updated 2026-10-03 (when it was uploaded and rolled out is not recorded; this row said not uploaded). AAB copy at `D:\Downloads\ayahreel-1.0.8+19.aab`, 127,716,191 bytes; versionCode 19, versionName 1.0.8, signed with the upload key — SHA-1 `C2:C9:DA:6D…`, SHA-256 `CA:9D:DD:CF…`, same as `+18`); feed `android.latest` not raised. On this PC 799 tests pass and 12 fail, all Windows only — `+18`'s five, and seven in `download_test.dart` that compare a `/`-built path with Windows's `\` | Patch 1, the save fix for 3 and 4 GB phones (`4a2bba3` + `2c3fcaf`, 2026-10-04), plus the Report button on failed saves (`c8aa7ed`): **published to stable 2026-10-04 ~16:55 UTC** from this PC on `1350bb2` (release commit + the fix + `c8aa7ed` + ledger and CI-only commits). Built deliberately from `1350bb2` and not origin's head, since `b94052c` bumps `pubspec.yaml` to +20; the build printed "AyahReel version: 1.0.8+19". Dart only since `6dc8fe1`, icon set the same by grep; dry run "No issues detected" with no warning (no Kotlin, Java or asset diff). Codemagic's `android-patch` had built it four times earlier that day (tags `apatch-dry-1.0.8+19`, `--2`, `--3` and `apatch-1.0.8+19`) and published nothing, because of the PC-checkout asset differences (see "Android patches from Codemagic"); **Patch 2** (id 694308): **published to stable 2026-10-05 ~02:20 UTC** from this PC's `C:\Users\dell\ayah_reels` checkout, branch `patch/1.0.8-19` at `7105f63` = `1350bb2` (Patch 1) + `8525c11` (cherry-pick of `e17c800`: the 2026-10-04 code review's fixes — the stall watchdog that cancelled healthy encodes after a background freeze, no second FFmpeg graph beside a wedged one on a small phone, background deaths not counted as memory losses, whole-file JSON writes and single-read init for settings/arena/libraries, the monochrome notification icon (Android 8.0 crash), serialized reminder windows, the `%FF` link crash, the ink lock after reopening a reel, the old English surah cache adopted, the dedication line measured without a GlobalKey, stable graded-backdrop names, the search index and arena corpus off the UI isolate) + `7105f63` (GitHub Actions CI only). GitHub Actions on the branch: analyze clean, every test passes; Codemagic's Android dry runs of the same Dart (`apatch-dry-1.0.8+19--4` on `7105f63` and `apatch-dry-1.0.7+17--3` on `40c690f`, both pushed 2026-10-04 22:28 UTC): analyze and test pass, Gradle built, release found, no Kotlin or Java change, icon font, shaders, manifests, other fonts and pictures the same; only NOTICES and json/README differ, the PC checkout's CRLF bytes, so the publish is the PC's. PC dry run 2026-10-05 02:16 UTC: "No issues detected", no `[WARN]`; the build printed "AyahReel version: 1.0.8+19" (Shorebird 1.6.123, Flutter 3.47.5); **Patch 3 published to stable 2026-10-05 ~12:20 UTC from Codemagic** (tag `apatch-1.0.8+19--3` on `855c542`, build `6ac38d372e8bb15cf38e2fa6`, "✅ Published Patch 3!"; the first try, `apatch-1.0.8+19--2` on the same commit, hung in its first dry run for 68 minutes and was cancelled; only the two allowed assets differed). **Patch 4 published to stable 2026-10-05 ~13:10 UTC from Codemagic**: tag `apatch-1.0.8+19--4` on `80d15ab` (the image-cache change, cherry-pick of `3927308`) — "✅ Published", with only the two verified assets allowed. Patch 3 was prepared as branch `patch/1.0.8-19` at `e29b897` (= `83d790d` + the render-folder fix `cccba8f` + Codemagic-only commits); before that at `83d790d` = Patch 2's `7105f63` + `d663192` + `83d790d` (cherry-pick of `069bee5`, the vanished-backdrop fix); `d663192` is the cherry-pick `-x` of the 2026-10-05 second review's fixes (`fd1285f` on `design/living-sky-home`, Dart only: verse-card memo keyed on the voice's timings, word-highlight holes, square-pixel scenes, hardware-probe freeze/sharing/retirement, render pictures written whole, upload silence detection via `ametadata`, recitation caches cleared with storage, atomic joins/conversions, quiz drag-to-answer and double filing, identical challenge rounds, reminder window kept through a past day / re-laid on language or zone change, single-read rewards init, My Reels kept through one bad entry, player/reopen/picker/onboarding fixes, l10n and RTL fixes). Its native half `4fe79c6` (Android launch-link replay, iOS widget noon) is store-build only and not on the branch. Icon set the same as the release by grep. GitHub Actions on the branch (at its head): analyze clean, every test passing. Same Dart as `+20` Patch 2 above (lib identical). To be cut on the PC. **Patch 5** queued 2026-10-07 05:24 UTC on Codemagic: tag `apatch-1.0.8+19--5` on `a22f085` = Patch 4's `80d15ab` + `a22f085` (cherry-pick `-x` of `b96ee14`: photos FFmpeg can't open (a Galaxy S24 Ultra's HEIC, 2026-10-06: "Option loop not found") made into a PNG through Flutter's decoder by `StillSource`; the encode's `.part`, passes and progress file made in the render folder instead of the cache folder Android empties (a 3.6 GB phone, 2026-10-06: "the rendered reel has no picture"); an output gone after a successful encode reported as "No such file or directory", so the save renders once more; feedback notes carry `code: 2026-10-07`. Dart only, no icon, asset, pubspec or native change. GitHub Actions on the branch: analyze clean, 845 tests passed). **Published to stable 2026-10-07 ~05:57 UTC** (Codemagic build `6ac5d7822e8bb15cf3976057`: analyze, test, patch passed; no Kotlin or Java change; icon font, shaders, manifests, other fonts and pictures the same; only `NOTICES` and json/README differed, the approved two-asset exception). Next is Patch 6; **Patch 6** (id 705001): **published to stable 2026-10-08 ~13:40 UTC** — the "None" verse translation (`75ffe97`) and, for the smallest phones, lean x264 plus a note that says where a lost save died (`4ade252`, see `EXPORT_MEMORY.md`); feedback code date `2026-10-08`. Dart only, no icon change — from `451205f` on `patch/1.0.8-19` (`a22f085` + cherry-picks of `75ffe97`, `4ade252` and the workflow file), tag `gpatch-1.0.8+19`, by GitHub Actions `android-patch.yml` (Shorebird 1.6.124 on ubuntu-latest): dry run "No issues detected", no native change, only the two PC assets (`NOTICES.Z`, `quran_verses.json`), matched by `tool/verify_asset_diffs.py`, so published with the approved exception |
| `1.0.8+18` | Android | `4daca10` on `design/living-sky-home` (`d517db2` + the version bump; same code as the `4953e87` it was built from before a rebase), `shorebird release android --build-number=18` on this machine, Shorebird's Flutter 3.47.5 | 2026-10-02 | — | Play: **superseded by `+19`, never to be uploaded** (copy at `D:\Downloads\ayahreel-1.0.8+18.aab`; versionCode 18, signed with the upload key `C2:C9:DA:6D…`); feed `android.latest` not raised. 784 of 789 tests pass on this PC; the five failures are Windows or timezone only (a symlink needing privilege, `/` vs `\` in a path compare, reminders read in UTC on a UTC+4 machine). Built before the recitation download fix `c280376` (merged as `c60abaf`), so it does not have it | none |
| `1.0.7+9` | iOS | tag `v1.0.7` = `f3d72b3`, Codemagic | 2026-09-25 | sdkBuild `23F81a` (= the 26.6 pin) | App Store: READY_FOR_SALE (WAITING_FOR_REVIEW 2026-09-25; live as of the 2026-10-09 check) | `patch-1.0.7+9` on `218b7c1` (greeting on the badge's line), tag pushed 2026-09-26 — Codemagic build result not recorded; `patch-1.0.7+9--2` on `5ed7add` (greeting + verse numbers, branch `patch/1.0.7-verse-numbers` = `218b7c1` + cherry-pick of `e9ea60f`), tag pushed 2026-09-28 — **Codemagic build failed**, nothing shipped: asset change in `MaterialIcons-Regular.otf` (the new `format_list_numbered_rtl_rounded` icon; see "Icons" below); `patch-1.0.7+9--3` on `a359b7e` (same, with the row's icon swapped for `tag_rounded`, already in 1.0.7), tag pushed 2026-09-28 — Codemagic build result not recorded, but expect the same refusal: the Android dry run of `a359b7e` found `more_horiz` added to the font (case 2 under "Icons"); `patch-1.0.7+9--4` on `0a702b1` (same, the menu opened with `showMenu`; Android dry run clean, font byte-identical to the release's), tag pushed 2026-09-28 — Codemagic build result not recorded; `patch-1.0.7+9--5` on `0aebd8c` (same, the Verse numbers row moved from beside Verse translation to directly above Daily streak nudge; Android dry run clean), tag pushed 2026-09-28 — Codemagic build result not recorded; `patch-1.0.7+9--6` on `1684297` (on top of `--5`: 109 reciters with search and surahs a voice lacks greyed out, the surah-file and Fares Abbad recitation fixes, preview errors that say what failed, compact font cards, and one notification a day — Quran quizzes and reels with pictures; branch `patch/1.0.7-reciters-quizzes` = `0aebd8c` + cherry-picks of `b481863`…`5d60727`, leaving out `35048bf` (its Dart calls a native picker 1.0.7 doesn't have) and `94bd7a4` (an asset)); icon set checked against `v1.0.7` by grep — **no Android dry run**, this machine no longer has Shorebird or the Android SDK; 753 tests pass on the branch; tag pushed 2026-09-30 — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `1684297`); `patch-1.0.7+9--7` on `7ebf4ea` (on top of `--6`: each part of the day has three or four endings taken in turn, so no two nights end alike — at nine every night it had said "before you sleep"; three templates rewritten in all five languages where an ending doubled a word, the tea line with them; a window laid in older words is laid again at the next launch (`ReminderCopy.version`), so phones on `--6` drop its fortnight of identical endings; cherry-pick of `49740c1`); no icon, native or asset change; 756 tests pass on the branch; tag pushed 2026-09-30 — **Codemagic build succeeded** (2026-09-30 05:30 UTC); `patch-1.0.7+9--8` on `d308c56` (on top of `--7`, two cherry-picks: `25b8a4a` of `fa05401`, 2026-10-01 — saves that failed at their last step on phones short of storage, renders and gallery-named copies never deleted from the cache; and `d308c56` of `d82163d`, 2026-10-02 — FFmpeg's log and statistics events switched off and save progress read from FFmpeg's `-progress` file, for Play's 1.0.7 ANR in `StandardMessageCodec` during an export; a failed encode's log fetched once; the `-benchmark` diagnostic removed); Dart only, no icon, native, asset or `codemagic.yaml` change since `--7`, icon set same as `v1.0.7` by grep, Xcode pin 26.6 = `23F81a`, 773 tests pass on the branch; Android dry run of the same commit clean on 2026-10-02 (Android Patch 5, from the user's Windows PC, which does have Shorebird and the SDK); tag pushed by the user 2026-10-02 — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `d308c56`, 2026-10-02 17:35 UTC); `patch-1.0.7+9--9` on `e49297c` (on top of `--8`, cherry-pick `-x` of `c280376`: recitations that a slow or broken connection used to lose now finish. Per-ayah files get 30 s without a byte instead of 30 s for the whole file, and are streamed to disk; requests that don't answer are aborted instead of left running; surah slices resume from the byte reached and keep what came across fetches; tries are 1/2/4 s apart and a try that brought bytes doesn't count; the surah text is retried; the preview retries when the app comes back to a connection error. Reproduced first through the real `RecitationService` behind a bad-network proxy: 600 kbps, a drop every 2.5 MB and a 40 s stall each failed with "offline" before, and finished after); Dart only, no icon, native, asset or `codemagic.yaml` change since `--8`, icon set same as `v1.0.7` by grep (the one extra hit, `Icons.adaptive`, is a doc comment in `settings_screen.dart`), Xcode pin 26.6 = `23F81a`, `flutter analyze` clean and 795 tests pass on the branch; **no Android dry run before the tag**: the PC session was cutting Android Patch 6 from the same change (patch-id `08393732ee0c`) and had not reported 40 minutes after the fix reached GitHub; tag pushed 2026-10-02 21:21 UTC on the user's go-ahead — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `e49297c`, 2026-10-02 21:34 UTC); `patch-1.0.7+9--10` on `7d74ff1` (on top of `--9`: the save fix for small phones, `be724a0` = cherry-pick `-x` of `4a2bba3` — exports planned to the phone's memory, one decoder thread per verse card, a lost export remembered, loop-aware pass cuts, hardware-encoder timeouts, an `export` line in feedback notes — and `1778d5a`, the 32-bit check without dart:ffi; the other four commits since `--9` are `codemagic.yaml` only, adding `android-patch` and leaving `ios-patch` as it was); Dart only, no icon, native or asset change, icon set same as `--9` by grep (the extra `Icons.adaptive` is the known doc comment), Xcode pin 26.6 = `23F81a`, `flutter analyze` clean and 814 tests pass on the branch. **No clean Android dry run before the tag**: Codemagic's Android checks of this commit found only the PC-checkout asset differences (NOTICES, a JSON or README; no icon font, shader or Kotlin change), and the PC wasn't reachable. Tag pushed 2026-10-04 15:21 UTC on the user's standing go-ahead ("ota to the users … don't ask") — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `7d74ff1`, 2026-10-04 16:07 UTC); `patch-1.0.7+9--11` on `40c690f` on `patch/1.0.7-reciters-quizzes` = `--10` + `48a0836` (the Report button on failed saves and the next-launch notice after a lost one) + `bc12ac2` (the 2026-10-04 review fixes) + `40c690f` (`.github` only). Dart only since `--10`; `codemagic.yaml` unchanged since `--10`, so Xcode pin 26.6 = `23F81a`; the Android dry run of this exact commit, `apatch-dry-1.0.7+17--3`, has the icon font and shaders the same; GitHub Actions analyze clean and every test passing. The first push from the VPS session was blocked by Claude Code's permission classifier; tag pushed 2026-10-05 01:57 UTC once the user approved it — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `40c690f`: analyze, test and patch passed, 02:12 UTC). iOS now has the Report button and the review fixes; next is `--12`; `patch-1.0.7+9--12` on `53e2a0f` on `patch/1.0.7-reciters-quizzes` = `--11`'s `40c690f` + `c662484` + `53e2a0f` (cherry-pick of `069bee5`, the vanished-backdrop fix); `c662484` is the cherry-pick `-x` of the 2026-10-05 second review's fixes (`fd1285f` on `design/living-sky-home`, Dart only: verse-card memo keyed on the voice's timings, word-highlight holes, square-pixel scenes, hardware-probe freeze/sharing/retirement, render pictures written whole, upload silence detection via `ametadata`, recitation caches cleared with storage, atomic joins/conversions, quiz drag-to-answer and double filing, identical challenge rounds, reminder window kept through a past day / re-laid on language or zone change, single-read rewards init, My Reels kept through one bad entry, player/reopen/picker/onboarding fixes, l10n and RTL fixes). Its native half `4fe79c6` (Android launch-link replay, iOS widget noon) is store-build only and not on the branch. Icon set the same as the release by grep. GitHub Actions on the branch (at its head): analyze clean, every test passing (applied cleanly to 1.0.7, same 57 files). `codemagic.yaml` unchanged since `--11`, so Xcode pin 26.6 = `23F81a`. Codemagic Android dry run of this exact commit `apatch-dry-1.0.7+17--4` pushed 2026-10-05 03:57 UTC: the working Codemagic app (`6a63ba37…`) started no build for it in the 12 minutes watched (cause not known: queue or build minutes; its log needs a login), and the second app (`6a9d08ca…`) failed at once as it always does. No assets, pubspec, `codemagic.yaml` or native files differ from the branch's last patch, and the diff adds no widget that brings back a framework fallback icon; tag pushed 2026-10-05 07:36 UTC from the VPS session on the user's go-ahead (the user ran the tag command; the paste wrapped and did nothing, so the session ran it) — **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `53e2a0f`, 07:53 UTC). iOS now has the second review's fixes and the vanished-backdrop fix; next is `--13`; `patch-1.0.7+9--13` on `3a72b6f` on `patch/1.0.7-reciters-quizzes` = `--12`'s `53e2a0f` + the render-folder fix `91b703e` + the image-cache change `fc60a2d` + Codemagic-only commits + `3a72b6f` (cherry-pick `-x` of `b96ee14`: photos FFmpeg can't open (a Galaxy S24 Ultra's HEIC, 2026-10-06: "Option loop not found") made into a PNG through Flutter's decoder by `StillSource`; the encode's `.part`, passes and progress file made in the render folder instead of the cache folder Android empties (a 3.6 GB phone, 2026-10-06: "the rendered reel has no picture"); an output gone after a successful encode reported as "No such file or directory", so the save renders once more; feedback notes carry `code: 2026-10-07`. Dart only, no icon, asset, pubspec or native change. GitHub Actions on the branch: analyze clean, 845 tests passed). `codemagic.yaml` changed since `--12` only inside `android-patch`, so `ios-patch` and its Xcode pin 26.6 = `23F81a` are as they were. Tag pushed 2026-10-07 05:24 UTC on the user's go-ahead ("ota at end"). **Codemagic build succeeded** (GitHub check "iOS - Shorebird OTA patch" on `3a72b6f`, build `6ac5d78722339b6d56c74d37`: analyze, test, patch and publishing passed, 06:27 UTC; the check run stayed "in progress" on GitHub though its summary says finished). Next is `--14` |
| `1.0.7+17` | Android | `v1.0.7` line, built locally (exact commit not recorded; its icon font matches `v1.0.7`'s) | 2026-09-25 | — | Play: not recorded | Patch 1: not recorded (this row said `218b7c1` was unpublished, but Shorebird numbered the next one 2); **Patch 2** on `0a702b1` (greeting + verse numbers, branch `patch/1.0.7-verse-numbers`), published to stable from this machine 2026-09-28 after a clean dry run; **Patch 3** on `0aebd8c` (same, the Verse numbers row moved to directly above Daily streak nudge), published to stable 2026-09-28 after a clean dry run; **Patch 4**: on stable per `shorebird patches list` (id 684445), though this row had it as not made — who cut it, from which commit and when is not recorded; **Patch 5** on `d308c56` (branch `patch/1.0.7-reciters-quizzes`: everything in iOS `--7` — the reciters, preview errors, one notification a day with its endings — plus the storage fix `25b8a4a` and the FFmpeg main-thread fix for this release's ANR and `writeBytes` OOM on Play), published to stable 2026-10-02 from the `C:\Users\dell\ayah_patch_android` worktree after a clean dry run (no icon, native or asset diff); **Patch 6** (id 691513), the recitation download fix = iOS `--9`: built from `03ac5cb`, a cherry-pick of `c280376` onto `d308c56` whose tree is identical to the branch head `e49297c` (patch-id `08393732ee0c`), published to stable 2026-10-03 from the same worktree after a clean dry run (no icon, native or asset diff; built with the release's Flutter 3.47.1). The first dry run hung overnight with nothing built, the PC most likely asleep; the second took about 5 minutes. On this PC 783 tests pass and 12 fail, all Windows only — the usual five, and seven in the new `download_test.dart` that compare a `/`-built path with Windows's `\` (all 13 pass with a separator-proof compare); **Patch 7**, the save fix for 3 and 4 GB phones plus the Report button on failed saves and the next-launch notice after a lost one: **published to stable 2026-10-04 ~16:50 UTC** from the `C:\Users\dell\ayah_patch_android` worktree on `48a0836` (`origin/patch/1.0.7-reciters-quizzes`: `e49297c`, whose tree is Patch 6's, + `be724a0` + `1778d5a` + `48a0836` + CI-only commits). Dart only, icon set the same as Patch 6 by grep; dry run "No issues detected" with no warning. Codemagic's `android-patch` had built it earlier that day (tags `apatch-dry-1.0.7+17`, `apatch-1.0.7+17`, `apatch-dry-1.0.7+17--2`) and published nothing, because of the PC-checkout asset differences. Android now has the Report button and iOS doesn't, until `patch-1.0.7+9--11` is tagged; **Patch 8** (id 694316): **published to stable 2026-10-05 ~02:25 UTC** from the `C:\Users\dell\ayah_patch_android` worktree, `40c690f` on `patch/1.0.7-reciters-quizzes` = `48a0836` (Patch 7) + `bc12ac2` (the same review fixes, less the dedication measure and the verse inks, which 1.0.7 doesn't have) + `40c690f` (CI only). GitHub Actions on the branch: analyze clean, every test passes; Codemagic's Android dry runs of the same Dart (`apatch-dry-1.0.8+19--4` on `7105f63` and `apatch-dry-1.0.7+17--3` on `40c690f`, both pushed 2026-10-04 22:28 UTC): analyze and test pass, Gradle built, release found, no Kotlin or Java change, icon font, shaders, manifests, other fonts and pictures the same; only NOTICES and json/README differ, the PC checkout's CRLF bytes, so the publish is the PC's. PC dry run 2026-10-05 02:20 UTC: "No issues detected", no `[WARN]`; the build printed "AyahReel version: 1.0.7+17" (the release's Flutter 3.47.1). Not fixable by any patch: the file-picker out-of-memory crash (`file_selector_android` sends the whole picked file over the channel; 7 users in Play's 28 days to 2026-10-04), fixed natively in 1.0.8 by `AudioPicker`; **Patch 10 published to stable 2026-10-05 ~12:50 UTC from Codemagic**: tag `apatch-1.0.7+17--3` on `fc60a2d` (the image-cache change, cherry-pick of `3927308`) — "✅ Published", with only the two verified assets allowed; **Patch 9 published to stable 2026-10-05 ~10:20 UTC from Codemagic** (tag `apatch-1.0.7+17--2` on `d6ba48c` = `6643bf0` + the Codemagic exception workflow `3ef0fb4`, no app code; build `6ac376002e8bb15cf38dcf05`, "✅ Published Patch 9!"; arm32 1.84 MB, arm64 and x86_64 1.71 MB). The first Android patch from Codemagic of a PC-built release: the only asset differences were `NOTICES.Z` and `quran_verses.json`, passed by `tool/verify_asset_diffs.py` against the release's own bundle and then `--allow-asset-diffs`, the exception the user allowed on 2026-10-05 (see "Android patches from Codemagic"); no Kotlin or Java change, icon font the same. Before that it was prepared as `6643bf0` on `patch/1.0.7-reciters-quizzes` (= iOS `--12`'s `53e2a0f` + the render-folder fix `cccba8f` + Codemagic-only commits; the render-folder fix is not on iOS, which doesn't empty its temporary folder under a running app); before that (= iOS `--12`; `c662484` + the vanished-backdrop fix `53e2a0f`), cherry-pick `-x` of the 2026-10-05 second review's fixes (`fd1285f` on `design/living-sky-home`, Dart only: verse-card memo keyed on the voice's timings, word-highlight holes, square-pixel scenes, hardware-probe freeze/sharing/retirement, render pictures written whole, upload silence detection via `ametadata`, recitation caches cleared with storage, atomic joins/conversions, quiz drag-to-answer and double filing, identical challenge rounds, reminder window kept through a past day / re-laid on language or zone change, single-read rewards init, My Reels kept through one bad entry, player/reopen/picker/onboarding fixes, l10n and RTL fixes). Its native half `4fe79c6` (Android launch-link replay, iOS widget noon) is store-build only and not on the branch. Icon set the same as the release by grep. GitHub Actions on the branch (at its head): analyze clean, every test passing. Codemagic dry run `apatch-dry-1.0.7+17--4`. To be cut from the `C:\Users\dell\ayah_patch_android` worktree. **Patch 11** queued 2026-10-07 05:24 UTC on Codemagic: tag `apatch-1.0.7+17--4` on `3a72b6f` = Patch 10's `fc60a2d` + `3a72b6f` (cherry-pick `-x` of `b96ee14`: photos FFmpeg can't open (a Galaxy S24 Ultra's HEIC, 2026-10-06: "Option loop not found") made into a PNG through Flutter's decoder by `StillSource`; the encode's `.part`, passes and progress file made in the render folder instead of the cache folder Android empties (a 3.6 GB phone, 2026-10-06: "the rendered reel has no picture"); an output gone after a successful encode reported as "No such file or directory", so the save renders once more; feedback notes carry `code: 2026-10-07`. Dart only, no icon, asset, pubspec or native change. GitHub Actions on the branch: analyze clean, 845 tests passed). **Published to stable 2026-10-07 ~05:43 UTC** (Codemagic build `6ac5d7822e8bb15cf3976055`: analyze, test, patch passed; no Kotlin or Java change; icon font, shaders, manifests, other fonts and pictures the same; only `NOTICES` and json/README differed, the approved two-asset exception). Next is Patch 12; not patched on 2026-10-08: `75ffe97` and `4ade252` conflict with this branch's code (settings, renderer, preview, overlay) |
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

## Store builds from GitHub Actions, straight to both stores

**From 1.0.10, every build passes `--dart-define=WORDS_KEY`** (added
2026-10-24): the key the app reads its own word timing with from the
private Worker (`lib/data/words_host.dart`). The GitHub workflows pass the
repo secret `WORDS_KEY` (set on `Mulhimfy/ayahReel-ci` and origin;
value in `/root/keys/ayahreel-words.env` as `WORDS_APP_KEY`), and redact
it from uploaded logs. It is a Dart const, so a patch has to be built
with the release's value: a different or empty one changes a const. A
build without it still works, with no word timing for the voices the app
times itself. Codemagic passes `${WORDS_KEY:-}`, which is empty unless set
in its environment: don't release or patch 1.0.10+ there without it.
Releases before 1.0.10 don't read it, so it changes nothing in their
patches.

Since 2026-10-12, with Codemagic's free minutes used up, both store builds
run on GitHub, and each ends in its store. Either tag **ships**: it makes
the Shorebird release that later patches target, and a store review that
ends with every user getting the build. It is the user's call, like a
patch tag, and its row goes in the table above.

- **Android**: `git tag garelease-<build>` (the build number in
  `pubspec.yaml`) runs `.github/workflows/android-release.yml`.
  - It runs `shorebird release android --build-number=<build>
    --flutter-version=<flutter_version.txt>` on ubuntu-latest.
  - It signs with the upload key from the repo secrets. The job stops
    unless the key's SHA-1 is Play's `C2:C9:DA:6D…`.
  - It checks the bundle: bundletool reads the package, versionCode and
    versionName, and keytool reads the signer.
  - Then `tool/play_upload.mjs release` uploads it to production with
    status completed: everyone at once, no staged rollout. The notes come
    from `docs/store/release-notes/<version>/play.json`, in the six
    languages the listing has. The commit sends it for review.
- **iOS**: `git tag girelease-<version>[--N]` runs
  `.github/workflows/ios-release.yml` on `macos-26`.
  - Xcode is 26.6. The job stops unless the SDK build is `23F81a`, the
    pin in `ios-patch.yml`, so a release and its patches share an Xcode.
  - Signing works as in `ios-patch.yml`.
  - The build number comes from Apple: one above the newest in TestFlight
    or on the App Store. It passes over a number Shorebird already has a
    release for (`1.0.9+10`, below).
  - It runs `shorebird release ios --flutter-version=<flutter_version.txt>` and checks
    the IPA (bundle id, version, build, `DTSDKBuild`). A job of its own
    uploads it with `app-store-connect publish`.
  - A Linux job then waits for Apple's processing and submits the build
    for review as App Store version `<version>`: `AFTER_APPROVAL`, no
    phased release, copyright "2026 AyahReel". What's New comes from
    `docs/store/release-notes/<version>/app-store.json`; the listing is
    en-US only.
- **One Flutter (since 2026-10-12):** `flutter_version.txt` (3.47.5) is
  the version for store builds, preview APKs, desk previews, CI tests and
  Codemagic. `tool/check_flutter_version.sh` fails the tests and stops
  both release jobs if anything pins another version, or if a `shorebird
  release` doesn't name one. Before this, the previews and tests ran on
  3.44.6 while 1.0.8 and 1.0.9 shipped on 3.47.5. To move Flutter, change
  the file and codemagic.yaml's `flutter:` lines together, and pick a
  version Shorebird carries (`shorebird flutter versions list`).
- A release built here is patched by `android-patch.yml` /
  `ios-patch.yml` with no asset exception: same runners, same line
  endings.
- The AAB or IPA is kept as the run's artifact as soon as it is built.
  If the upload, Play or submit job fails, `gh run rerun <id> --failed`
  repeats only that job, with the same build. Shorebird makes a
  version+build only once, and Play refuses a version code it has taken
  once.

## Android store builds to Play (Codemagic → GitHub → Play)

Since 2026-10-07 an Android store build can go to Play without the PC. Push
`arelease-<n>` (the build number in `pubspec.yaml`): Codemagic's
`android-release` builds and signs the AAB, and GitHub Actions' "Play
upload" (`.github/workflows/play-upload.yml`) waits for that build,
downloads the AAB with the `CODEMAGIC_TOKEN` repository secret and uploads
it with a keyless 1-hour Play token (`tool/play_upload.mjs`).

- It lands as a **draft** on production, with the newest production
  release's notes copied. A draft reaches no one until "Send for review" /
  rollout in Play Console, which stays the user's call. Pushing the tag
  still needs the user's yes: it makes a Shorebird release and a Play draft.
- `gh workflow run play-upload.yml -f mode=check` prints every track and
  changes nothing; `-f mode=upload -f tag=arelease-<n>` uploads a build again.
- iOS already went to the store from Codemagic: every `v*` tag goes to
  TestFlight and App Review (`submit_to_app_store: true`).
- A PC-built AAB (`+19` to `+22`) is not covered; it is uploaded by hand.

## Android patches from GitHub Actions

Since 2026-10-08, `.github/workflows/android-patch.yml`: the Codemagic
job below, run on GitHub's Linux runners while Codemagic billing is off.
Same dry run, same verified two-asset exception, same verdict lines in
the run's summary. Tag `gpatch-dry-<release>` to check only, or
`gpatch-<release>` to check and publish if clean. A later patch of the
same release takes a suffix (`gpatch-1.0.8+21--2`). The prefix differs
from Codemagic's `apatch-` so the two can never both publish one patch.
The tagged commit must contain the workflow file, so cherry-pick it onto
a patch branch that predates it. The Shorebird API key is the repository
secret `SHOREBIRD_TOKEN`; a copy is at `/root/keys/shorebird-api-key.txt`
on the VPS. Read a run with `gh run view <id> --log` or its summary.
Ground truth without the CLI: `curl -H "Authorization: Bearer $(cat
/root/keys/shorebird-api-key.txt)"
https://api.shorebird.dev/api/v1/apps/<app_id>/releases` and
`…/releases/<id>/patches` (number, channel, artifacts). A publish run builds
three times and once filled the runner's disk, so the job frees disk first.
If a run dies, check the patches list before tagging again.

**Since 2026-10-13 the tags go to the public mirror `Mulhimfy/ayahReel-ci`**,
not to `origin`: the private repo's jobs don't start ("recent account
payments have failed"), and public repos' Actions minutes are free.
Same workflow files, same secrets (copied from `/root/keys`).
`tool/public_mirror.sh <ref> <branch> [tag]` pushes a snapshot of the
private commit (same tree and message, no history, noreply author) and
tags it there; see `CLAUDE.md`. Record both commits.

**2026-10-17, from the VPS via the public mirror: prepared, NOT
published.** From two 1.0.9 notes (`code: 2026-10-14`): a 3647 MB phone
whose render process died five times on tightest x264, failing every
Save, and a 1831 MB phone whose app died in a tightest pass
(`EXPORT_MEMORY.md`, 2026-10-17). `patch/1.0.9` = `28d26bd` (mirror
`392d2a1`): Patch 2's code (`690ad56`) + the 2026-10-15 save-flow review
and today's fix, cherry-picked `-x`; its `lib/` and `test/` are
`feat/live-recitation`'s at `9d836b0` file for file, and nothing under
`android/`, `ios/`, `assets/` or `pubspec.yaml` changed since `690ad56`.

- `9ccf9e3`, `34b2f75`, `ca37a8a`, `34eb529`, `7ead2b2` (feat
  `ea1560d`, `c67fc2a`, `b824c5b`, `a738b35`, `d9435bc`): the 2026-10-15
  save-flow review and its second pass (reclaims, restarts, cancels,
  records, Save's wait, reels too heavy to play made again, My Reels
  copies). `d9435bc`'s `RenderService.kt` half is left out: it, and
  `2ff5649`, wait for the 1.0.10 store build.
- `28d26bd` (feat `9d836b0`) **A step below tightest.**
  `ExportBudget.smallest` (4 cards a pass, the encoder handed 720x1280),
  the out-of-memory retry going down the whole ladder, `leanLost`, a
  12 s wait for a slow first render-process binding, and `, in the app`
  plus the budget in a lost save's note. Feedback code date `2026-10-17`.
  Android and iOS (the budget ladder runs on both).

Checks: `feat/live-recitation` `9d836b0` (mirror `eed3216`): analyze
clean, 971 passed, 143 skipped (run 39043721630). `patch/1.0.9` the same
(run 39043976905). Dry run `gpatch-dry-1.0.9+23--5` (run 39043979586):
"No issues detected", no native or asset diff. iOS dry run
`gipatch-dry-1.0.9+11--3` (run 39043990186, Xcode 26.6, SDK `23F81a`):
"No issues detected", no native or asset change. Both runs' artifacts
checked for the values in `/root/keys`: none.

To ship (the user's call): `tool/public_mirror.sh patch/1.0.9
patch/1.0.9 gpatch-1.0.9+23--3` and `... gipatch-1.0.9+11--3`, then
record them here. Not for 1.0.8: no render process there.

**For the 1.0.10 store build, not in any patch (native):** `d220473` on
`feat/live-recitation` (mirror `564171e`), from Play's Crashes and ANRs
(28 days to 2026-10-17). `RenderBackend.kt` passes
`--enable-impeller=false` from `MainActivity.getFlutterShellArgs` on
phones where Impeller would take OpenGL ES (the engine's own rules from
3.47.5, before the first engine start, plus the engine's log line after
the first frame for phones the rules miss), which ends the
`CreateSnapshotSurface`/`DeviceBufferGLES`/`RenderPassGLES` crashes and
the PowerVR surface-creation ANR there; Vulkan phones keep Impeller.
Supersedes `fix/android-skia` (Skia everywhere). `AppComponents.kt`
(`appComponentFactory`, Android 9+) runs the notification plugin's alarm
receiver, and `BootReceiver` its boot work, on one worker thread under
`goAsync` (the `ScheduledNotificationReceiver` ANRs). Already fixed in
1.0.9's store build: Gson's "Missing type parameter" (keep rules, Play
shows it on 1.0.3/1.0.4 only) and the boot receiver's alarm-limit crash
(`BootReceiver`, 1.0.8 only). Check the rules again on every Flutter
upgrade (`RenderBackend`'s doc).

**Also for the 1.0.10 store build (native), 2026-10-21:** `7ac4743` on
`feat/live-recitation`, from a 1.0.9 note (the app gone in pass 5/17
with 166 MB and 1.3 GB free; `EXPORT_MEMORY.md`, 2026-10-21).
`RenderService`'s `exitInfo` takes `since`, so the next launch can ask
how the app's own process ended during a save (closed by the user: not
a loss; otherwise Android's reason in the note), and its encode thread
runs at nice +4, which FFmpeg's threads inherit. Feedback code date
`2026-10-21`. The Dart half does nothing on 1.0.9's native side, so it
is not for a 1.0.9 patch. Play's Crashes and ANRs (28 days to
2026-10-21) had nothing new on 1.0.9: the Reno2 Z Impeller GLES crash
and the background and PowerVR ANRs, all answered by `d220473` above.

**Also for the 1.0.10 store build (native), 2026-10-28:** `2de49f7` on
`voices/sobhi` (= `feat/live-recitation`, mirror `6d72a73` with
`dc021e8`), from Play's vitals (28 days to 2026-10-28: slow cold starts
7.50%, P90 4.3 s, P99 9–10 s, high on 3–4 GB phones; slow warm starts
16.75% against a peer median of 10.97%, P90 2.6 s). `MainActivity`'s
`popSystemNavigator` sends the app behind on Back from its first screen
(`moveTaskToBack`, as the task's root only) instead of letting Flutter
finish the activity and the engine with it; `preloadFfmpeg` loads
FFmpegKitConfig, and with it FFmpeg's nine native libraries, on a
thread of its own at the top of `onCreate`, beside the engine's start,
rather than on the main thread inside the plugin's registration
(`proguard-rules.pro` keeps the class name). The same commit's Dart half
(ambient motion at a 30 fps beat, one backdrop for the shell's three
blurs, `OnScreen.settle` waiting again) is patchable but not patched.
Play's Crashes and ANRs (28 days to 2026-10-28): nothing new on 1.0.9
beyond one more background `CreateSnapshotSurface` crash (Oppo Reno4 F,
Android 12, 2026-10-24), which `d220473`'s Skia rule covers (MediaTek,
vendor API 31).

**2026-10-14, from the VPS via the public mirror: saves reclaimed in
the background, and the Telegram invitation. Dart only.** At the user's
word ("fix it and comm push all", then "... then ota push it"). From a
feedback note (Infinix X6525B, Android 13 Go, `version: 1.0.9`, `code:
2026-10-13`: "render: RenderFailed(outOfMemory): the render process died
during the encode", with no `survived`) and the user's request for a
Telegram invitation. `patch/1.0.9` = `690ad56` (mirror `b0332ca`):
Patch 1's code + these; `git log garelease-23..patch/1.0.9 -- lib` is
Patch 1's three fixes and these six.

- `12b3289`, `ce8c59f`, `d1942de` (feat `999f0db`, `fcd37ea`,
  `f0f192e`) **Saves reclaimed in the background run again.** The
  owner left a slow save (or the screen timed out), Android reclaimed
  the render process, and the renderer read it as out of memory and
  failed the save. Now a death heard with the app away, or under 10 s
  after it came back, reruns the same encode once the app is in front;
  after any death the next encode waits up to 20 s for a new render
  process. `EXPORT_MEMORY.md`, 2026-10-14. Feedback code date
  `2026-10-14`. Android only in effect: iOS encodes in the app.
- `b05d143`, `8d1b11e`, `690ad56` (feat `37460a0`, `8f2f4a3`,
  `86a2c88`) **The Telegram invitation** (`lib/widgets/telegram_invite.dart`):
  a dialog to t.me/AyahReel 8 s after a new badge, 10 s after a
  finished quiz, 8 s after a made card, 15 s after a saved reel. Only
  once the install is 3 days old (or from before 2026-10-10) and after
  3 good moments or 3 reels; twice in a lifetime at most, the second 2
  days or more after the first and inside its week. Join or "I've
  joined" ends it, as does the channel opened from Settings. Uses
  `Icons.send_rounded`, already in the font (the Settings row).

Not in the patch: `a09058e` on `feat/live-recitation` and `main`, the
native half of keep-the-screen-on during a save, for the next store
build (its Dart half is in the patch and does nothing until then).

Checks: on `690ad56`, tests 947 passed, 143 skipped, analyze clean
(run 38605608927). Dry run `gpatch-dry-1.0.9+23--4` (run 38603694279) on
`b05d143`: "No issues detected", no native or asset diff (the two later
commits drop an import and add a guard). Earlier dry runs of the save
fixes alone: `--2` (38576553851), `--3` (38584470902).

| Release | Commit (mirror) | Tag | GitHub run | Patch |
|---|---|---|---|---|
| `1.0.9+23` | `690ad56` (`b0332ca`), `patch/1.0.9` | `gpatch-1.0.9+23--2` | 38606132844 | **Patch 2**, published to stable 2026-10-14 ~17:34 UTC (arm, aarch64, x86_64; patch id not in the log, not recorded); its own check "No issues detected" |
| `1.0.9+11` (iOS) | `690ad56` (`b0332ca`), `patch/1.0.9` | `gipatch-1.0.9+11--2` | 38606136390 | **Patch 2**, published to stable 2026-10-14 ~17:45 UTC (Xcode 26.6, the release's; patch id not in the log, not recorded) |

Next tags: `gpatch-1.0.9+23--3`, `gipatch-1.0.9+11--3` (on the mirror).
Not patched: the 1.0.8 releases (no render process there, and the
invitation is for 1.0.9).

**2026-10-13, from the VPS via the public mirror: saves that play, and
Play's crashes and ANRs. Dart only.** At the user's word ("fix them all
... ota patch it at end"). From a feedback note (Realme RMX3830, 1.0.9:
"every reel I save says playback error") and Play's Crashes and ANRs,
28 days to 2026-10-13. 1.0.9 is branch `patch/1.0.9` = `d7e28c9`
(`garelease-23`'s `8e4b5fc` + release-job, ledger and CI commits + the
three fixes below); `git diff 8e4b5fc d7e28c9 -- lib` is only them.

- `e2f8ee3` **Saves that play.** Lean x264 (the tightest budget) ran
  without its macroblock tree and coded the grain into every frame:
  12-26 Mbps reels, over the H.264 level they declare, which phones'
  decoders refuse ("playback error"). mbtree back on with a 5-frame
  lookahead, and every x264 encode capped at twice the hardware ladder
  over a one-second buffer (`EXPORT_MEMORY.md`, 2026-10-13). Saves of
  the same reel on tightest phones get a new cache key (`_lx`), so the
  broken file isn't handed back; reels already saved stay broken.
  Feedback code date `2026-10-13`.
- `3ef77be` **Reminders: 30 days on Android, laid again weekly.**
  ScheduledNotificationReceiver ANRs (realme C63, iotapk; Android 16)
  and the boot receiver's alarm-limit crash (Infinix HOT 50i): the
  plugin rewrites its whole list on the main thread for every alarm;
  90 days made it ~150 KB. Stale entries (alarms the system dropped)
  were never re-laid and fired together after a reboot.
- `d7e28c9` **OnScreen waits for a frame drawn since the app came
  back.** The CreateSnapshotSurface SIGSEGV family (12 + 4 + 2 + 1 + 1
  users on 1.0.8: `OUTLINED_FUNCTION_7962`/`_1031`,
  `DeviceBufferGLES::OnGetContents`, unsymbolized arm64/armv7; one
  bug, flutter/flutter#192365). "Resumed" can come before the surface,
  and reminders re-armed on the way back from the system's settings
  drew their pictures right then.
- 1.0.8 only: `4519820` (scene matching normalizes its stems once; the
  `IrregexpInterpreter` ANR on `1.0.8+19` Patch 7), already in 1.0.9.

The four 1.0.8 branches got `4519820` and `e2f8ee3` cherry-picked with
`-x` (`EXPORT_MEMORY.md` kept as the branch had it), the reminder change
by hand on their older `ReminderService` (no Friday second, no ceiling
code), and `d7e28c9` with `main.dart` by hand; their `lib/` is the same
file for file. Flutter tests green on all six branches (feat: 939
passed, 143 skipped, analyze clean).

Mirror commits: `patch/1.0.9` `4756e5d` = `d7e28c9`; `patch/1.0.8-22`
`610e998` = `ef7a4d0`; `-21` `c4252fb` = `2d8da7c`; `-20` `5df885f` =
`beafd1f`; `-19` `77d7651` = `e5b3f1e`.

Dry runs first, all clean: `gpatch-dry-1.0.9+23` (run 38446960751)
"No issues detected", no native or asset diff (that release was built
on GitHub's runner); the four 1.0.8 ones (runs 38447031923,
38447037903, 38447047749, 38447056275) "No issues detected", no native
diff, only the two PC assets, verified. **Published to stable**
(Shorebird's patches list, 2026-10-13; arm, aarch64 and x86_64):

| Release | Commit (mirror) | Tag | GitHub run | Patch |
|---|---|---|---|---|
| `1.0.9+23` | `d7e28c9` (`4756e5d`), `patch/1.0.9` | `gpatch-1.0.9+23` | 38448430138 | Patch 1 (id 716426) |
| `1.0.8+22` | `ef7a4d0` (`610e998`), `patch/1.0.8-22` | `gpatch-1.0.8+22--5` | 38448586754 | Patch 4 (id 716437) |
| `1.0.8+21` | `2d8da7c` (`c4252fb`), `patch/1.0.8-21` | `gpatch-1.0.8+21--5` | 38448594241 | Patch 5 (id 716432) |
| `1.0.8+20` | `beafd1f` (`5df885f`), `patch/1.0.8-20` | `gpatch-1.0.8+20--4` | 38448606103 | Patch 8 (id 716436) |
| `1.0.8+19` | `e5b3f1e` (`77d7651`), `patch/1.0.8-19` | `gpatch-1.0.8+19--4` | 38448615207 | Patch 9 (id 716440) |

iOS, same code: `gipatch-1.0.9+11` on the mirror's `4756e5d` (=
`d7e28c9`), run 38448437728 (`ios-patch.yml`, macos-26): Xcode 26.6,
SDK `23F81a` as the release's; its own dry run "No issues detected", no
native or asset change; **published to stable as `1.0.9+11` Patch 1**
(id 716474, aarch64), 2026-10-13 ~19:05 UTC. Android's dry run of the
same code had checked the icon font first. The App Store serves 1.0.9
(READY_FOR_SALE, checked 2026-10-13 with the VPS's ASC key).

Next tags: `gpatch-1.0.9+23--2`, `gpatch-1.0.8+22--6`, `+21--6`,
`+20--5`, `+19--5`, `gipatch-1.0.9+11--2` (on the mirror). Not patched:
`1.0.7+17` and `1.0.7+9`: no lean x264 there (`patch/1.0.7-reciters-quizzes`
has no `mbtree=0`), and Play's issues above are on 1.0.8 and 1.0.9;
1.0.7's Android reminders keep their 90 days.

Not in any patch, for the next store build (the user's call; since
2026-10-18 done the narrow way in `d220473`, see above):
`fix/android-skia` (`c5076a2`), the manifest's
`io.flutter.embedding.android.EnableImpeller=false`, which ends both
Impeller OpenGL ES failures (the snapshot crash and the PowerVR
shader-compile ANR at surface creation on 1.0.9). Not shipped on
2026-10-14: it moves every phone to Skia, also those where Impeller runs
on Vulkan and works. In this engine (`ff900e7`, `flutter_main.cc` and
`driver_info_vk.cc`) only these take Impeller's OpenGL path: Adreno 650
and older, PowerVR older than CXT, Huawei Maleoon, Xclipse below Vulkan
1.3, and phones whose Vulkan won't start; below API 29 it is Skia
already. The narrower fix is Skia for those phones alone, passed as
`--enable-impeller=false` (command-line flags beat the manifest in
`FlutterLoader`) from the first engine start in each process. First
check whether the 10-13 patches ended the snapshot crash on 1.0.8+19..22
and 1.0.9+23; if they did, Impeller stays. Also native: the
notification plugin's receivers still work on the main thread
(`goAsync`, or a fork that skips past-due entries at boot).

**2026-10-11 ~21:32 UTC, from the VPS: the save fixes, Dart only.**
At the user's word ("patch the save stuff only", then "to android"). One
commit, `18a6368`, on the new branch `patch/1.0.8-22` (= `main`'s
`b64f88f`, which has no app code past `9fee862`, +22's Patch 2), and
cherry-picked `-x` onto the other three branches, whose `lib/` was the
same file for file:

- Verse cards wait for the app to be on screen before `toImage`
  (`OnScreen.settle`, from `f6267a1` on `feat/live-recitation`): Play's
  largest 1.0.8 crash, 16 users, Impeller's OpenGL path segfaulting in
  `CreateSnapshotSurface` with the app in the background. Also the
  2026-10-11 note from a 1897 MB phone that died at "cards".
- No MediaCodec after a save died in it, or after two lost saves
  (`PhoneBudget.hardwareTrusted`, from `427c3c7`).
- Lean x264 (the smallest phones) runs `superfast`, passes and join.
- A lost save's note gives the save's own peak memory and says "x264
  only" once the hardware is retired; feedback code date `2026-10-11`.

The render process (native, `427c3c7`) waits for the store build:
`export_budget.dart` is the branch's file whole, and its render-process
counters stay at zero without it. No icon, asset, pubspec or native
change. Flutter tests green on all four branches. Dry runs
`gpatch-dry-1.0.8+19`, `+20`, `+21`, `+22--3` (runs 38174379844,
38174380038, 38174379728, 38174387173): "No issues detected", only the
two PC assets, verified. All four **published to stable** (Shorebird's
patches list, 2026-10-11; arm, aarch64 and x86_64):

| Release | Commit | Tag | GitHub run | Patch |
|---|---|---|---|---|
| `1.0.8+22` | `18a6368` (`patch/1.0.8-22`) | `gpatch-1.0.8+22--4` | 38175558765 | Patch 3, ~21:32 UTC |
| `1.0.8+21` | `8100139` (`patch/1.0.8-21`) | `gpatch-1.0.8+21--4` | 38175557041 | Patch 4, ~21:32 UTC |
| `1.0.8+20` | `61e86cd` (`patch/1.0.8-20`) | `gpatch-1.0.8+20--3` | 38175557281 | Patch 7, ~21:33 UTC |
| `1.0.8+19` | `3a8decc` (`patch/1.0.8-19`) | `gpatch-1.0.8+19--3` | 38175557136 | Patch 8, ~21:32 UTC |

Not patched: iOS (the user asked for Android only) and `1.0.7+17`. Next
tags: `gpatch-1.0.8+22--5`, `+21--5`, `+20--4`, `+19--4`.

**2026-10-09 ~16:38 UTC, queued from the VPS: "Join us on Telegram".**
Settings' "Invite someone · earn ✦ 5" row replaced by a row that opens
`https://t.me/AyahReel` in the external app (`Icons.send_rounded`,
already in the font; the invite stays on the home screen's button).
Dart only. Main commit `9fee862`; cherry-picked onto the patch branches.
The user asked for the OTA push in the same message. All four
**published to stable** (Shorebird's patches list, 2026-10-09):

| Release | Commit | Tag | GitHub run | Patch |
|---|---|---|---|---|
| `1.0.8+22` | `9fee862` (`main`) | `gpatch-1.0.8+22--3` | 37960599926 | Patch 2, ~16:56 UTC |
| `1.0.8+21` | `92c3464` (`patch/1.0.8-21`) | `gpatch-1.0.8+21--3` | 37960600940 | Patch 3, ~16:55 UTC |
| `1.0.8+20` | `8971313` (`patch/1.0.8-20`) | `gpatch-1.0.8+20--2` | 37960602917 | Patch 6, ~16:56 UTC |
| `1.0.8+19` | `2b216c2` (`patch/1.0.8-19`) | `gpatch-1.0.8+19--2` | 37960603849 | Patch 7, ~16:58 UTC |

Not patched: `1.0.7+17` (its branch conflicts with the 2026-10-08
changes).

iOS, same day ~16:50 UTC, at the user's word: `patch-1.0.7+9--14` on
`d63ac02` (`patch-1.0.7+9--13`'s `3a72b6f` + the Telegram commit, pushed
to `patch/1.0.7-reciters-quizzes`). **Not published.** The only check run
came from Codemagic app `6a9d08ca…` and failed at once: "App Store
Connect integration "AyahReel ASC key" does not exist". The working app
`6a63ba37…` posted no check for the tag, so a tag push alone does not
start it while that account's billing is off (the API's 402 is not the
only symptom). The Codemagic dashboard then said why: "You have run out
of build minutes on your personal account and cannot start new builds".
The free minutes reset monthly, and tag builds need them as much as API
calls do.

So iOS patches moved to GitHub Actions too: `.github/workflows/ios-patch.yml`,
tags `gipatch-dry-<release>` / `gipatch-<release>[--N]`, `macos-26` with
Xcode 26.6 (the job stops unless the iOS SDK build is `23F81a`). Signing
as on Codemagic: `codemagic-cli-tools` fetches the existing certificate and
App Store profiles (never creates them) with the repo secrets `ASC_KEY_ID`
`6ZMFW75VF7` (since 2026-10-14; `M2J3MM4WX5` leaked with the log and is
revoked), `ASC_ISSUER_ID`, `ASC_KEY_P8` (set from the VPS)
and `CERTIFICATE_PRIVATE_KEY` (the key of the distribution certificate;
the readable copy is the VPS's `/root/keys/ayahreel-ios-cert-key`, and
the PC's `C:\Users\dell\keys\ayahreel-ios-cert-key` is stale). Replaced on
2026-10-14 after an unredacted patch log leaked it on the public CI
mirror (CLAUDE.md): certificate `QC4CGJ346D` revoked, `AWY4M8ZZQG`
(expires 2027-10-14) made from a new key, with new App Store profiles
`P35M3M9UAM` (`com.ayahReel.app`) and `F9NWM929G6` (`.AyahWidget`); the
secret on both repos and Codemagic's `ios_signing` group hold the new
key. Store builds are unaffected; the next iOS build or patch signs with
the new certificate. No `--dart-define=META_APP_ID`: the code's default is
the Meta app id. macOS minutes count 10x against the repo's Actions
allowance. The Telegram patch of `1.0.7+9` goes out as `gipatch-1.0.7+9`.
`gipatch-1.0.7+9` (run 37963448840, on `fb7d615`) stopped at signing,
nothing built: the certificate key, set from PowerShell, was "not valid"
to `codemagic-cli-tools`. The job now strips CRLF and a BOM and checks the
key with `openssl` first (it was a UTF-8 BOM). `gipatch-1.0.7+9--2`
(run 37963722615, `50c07b4`) signed and built, then Shorebird refused:
"Your ios/Podfile.lock is different from the one used to build the
release". Not published. Podfile.lock isn't committed; the release's hash
is on Shorebird (`podfile_lock_hash` on the release's iOS artifacts,
`26ea10fe…`), the runner has CocoaPods 1.17.0, and the only pods are the
local `Flutter` and `flutter_local_notifications`. The job now runs
`tool/podfile_lock_match.py`, which finds the CocoaPods version that makes
the runner's lock byte-identical to the release's, then checks again under
that version; if none matches, it stops.

**`gipatch-1.0.7+9--3`** (run 37964737495, `82dc713` on
`patch/1.0.7-reciters-quizzes`): the release's lock was CocoaPods 1.16.2's,
byte for byte; checked again under 1.16.2, "No issues detected", and
**published to stable as `1.0.7+9` Patch 12** (2026-10-09, ~17:28 UTC). Since
`--13`'s `3a72b6f` it adds only the Telegram commit `d63ac02` plus the
workflow and `tool/podfile_lock_match.py`. Xcode 26.6, sdkBuild `23F81a`.
Next iOS patch of this release: `gipatch-1.0.7+9--4` (GitHub) or
`patch-1.0.7+9--15` (Codemagic, once it has minutes).

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
- **The exception (allowed by the user, 2026-10-05):** for a PC-built release, `android-patch` passes `--allow-asset-diffs` only when `tool/verify_asset_diffs.py` finds that exactly `NOTICES.Z` and `quran_verses.json` changed, with the release's own content (same verses; same licences for the same packages, however grouped), and nothing else. A patch never carries assets, so phones keep the release's copies. The verdict step "no PC asset exception needed" shows a cross when it was used. `--allow-native-diffs` is still never passed, and any other asset change still means a store build.
- **Why not, exactly (2026-10-05):** the Codemagic logs name two files, `base/assets/flutter_assets/NOTICES.Z` and `base/assets/quran_verses.json` (the home widget's verses, `android/app/src/main/assets/`, which `.gitattributes` doesn't pin, so the PC checks it out with CRLF). The json can be given the release's bytes: `tool/match_release_bytes.py` does that from the release AAB Shorebird downloads (`$TMPDIR/<random>/artifact`). NOTICES.Z can't: Flutter gzips NOTICES on the machine that builds, and a gzip header records that machine's OS (zlib's `OS_CODE`, 10 on Windows, 19 or 7 on macOS), so a Mac's NOTICES.Z never equals a Windows one byte for byte, whatever the line endings. Tried on `apatch-dry-1.0.8+19--6` (the script found the release, 127,716,191 bytes, and then crashed reading NOTICES.Z as zlib; it is gzip). The other runs of that round (`apatch-dry-1.0.8+20--2`/`--3`, `apatch-dry-1.0.8+19--5`, `apatch-dry-1.0.7+17--5`/`--6`) were cancelled or ran the script's first version. So a PC-built release is patched from the PC, or with a deliberate, user-approved exception for exactly these two files; a release built on Codemagic (`arelease-<build>`) has none of this.
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
| `23F81a` | 26.6 (17F113) | `1.0.6+8`, `1.0.7+9` — checked 2026-09-25; `1.0.9+11` — 2026-10-12 (the IPA's `DTSDKBuild`) |
