# Saves that die on small phones — what we know, what to do next

Read this before touching the export (`lib/render/video_renderer.dart`,
`lib/data/export_budget.dart`) for a "can't save" or "the app closed"
report.

## The symptom

Feedback with `source: exportTrouble` and an `export` field like

    tightest, 2772 MB, 32-bit, 2 lost · lost: the app closed while a reel was saving

The app died during a save, and the next launch noticed it. Android's
low-memory killer leaves no error behind, so until 2026-10-08 a note
couldn't say where the save died or how big the app had grown. Almost
every such phone has 2–3 GB of memory, and many run the app as 32-bit
code, which gives the whole process about 3 GB of address space.

## How a save spends memory

A save is FFmpeg running inside the app's own process. One `-i` input
and one overlay per verse card; word highlighting makes a card per word.
Measured with desktop FFmpeg 8.0.1 and the app's own graph (2026-10-04):

| Part | Memory |
|---|---|
| The graph before any verse | about 350 MB |
| … of which libx264 at 1080x1920, veryfast | about 200 MB |
| Each verse card in a pass | 12–17 MB (about 8 MB of it per-input overhead) |

`PhoneBudget` (`export_budget.dart`) sizes each save to the phone:

| Budget | Who | Cards per pass | Encoder threads | Since |
|---|---|---|---|---|
| roomy | everyone else | the plan's own | up to 16 | — |
| tight | under 4.6 GB, or 32-bit, or 1 loss | 16 | 4 | `4a2bba3` |
| tightest | under 3.2 GB, or 2 losses | 8 | 2 | `4a2bba3` |
| tightest + lean x264 | same phones | 8 | 2, no lookahead or B-frames | 2026-10-08 |

The lean x264 settings (`VideoRenderer.leanX264`:
`rc-lookahead=0:bframes=0:mbtree=0:sync-lookahead=0`) took a 4-second
1080x1920 encode at 2 threads from 339 MB to 199 MB peak, and from
13.6 s to 7.5 s. The cost is a bigger file: 1.6x on FFmpeg's busy
`testsrc2` pattern, less on a verse over scenery. Phones whose hardware
encoder works (`h264_mediacodec`) don't run x264 at all, so this doesn't
help them.

Earlier fixes, all in the 2026-10-07 code: the budget and losses
(`4a2bba3`), the image cache's memory handed to the encode (`3927308`),
renders kept out of the cache folder (`cccba8f`, `b96ee14`), and
background deaths not counted as losses (`e17c800`).

## What a note says since 2026-10-08

While a foreground save runs, `PhoneBudget` writes its stage and the
app's memory into `export_budget.json` every 3 seconds and at each
stage. If the app dies, the next launch's note reads, for example:

    lost: the app closed while a reel was saving (pass 3/7, 8 cards; app 640 MB, 690 MB at most; phone 180 MB free)

- **stage**: `starting`, `cards` (drawing the verse PNGs in Flutter),
  `N cards in one pass`, `pass i/n, N cards`, `join`. `, hardware` means
  the MediaCodec encoder was running.
- **app … MB**: the process's resident memory (`VmRSS`) at the last
  reading, and its peak (`VmHWM`).
- **phone … MB free**: `MemAvailable` at that moment.

Only notes with `code: 2026-10-08` or later carry this, and the stage
only says where the save was within about 3 seconds.

## What to do with the next reports

1. **Stage `cards`.** The save died while Flutter drew the verse cards,
   before FFmpeg started. Look at `AyahRasterizer` (PNG encoding on the
   UI isolate, the image cache), not at the encoder.
2. **A pass with `, hardware`.** MediaCodec was encoding, and lean x264
   didn't apply. Try software x264 lean on the tightest budget, or a
   lower hardware bitrate there.
3. **A pass, software, with a high peak** (past about 600 MB on a
   2–3 GB phone). The per-card inputs are the cost. Next lever: the
   constant-memory renderer below.
4. **A modest peak (under about 450 MB) but little free memory** (under
   about 150 MB). The phone itself is full, and the system kills the
   foreground app anyway. Only a smaller save (720p on the tightest
   budget) or FFmpeg out of the app's process can help.
5. **`join`.** The join re-encodes only when the passes can't be stream
   copied (`copyVideo`). Find out why.
6. **No more such notes from `2026-10-08` code.** Stop here.

## The bigger levers, in order of cost

- **720p on the tightest budget.** Add `scale=720:1280` before the
  encoder only. x264's frames shrink 2.25x. Dart only, so an OTA can
  carry it, but every reel those phones make looks softer.
- **Constant-memory renderer.** Collapse the per-card PNG inputs into
  one stream: every card padded to a full 1080x1920 transparent PNG,
  fed through the concat demuxer with durations, and one overlay at
  0,0. Memory stops growing with the card count. Fades between cards
  and the letterbox layout need rework. A big renderer change; test it
  on a real 3 GB phone before any OTA.
- **FFmpeg in its own process.** An Android service with
  `android:process=":render"` running the encode. A kill takes down
  the save, not the app, and on 32-bit gives FFmpeg its own address
  space. Kotlin, so it needs a store build. This is the only fix that
  makes "the app closed" impossible.
