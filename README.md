# Ayah Reels

Create a Quran recitation reel (9:16 mp4) — any of the 114 surahs, any verse range — in under a minute.

```
flow
────
screen 1  pick reciter (tap = hear it)
screen 2  pick verses  (any surah, tap first + last ayah)
screen 3  pick scenery (swipe, live verse preview)
screen 4  style it     (type, colour, grade — on a still frame)
screen 5  reel plays instantly ──> [Share] / save
```

## Content sources & accuracy

- **Text**: Tanzil Uthmani + Saheeh International via alquran.cloud, cached
  to disk after one fetch per surah. The source glues the Basmala onto
  ayah 1 of every surah; the app strips it everywhere except Al-Fatiha
  (where it *is* ayah 1) so displayed verse text matches the mushaf.
- **Audio**: two kinds of voice (`AudioSource` in `lib/data/models.dart`).
  *Per-ayah files* — EveryAyah.com, plus Tarteel's CDN and King Saud
  University's Ayat project for voices EveryAyah lacks — are concatenated
  on-device with FFmpeg; each ayah's window is its measured (ffprobe)
  duration, so text/audio sync is exact by construction. *One file per
  surah* — mp3quran.net — comes with a published table of where each
  ayah is (`ayat_timing`), or quranicaudio.com with the Quranic Universal
  Library's segments (Mahmoud Ali Al-Banna, whose table counts the basmala
  as verse 1's — `openingMs` has the app skip it). The app fetches only the byte
  range a reel needs (Ayat al-Kursi is ~2.5 MB of a 113 MB Al-Baqarah),
  and moves every verse boundary into the reciter's breath: see
  `lib/data/surah_slice.dart`. Three reciters ship a bundled Al-Fatiha for
  an instant offline first run; the rest stream on demand.
- **Adding a reciter**: add its entry to `reciters` in
  `lib/data/fatiha_data.dart`, then run `python3 tool/verify_reciters.py
  --only <id>` (network, ffmpeg; a few minutes). It checks every file, and
  for a surah-file voice every table and whether the tables line up with
  the audio, and writes `tool/reciters_verified.json`, which
  `test/reciter_sources_test.dart` holds the app to. Give a new voice the
  `pace` it measured, and its style line in the four tables in
  `lib/l10n/l10n.dart`. A surah a voice's host can't serve (a missing
  file, a table from another recording) goes in its `missing` set, and
  the pickers then don't offer that pair. A voice kept although the tool
  can't vouch for its sync or its sound is named, with why, in the
  tool's `USER_ACCEPTED`. `--survey` scores every Hafs set mp3quran has.
  Delete `build/verify_reciters` to fetch everything afresh.
- **Scenery**: 379 scenes in two shapes — portrait (1080x1920, the verse
  drawn on top) and wide (1920x1080, letterboxed with the verse below).
  24 ship inside the app so it works offline on a cold install; the rest
  are served from the releases of
  [ayah-reels-scenes](https://github.com/Mulhimfy/ayah-reels-scenes) and
  cached on device the first time one is chosen. A *poster* for every
  scene is bundled (~4 MB for all 379), which is what lets the picker
  draw the whole library instantly with no network — only the file
  behind a chosen scene ever travels.
- **Growing the library**: `tool/harvest_scenes.py` (discover, fetch),
  `tool/curate_scenes.py` (score, build, gallery, sync),
  `tool/publish_scenes.py` (stage, upload). Scenes are scored for
  readability against the app's own scrim, deduplicated across sources,
  and rejected outright if a face is detected.

## Typography and the grade

The fourth screen is where a reel stops looking like everyone else's,
and both halves of it are built on the same rule: **the preview is the
file**.

- **Faces.** Sixty-five families over sixty-six files, all bundled
  rather than fetched: **ten** the verse can be set in — every one of
  them proved against all 6236 verses, which is why there are ten and
  not fifty — **thirty** for a Latin translation, **nine** for one in
  Arabic script (Nastaliq among them, for Urdu), and **twenty** more
  offered on a card and nowhere else. That last tier exists because a
  display face cannot always draw the transliteration marks a
  translation needs, and a card is typed by the person holding it
  rather than being a claim about the Quran. Each carries a size factor and a line height *derived from its
  own metrics*, so two faces at one nominal size are the same size on
  the page and no face runs its lines into each other.
  `tool/fetch_fonts.py` writes the set; `tool/verify_fonts.py` proves,
  over all 6236 verses and every edition, that each face can set what
  it is offered for and that those two numbers still match the files.
  A face that cannot — Reem Kufi, Gulzar, Lora, Playfair and others —
  is not offered, and `assets/fonts/README.md` says why for each.

- **Colour.** Twenty-four swatches, applied to either the verse or the
  accent (the rule under it, and the word as it is recited). Every one
  of them is named for a screen reader.

- **The grade.** Seven designed looks — plus the scenery as it was
  shot, which is where every reel starts — and warmth, vibrance,
  vignette, grain and a fade. All of it is one derivation in
  `lib/data/reel_effects.dart`, emitted twice: as Flutter colour
  filters over the preview, and as an FFmpeg chain in the encode —
  with the FFmpeg form's clamping read back so the two cannot disagree
  (`test/reel_effects_test.dart` pins exactly that). It rides the
  scenery and nothing else: the legibility scrim, the letterbox band
  and the verse are not footage and are not graded. A reel nobody has
  graded costs the encode nothing — the whole feature drops out of the
  filtergraph.

Nothing plays on that screen, deliberately: a running video is the
worst possible ground for judging a typeface, and every scenery in the
app's own library already ships the still.

## Setup

```
cd ayah_reels
flutter create . --platforms=android,ios   # generates android/ ios/
flutter pub get
```

Then add assets (each folder has a README with sources):

1. `assets/audio/` — 3 reciter mp3s (required)
2. Nothing: `assets/fonts/` is committed, and `tool/fetch_fonts.py`
   reproduces it if a face ever has to be replaced
3. `assets/backgrounds/` — 5 looping mp4s (optional, gradient fallback exists)
4. Verify timings: `tool/verify_timings.md` (required before trusting sync)

## Platform config (FFmpeg on mobile)

Uses `ffmpeg_kit_flutter_new` (maintained fork of retired ffmpeg-kit; ships Android + iOS binaries).

- **Android**: in `android/app/build.gradle` set `minSdkVersion 24`
- **iOS**: in `ios/Podfile` set `platform :ios, '15.0'`, then `cd ios && pod install`

## Run

```
flutter run
```

## Architecture

```
timing table (fatiha_data.dart)
      │ drives BOTH
      ├──> live preview (AnimatedSwitcher on audio position)
      └──> export (FFmpeg overlay enable=between(t,start,end))

AyahOverlay widget
      │ rendered ONCE, used TWICE
      ├──> on screen (preview)
      └──> rasterized to transparent PNG (burned into mp4)
```

Preview and export can't disagree: same data, same widget.

## The home-screen widget

A verse from the Quran on the home screen, turning at midnight and at
noon, over a photograph from the scene library. Native on both platforms
(`android/.../VerseWidget.kt`, `ios/AyahWidget/`) and self-contained:
each side carries its own copy of the ninety-verse rotation and does
the same date arithmetic as `lib/data/quran_verses.dart`, so it keeps
turning without the app being opened and never needs an App Group or a
background task. A tap opens the app on that verse's reel
(`ayahreel://verse/2/152`, see `lib/data/home_widget_service.dart`).

The list is edited in one place, `tool/quran_verses.json`, and fetched
and copied by `tool/quran_verses.py` (`fetch`, then `gen`); the
backgrounds by `tool/widget_backgrounds.sh`. `test/quran_verses_sync_test.dart`
fails the build if a copy drifts. Being native, any change to the
widget needs a store release — Shorebird cannot patch it.

## Beyond one reel

- **Verse of the day** (`lib/data/daily_verses.dart`, `widgets/day_verse_card.dart`):
  the home screen carries one short verse a day from a curated list of 37,
  chosen by day of the year; on Friday it becomes the Jumu'ah card with the
  verse of Salawat (33:56). Tap → voice → verses (already selected) → scenery.
- **Series** (`lib/data/series_planner.dart`, `series_library.dart`,
  `screens/series_*.dart`): a whole surah over N days, M reels a day. The
  split is a dynamic programme over the surah's own passage boundaries
  (`ruku_index.dart`, 558 rukus from the quran.com API), scored on evenness,
  a cliff-free length curve, and a penalty for cutting mid-passage. Each reel
  is made through the normal wizard; the export ticks its day on the streak.
  Days also light on a long press.
- **Scenes matched to the verses** (`lib/data/scene_matcher.dart`): the
  scenery screen can read the selection and pick one scenery per verse from
  what the verse names — sea, night, mountains, garden, path, sacred — via an
  Arabic light stemmer over the Uthmani text (dagger alif expanded, the
  article's shadda read). Deterministic; never the same scene twice; already
  downloaded scenes win ties.
- **Edit again** (`lib/data/reel_recipe.dart`, `screens/reopen_reel.dart`):
  every export stores its recipe — voice, verses, scenes, frame, styling,
  trim — so a saved reel reopens in the preview with everything as it was.
- **The mark on a reel** stands at the foot of the frame — 360px above
  the bottom edge in full frame, above the band the feeds draw their
  caption and account name over, and detached from the verse, so a
  verse dragged up the frame does not drag the signature into the
  middle of the picture with it. In letterbox it signs the card.
- **The opening frame** wears a different picture every twelve hours,
  drawn from the whole library: every upright still on the nature
  shelves (sky, mountains, desert, water, forest, road, sacred) that the
  catalog measured dark enough at the top for the headline — a couple
  of hundred, walked in one fixed shuffled order so every one comes up
  before any comes round again (`CinematicHero.library`, `pickFor`).
  One not yet on the phone is fetched while a bundled picture stands in
  for it, and the next half-day's is fetched while this one is looked
  at; without a catalog or a connection the two bundled shelves — day
  and night — carry on (`sceneFor`).
- **Word highlight** covers 11 of 37 voices: the nine quran-align folders the
  app plays as-is, plus Husary and Abdul Basit murattal via the release's
  64kbps files, which ffprobe shows are the same recordings (a constant 70ms
  encoder offset). QUL's wider set aligns gapless surah recordings and does
  not transfer to per-ayah audio, so it was not taken.

## Cards

A tab of its own, and the other thing this app makes: a still — a
verse, a hadith or the user's own words, set on a ground and exported
as a picture — and a run of them is a carousel.

```
tab       four ways in: a verse, a hadith, today's verse, a blank card
          and the look and shape a new card starts on, shown as real cards
composer  the card, a rail of seven tools, a filmstrip when there are several
export    PNG per card at 1080 across ──> [Share] / save to gallery
```

The Quran side of the finder is a *reader* rather than a search box,
and that is a correction rather than a shortcut: the Arabic is bundled
whole and the translations are not, so a search box there could only
ever match Arabic — anybody typing "mercy" into it got nothing. It
opens on a surah and lists its verses to read, and the surah is chosen
through the picker the verse step has always used, which searches
names, numbers and references in either script.

Sharing a card goes three ways: the share sheet, the gallery, or
straight into Instagram's story composer — and the story route re-cuts
the card to 9:16 on the way out rather than letting Instagram box a
4:5 picture. Re-cutting costs nothing (every position on a card is a
fraction), and the strip it opens up at the foot is where the mark
climbs to clear the bar Instagram draws along the bottom of a story —
the same floor the reels measured off a posted reel.

A deck ends with one more card in its own paper, frame and type,
saying "made by ___ / with AyahReel". It is on the filmstrip before
anything is exported, a tap on it takes it off, and the maker's name
leads: "made by Yusuf" is what a friend keeps, where "made with
AyahReel" alone is what gets cropped off before a carousel is posted.
Making a card — saved, shared or sent to a story — advances the same
daily streak a reel does, because the lever on a habit is how often
rather than how much; it does not touch the reel badges, which count
reels.

Nothing in the composer is written to disk until the card has actually
been made. The shelf in the Cards tab holds what was saved or shared;
a library that fills itself with half-started drafts is a library
nobody opens twice.

- **Everything is a fraction, never a pixel** (`lib/data/card_style.dart`).
  A card is drawn at ~320pt in the composer and at 1080px in the file, and
  the two have to be the same picture, so every size, position and shadow
  in a card is a fraction of the card's own width. That is also what lets
  one card be re-cut between square, post and story: the vertical
  positions are carried in *width* units, so a composition keeps its
  proportions and only what no longer fits is shrunk
  (`CardCompose.reshape`).
- **One widget, drawn twice** (`lib/widgets/card_canvas.dart`): the
  composer shows it and `lib/render/card_exporter.dart` rasterizes the
  same widget — the same arrangement the reels' verse card has always
  had, so the file cannot drift from what was approved. The grade, the
  vignette and the grain are the reels' own values through
  `ReelFinish`, and the mark is the reels' own mark.
- **The scenery is the reels' library, whole** (`SceneCatalog`): one
  catalog, one set of files, one download cache — a scenery added to
  `catalog.json` appears in both pickers on the same build. A card crops
  rather than letterboxes, so the wide sceneries are usable too, and a
  clip contributes a frame cut out of it with FFmpeg
  (`lib/data/card_images.dart`).
- **Hadith, offline** (`lib/data/hadith_library.dart`,
  `tool/fetch_hadith.py`): about six thousand short hadith from the two
  Sahihs, the four Sunan, the Muwatta and the two classical forties —
  every one of them short enough to put on a card, with the transmission
  chain stripped from the front of the Arabic, and nothing graded weak
  (see the tool for the rule and `tool/verify_hadith.py` for what holds
  it). One gzipped file per language of which a phone reads two, ~1.5 MB
  shipped, read in a background isolate the first time the finder is
  opened.
- **A piece rather than the whole** (`lib/widgets/scripture_finder.dart`):
  almost nothing anybody quotes is the whole of a hadith with its chain,
  so the finder lays the words out one by one — tap the first, tap the
  last, and that is what travels to the card.
- **Made for someone** (`lib/data/dedication.dart`): a reel or a deck
  can be dedicated — a gift for somebody who will see it, or sadaqah
  jariyah on behalf of somebody. The line is drawn above the app's mark
  by the mark's own widget, which is what makes it one implementation
  for both products and one overlay in the filtergraph: the exporter
  places that PNG at `H-h-inset`, so a taller mark grows upward and the
  wordmark does not move. The gap under the verse drops by exactly what
  it grew. Stored as the intention and the name rather than as a
  sentence, so a reel dedicated in English and reopened in Arabic
  prints an Arabic dedication — and it is in the render key only when
  it exists, so no reel made before it was added is re-encoded. Sharing
  a dedicated one sends a message written to the recipient with both
  store links on it, because a gift nobody can answer with one of their
  own is a gift that stops where it lands.
- **The library keeps recipes, not pictures** (`card_library.dart`): a
  deck is a few kilobytes of JSON and one small cover, and it re-renders
  at full size whenever it is opened again. There is no flattening step
  to undo, which is what makes a card editable forever.

## Tanafus

The arena: a quiz on the Quran, made to be played with someone. The
name is 83:26 — *so for this let the competitors compete* — and the
verse stands over the lobby's door. Its mark is a crown of light: the
crown promised to the one who carries the Quran, drawn the way the
arena draws a round, as a constellation — seven stars on a thread of
light, the light going round it and the stars twinkling wherever the
mark is alive (`TanafusMark`; geometry, no asset). Two doors lead to
the arena from the shell: a small roundel at the top corner of every
tab with the crown leaning inside it and a gold dot on its shoulder
until it has been opened once, and the floating button at the foot of
the three tabs that make things (Settings keeps the invitation there).
The Cards tab has a second room for it, beside the cards, whose door
(`ArenaPortal`) opens the same lobby the roundel does — a pane of the
arena's own colour and weather, the most alive thing on the tab.

```
lobby     play now, or beat a code; the whole Quran, a juz or a surah;
          which of six games; no clock (since 2026-10-24)
round     ten questions, each waiting for its answer, its number in a
          ring; a right answer throws gold, a wrong one lights the
          right answer
result    the round drawn as a constellation, the score in one small
          line under it, the code with its three steps, the story,
          the share sheet, the review behind a gold button
shelf     every round kept whole, as its own small constellation —
          reopened and shared again from there, or taken off
```

- **Six games, all from the bundled text** (`lib/data/arena_engine.dart`):
  complete the verse, the missing word, which surah, what comes next,
  order the words, and the surah's own facts (length, number, place of
  revelation, what follows, what the name means, which juz it opens
  in). The Arabic is the search index the app already ships, the juz
  boundaries and the surah facts are generated tables
  (`tool/surah_facts.py` → `juz_index.dart`, `surah_facts.dart`), so a
  phone with no connection plays the whole thing. Every question is
  guarded against having two right answers: a stem is lengthened until
  no other verse shares it, a verse to name has to be unique in the
  Quran, a verse to follow unique in its surah, and the refrains never
  come up. Wrong answers sit close to the right one — the same surah's
  endings, a word that rhymes, the neighbouring surahs — so the ear
  cannot answer alone. `test/arena_engine_test.dart` checks every kind
  of question against the corpus across every kind of scope.
- **A round is a pure function of a seed.** The same seed, scope, games
  and clock make the same ten questions on any phone, which is what
  lets a score travel as twelve letters (`arena_challenge.dart`):
  Crockford base32 with a checksum, forgiving of a lowercase or a
  mistaken O, findable inside a pasted message. Whoever plays the code
  gets the sender's exact ten and the sender's score to beat, and the
  result says how the two stand — *you beat Amina*, *level with Amina*,
  *Amina still leads* — without a verdict on the one who stands lower.
  A pinned round in the engine test fails the build if the generator
  drifts, because every code in the wild depends on it.
- **The constellation** (`lib/widgets/arena_constellation.dart`). A
  round is drawn, not summarised: every question a star, gold when it
  was answered and a hollow ring when it was not. The stars are
  scattered over the disc the way a sky is — each placed at the best
  of two dozen seeded tries, the one farthest from every star already
  standing — and the thread of play order walks from the topmost star
  to its nearest unvisited neighbour and on, so the round reads as a
  figure and not a tangle; a fainter net joins every star to its two
  nearest, and far faint stars stand behind. The first words of each
  verse sit beside its star in the mushaf's own face, on whichever of
  eight sides has room: away from other stars, away from labels
  already set, inside the frame. The score is not in the picture; it
  is a small line under it. One painter draws the story, the result
  page (where it draws itself in, star by star) and the thumbnail a
  round keeps on the shelf, where nothing is ever thinner than a hair.
- **Two doors out of a result.** An Instagram story
  (`lib/render/arena_story.dart`, 1080×1920: the crown, the
  constellation, the score in one small line, against a code the two
  scores either side of a hairline, *beat my score*, the app's icon and
  name at the foot and nothing else — no code, since nobody can copy
  one off a picture) straight into the story composer through the same
  hand-off the cards use, with the code put on the clipboard first so
  it can be pasted on as a sticker; and the share sheet with the same
  picture and a message that says *copy this code*, names the road to
  paste it, and carries both store links. Under the code on the page,
  the three steps — copy it, share it, see who beats it. Every round
  makes a code, so every round can be sent.
- **The review waits folded** behind a gold button, so the top of the
  page is the whole of what a glance takes in. Open, a wrong answer shows what
  was tapped, struck through, over the right one, and a tap opens the
  question exactly as it was answered — the same card, the same
  options, nothing to change.
- **`ayahreel://arena/<code>`** opens the lobby on the challenge, with
  the sender's name when the link says (`?by=`). The Android manifest
  lists the `arena` host beside `verse`; that is a store build, not a
  patch. iOS registers the scheme alone and needs nothing.
- **The light** (`lib/widgets/arena_fx.dart`): an aurora of five
  drifting blobs behind every arena screen, a glint that runs across a
  button when it is pressed and now and then unasked, light that
  follows the finger over a card, a ring the clock burns down with a
  head that turns to rose in the last quarter, a burst of gold seals
  for a right answer, the crown of light, and a bloom the arena rises
  out of. All paint, no assets, and all of it stops under reduced
  motion.
- **Looking at it without a phone:**
  `ARENA_PREVIEW_OUT=/tmp/arena flutter test test/tools/arena_preview_test.dart`
  draws the shell with its doors, the Cards tab's two rooms, the lobby
  with and without its first-time note and with a code, every kind of
  question before and after it is answered, the result with its review
  open and a question looked at again, a result against a code, the
  shelf, and the story in both scripts; `test/tools/mark_preview_test.dart`
  draws the crown at every size it is worn at, and the two doors.

## Deliberate limits

- 109 reciters (3 offline + 106 streamed, incl. 6 Mujawwad sets) and another recording of one of
  them (Alafasy's Taraweeh of 1430), 5 bundled backgrounds + your own photo/video, 1 translation
- No signup, no settings, no watermark
- Next: more translations, transliteration, more word-aligned voices as
  releases against EveryAyah audio appear
