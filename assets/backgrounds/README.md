# Bundled sceneries

The 23 sceneries that ship inside the app. They are the ones that work
before the device has ever seen a network, so every picker tab has
something in it on a cold install.

**The full library is 376 scenes and does not live here.** It is built
by `tool/harvest_scenes.py` + `tool/curate_scenes.py`, published with
`tool/publish_scenes.py`, and served from

    https://github.com/Mulhimfy/ayah-reels-scenes/releases/download/v1/<id>.<ext>

The app fetches a scene the first time it is chosen and keeps it in
`<app support>/scenes/` forever after. See `lib/data/scene_catalog.dart`.

## Why every scene's poster is bundled but only 23 files are

`assets/scene_thumbs/` holds a 216x384 poster for all 376 scenes —
about 4 MB for the lot. That is what lets the picker draw the entire
library instantly, offline, on a fresh install: the grid is always
complete, and only the full-size file behind a *chosen* scene ever has
to travel. Without it a streamed library shows empty squares.

## The two shapes

| bucket | size | how the reel uses it |
|---|---|---|
| portrait | 1080x1920 | fills the frame, verse drawn **on** it |
| wide | 1920x1080 | letterboxed, verse **below** it |

Portrait scenes are scored hard on readability, because the verse sits
on top: brightness through the middle band, hot spots, and fine detail
all count against them. Wide scenes carry nothing over the picture, so
they are judged on detail and tonal range instead and are free to be
bright.

## Changing the bundled set

Do not hand-edit the list in `lib/data/fatiha_data.dart`. Adjust
`BUNDLE_STILLS_PER_TAB` / `BUNDLE_CLIPS` in `tool/publish_scenes.py`,
re-run `stage`, and regenerate the list — the ids, poster gradients and
`knownAspect` all have to agree with the catalog or the picker and the
exporter will disagree about what a scene is.

## Rules every scene has to satisfy

Enforced by the curation pass, not by eye:

- No people. Any detectable face is rejected outright.
- Dark and quiet if portrait — white and gold verse text goes on top.
- Already framed: filled and centre-cropped to the exact export size,
  EXIF orientation baked in, metadata stripped. Flutter honours EXIF
  orientation and FFmpeg's image demuxer does not, so an un-normalized
  photo previews upright and **exports sideways**.
- Clips carry one video stream and nothing else. Stock footage often
  ships a `tmcd` timecode track; ffmpeg copies it by default, and the
  resulting two-stream mp4 stalls Chrome and mobile players forever
  with no error. `-map 0:v:0 -write_tmcd 0` is not optional.
- `gradientArgb` is the scene's own measured top/bottom average. It is
  the picker poster, the pre-load frame, the My Reels thumbnail, and
  the fallback the exporter renders if an asset ever goes missing.

Full-range note, already handled: JPEG is full-range and would export
with lifted blacks against the limited-range clips, but the render
chain's `scale=...:out_range=tv` converts it. Don't drop that filter.

After changing any bundled asset's look, bump the render-cache version
salt in `lib/render/video_renderer.dart` so previously exported reels
aren't served from cache.

## The home-screen widget's copies

The widget is drawn by the launcher (Android) or WidgetKit (iOS), never
by Flutter, so it cannot see this folder. `tool/widget_backgrounds.sh`
cuts every scenery here — a still frame for each clip — to a 960x640
frame and copies it into `android/app/src/main/res/drawable-nodpi/` and
`ios/AyahWidget/Backgrounds/` as `wbg_00.jpg` … `wbg_23.jpg`. Re-run it
after changing the bundled set, and keep `BACKGROUNDS`/`backgroundCount`
in `VerseWidget.kt` and `AyahWidget.swift` equal to the number of frames.
