# Verifying ayah timings (do this once per reciter, before release)

The timing tables in `lib/data/fatiha_data.dart` are placeholders. One wrong number = out-of-sync text = lost trust. Verify each against the exact bundled mp3.

## Easiest method (exact by construction)

Build each full-surah mp3 by concatenating EveryAyah's per-ayah files, and record each file's duration while doing it:

```
ffprobe -v error -show_entries format=duration -of csv=p=0 001001.mp3
```

Then ayah N's window = cumulative sum of durations:

```
ayah 1: 0 ..... d1
ayah 2: d1 .... d1+d2
ayah 3: d1+d2 . d1+d2+d3   (and so on)
```

Because the bundled mp3 is literally those files joined, the timings are exact, not estimated.

## Update

Convert to milliseconds, write into the `timings:` list for that reciter. Re-run the app, play preview, confirm each verse flips exactly on the reciter's breath.
