#!/usr/bin/env bash
# The home-screen widget's backgrounds: photographs from the scene
# library, each cut to a frame the widget can use and copied into the
# native resources on both platforms.
#
#     bash tool/widget_backgrounds.sh
#
# Needs ffmpeg, and the network the first time: a source that is not
# one of the bundled sceneries in assets/backgrounds/ is fetched from
# the published library (the baseUrl in assets/catalog.json — the same
# release the app streams scenes from) into videos/_widget_src/, which
# is not tracked. The frame count is written into VerseWidget.kt and
# AyahWidget.swift, and test/widget_backgrounds_sync_test.dart refuses
# a build where the files and the constants disagree.
#
# Why a separate copy. The widget is drawn by the launcher (Android) or
# by WidgetKit (iOS), never by Flutter, and neither process can see
# assets/backgrounds/ or the scenes the app has fetched. Android reads
# res/drawable, iOS reads the extension's own bundle.
#
# Why these and not the bundled sceneries. The first cut took the 23
# sceneries the app bundles and cut each from the middle. Portrait
# sceneries are chosen for a reel, where the verse sits on the middle
# of the picture, so that band is deliberately the quietest part of
# them — sky, haze, sand — and four of the 23 were abstracts to begin
# with. On the home screen that read as a widget that only ever shows
# abstract backgrounds. So: hand-picked from the whole library,
# photographs with a subject in them, no abstracts, no people, and each
# one cut at the band where its subject is.
#
# The shape. The sources are 1080x1920 portrait or 1920x1080 wide; the
# widget is a 2:1-ish rectangle on Android (4x2 cells) and a small
# square, a medium 2:1 or a large near-square on iOS. Every one is cut
# to 960x640 (3:2), and each platform then centre-crops that to
# whatever the widget actually is. 3:2 loses the least to either a
# square or a 2:1 crop, and 960 wide is a hair over a 4x2 widget on an
# xxhdpi phone (~840px), so nothing is upscaled more than a fraction.
# A full frame would be seven times the pixels — RemoteViews turns away
# bitmaps past a few MB, and a WidgetKit process is capped near 30 MB —
# for no gain in a picture behind text.
#
# The second column is where the subject is: the point of the source,
# as a fraction of its height from the top, that lands in the middle
# of the frame. A wide source keeps 75% of its width whichever way, so
# 0.5 is the whole answer there; a portrait one keeps 37% of its
# height, so it matters. Clamped, so 0 and 1 mean the very top and the
# very bottom.
#
# Order matters: the widget turns one picture over every half-day, in
# this order, so each tab's pictures are spread an equal distance apart
# through the list and neighbours are always different in kind. A
# verse's own turn is a separate count (see VerseSchedule), so the
# pairing of verse and picture drifts over months rather than
# repeating.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLED=assets/backgrounds
CACHE=videos/_widget_src
ANDROID=android/app/src/main/res/drawable-nodpi
IOS=ios/AyahWidget/Backgrounds
KT=android/app/src/main/kotlin/com/ayahreel/app/VerseWidget.kt
SWIFT=ios/AyahWidget/AyahWidget.swift
W=960; H=640
BASE_URL=$(sed -n 's/.*"baseUrl":"\([^"]*\)".*/\1/p' assets/catalog.json)

# 100 photographs, in rotation order: "<scene file>  <subject>".
ORDER=(
  'cinematic_pixabay_12.jpg         0.5  '  # cinematic (wide)
  'sacred_pexels_03.jpg             0.45 '  # sacred
  'aurora_pexels_09.jpg             0.5  '  # sky
  'desert_pexels_15.jpg             0.45 '  # desert
  'field_pixabay_05.jpg             0.4  '  # forest
  'mountains_pexels_01.jpg          0.45 '  # mountains
  'road_pexels_01.jpg               0.55 '  # road
  'aerial_coast_pexels_04.jpg       0.5  '  # aerial (wide)
  'ocean_pexels_01.jpg              0.5  '  # water
  'cinematic_commons_02.jpg         0.5  '  # cinematic (wide)
  'sacred_pexels_04.jpg             0.45 '  # sacred
  'aurora_pexels_02.jpg             0.6  '  # sky
  'desert_pexels_08.jpg             0.68 '  # desert
  'forest_pexels_10.jpg             0.5  '  # forest
  'mountains_openverse_01.jpg       0.55 '  # mountains
  'road_pexels_03.jpg               0.55 '  # road
  'cinematic_commons_03.jpg         0.5  '  # cinematic (wide)
  'aerial_coast_openverse_01.jpg    0.5  '  # aerial (wide)
  'sacred_pexels_07.jpg             0.45 '  # sacred
  'aurora_pexels_10.jpg             0.6  '  # sky
  'cinematic_pixabay_14.jpg         0.5  '  # cinematic (wide)
  'desert_pixabay_05.jpg            0.5  '  # desert
  'forest_pexels_06.jpg             0.55 '  # forest
  'mountains_pexels_07.jpg          0.5  '  # mountains
  'sacred_pexels_08.jpg             0.38 '  # sacred
  'road_pexels_12.jpg               0.55 '  # road
  'water_pixabay_03.jpg             0.55 '  # water
  'aerial_water_pixabay_04.jpg      0.5  '  # aerial (wide)
  'cinematic_commons_06.jpg         0.5  '  # cinematic (wide)
  'aurora_commons_01.jpg            0.6  '  # sky
  'desert_pixabay_03.jpg            0.72 '  # desert
  'forest_pixabay_06.jpg            0.65 '  # forest
  'snow_pixabay_01.jpg              0.55 '  # mountains
  'sacred_pexels_10.jpg             0.5  '  # sacred
  'cinematic_pixabay_19.jpg         0.5  '  # cinematic (wide)
  'road_pexels_26.jpg               0.5  '  # road
  'aurora_pexels_12.jpg             0.62 '  # sky
  'aerial_water_openverse_01.jpg    0.5  '  # aerial (wide)
  'sacred_pexels_16.jpg             0.45 '  # sacred
  'cinematic_pexels_05.jpg          0.5  '  # cinematic (wide)
  'desert_pexels_24.jpg             0.7  '  # desert
  'field_pixabay_04.jpg             0.5  '  # forest
  'mountains_pexels_09.jpg          0.3  '  # mountains
  'ocean_pexels_03.jpg              0.42 '  # water
  'road_pexels_02.jpg               0.55 '  # road
  'clouds_pixabay_04.jpg            0.4  '  # sky
  'sacred_openverse_06.jpg          0.55 '  # sacred
  'cinematic_pexels_06.jpg          0.5  '  # cinematic (wide)
  'aerial_coast_pexels_05.jpg       0.5  '  # aerial (wide)
  'desert_pexels_16.jpg             0.5  '  # desert
  'forest_pexels_03.jpg             0.5  '  # forest
  'mountains_pexels_04.jpg          0.42 '  # mountains
  'cinematic_commons_01.jpg         0.5  '  # cinematic (wide)
  'sacred_pexels_06.jpg             0.55 '  # sacred
  'clouds_pixabay_02.jpg            0.5  '  # sky
  'road_pexels_04.jpg               0.6  '  # road
  'clouds_pexels_04.jpg             0.5  '  # sky
  'desert_pexels_25.jpg             0.55 '  # desert
  'forest_pexels_04.jpg             0.5  '  # forest
  'mountains_pexels_05.jpg          0.5  '  # mountains
  'cinematic_commons_04.jpg         0.5  '  # cinematic (wide)
  'sacred_pexels_09.jpg             0.62 '  # sacred
  'aerial_forest_pexels_02.jpg      0.5  '  # aerial (wide)
  'clouds_commons_01.jpg            0.5  '  # sky
  'road_openverse_03.jpg            0.5  '  # road
  'cinematic_commons_05.jpg         0.5  '  # cinematic (wide)
  'sacred_pixabay_11.jpg            0.48 '  # sacred
  'desert_pexels_19.jpg             0.78 '  # desert
  'forest_pixabay_05.jpg            0.4  '  # forest
  'mountains_commons_01.jpg         0.3  '  # mountains
  'aurora_pexels_08.jpg             0.7  '  # sky
  'cinematic_pixabay_15.jpg         0.5  '  # cinematic (wide)
  'aerial_mountain_pixabay_03.jpg   0.5  '  # aerial (wide)
  'sacred_pexels_12.jpg             0.7  '  # sacred
  'road_pexels_22.jpg               0.55 '  # road
  'water_pexels_01.jpg              0.7  '  # water
  'desert_openverse_05.jpg          0.65 '  # desert
  'forest_pexels_07.jpg             0.5  '  # forest
  'rock_pexels_01.jpg               0.65 '  # mountains
  'cinematic_openverse_02.jpg       0.5  '  # cinematic (wide)
  'sky_pixabay_03.jpg               0.4  '  # sky
  'sacred_pexels_14.jpg             0.6  '  # sacred
  'aerial_water_pixabay_05.jpg      0.5  '  # aerial (wide)
  'cinematic_pexels_04.jpg          0.5  '  # cinematic (wide)
  'road_openverse_04.jpg            0.55 '  # road
  'desert_pexels_27.jpg             0.35 '  # desert
  'forest_pexels_08.jpg             0.5  '  # forest
  'mountains_pexels_11.jpg          0.45 '  # mountains
  'clouds_pixabay_03.jpg            0.55 '  # sky
  'sacred_pixabay_13.jpg            0.5  '  # sacred
  'cinematic_pixabay_22.jpg         0.5  '  # cinematic (wide)
  'water_pexels_05.jpg              0.42 '  # water
  'aerial_mountain_pexels_04.jpg    0.5  '  # aerial (wide)
  'road_pexels_29.jpg               0.55 '  # road
  'desert_pexels_30.jpg             0.6  '  # desert
  'field_pexels_11.jpg              0.5  '  # forest
  'rock_pexels_05.jpg               0.55 '  # mountains
  'clouds_pixabay_06.jpg            0.6  '  # sky
  'sacred_pexels_18.jpg             0.6  '  # sacred
  'cinematic_commons_08.jpg         0.5  '  # cinematic (wide)
)

# The source for scene file $1, fetching it into the cache if it is
# neither bundled nor already there. Prints the path.
source_of() {
  local f=$1
  if [ -f "$BUNDLED/$f" ]; then echo "$BUNDLED/$f"; return; fi
  mkdir -p "$CACHE"
  if [ ! -s "$CACHE/$f" ]; then
    echo "fetching $f" >&2
    curl -fsSL --retry 3 -o "$CACHE/$f.part" "$BASE_URL/$f"
    mv "$CACHE/$f.part" "$CACHE/$f"
  fi
  echo "$CACHE/$f"
}

mkdir -p "$ANDROID" "$IOS"
rm -f "$ANDROID"/wbg_*.jpg "$IOS"/wbg_*.jpg

i=0
for entry in "${ORDER[@]}"; do
  read -r f subject <<<"$entry"
  src=$(source_of "$f")
  name=$(printf 'wbg_%02d.jpg' "$i")
  case "$f" in
    *.mp4) input=(-ss 1 -i "$src" -frames:v 1) ;;
    *)     input=(-i "$src") ;;
  esac
  # Scale so the shorter dimension fills, then cut a 3:2 frame with
  # the subject in the middle of it, kept inside the picture. -q:v 5
  # is roughly JPEG quality 80, ~100 KB a frame.
  ffmpeg -v error -y "${input[@]}" \
    -vf "scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H}:(iw-${W})/2:clip(${subject}*ih-${H}/2\,0\,ih-${H})" \
    -q:v 5 -pix_fmt yuvj420p "$ANDROID/$name"
  cp "$ANDROID/$name" "$IOS/$name"
  echo "$name  <-  $f  @ $subject"
  i=$((i + 1))
done

# The count the two widgets rotate through. Written through a temp
# file rather than sed -i, which is spelled differently on macOS.
sed -E "s/(private const val BACKGROUNDS = )[0-9]+/\1$i/" "$KT" > "$KT.tmp" && mv "$KT.tmp" "$KT"
sed -E "s/(private let backgroundCount = )[0-9]+/\1$i/" "$SWIFT" > "$SWIFT.tmp" && mv "$SWIFT.tmp" "$SWIFT"
grep -q "BACKGROUNDS = $i$" "$KT" || { echo "could not set BACKGROUNDS in $KT" >&2; exit 1; }
grep -q "backgroundCount = $i$" "$SWIFT" || { echo "could not set backgroundCount in $SWIFT" >&2; exit 1; }

echo "$i backgrounds -> $ANDROID and $IOS"
du -sh "$ANDROID" "$IOS"
