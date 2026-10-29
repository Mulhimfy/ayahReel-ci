# Release runbook

AyahReel is live. The App Store has had it since **2026-08-09**; Play has had
it in **closed testing since around 2026-08-11**. Both listings are frozen
around the identifiers below, and 1.0.3 is the current train.

This started as a pre-launch checklist and is now the runbook. Read it for
what is permanent, what has to move on every release, and in what order — the
ordering is the part that bites, and none of it is recoverable by editing a
file afterwards.

## Settled

The first two are frozen for good — nothing below can undo them.

- [x] Android `applicationId` → `com.ayahreel.app`, iOS bundle id →
      `com.ayahReel.app` (both were `com.example.*`, which Play rejects). The
      **case difference is deliberate**: the App Store Connect record (Apple ID
      6794389870) was created as `com.ayahReel.app`, and Apple matches bundle
      ids case-sensitively — an IPA built as `com.ayahreel.app` is rejected with
      "no suitable application record found". Play is a separate namespace and
      keeps the all-lowercase id. **Both are now spent.** Changing either does
      not rename this app, it creates a different one and orphans every
      install; there is no migration and no support ticket that undoes it.
- [x] Release signing wired to `android/key.properties` (gitignored), with debug
      fallback so `flutter run --release` still works.
- [x] Explicit `version:` in pubspec, currently `1.0.3+13`. See "Build
      numbers" and "The update prompt" below — it is now the only version
      string anybody types by hand.
- [x] Build number auto-increments +1 per build, shared by Android and iOS.
      See "Build numbers" below.
- [x] Git repo initialized. Required for both the above and for Shorebird.
- [x] Verified: `flutter analyze` clean, 363 tests pass (9 skipped — they want
      release word-alignment data that is not in the repo), release AAB builds.
- [x] `ITSAppUsesNonExemptEncryption` = `false` in `ios/Runner/Info.plist`. The
      app only talks HTTPS, so it is exempt; without the key App Store Connect
      holds every build at "Missing Compliance" until answered by hand.
- [x] `NSPhotoLibraryAddUsageDescription` in `ios/Runner/Info.plist`. `gal`
      writes the finished reel to the "Ayah Reels" album via add-only photo
      access, which is a *separate* key from `NSPhotoLibraryUsageDescription`
      (that one only covers `image_picker` reading a background). Missing it
      crashes the save path on iOS.
- [x] App Store Connect metadata: subtitle, keywords, support + privacy policy
      URL, copyright, review notes, Lifestyle/Photo & Video categories, content
      rights, 4+ age rating, privacy label (published; what it says now is
      under the share-report item below), free
      in all 175 countries, screenshots and description. The 1024 icon for the
      listing is `docs/store/icon_master_1024.png`, and Play's 512 is
      `docs/store/play_store_512.png`.
- [x] App icon — the Verse Prism (owner's pick, 2026-10-26: `ayah_icons_v5`,
      `04_verse_prism_gold`): a beam through a glass prism, fanning out as
      the lines of Al-Fatiha, on a gold field. On both platforms, and on the
      story cards (the Tanafus result, the invite, the verses): those draw
      `docs/store/invite/app_icon_384.png`, baked into
      `lib/render/invite_story_images.dart` by `tool/invite_story_images.py`,
      so a patch can carry it. Android has the legacy launcher, the round
      variant (declared as `android:roundIcon`, which API 24–25 launchers
      need), and an adaptive icon (the gold field as its background layer,
      the prism and its lines as the foreground) — plus a monochrome layer
      (the prism's outline, the beam, three lines), so Android 13+ themed
      icons don't fall back to a grey blob. iOS has all 15 sizes, every one
      flattened to RGB: an alpha channel anywhere in the set is an automatic
      App Store rejection. Masters for the store listings live in
      `docs/store/`: `icon_master_1024.png`, `play_store_512.png`,
      `feature_graphic_1024x500.png`. The launcher icons are native files:
      they change with each platform's next store build, never by a patch.
- [x] Play listing: privacy policy URL, data-safety form, content rating,
      screenshots, feature graphic — all filled, or the app would not have
      reached closed testing. The policy is hosted on Notion and linked from
      Settings → Legal; the same URL is the one in App Store Connect. iOS also
      shows Apple's standard EULA there — not required while the app is free,
      but mandatory under guideline 3.1.2 the moment auto-renewable
      subscriptions exist, so it ships now.
- [x] Data-safety form declares the network fetches this app makes (Quran text,
      recitation audio, word-alignment data) and the `POST_NOTIFICATIONS`
      daily-reminder usage. **Re-check it whenever a release adds a call.**
      1.0.3 added one — `UpdateService` fetching the version feed — which is a
      public gist holding two version strings, carries no user data in either
      direction, and needs no new declaration.
- [ ] **Declaring the Tanafus share report** (`ArenaShareReport`, branch
      `feat/live-recitation`, 2026-10-10). Every tap on a Tanafus result's
      share buttons posts to the feedback inbox (FormSubmit) without the
      user writing anything: new or old user and since when, reel counts,
      the round (scope, right/wrong, score), what the card shows, and share
      counts. No name, identifier or challenge code. It is plain Dart, so a
      patch would ship it as surely as a store build. Where each disclosure
      stands (2026-10-11):
      - [x] Play data safety: was "No data collected". Sent for review on
        2026-10-11 (managed publishing off, the only change in it): collected,
        none shared, encrypted in transit, no accounts. Email address
        (optional, app functionality), Diagnostics (optional, app
        functionality + analytics), App interactions (required, app
        functionality + analytics), Other user-generated content (optional,
        app functionality), Other actions — the quiz results (required,
        analytics). The optional ones are the feedback form's; deletion
        requests left unanswered (optional question).
      - [ ] Privacy policy (Notion): the user added the share-note paragraph
        on 2026-10-11, but inside "Information stored on your device",
        whose intro says it never leaves the device. Still to fix: move it
        to its own section, the "In short" lines ("no analytics", "only two
        things ever reach us"), the "Last updated" date, two typos. Then
        copy the text into `docs/store/privacy-policy.md` and
        `docs/privacy-policy.html`.
      - App Store label: left as it is, the user's call. It already
        declares Product Interaction (with Email Address, Customer Support,
        Other Diagnostic Data — "linked to you", App Functionality only);
        *Analytics* is not ticked as a purpose.
- [ ] **Play listing: the new icon and feature graphic, once Play's public
      rollout is out** (owner's ask, 2026-10-26). Play is still in closed
      testing. After the production rollout, upload
      `docs/store/play_store_512.png` as the app icon and
      `docs/store/feature_graphic_1024x500.png` as the feature graphic, on
      the main store listing, and send the change for review. The App Store
      listing takes its icon from the build (`Icon-App-1024x1024@1x.png`),
      so it changes with the next iOS store build on its own.

## Preview APKs

A branch can be tried on a phone without a store build or a patch: push a
commit whose message carries `[apk]`, and `.github/workflows/apk-preview.yml`
builds an arm64 release APK and publishes it as a pre-release named
`preview-<sha7>` in this repo. It installs **beside** the store app, as
"AyahReel Preview" (`com.ayahreel.app.preview`), so the phone keeps its
reels and settings; it is signed with the upload key from the repo secrets,
so each preview installs over the previous one. A plain `flutter build`, not
Shorebird: it reaches no store and no patch can target it. Nothing to record
in `RELEASES.md`. It builds with the store builds' Flutter, `flutter_version.txt`;
`tool/check_flutter_version.sh` fails CI if any build or test pins another.

## Standing rules

- Ship the **`.aab`**, not the `.apk`. The universal APK is 236 MB because it
  bundles all three ABIs; the bundle splits per device (arm64 ≈ 60 MB of native
  libs, well under Play's 200 MB per-device download cap). Most of that weight
  is `ffmpeg_kit_flutter_new`.

## Build numbers

Both stores require the build number to be strictly greater than the last
accepted upload — Apple rejects a duplicate `CFBundleVersion`, Play a duplicate
`versionCode`.

**There are now two sources of truth, one per platform, and they will diverge.**

- **iOS builds on Codemagic** ask Apple: `codemagic.yaml` runs
  `app-store-connect get-latest-app-store-build-number 6794389870` and adds 1.
  `build_number.txt` is ignored there, and has to be — Codemagic clones the repo
  fresh, so the script below would write into a workspace that is discarded and
  every build would emit the same number.
- **Android builds locally** use `build_number.txt` via the script below.
- **Since 2026-10-12 both run on GitHub Actions** (RELEASES.md, "Store builds
  from GitHub Actions"). `ios-release.yml` asks Apple the same way, and passes
  over a number Shorebird already has a release for. `android-release.yml`
  builds the number its tag names (`garelease-<n>`), which must equal
  `pubspec.yaml`'s; keep `build_number.txt` equal to it.

Gaps are legal on both stores, so the two counters drifting apart is harmless.
What matters is that each is monotonic within its own store.

For local Android builds, always go through the script so the file stays the
authoritative Play counter. Sync the version first — Codemagic does that step
for you on iOS, and nothing does it for you here:

```bash
bash tool/sync-version.sh
shorebird release android --build-number=$(bash tool/build-number.sh)
```

```powershell
./tool/sync-version.ps1
shorebird release android --build-number=$(./tool/build-number.ps1)
```

Forgetting the first line is caught, not shipped: `flutter test` fails on
version_sync_test.dart. Run the suite before a release build and it cannot get
past you.

Anything that reaches a store goes out through `shorebird release`, never
`flutter build appbundle` / `flutter build ipa`. A plain Flutter build has no
updater linked into it, so it can never be patched — every Dart fix would need
a fresh store review. Builds up to **vc8** were cut that way and are stuck with
it; there is no retrofit. Plain `flutter build` stays fine for local debugging.

iOS is not built by hand at all — Codemagic runs `shorebird release ios` on a
version tag (see `codemagic.yaml`).

The `--build-number` flag is the only thing that reaches **iOS** —
`CFBundleVersion` resolves from `FLUTTER_BUILD_NUMBER`, which Gradle cannot
influence. A bare `flutter build apk` still gets a sane Android versionCode
(Gradle reads `build_number.txt` directly) but iOS would not.

Gaps in the sequence are legal, so if a number gets burned by a rejected
upload, just run the script again. **Commit `build_number.txt` after each Play
upload** so the counter doesn't reset or collide from another machine. It has no
bearing on iOS any more — Codemagic gets that number from Apple.

## The update prompt — two numbers, every release

Users on an older build get a soft prompt on launch ("A new version is out" —
Not now / Update), which opens this app's store listing. It comes back on
**every launch** until they update, then goes silent by itself. "Not now"
closes that launch's dialog and buys nothing beyond it: the day's grace this
used to give meant a once-a-day user was asked once and then left alone for
weeks with an update they never installed. There is no version
of this that blocks the app, and there must never be: Apple rejects update
walls, and someone who opened AyahReel to hear a verse gets to hear it.

It works off exactly one comparison:

```
  app  : kAppVersion            (lib/data/app_version.dart)
  feed : {platform}.latest      (the public gist)
  app < feed  ->  prompt
```

**Per release you touch two numbers, and both of them describe the build you
just shipped. Never a "next" number, never a guess.**

1. Bump `version:` in `pubspec.yaml` — as always. It is the only version
   anybody types.
2. `kAppVersion` follows on its own. `tool/sync-version.sh` (or its `.ps1`
   twin) writes it from pubspec; Codemagic runs that before every build and
   every patch; `test/version_sync_test.dart` fails the build if the two ever
   drift apart. Run the script yourself before a local Android build — and
   never edit the constant by hand, which is the whole point of it existing.
3. Ship it. Wait.
4. **Only once the build is actually downloadable on that store**, raise that
   platform's `latest` in the feed.

Step 4 last, always. A feed that names a version the store has not published
yet sends every user to a listing still offering the build they already have,
and they will conclude the prompt is broken — which it will be.

iOS and Android have separate keys because they are released separately and
routinely sit on different versions:

```json
{ "ios": {"latest": "1.0.3"}, "android": {"latest": "1.0.2"} }
```

Raise each one the day *that* store goes live. Play review and Apple review do
not land together.

The feed lives in a **public gist**, not in this repo — `Mulhimfy/ayahReel` is
private, so its `raw.githubusercontent.com` URLs 404 for every phone on earth.

- Edit it: <https://gist.github.com/Mulhimfy/941b3343d0d50daaf32772a0c912e961>
- The app reads: `https://gist.githubusercontent.com/Mulhimfy/941b3343d0d50daaf32772a0c912e961/raw/update.json`
  (mirrored in `UpdateService.feedUrl`, `lib/data/update_service.dart`)

Raw gist responses cache for about five minutes, so the prompt starts within
minutes of the edit. **Keep the URL hashless.** GitHub's "Raw" button hands out
a `/raw/<revision-sha>/update.json` form pinned to one edit — paste that into
the app and the feed is frozen at today's version forever.

**An empty `feedUrl` disables the whole check** — which is the correct state
until a feed exists. Every other failure (no network, 404, malformed JSON) is
silent by design and ends as "no update".

### Patching, and the one way to get this wrong

`kAppVersion` is Dart, so a Shorebird patch *can* change it — and a patch must
never raise it. A patch does not change what the store installed, so a patched
app that claims a higher version starts lying about which build it is, and
stops prompting for the real update it is missing.

**A patch's `kAppVersion` is the version of the release being patched**, which
is not always what pubspec says. Send the update checker back to users still on
1.0.1 and the fix is cut from a commit whose pubspec has moved on to 1.0.3 —
ship *that* number and every one of those phones reads itself as current and
stays silent forever, failing exactly the users the patch was for.

The `ios-patch` workflow handles this without being asked: the tag names the
release (`patch-1.0.1+12`), and the tag is what it syncs `kAppVersion` from,
not pubspec. Patching the release you just built is the same number either way,
so this only ever shows up when it matters.

The prompt mechanism itself ships fine over the air: it is pure Dart over
`http` and `url_launcher`, both already linked into the app. Adding
`package_info_plus` or Play's in-app-update plugin would end that — anything
native needs a store build — which is exactly why the version is a constant
rather than a read of the installed package.

### Back-patching the checker into the releases that shipped without it

**1.0.3 is the first build that reads the feed at all.** Every install older
than it is deaf to the gist: raising `latest` does nothing for those users, now
or ever, until the checker is patched into their release. That is the one-time
job below, and it is the reason the feature was written to be Dart-only.

It is not urgent and it is not automatic. Do it per platform, *after* that
store's `latest` has gone up, so a patched old build has something true to say.

The releases that can take it (`shorebird releases list --platform=<p>`):

```
android                    ios
  1.0.2+12   <- the live one   1.0.2+4   <- the live one
  0.1.0+11   <- stragglers     1.0.1+4
                               1.0.1+3   <- listed as "0.1.2" on the store
                               0.1.1+3 / +2
                               0.1.0+2
```

Android builds at or below **vc8** are not on this list and never will be —
they were cut with plain `flutter build`, have no updater linked in, and cannot
be reached by any patch. Those users move only when they update by hand.

**A patch carries the entire Dart diff, not the one fix you have in mind.**
Tagging today's `main` as a patch of 1.0.2 does not send the checker to 1.0.2
users; it sends them all of 1.0.3's Dart, on top of a 1.0.2 binary whose assets
and native code are a release behind. Shorebird refuses that outright (it
checks for asset and native diffs and this release changed both), which is the
correct answer arriving as a failed build.

So each target gets its own branch, off the last thing that release actually
shipped — the newest `patch-<that version>` tag if one exists, otherwise the
release commit:

```bash
git checkout -b patch/checker-1.0.2-ios patch-1.0.2+4   # not main
git checkout main -- lib/data/app_version.dart
git checkout main -- lib/data/update_service.dart
git checkout main -- lib/widgets/update_dialog.dart
# then add the one call: maybePromptUpdate(context) in home_shell.dart
git commit -am "Give 1.0.2 the update prompt"
```

Four files, no pubspec change, no assets: `http` and `url_launcher` are already
linked into every one of these releases, which is what makes this possible at
all.

Then ship it — iOS by tag, Android from here:

```bash
git tag patch-1.0.2+4 && git push origin patch-1.0.2+4    # iOS, via Codemagic
```

```powershell
./tool/sync-version.ps1 1.0.2      # Android — nothing does this for you
shorebird patch android --release-version=1.0.2+12
```

The tag on the iOS side already carries the version, so `kAppVersion` is set
from it automatically. On Android the sync is yours to run, and getting it
wrong is the failure described just above: a 1.0.2 phone told it is 1.0.3 goes
quiet permanently. `flutter test` catches the reverse mistake (a constant left
matching pubspec) — it does *not* catch this one, because on a patch branch the
two are *supposed* to differ. Read the number back before you push.

A tag name is only reusable once; for a second patch of the same release,
append `--2` (see "Patching iOS" below).

### Testing it

Point `kAppVersion` at something old (`0.9.0`), run, and the prompt appears.
"Not now" dismisses it and the next launch asks again — nothing is written to
disk and there is nothing to re-arm. (Older builds wrote an `update_check.json`
snooze file into the app-support directory; it is now ignored and harmless.)
Only one thing silences the prompt: a `kAppVersion` that has caught up with the
feed.

## Shorebird setup (after the keystore, before the release build)

Shorebird is not on pub — it ships its own installer. On Windows:

```powershell
Set-ExecutionPolicy RemoteSigned -scope CurrentUser
iwr -UseBasicParsing 'https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1' | iex
# restart the shell so PATH picks up shorebird
```

Then, from the app root:

```bash
shorebird login                     # opens a browser
shorebird init                      # writes shorebird.yaml — COMMIT IT
shorebird flutter versions list     # Shorebird ships its own Flutter (3.44.7)
```

`shorebird.yaml` carries the `app_id` the installed app uses to find patches. If
it is missing from a build, patches silently never arrive.

### The Codemagic API key expires — 2027-08-06

Android is released and patched from this machine, where `shorebird login` is
enough. iOS cannot be: there is no Mac here, so Codemagic builds it, and
Codemagic authenticates with an API key instead of a browser session.

The key in use was minted 2026-08-06 at <https://console.shorebird.dev> →
Account → API Keys, with a **one-year** lifetime, and lives in Codemagic as the
secret `SHOREBIRD_TOKEN` in the variable group `shorebird`. Full access is the
only scope on the free plan, so treat it like a password: it can manage apps,
collaborators and billing.

**Around August 2027 it dies.** The symptom is an iOS build failing at the
release step with an authentication error and nothing in this repo having
changed — easy to misread as a Shorebird or Codemagic outage. To rotate: mint a
new key, paste it over the existing `SHOREBIRD_TOKEN` value, delete the old key.
Nothing in the repo changes; `codemagic.yaml` only ever names the group.

(`shorebird login:ci`, which older docs mention, has been retired and now just
prints a pointer to the console.)

Release, then patch:

```bash
shorebird release android           # this artifact goes to Play
# ... fix Dart code, then COMMIT (versionCode comes from commit count) ...
shorebird patch android --release-version 0.1.0+<n>
```

`<n>` must be the build number of the release users actually installed — NOT a
freshly bumped one. Do not run `tool/build-number.sh` when patching. Every
Gradle build prints the string it used (`AyahReel version: 0.1.0+8`), and
`shorebird releases list` shows what was released.

**On iOS, `<n>` is Apple's number, not `build_number.txt`'s.** Codemagic derives
it per build, so `build_number.txt` will not tell you what shipped. The build log
prints the answer directly (`Shorebird release-version for this build will be
0.1.0+<n>`); `shorebird releases list` and the TestFlight build list also show
it. Guessing here silently produces a patch that no installed app will ever pick
up.

### The iOS release build ends on a red step, and that is fine

A `v*` tag builds the IPA, uploads it, and waits for Apple to finish processing
— all of which can succeed and still leave the Codemagic run marked failed, on
the last post-processing step:

```
Submit build ... to TestFlight beta review
  Failure: Complete test information is required ... for external testing.
  App is missing required Beta App Information: Feedback Email.
  App is missing required Beta App Review Information: First Name, Last
  Name, Phone Number, Email.
```

**Nothing is wrong with the build.** The binary is on App Store Connect and
processed; only submission to *external* TestFlight review is blocked. Internal
testers can install it immediately, and it can be attached to a version record
and submitted to the App Store as normal — external testers are the only thing
gated.

It is a one-time form, per app, not per build:
<https://appstoreconnect.apple.com/apps/6794389870/testflight/test-info>.
Until it is filled, read a red run on that step as green and check the App
Store Connect build list rather than the Codemagic badge.

### Patching iOS: push a tag — and know that the push IS the ship

There is no Mac here, so iOS patches are cut by CI. Pushing any tag matching
`patch-*` runs the `ios-patch` workflow, which ends in `shorebird patch ios`.
**That publishes straight to installed apps.** There is no staging step, no
approval, and no review between the push and users receiving it.

```bash
git tag patch-1.0.1+3 && git push origin patch-1.0.1+3
```

The part after `patch-` must be a release version exactly as `shorebird
releases list` reports it. A release accepts any number of patches, each
superseding the last, but git will not reuse a tag name — so for the second and
later patches to one release, append `--<anything>`, stripped before the
version is read:

```bash
git tag patch-1.0.1+3--2 && git push origin patch-1.0.1+3--2
```

Tag only when HEAD is the release commit plus the fix; the patch carries
everything else on the branch too.

Users land on a patch on their **second** launch — the updater downloads in the
background on one launch and applies on the next. Fresh App Store downloads are
no different: Apple keeps serving the released binary until a new build ships,
so they take the same two launches.

A patch build produces **no IPA and never touches Apple** — that workflow has no
`app_store_connect` publishing block. Nothing is submitted and nothing enters
review. A patch cannot be unpublished; the only way back is a newer patch over
the top. To stop one mid-flight, cancel the build in the Codemagic UI.

## The home-screen widget (native: store build only)

Everything under `android/app/src/main/{kotlin/.../VerseWidget.kt,res/}`
and `ios/AyahWidget/` is native. A change there — the layout, the
backgrounds, the verse list's native copies, the turn times — ships
only in a store build; `shorebird patch` refuses the diff, correctly.
The Dart list (`lib/data/quran_verses.g.dart`) and the card can be
patched, but the widget will keep showing the *old* list until the next
store build, so a verse-list change is a store-build change too.

iOS specifics:

- The widget is the `AyahWidgetExtension` target, bundle id
  `com.ayahReel.app.AyahWidget`. It needs a provisioning profile of its
  own; codemagic.yaml fetches (and, on the first run, `--create`s) one
  alongside the app's. No capability has to be enabled on it in the
  portal — there is no App Group.
- Its `Info.plist` takes CFBundleShortVersionString and CFBundleVersion
  from the same FLUTTER_BUILD_* settings as the app (via
  `ios/Flutter/Widget.xcconfig`), because App Store Connect rejects an
  extension whose numbers differ from its app.
- The extension is not a CocoaPods target and must never become one:
  it links WidgetKit and SwiftUI only.

Android needs nothing beyond the build: the widget is a receiver in the
manifest, and Play has no notion of it.

## Constraints to remember once live

- **Patches here can only change Dart code.** Native changes can never be
  patched: adding/removing/upgrading any plugin, permission changes, minSdk,
  the Flutter engine version, app icon. All of those need a store release.
  Shorebird itself can carry assets behind `--allow-asset-diffs`; this project
  deliberately never passes it — see the asset note below.
- **Do not `flutter pub upgrade` casually after release.** This app has 9 native
  plugins (`ffmpeg_kit_flutter_new`, `video_player`, `audioplayers`,
  `image_picker`, `gal`, `share_plus`, `flutter_local_notifications`,
  `flutter_timezone`, `url_launcher`). Bumping any of their native code
  invalidates patching.
  `pubspec.lock` is committed — keep it that way.
- **Avoid `--obfuscate`.** Shorebird currently flags an obfuscation issue. If it
  is ever enabled, it must be identical on both release and patch builds.
- **Asset changes are refused, by choice.** `codemagic.yaml` omits
  `--allow-asset-diffs` on purpose: assets do not travel over the air, so a
  patch that appeared to succeed would behave differently from what was tested.
  Editing `assets/catalog.json`, `assets/scene_thumbs/`, `assets/backgrounds/`
  (12 MB) or `assets/fonts/` (2.5 MB) therefore **fails the patch build** —
  which is the right answer, since it needs a store release. Quran text,
  recitations and alignment data are already fetched remotely; the faces a reel
  is typeset in deliberately are not, so adding one to the style step is a
  release and never a patch — see `lib/data/verse_font.dart`.
  To pull a bad scenery *now*, add its id to `SceneCatalog.withdrawn`
  (`lib/data/scene_catalog.dart`). That is Dart, so it patches; the real asset
  deletion follows in the next store build, and the id comes back out of
  `withdrawn` in that same commit.

## Known warning (not blocking)

`ffmpeg_kit_flutter_new`, `flutter_timezone`, and `share_plus` still apply the
Kotlin Gradle Plugin directly. Builds fine on Flutter 3.44.6, but a future
Flutter will fail on it. Watch those plugins' changelogs — and note that fixing
it will require a store release, not a patch.
