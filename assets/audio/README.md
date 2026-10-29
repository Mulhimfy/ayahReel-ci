# Audio assets (required before first run)

Download each reciter's full Surah Al-Fatiha mp3 and save with these exact names:

| file | source (free distribution) |
|---|---|
| `alafasy_001.mp3` | everyayah.com — Alafasy_128kbps, Surah 001 |
| `husary_001.mp3` | everyayah.com — Husary_128kbps, Surah 001 |
| `abdulbasit_001.mp3` | everyayah.com — Abdul_Basit_Murattal_192kbps, Surah 001 |

EveryAyah serves per-ayah files (001001.mp3 ... 001007.mp3). Concatenate them into one file per reciter, e.g.:

```
ffmpeg -i "concat:001001.mp3|001002.mp3|001003.mp3|001004.mp3|001005.mp3|001006.mp3|001007.mp3" -acodec copy alafasy_001.mp3
```

IMPORTANT: after building each file, verify/update the timings in `lib/data/fatiha_data.dart` against it (see `tool/verify_timings.md`). The timing table must match this exact audio.
