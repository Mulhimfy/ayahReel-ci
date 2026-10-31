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
| tightest + lean, superfast | same phones | 8 | 2, x264 `superfast` | 2026-10-11 |
| tightest + lean with mbtree | same phones | 8 | 2, `superfast`, 5-frame lookahead, mbtree on | 2026-10-13 |
| smallest | a save lost in an x264 encode on tightest | 4 | 2, lean, the encoder handed 720x1280 | 2026-10-17 |

And separately from the budget, since 2026-10-11 (`PhoneBudget.hardwareTrusted`):
a phone where a save died inside a hardware encode (`, hardware` in the
stage), or that has lost two saves anywhere, never uses MediaCodec
again. It runs x264, slower but finished.

The first lean x264 settings (`rc-lookahead=0:bframes=0:mbtree=0:sync-lookahead=0`)
took a 4-second 1080x1920 encode at 2 threads from 339 MB to 199 MB
peak, and from 13.6 s to 7.5 s, with a 1.6x bigger file. That was
measured on FFmpeg's `testsrc2`, which has no grain, and it was wrong
for real reels; see 2026-10-13 below. Since then lean is
`rc-lookahead=5:mbtree=1:bframes=0:sync-lookahead=0`. Phones whose
hardware encoder works (`h264_mediacodec`) don't run x264 at all, so
this doesn't help them.

Earlier fixes, all in the 2026-10-07 code: the budget and losses
(`4a2bba3`), the image cache's memory handed to the encode (`3927308`),
renders kept out of the cache folder (`cccba8f`, `b96ee14`), and
background deaths not counted as losses (`e17c800`).

## 2026-10-11: two reports, and FFmpeg moved out of the app

Two notes from `code: 2026-10-08`:

    tightest, 3647 MB, 2 lost · lost: … (4 cards in one pass, hardware; app 305 MB, 1079 MB at most; phone 443 MB free)
    tightest, 3761 MB, 1 lost      ("the saving is slow and the app sometimes stops", Realme RMX3830)

The first died in a hardware pass with the app at 305 MB and 443 MB of
the phone still free: not a phone out of memory. The likeliest cause is
the device encoder's path crashing the process (FFmpeg's MediaCodec
wrapper or the vendor code under it). Its 1079 MB peak was the whole
run's, so it may well predate the save. Done, all in one store build
(the render process needs native code):

- **The render process** (`android/…/RenderService.kt`,
  `lib/render/render_process.dart`). Every encode the renderer runs
  (`_encodeOnce`: passes, single encodes, the join) goes to a service in
  `android:process=":render"`. A crash or a low-memory kill there ends
  that process and not the app. Bound without `BIND_IMPORTANT`, it
  ranks below the app, so the system kills it first. The app sees
  `died`, records it (`PhoneBudget.renderDied`: a loss, `hwLost` if it
  was hardware, `survived` in the note), and the renderer's existing
  retries take over: hardware is redone on x264, and an x264 death is
  read as out of memory and redone a budget smaller. A hardware encode
  wedged past its cancel is ended by killing the process, which frees
  what it held; in the app it was "left behind". The probes, ffprobe
  and the small FFmpeg jobs elsewhere still run in the app.
  Fallbacks: if no binding comes within 4 s, FFmpeg fails to start there
  (`unavailable`), or three encodes die there in one run, the app
  encodes in-process as before for the rest of the run.
- **Hardware retired** after a death in it, or after two losses
  (above). This one is Dart only, so an OTA can carry it.
- **`superfast`** for lean x264, which is now also the x264 the retired
  phones run. Speed for the slowest phones, at a larger file.
- **The peak is the save's own.** `exportStarted` writes 5 to
  `/proc/self/clear_refs`. Where Android allows it, the note says
  `… MB at most in the save`. The render process's memory goes in the
  note as `render … MB` when the save ran there.
- `FeedbackService.codeDate` is now `2026-10-11`.

**Not device-tested.** No phone or emulator was available. Before a
release, save on a real phone and check that the reel saves, that
`render-process encode` shows in the debug log, and that cancel works
mid-save.

Later the same day, a third `code: 2026-10-08` note ("the clip wasn't
saved"):

    tightest, 1897 MB, 32-bit, 1 lost · lost: … (cards; app 131 MB, 167 MB at most; phone 444 MB free)

It died while Flutter drew the verse cards, before any FFmpeg, with the
app small and the phone not full: a crash, not memory. It matches Play's
largest 1.0.8 crash (16 users, Honor/realme/Infinix): Impeller's OpenGL
path segfaulting in `toImage` with the app out of sight. Fixed on this
branch by `OnScreen.settle` (`f6267a1`, `lib/render/on_screen.dart`): a
save left in the background waits there and goes on when the app is
back. Dart only, so a 1.0.8 patch could carry it — and did: the same
evening the save fixes went out to 1.0.8+19..+22 as Patches 8, 7, 4 and
3 (`OnScreen.settle`, hardware retirement, `superfast`, the save's own
peak; RELEASES.md). Their notes say `code: 2026-10-11` with `version:
1.0.8`; the render process came with the store build, Android `1.0.9+23`
(2026-10-12; RELEASES.md).

## 2026-10-13: saved reels that wouldn't play

One note from `version: 1.0.9`, `code: 2026-10-11`, Realme RMX3830
(Android 15), source `settings`:

    tightest, 3761 MB, 4 lost, x264 only
    "every time I save a reel and then play it, it says playback error"

The save finished, and the file wouldn't play. FFmpeg's own picture
check (`_decodesToPicture`) passed, because FFmpeg decodes anything.
The cause was the lean x264 above. `superfast` and lean's
`rc-lookahead=0`/`mbtree=0` turn off x264's macroblock tree. That is
what lets x264 skip the grain the graph adds to every frame
(`noise=c0s=2:c0f=t+u`, more with the Grain slider), so without it
every frame coded the grain in full. Desktop FFmpeg 8.0.1, the app's
graph, 1080x1920, 2 threads, 8 cards, 150 frames:

| x264 | still sky | moving scenery | peak memory (sky) | time (sky) |
|---|---|---|---|---|
| roomy (`veryfast`) | 0.05 Mbps | 1.3 Mbps | 428 MB | 19.3 s |
| lean until 2026-10-13 | **26.4 Mbps** | **12 Mbps** | 314 MB | 25.4 s |
| lean since 2026-10-13 (mbtree, lookahead 5) | 0.05 Mbps | 1.3 Mbps | 344 MB | 16.4 s |

The stream says High@4.0, and Level 4.0 allows 25 Mbps, which is
about what a budget phone's decoder is built to. The old lean was
past that, 200 times the size, and slower than `veryfast` too. The
Grain slider at its top took even roomy x264 to 58 Mbps.

Fixed, all in Dart:

- **Lean keeps the macroblock tree** on a 5-frame lookahead
  (`VideoRenderer.leanX264`). That costs 30 MB more than the old lean
  for the bare encode (220 MB against 189; `veryfast` is 325).
- **Every x264 encode has a ceiling** (`_x264CeilingFor`): twice the
  hardware rate at the same length (12M, 8M, 6M, 4M), with a buffer
  of one second, for both quality settings. A reel under it is
  unchanged. With the grain at its top and three-second passes joined
  by stream copy, the joined file peaks at 17.5 Mbps over any second,
  and it still says Level 4.0. The join's re-encode uses the same
  settings now (`videoCodec`).
- **The render key** carries `_lx` on a phone planned `tightest`, so
  a Save of a reel made with the old lean renders it again. Without
  this, My Reels (one entry per key) and the "already in gallery"
  check hand back the old file. Reels already saved stay as they
  were. The user has to delete them and save again.
- `FeedbackService.codeDate` is now `2026-10-13`.

Affected: phones on the tightest budget running x264, which are every
phone with two lost saves (`x264 only`) and any phone under 3.2 GB
without a working hardware encoder. That covers 1.0.8 since Patches
3, 4, 7 and 8 (2026-10-11) and 1.0.9+23 (the lean x264 itself goes
back to 2026-10-08). Also any x264 reel with heavy grain. iOS encodes
every reel on x264 (there is no `h264_mediacodec` there), so the
ceiling applies to every iOS save, and lean to iPhones on the tightest
budget. Shipped 2026-10-13 as Shorebird patches to Android `1.0.9+23`
and `1.0.8+19` to `+22`, and iOS `1.0.9+11` (`RELEASES.md`). **Not
device-tested** before it shipped: save a reel on the tightest budget
on a real phone (the preview APK of `patch/1.0.9` installs beside the
store app), play it in the gallery, and check its size.

## 2026-10-14: saves the system ended while the app was away

One note from `version: 1.0.9`, `code: 2026-10-13`, Infinix X6525B
(Android 13 Go), source `exportTrouble`, "my reel didn't save, and it
takes long":

    tightest, 7742 MB, 32-bit, 1 lost · render: RenderFailed(outOfMemory): the render process died during the encode

The render process died, yet the note counts no death: no `survived`,
still `1 lost`, no `x264 only`. `PhoneBudget.renderDied` skips only
when the app is out of sight, so every encode that died there died
with the app away. The save was slow, its owner left it running, and
Android, quickest on Go phones, reclaimed the background app's biggest
process. The renderer took that for a lack of memory: x264 after
hardware, then nothing smaller than tightest, so the save failed with
the "out of memory" message.

Fixed in Dart (`_encodeOnce`, `VideoRenderer.reclaimedAway`). A
render-process death counts as reclaimed when the app is away as the
death is heard, or came back under 10 s before after leaving during
that encode (`OnScreen.departures`: hidden or paused, not the
notification shade). A frozen app hears of the death only once it
thaws. An encode the stall watchdog had given up on doesn't count:
that goes to x264 as before. A reclaimed encode runs again on the
same encoder and budget once the app is in front (`OnScreen.back`).
There is no limit, since each rerun needs its owner to leave and come
back. It counts neither as a lost save nor toward the three deaths
that send encodes back into the app. After any death, the next encode
waits up to 20 s for a new render process (`RenderProcess.awaitRestart`)
instead of falling back into the app after RenderClient's 4 s, and a
render superseded during that wait stops before its encode reaches
the process. `FeedbackService.codeDate` is `2026-10-14`. Android
`1.0.9` only: 1.0.8 has no render process, and iOS encodes in the app.

The likeliest trigger is the screen's own timeout. A save of several
minutes on a slow phone outlasts it, and with the screen off the app
is in the background. From the next store build, a save the user
waits on keeps the screen on (`RenderProcess.keepScreenOn`,
`FLAG_KEEP_SCREEN_ON` in `RenderClient`). The Dart call is in the
patch and does nothing on 1.0.9's native code.

Not fixed: a save left in the background still pauses there. Keeping
it going needs a foreground service with a notification around the
render process: native, a store build, and a Play foreground-service
declaration.

## 2026-10-15: the save-flow review

A review of the path from Save to the gallery, `code: 2026-10-15`:

- **Reclaimed or not.** A pass that started with the app already away
  now counts as away for the reclaim test (it was missed: no departure
  during that encode). From the 1.0.10 store build, Android's own
  record of the death (`ApplicationExitInfo`, Android 11+, via
  `RenderProcess.lastExit`) decides instead of the timing: a crash or a
  death with the app in front is the encode's, one out of sight is a
  reclaim. The debug log says `render: the render process ended: …`.
- **Restart.** `awaitRestart` waits up to 60 s, not 20, and a binding
  that still fails after it sends that one encode to the app without
  turning the render process off for the run (twice in a row does).
  From 1.0.10 the app binds afresh after a death (`restart`), which
  skips Android's restart backoff.
- **Cancel.** A cancelled encode still running in the render process
  gets 5 s to stop before the next encode is sent, then its process is
  ended (`RenderProcess.settleCancelled`), so a new save never queues
  behind a wedged one.
- **Records.** The in-app hardware probe has its own stage, `hardware
  probe`, and a death there counts as a hardware loss. A render-process
  death in the eager render no longer counts as a lost save. The 3 s
  memory reading is written without an fsync, queued behind the marks.
- **Time.** A Save tapped during the eager render restarts it for the
  progress bar when it is barely started, and otherwise joins it with
  the decoders released and every core from its next encode. A save
  that stepped down to tightest mid-run is cached under the `_lx` key,
  so the next Save finds it instead of encoding it again.
- **iOS** keeps the screen on during a save from the 1.0.10 store build
  (`isIdleTimerDisabled`).
- **My Reels** copies to a `.part` and renames it; strays from cut-short
  copies are swept at the first save of a launch.

A pre-2026-10-13 lean reel without `_lx` (made on an out-of-memory
retry) is no longer served: any cached or My Reels reel heavier than
18 Mbps on average, past a 2 MB allowance for what every reel carries,
is made again (`VideoRenderer.tooHeavyToPlay`, `c67fc2a`, `b824c5b`).

### Second pass over it, same day

- **Save after a finished eager render** no longer "joins" it: that
  left the scenery decoders released for the rest of the visit. Only a
  render still running is joined or restarted, and one waiting for a
  letterbox aspect simply becomes the foreground render. A render on
  the device encoder is always joined (threads don't change its pace).
- **`_lx`** answers to what lasts past the run (`PhoneBudget.lasting`):
  an in-app out-of-memory step-down for this run only is cached under
  the plain key, which the next launch asks for.
- **Records.** The stage after a hardware probe becomes `planning`, so
  a death before the first encode is not a hardware loss. A device
  encoder that crashed in the eager render (Android's record says
  `crashed`) is retired, without counting as a lost save. Leaving the
  app writes the `hidden` mark at once, not behind a reading.
- **Render process.** The pid is read at every encode (an idle unbind
  and a reclaim gave a new process with the old pid). A wedged
  cancelled encode's kill waits until the death is heard, and native
  `restart` rebinds whenever the service isn't connected. Before
  Android 11, `exitInfo` answers `unsupported` at once (it cost every
  death a second), and a watchdog give-up isn't asked about. Builds
  without `restart` (up to 1.0.9) wait 20 s for Android's restart, and
  a second wait after one given up on is 5 s.
- **My Reels.** The sweep keeps every `reel_*.mp4` named by the index
  or by `library.json.bad`; entries a build can't read stay in the
  index. Copies go through `copyWhole` (a `.tmp` beside the name).

## 2026-10-17: a step below tightest

Two notes from `version: 1.0.9`, `code: 2026-10-14`:

    tightest, 3647 MB, 7 lost, 5 survived, x264 only · render: RenderFailed(outOfMemory): the render process died during the encode
    tightest, 1831 MB, 32-bit, 2 lost, x264 only · lost: the app closed while a reel was saving (5 cards in one pass; app 91 MB, 261 MB at most; phone 352 MB free)

The first is the 3647 MB phone of 2026-10-11 again ("2 lost" then).
Its render process died five times with the app in front (from
`2026-10-14` code a death with the app away is rerun, not counted), in
lean x264 on the tightest budget. An x264 death is read as out of
memory and answered one budget smaller, and below tightest there was
nothing: every Save failed at its first death. The second phone's app
itself died in a tightest pass, small (91 MB) and with no render
process memory in the note, so either the encode ran in the app or
the app died before the next reading.

Play's vitals for 1.0.9 (28 days to 2026-10-17) have nothing on the
save: one Impeller OpenGL crash in `glDrawArrays` on a MediaTek
PowerVR phone (Oppo Reno2 Z) and one surface-creation ANR (Oppo
CPH2269, PowerVR). Both native; see RELEASES.md on Skia for those GPUs.

Done, Dart only:

- **`ExportBudget.smallest`.** Four cards a pass, two threads, lean
  x264, and the encoder handed 720x1280 (`VideoRenderer.outputScale`:
  the graph still composes at 1080x1920, a `scale=720:1280:flags=area`
  before the encoder). Desktop FFmpeg 8.0.1, the app's graph, lean x264
  on two threads, 150 frames: tightest (8 cards, 1080x1920) peaks at
  326 MB in 7.2 s; smallest at 233 MB in 4.3 s. Four cards at 1080x1920
  is 299 MB; a graph composed at 720 throughout would be 208 MB.
- **Down the whole ladder in one save.** The out-of-memory retry steps
  a budget at a time until an encode finishes or there is nothing
  smaller, where it used to step once and fail.
- **Who plans smallest for good.** Losses still step a phone down only
  as far as tightest. A loss inside an x264 encode on a lean budget
  (`leanLost` in `export_budget.json`) takes it to smallest: a render
  death in a save, or the app dying in a pass or the join. A hardware
  death, the cards, an old loss: none of these, so a 3 GB phone that
  lost a save in 1.0.8 doesn't make every reel softer. The running mark
  now carries the save's `budget`; a mark from older code is read at the
  phone's own budget then.
- **The render process waited for once.** A first binding that takes
  longer than RenderClient's 4 s (a new process on a slow phone short
  of memory) used to send every encode of the run into the app. Now the
  app waits up to 12 s for the process to be listed, asks once more, and
  only then encodes in the app.
- **The note says where.** `, in the app` after the stage when an
  Android encode ran in the app's process, and the budget after it:
  `lost: … (5 cards in one pass, in the app, tightest; app …)`.
- `FeedbackService.codeDate` is `2026-10-17`.

**Not device-tested.** Check on a phone planned smallest that a reel
saves, plays, and that its passes join by stream copy at 720x1280.

## 2026-10-21: a save on a phone with room, and the app gone

One note from `version: 1.0.9`, `code: 2026-10-14` (so none of the
2026-10-15 or 10-17 work), source `exportTrouble`, "My reel didn't
save", Android 12 (`SP1A.210812.003`):

    tightest, 3704 MB, 1 lost · lost: the app closed while a reel was saving (pass 5/17, 6 cards; app 166 MB, 328 MB at most; phone 1333 MB free)

The phone was planned `tight` when it died (3.7 GB, no loss yet); the
loss itself made it `tightest`. Not memory: the app at 166 MB, 1.3 GB
of the phone free, and no render-process figure (2026-10-14 code kept
a stale pid there; FFmpeg was not in the app, which would be 300 MB
and up). A 17-pass save on x264 with four threads is minutes long. So
the app was ended by something other than the low-memory killer: the
user closing it (swiped out of the recent apps, which 2026-10-14 code
could count as a loss when the hidden mark landed late), an ANR
("isn't responding", then Close), or a crash. Play's vitals for 1.0.9
(28 days to 2026-10-21) have no crash of the app on Android 12 and an
input-dispatch ANR with the main thread idle (1 user), which is what a
phone too busy to schedule the main thread looks like.

Done, for the 1.0.10 store build (native) with the Dart beside it:

- **Android says how the app ended.** The running mark carries the
  app's pid and when the save began (`pid`, `since`). The next launch
  asks `ApplicationExitInfo` for that pid's record from after `since`
  (`RenderProcess.appExit`, the same `exitInfo` call, which now takes
  `since`). Closed by the user (`REASON_USER_REQUESTED`, "remove task",
  or `USER_STOPPED`) or ended out of sight: not a lost save, no smaller
  budget, no notice; counted as `N closed` in the summary. Anything
  else counts as before, and the note says Android's reason:
  `lost: … (pass 2/9, 8 cards; Android: not responding, importance 100; app …)`.
  On 1.0.9's native side `exitInfo` knows only the last two minutes, so
  a patch there changes nothing.
- **FFmpeg a notch below the app.** The render process's encode thread
  runs at nice +4 (`RenderService.ENCODE_PRIORITY`), and FFmpeg's
  threads inherit it, so a save that fills every core leaves the app's
  main and UI threads first. Short of `THREAD_PRIORITY_BACKGROUND`,
  which would also move the encode onto the slow cores.
- `FeedbackService.codeDate` is `2026-10-21`.

What the next such note says: `N closed` with no loss means people
give up on long saves; look at the save's length (passes) and speed,
not memory. `Android: not responding` means the save starves the app:
fewer threads on `tight`. `Android: low memory` with room in the note
means the phone filled between readings.

## 2026-10-21: long verses line by line, and verse motion

Not a report: a feature, and what it costs a save. A reel can now cut
its long verses into lines (Settings → Customize, or the reel screen's
Motion sheet), carry the surah's name, and move its verse (style step →
Motion: fade or rise in and out, a gold thread drawn under the words,
a band of light through the letters, recited words staying gold, words
waiting faint).

- **Every reel without lines or motion takes the old path, byte for
  byte.** `VideoRenderer.render` only goes through `_unitCards` and
  `VerseMotionGraph` when a verse is cut or the motion is on; the
  defaults are off. The surah's name, on by default for new reels, is
  one small PNG and one untimed overlay, like the dedication.
- **Cards.** A cut verse is one card per part instead of one per verse,
  and each part is smaller. With the word highlight, the trail or the
  unveil, a part has a card per word window, exactly as a whole verse
  with the highlight always had. `RenderPlan` counts them as it counts
  any card, so the per-pass budgets still bound the memory.
- **Motion pieces.** A fade or rise is a `loop` of the card (references,
  no copies) through `fade`, which needs a writable frame: one copy of
  the card (about 2 MB at 1080x440) held by its overlay from the start
  of the pass. At most two per unit. Cropped strips (thread, light)
  are zero-copy.
- **Light.** One glint card per unit with light on, an input like any
  card: `RenderPlan` is handed it as a card, so a pass holds fewer
  units rather than more memory.
- **Measured** with desktop FFmpeg 8.0.1, one pass holding every card
  of Ayat al-Kursi and 2:256 cut into 6 lines with word windows
  (`test/tools/export_motion_tool_test.dart`, then the commands it
  writes), x264, two threads, 44 s: no motion 83 inputs, 1189 MB peak;
  light 89 inputs, 1214 MB; rise + trail + thread 85 inputs, 1122 MB.
  The cost is the card count, as before; motion adds next to nothing
  on top of it. The app splits such a reel into passes of 48, 16, 8 or
  4 cards by budget, as it does any reel.

**Not device-tested.** No phone or emulator here. Before a release,
save a reel with long verses line by line and each motion preset on a
real phone (the preview APK installs beside the store app), and check
that the lines change where the reciter ends them and the file plays.

## 2026-10-21 (evening): lines and the light by default

Not a report: the defaults changed. A new install makes every reel one
line at a time, the scenery changing with each line, the light passing
through the words (fade + light, `VerseMotion.standard`), the word
highlight on, and no surah name. Before, a new reel showed each verse
whole and still. So `_unitCards` and `VerseMotionGraph` are now the path
most reels take, not the opt-in one; a reel with lines off and motion
set to Still still takes the old one.

- **What a default reel holds over the old default.** Per unit (a line,
  or a verse shown whole): its base card and its glint card. The word
  windows are the same cards either way (`highlightPlan`'s cap of 120 is
  unchanged), and parts are smaller cards than whole verses.
- **The light** is four layered crops of the glint card now (216, 140,
  88 and 48 px wide at 0.14, 0.26, 0.45 and full strength,
  `LightLook.layers`), not two, so its edges don't read as a box. Each
  layer's copy of the glint is made once, from the still, and held for
  the pass: three small copies a unit (about 1.2 MB each for a one-line
  card), where it was one.
- **Measured** on the GitHub runner (the desk-previews workflow's
  `encode` input), FFmpeg 6.1.1, x264, one pass holding every card of
  2:255-256 (44 s, word timing):

  | reel | inputs | peak | time |
  |---|---|---|---|
  | before: whole verses, still | 78 | 1122 MB | 29.3 s |
  | now: one line, light, highlight | 100 | 1293 MB | 32.8 s |
  | two lines, still, surah name | 83 | 1152 MB | 29.5 s |
  | two lines, light, surah name | 89 | 1303 MB | 33.9 s |
  | two lines, thread | 85 | 1307 MB | 31.9 s |
  | two lines, gilded | 85 | 1294 MB | 32.2 s |
  | two lines, unveil | 83 | 1223 MB | 30.2 s |

  So a default reel costs about 15% more memory and 12% more time than
  it did, held in one pass. On this FFmpeg the moving pieces (thread or
  light, and the fades) come to about 150 MB a pass whatever the motion;
  the 2026-10-21 morning figures on FFmpeg 8.0.1 put them near nothing.
  `RenderPlan` counts glint cards as cards and the passes of a tight
  phone hold 16, 8 or 4 cards, so the motion's share shrinks with the
  pass. If notes start showing `cards`-stage or pass losses on 3 GB
  phones from builds after this, the first lever is to turn the light's
  layers down to two on `tight` and below.

## 2026-10-21 (night): luminous bands, a light in any colour, and a held picture

What this round added to a save, measured as before: the export tool's
reels, one pass, FFmpeg 6.1.1 on the runner (`desk-previews.yml`,
`encode=true`).

| Reel | Inputs | Peak | Time |
| --- | ---: | ---: | ---: |
| defaults (full frame, a line at a time, the light) | 100 | 1320 MB | 19.6 s |
| sky (Gilded in sky blue, the name pinched to 1.4) | 91 | 1273 MB | 18.2 s |
| band (wide card over a luminous band, PNG re-read per frame) | 102 | 1371 MB | 43.2 s |
| band (the same, the band decoded once and held) | 102 | 1272–1289 MB | 35.0–35.6 s |

- **A light in another colour** costs nothing: the glint and the thread
  are drawn in it instead of gold (`AyahOverlay.glintColourFor`,
  `rasterizeThreadStrip(accentArgb)`), the same cards as before.
- **A luminous band** (`BandGlow`) is one 1080x1920 PNG. A still
  scenery folds it into the flattened base frame once
  (`_flattenLetterbox`), so only a video scenery feeds it per frame.
  Read as a looped image input it was decoded again for every frame;
  it is now one input decoded once and repeated by the `loop` filter
  (`_bandLoop`): 8 s and about 80 MB less on the tool's band reel.
- **The same for a still scenery's base frame was tried and taken
  back.** Holding it with `loop` instead of `-loop 1` cut the peak by
  60–80 MB on every reel but made them a third slower on FFmpeg 6.1
  (26.3–26.9 s against 19.6 s for `defaults`, two runs), where the
  looped input's PNG decode runs on spare decoder threads. On FFmpeg 8
  on two busy cores it was 2.8 times faster. Worth trying again for the
  tightest budgets only (`sceneThreads` set), where that decode has one
  or two threads and memory is what runs out; measure on a phone first.

## 2026-10-23: an iPhone's save lost at "starting"

One note, iOS 16.2 (build 20C65), `version: 1.0.9`, `code: 2026-10-14`,
176 reels made, source `exportTrouble`, "My reel didn't save":

    tight, 1 lost · lost: the app closed while a reel was saving (starting)

Nothing more could be said, for two reasons now fixed in Dart
(`code: 2026-10-23`):

- **iOS recorded no memory.** `PhoneBudget._memoryNow` read only Linux's
  /proc, so an iPhone's note never had `app … MB`. It now reads the app's
  resident memory and its peak from the runtime (`ProcessInfo.currentRss`
  and `maxRss`; the phone's free memory needs native code iOS doesn't
  give a patch), and the 3-second reading runs on iOS too.
- **"starting" hid a joined render.** The stage is written by the render
  as it draws cards and runs passes. A Save that joins the eager render
  already encoding (or restarts it) starts the record after those stages
  have passed, so a death in the rest of that encode read "starting".
  The join now writes `joined the eager render at N%`, the restart
  `eager render restarted`.

What it likely was: an iPhone on `tight` (under 4.6 GB, so an XR, 11 or
older) encodes in the app, on x264, beside the preview; dying in the
first seconds of the encode, with no `hidden` mark, is the system ending
a foreground app for memory (jetsam). The 1.0.10 store build keeps the
screen on during a save (`isIdleTimerDisabled`), which rules out the
auto-lock half of it. If the next iPhone notes say `joined the eager
render` with a high peak, the lever is the same as on Android: plan iOS
saves one step smaller (`tightest`) when the phone is under 4 GB.

**Done 2026-10-24 (needs the 1.0.10 store build):** an iPhone's memory
was never read (`PhoneBudget._readHardware` read only Android's
/proc/meminfo), so every iPhone started `roomy`, with the preview's eager
render beside the preview, and stepped down only after losing a save.
iOS now tells its memory (`physicalMemory` on the `ayahreel/render`
channel, asked once by `PhoneBudget.load`), and an iPhone under 3.2 GB
(an XR, X, 8, 8 Plus, SE of 2020 or older; iOS reports 2.8–2.9 GB)
starts `tightest`: the same 1080x1920, in passes of 8 cards on two
threads with lean x264, and no eager render. 4 GB iPhones keep `roomy`
and step down after a loss as before (what the owner agreed to:
only the small ones change). Notes from `code: 2026-10-24` carry the iPhone's
memory in the budget line. A build from before it answers nothing, and
the phone plans as it always did.

## 2026-10-31: black reels, and a save that fails with no trace

Two reports on `1.0.10`, `code: 2026-10-24`:

- **"Why are some of my videos black"**: Galaxy A07 (`BP4A…A075F…`,
  Android 16), `tight, 3611 MB`, 102 reels. Not memory. The renderer
  stands a dark gradient in for any scenery whose file is missing: the
  catalog's average colours for a library scenery, and `0xFF101418 →
  0xFF2A313B` (near black) for a picked photo or video. Nothing said
  so. The gallery picker's copy of a pick lives in the **cache folder**,
  which Android empties when storage runs low (on this class of phone,
  mid-session: see 2026-10-07's `.part` in the cache). The preview never
  showed it: a decoded still and a video player holding the file open
  keep showing a deleted file. So the reel came out black behind the
  verse, with the mark on it.
- **"I still can't save the video", "can't download the Quranic video,
  my internet is strong"**: one Motorola edge 2021 (`T1RM33.1…`, 7.4 GB,
  `roomy`), five notes and a Play review from 2026-10-30/31, `reels` 0
  then 3. Every note was sent from Settings and none carried a failure:
  `noteExportTrouble` was held in memory only, and the app had been
  opened again since. Its "connection" wording points at a download
  (scenery or recitation), which `0f58843`'s `net` line now names.

Fixed in `1cdad17` (Dart only, `code: 2026-10-31`):

- `PickedMedia.keep` moves each pick into `<support>/picked` (a rename;
  newest 16 / 600 MB kept, the newest always).
- `_sceneryOnPhone` in the preview checks every scenery file before a
  render: a cleared library scenery is downloaded again, a pick that
  has gone fails with `SceneryGone` ("pick it again"), never a black
  render. The renderer logs `render: scenery file missing` if a gradient
  stands in anyway.
- A hardware encode whose frames at 1/3 and 2/3 are flat black (27x48
  area-averaged luma, none above 20) is redone on x264 and MediaCodec
  is retired for good (`PhoneBudget.hardwareBlack`, counted in `hwLost`,
  so the summary says `x264 only`). x264 output is never judged dark.
- The last failed save is kept in `feedback.json` with its age, like
  `net`: `export: roomy, 7382 MB · render: … , 3 h ago`.

Next black report: if its note says `x264 only` the hardware check
fired; if the export line says `SceneryGone`, the pick was cleared
before the user saved; with neither, ask what kind of scenery it was.

## 2026-10-31 (later): a 4 GB iPhone's one big pass, and an Android death with no reason

Two notes, `version: 1.0.10`, `code: 2026-10-31`, source `exportTrouble`:

    tight, 3683 MB, 1 lost · lost: … (54 cards in one pass, roomy; app 429 MB, 1310 MB at most), just now
    tightest, 3862 MB, 1 lost · lost: … (2 cards in one pass, tight; app 215 MB, 378 MB at most; phone 985 MB free), just now

- **The iPhone** (iOS 27.2, Arabic, 0 reels made) is a 4 GB one, which
  kept `roomy` (2026-10-24): a reel under two minutes is one pass of up
  to 130 cards. Every iPhone encodes in the app, and iOS ends an app
  near 2 GB on these phones. 54 cards is about 350 + 54 × 12–17 MB of
  graph on top of the app: past it. Fixed in Dart: an iPhone under 4.6
  GB keeps `roomy` (the render ahead of Save, every core) but holds a
  pass to 16 cards (`PhoneBudget.passCardsFor`, `roomyPassCards`, used
  by `VideoRenderer._clipsFor`), what a `tight` Android phone holds. Its
  summary says `roomy, 3683 MB, passes of 16`. After a loss it plans
  `tight` as before.
- **The Android phone** (`A665L`, Android 13 Go, 4 GB) was planned
  `tight` and died in a short reel's one x264 pass, with the app small,
  the phone 985 MB short of full and no render-process figure (the
  encode had barely been handed to it). Not memory. The 1.0.10 native
  side should have given Android's reason, and the note had none: the
  question (`RenderProcess.appExit`) is asked from `main()`, answered on
  the main thread a Go phone's cold start keeps busy, and waited for
  3 s, after which it said nothing. Now it waits 20 s, and the note says
  `Android: no answer` or `Android: no record` instead of nothing. The
  mark carries `at` (the last reading's time), so the note says how far
  in the save was (`2 cards in one pass, tight, 4 s in`). A mark written
  by the process still running (the engine made again, the app alive)
  is counted `closed`, not lost.
- `FeedbackService.codeDate` is `2026-10-31c`.

Next such Android note: read `Android:` first. `no record` with room
means Android kept nothing (some vendors' task killers); `low memory`
with room means the phone filled between readings; `not responding`
means the save starved the main thread.

## What a note says since 2026-10-08

While a foreground save runs, `PhoneBudget` writes its stage and the
app's memory into `export_budget.json` every 3 seconds and at each
stage. If the app dies, the next launch's note reads, for example:

    lost: the app closed while a reel was saving (pass 3/7, 8 cards; app 640 MB, 690 MB at most; phone 180 MB free)

- **stage**: `starting`, `cards` (drawing the verse PNGs in Flutter),
  `hardware probe` (from `2026-10-15` code), `N cards in one pass`, `pass i/n, N cards`, `join`. `, hardware` means
  the MediaCodec encoder was running; `, in the app` (from `2026-10-17`
  code) that the encode ran in the app's process, not the render
  process. Then the budget it ran at (from `2026-10-17` code).
- **app … MB**: the process's resident memory (`VmRSS`) at the last
  reading, and its peak (`VmHWM`).
- **phone … MB free**: `MemAvailable` at that moment.

Only notes with `code: 2026-10-08` or later carry this, and the stage
only says where the save was within about 3 seconds.

## What to do with the next reports

1. **Stage `cards`.** The save died while Flutter drew the verse cards,
   before FFmpeg started. Look at `AyahRasterizer` (PNG encoding on the
   UI isolate, the image cache), not at the encoder. A small app and a
   phone with room (the 2026-10-11 note: 131 MB, 444 MB free) is a
   crash, most likely `toImage` with the app out of sight: check that
   the phone's code has `OnScreen.settle`, and Play's vitals for the
   stack.
2. **A pass with `, hardware`.** MediaCodec was encoding, and lean x264
   didn't apply. Try software x264 lean on the tightest budget, or a
   lower hardware bitrate there.
3. **A pass, software, with a high peak** (past about 600 MB on a
   2–3 GB phone). The per-card inputs are the cost. Next lever: the
   constant-memory renderer below.
4. **A modest peak (under about 450 MB) but little free memory** (under
   about 150 MB). The phone itself is full, and the system kills the
   foreground app anyway. Only a smaller save (`smallest`, from
   `2026-10-17` code) or FFmpeg out of the app's process can help.
5. **`join`.** The join re-encodes only when the passes can't be stream
   copied (`copyVideo`). Find out why.
6. **No more such notes from `2026-10-08` code.** Stop here.
7. **`render: … the render process died` with no `survived`** (from
   `2026-10-13` code or older): it died with the app away; see
   2026-10-14. From `2026-10-14` code such deaths are rerun, so a
   `render process died` failure there was heard with the app in front
   for 10 s or more: memory or a crash, as before.
8. **From `2026-10-11` code**, a note with `N survived` means the render
   process took N deaths and the app lived. A *lost* save there (the
   app itself died) is something else: look at the app's own memory,
   the `cards` stage first, since FFmpeg is no longer in the app.
9. **From `2026-10-17` code**, `smallest` in the summary means the phone
   lost an x264 save on tightest. A `render process died` failure on
   smallest has nothing smaller left: next is the constant-memory
   renderer, or composing at 720 throughout. `, in the app` on a
   lost save's stage means the render process wasn't to be had in time
   even after 12 s: look at why it can't start on that phone.

## The bigger levers, in order of cost

- **720p on the tightest budget.** Done 2026-10-17 as its own step,
  `smallest`, for the phones that lose a save on tightest (above).
- **Constant-memory renderer.** Collapse the per-card PNG inputs into
  one stream: every card padded to a full 1080x1920 transparent PNG,
  fed through the concat demuxer with durations, and one overlay at
  0,0. Memory stops growing with the card count. Fades between cards
  and the letterbox layout need rework. A big renderer change; test it
  on a real 3 GB phone before any OTA.
- **FFmpeg in its own process.** Done 2026-10-11 (above); shipped in
  Android `1.0.9+23` (2026-10-12).
