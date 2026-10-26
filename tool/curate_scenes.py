"""Curate, deduplicate and normalize the harvested candidate pool.

    python tool/curate_scenes.py score     -> videos/_work/scored.json
    python tool/curate_scenes.py build     -> <library>/<bucket>/<category>/*
    python tool/curate_scenes.py gallery   -> <library>/_review/index.html

Set SCENE_OUT to move the delivered library somewhere else.

The judgement that matters is *readability*, and it is measured on the
frame the viewer actually sees -- the source with the app's own scrim
(black, 15% at the top graduating to 45% at the bottom) composited on
top -- not on the raw photo. A frame that measures fine raw can still
swallow gold text once it is in place, and vice versa.

Verticals are scored hard: the verse is drawn over them. Horizontals are
letterboxed with the verse underneath, so nothing is written on the
picture and they are judged on sharpness and framing instead.
"""

import concurrent.futures as futures
import json
import os
import re
import shutil
import subprocess
import sys
import threading

import numpy as np
from PIL import Image, ImageOps

Image.MAX_IMAGE_PIXELS = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, "videos", "_work")
THUMBS = os.path.join(WORK, "thumbs")

# Where the library is delivered. <bucket>/<category>/ holds files already
# framed for the reel; _originals/ keeps the untouched source of each one,
# so a scene can be re-cropped later without re-downloading anything.
OUT = os.environ.get("SCENE_OUT",
                     r"C:\Users\dell\OneDrive\Videos\test\don't touch")
REVIEW = os.path.join(OUT, "_review")

VERT = (1080, 1920)
HORZ = (1920, 1080)

# The picker shows tabs, not harvest folders. Harvesting stays granular
# because a narrow query returns better frames than a broad one, but a
# tab holding four scenes is a dead end -- so the fine categories fold
# into a handful of tabs that are all worth opening.
TABS = {
    "sky": ["sky", "clouds", "aurora"],
    "mountains": ["mountains", "snow", "rock"],
    "desert": ["desert"],
    "water": ["ocean", "water", "rain"],
    "forest": ["forest", "field"],
    "road": ["road"],
    "sacred": ["sacred"],
    "abstract": ["abstract"],
    "aerial": ["aerial_mountain", "aerial_coast", "aerial_forest",
               "aerial_desert", "aerial_water", "aerial_land"],
    "cinematic": ["cinematic"],
}
TAB_OF = {cat: tab for tab, cats in TABS.items() for cat in cats}

# Scenes per tab, not per category: a tab is what the user actually
# opens, and tabs that differ threefold in depth read as broken. Within
# a tab the slots are drawn round-robin from its categories, so one
# prolific query cannot crowd out the others.
TARGET_PER_TAB = {"vertical": 48, "horizontal": 48}
# Nothing below this gets in regardless of how thin a tab is -- a bad
# background is worse than a small library. Set from the measured
# distribution: roughly the top third of verticals and the top half of
# horizontals clear it.
FLOOR = {"vertical": 62.0, "horizontal": 68.0}

# Minimum share of a bucket's tabs that must be moving footage. A
# letterboxed drone shot is the whole reason the horizontal bucket
# exists, and stills outnumber clips ten to one in the candidate pool,
# so without a floor here the wide tabs fill up with photographs.
# Verticals have no quota: a still is the better default there (no
# decoder, a fraction of the size, and it encodes faster).
CLIP_QUOTA = {"horizontal": 0.6, "vertical": 0.0}


def log(*a):
    print(*a, flush=True)


def ffmpeg(args, timeout=180):
    return subprocess.run(["ffmpeg", "-v", "error", "-y", *args],
                          capture_output=True, timeout=timeout)


# ── measurement ─────────────────────────────────────────────────────────

def cover(img, size):
    """Centre cover-crop to exactly `size`, the same fill the exporter's
    scale+crop performs, so what we measure is what gets rendered."""
    img = ImageOps.exif_transpose(img).convert("RGB")
    return ImageOps.fit(img, size, method=Image.LANCZOS, centering=(0.5, 0.45))


def scrimmed(gray_small):
    """Apply the app's graduated scrim to a small luma array."""
    h = gray_small.shape[0]
    y = np.linspace(0.0, 1.0, h)[:, None]
    return gray_small * (1.0 - (0.15 + 0.30 * y))


def measure(img, bucket):
    """Return (score 0-100, detail dict). Higher is better."""
    small = img.convert("L").resize(
        (96, max(1, 96 * img.height // img.width)), Image.BILINEAR)
    a = np.asarray(small, dtype=float)
    eff = scrimmed(a)
    h = eff.shape[0]

    if bucket == "vertical":
        # The verse block is centred by default but the user can slide it;
        # weight the middle 70% where it can actually land.
        band = eff[int(h * 0.15):int(h * 0.88)]
        mean = float(band.mean())
        p95 = float(np.percentile(band, 95))
        # Busyness: mean neighbour-to-neighbour luma step. Detail, not
        # brightness, is what actually shreds a line of Arabic script.
        busy = float(np.abs(np.diff(band, axis=0)).mean()
                     + np.abs(np.diff(band, axis=1)).mean())
        score = (100.0
                 - min(max((mean - 52.0) * 1.15, 0.0), 46.0)     # too bright
                 - min(max((p95 - 135.0) * 0.34, 0.0), 24.0)     # hot spots
                 - min(max((busy - 2.6) * 4.6, 0.0), 30.0)       # too busy
                 - min(max((22.0 - mean) * 0.9, 0.0), 12.0))     # dead black
        return score, {"mean": round(mean, 1), "p95": round(p95, 1),
                       "busy": round(busy, 2)}

    # Horizontal: the verse sits below the frame, so brightness is free.
    # Judge it on what still matters -- detail and tonal range -- and
    # build the score up from those rather than deducting from a perfect
    # 100, which just made every decent frame tie at the top.
    full = np.asarray(img.convert("L").resize((240, 135), Image.BILINEAR), dtype=float)
    sharp = float(np.abs(np.diff(full, axis=1)).mean() + np.abs(np.diff(full, axis=0)).mean())
    spread = float(full.std())
    mean = float(full.mean())
    score = (34.0
             + min(sharp, 26.0) * 1.55                           # real detail
             + min(spread, 62.0) * 0.42                          # tonal range
             - min(max((mean - 185.0) * 0.9, 0.0), 22.0)         # blown out
             - min(max((36.0 - mean) * 0.8, 0.0), 22.0))         # murky
    return min(score, 100.0), {"sharp": round(sharp, 2),
                               "spread": round(spread, 1),
                               "mean": round(mean, 1)}


# A background carries scripture; a stranger's face in it is a different
# picture than the one intended, and the background rules rule people out
# outright. Stock searches return them anyway -- a lone figure on a dune
# is exactly what "desert dusk minimal" surfaces -- so they get caught
# here rather than by eye across five hundred files.
_CASCADES = None
_CASCADE_LOCK = threading.Lock()


def _cascades():
    global _CASCADES
    with _CASCADE_LOCK:
        if _CASCADES is None:
            import cv2
            _CASCADES = []
            for name in ("haarcascade_frontalface_default.xml",
                         "haarcascade_profileface.xml"):
                path = os.path.join(cv2.data.haarcascades, name)
                c = cv2.CascadeClassifier(path)
                if not c.empty():
                    _CASCADES.append(c)
    return _CASCADES


def has_face(img):
    try:
        import cv2
        g = np.asarray(img.convert("L").resize((360, 360 * img.height //
                                                img.width)), dtype=np.uint8)
        g = cv2.equalizeHist(g)
        for c in _cascades():
            # minSize keeps a 12px smudge of rock from reading as a face;
            # anything big enough to be recognised is big enough to catch.
            if len(c.detectMultiScale(g, 1.12, 6, minSize=(26, 26))):
                return True
    except Exception:
        pass
    return False


_DENY = None


def _denylist():
    """Candidate ids and perceptual hashes that never enter the library.

    See tool/scene_denylist.txt: the scorer rates a scene on how well it
    sits under a verse, and something can be perfect by that measure and
    still be the last thing this app should show."""
    global _DENY
    if _DENY is None:
        ids, hashes = set(), []
        path = os.path.join(os.path.dirname(__file__), "scene_denylist.txt")
        try:
            with open(path, encoding="utf-8") as f:
                for line in f:
                    line = line.split("#")[0].strip()
                    if not line:
                        continue
                    parts = line.split()
                    if parts[0] != "-":
                        ids.add(parts[0])
                    if len(parts) > 1 and parts[1] != "-":
                        hashes.append(int(parts[1]))
        except FileNotFoundError:
            pass
        _DENY = (ids, hashes)
    return _DENY


def denied(c, frames):
    """True when [c] is on the denylist, by id or by how it looks.

    The hash check uses the same tolerance as near-duplicate rejection,
    so a re-encode or a re-upload of the same footage is still caught."""
    ids, hashes = _denylist()
    if c.get("id") in ids:
        return True
    if not hashes:
        return False
    for f in (frames if isinstance(frames, list) else [frames]):
        h = dhash(f)
        if any(hamming(h, d) <= 8 for d in hashes):
            return True
    return False


def dhash(img, n=8):
    g = np.asarray(img.convert("L").resize((n + 1, n), Image.BILINEAR), dtype=int)
    bits = (g[:, 1:] > g[:, :-1]).flatten()
    return int("".join("1" if b else "0" for b in bits), 2)


def hamming(a, b):
    return bin(a ^ b).count("1")


def gradient_argb(img):
    """Top-third and bottom-third average -- the picker poster, the
    pre-load frame, the My Reels thumbnail and the missing-asset
    fallback all come from this pair."""
    a = np.asarray(img.resize((32, 32), Image.BILINEAR).convert("RGB"), dtype=float)
    top = a[:11].reshape(-1, 3).mean(axis=0)
    bot = a[-11:].reshape(-1, 3).mean(axis=0)
    return [int(0xFF000000 + (int(c[0]) << 16) + (int(c[1]) << 8) + int(c[2]))
            for c in (top, bot)]


# ── per-candidate work ──────────────────────────────────────────────────

def video_frames(path, n=3, probe=False):
    """Pull n frames without decoding the whole clip. A probe file is
    only the head of the mp4 -- its moov reports the real duration but
    the bytes past the first few seconds are simply not there, so stay
    inside the window that was actually downloaded."""
    dur = 0.0
    try:
        p = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", path], capture_output=True, timeout=60)
        dur = float((p.stdout or b"0").decode().strip() or 0)
    except Exception:
        pass
    if dur <= 0:
        return [], 0.0
    frames = []
    span = min(dur, 2.4) if probe else dur
    for i in range(n):
        t = max(0.2, span * (i + 1) / (n + 1))
        # Thread-unique: the scorer runs a poolful of these at once
        # and a shared name would hand one worker another's frame.
        tmp = os.path.join(WORK, f"_f{threading.get_ident()}_{i}.jpg")
        r = ffmpeg(["-ss", f"{t:.2f}", "-i", path, "-frames:v", "1",
                    "-vf", "scale=480:-1", tmp], timeout=90)
        if r.returncode == 0 and os.path.exists(tmp):
            try:
                frames.append(Image.open(tmp).convert("RGB").copy())
            except Exception:
                pass
            os.remove(tmp)
    return frames, dur


def assess(c):
    path = c.get("probe_file") if c["kind"] == "video" else c.get("file")
    if not path or not os.path.exists(path):
        return None
    size = (VERT if c["bucket"] == "vertical" else HORZ)
    try:
        if c["kind"] == "image":
            img = Image.open(path)
            if min(img.size) < 500:
                return None
            framed = cover(img, size)
            if denied(c, framed):
                c["error"] = "denied"
                return None
            if has_face(framed):
                c["error"] = "face"
                return None
            score, detail = measure(framed, c["bucket"])
            c["dhash"] = dhash(framed)
            c["grad"] = gradient_argb(framed)
            c["src_size"] = list(img.size)
            c["dur"] = 0
        else:
            frames, dur = video_frames(path, probe=True)
            if not frames or dur < 2.0:
                return None
            framed = [cover(f, size) for f in frames]
            if denied(c, framed):
                c["error"] = "denied"
                return None
            if any(has_face(f) for f in framed):
                c["error"] = "face"
                return None
            scores = [measure(f, c["bucket"]) for f in framed]
            score = sum(s for s, _ in scores) / len(scores)
            detail = scores[len(scores) // 2][1]
            # A clip that changes a lot mid-shot is a cut, not a loop.
            hs = [dhash(f) for f in framed]
            c["cut"] = max(hamming(hs[0], x) for x in hs[1:]) > 26
            if c["cut"]:
                score -= 12
            c["dhash"] = hs[0]
            c["grad"] = gradient_argb(framed[len(framed) // 2])
            c["dur"] = round(dur, 1)
            c["src_size"] = list(frames[0].size)
            framed = framed[len(framed) // 2]
        c["score"] = round(float(score), 1)
        c["detail"] = detail
        os.makedirs(THUMBS, exist_ok=True)
        framed.resize((180, 320) if c["bucket"] == "vertical" else (320, 180),
                      Image.LANCZOS).save(
            os.path.join(THUMBS, c["id"] + ".jpg"), quality=72)
        return c
    except Exception as e:
        c["error"] = str(e)[:120]
        return None


def score_all():
    # Derived from what is actually on disk rather than from a handoff
    # file, so a retry pass topping up throttled downloads can run
    # alongside the main fetch without either clobbering the other.
    sys.path.insert(0, os.path.join(ROOT, "tool"))
    import harvest_scenes
    with open(os.path.join(WORK, "candidates.json"), encoding="utf-8") as f:
        cands = []
        for c in json.load(f):
            probe = c["kind"] == "video"
            p = harvest_scenes._path_for(c, probe=probe)
            if os.path.exists(p) and os.path.getsize(p) > 20000:
                c["probe_file" if probe else "file"] = p
                cands.append(c)
    # Resumable: this pass decodes three frames out of every clip and
    # runs two cascades over every still, so losing twenty minutes of it
    # to a stray kill is worth one file write per few hundred items.
    out_path = os.path.join(WORK, "scored.json")
    done, seen = [], set()
    if os.path.exists(out_path):
        try:
            with open(out_path, encoding="utf-8") as f:
                done = json.load(f)
            seen = {c["id"] for c in done}
            log(f"resuming: {len(done)} already scored")
        except Exception:
            done, seen = [], set()
    todo = [c for c in cands if c["id"] not in seen]
    log(f"scoring {len(todo)} of {len(cands)} fetched candidates")

    def flush():
        tmp = out_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(done, f, indent=1)
        os.replace(tmp, out_path)   # never leave a half-written file

    with futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        for n, r in enumerate(ex.map(assess, todo), 1):
            if r:
                done.append(r)
            if n % 250 == 0:
                log(f"  {n}/{len(todo)} scored, {len(done)} usable")
                flush()
    done.sort(key=lambda c: -c["score"])
    flush()
    log(f"{len(done)} usable -> scored.json")
    for b in ("vertical", "horizontal"):
        s = [c["score"] for c in done if c["bucket"] == b]
        if s:
            q = np.percentile(s, [10, 50, 75, 90, 98])
            log(f"  {b:11} n={len(s):5}  p10/50/75/90/98 = "
                + " / ".join(f"{x:.0f}" for x in q))


# ── selection + normalize ───────────────────────────────────────────────

def select(scored):
    """Fill each tab to its target, best-first, round-robin across the
    tab's categories so a six-query category cannot swamp a one-query
    one. Near-duplicates are dropped against everything kept so far,
    across tabs as well as within them -- the same famous dune photo is
    on four of these sites."""
    chosen, kept_hashes = [], []
    by_tab = {}
    for c in scored:
        tab = TAB_OF.get(c["category"], c["category"])
        by_tab.setdefault((c["bucket"], tab), {}) \
              .setdefault(c["category"], []).append(c)

    for (bucket, tab), cats in sorted(by_tab.items()):
        target = TARGET_PER_TAB[bucket]
        take, n_dup = [], 0

        def fill(limit, kinds):
            """Round-robin over the tab's categories, one scene each per
            sweep, restricted to `kinds`."""
            nonlocal n_dup
            queues = {k: [c for c in sorted(v, key=lambda c: -c["score"])
                          if c["kind"] in kinds]
                      for k, v in cats.items()}
            while len(take) < limit and any(queues.values()):
                progressed = False
                for cat in sorted(queues):
                    if len(take) >= limit:
                        break
                    while queues[cat]:
                        c = queues[cat].pop(0)
                        if c["score"] < FLOOR[bucket]:
                            queues[cat].clear()
                            break
                        if any(hamming(c["dhash"], h) <= 8 for h in kept_hashes):
                            n_dup += 1
                            continue
                        kept_hashes.append(c["dhash"])
                        take.append(c)
                        progressed = True
                        break
                if not progressed:
                    break

        # Clips first, up to the quota, then everything else fills the
        # rest. If the pool cannot meet the quota the tab just ends up
        # with more stills -- it is a floor, not a reservation.
        quota = int(target * CLIP_QUOTA.get(bucket, 0.0))
        if quota:
            fill(quota, {"video"})
        fill(target, {"image", "video"})

        seen = sum(len(v) for v in cats.values())
        clips = sum(1 for c in take if c["kind"] == "video")
        log(f"  {bucket:11}/{tab:11} {len(take):3}/{target} kept "
            f"({clips} clips, {seen} scored, {n_dup} dupes) "
            f"[{', '.join(sorted(cats))}]")
        chosen += take
    return chosen


def slug(c, used):
    base = re.sub(r"[^a-z0-9]+", "_",
                  f"{c['category']}_{c['source']}").strip("_")
    n = 1
    while f"{base}_{n:02d}" in used:
        n += 1
    name = f"{base}_{n:02d}"
    used.add(name)
    return name


def build_one(job):
    """Produce the app-ready file, and archive the original beside it.

    Ready means exactly what the exporter would have made of it: filled
    and centre-cropped to the reel frame, EXIF orientation baked in and
    metadata dropped. That last part is not cosmetic -- Flutter honours
    EXIF orientation and FFmpeg's image demuxer does not, so a rotated
    photo that is left as-is previews upright and exports sideways.

    The untouched source is kept under _originals/ so any scene can be
    re-framed later without going back to the internet."""
    c, dest = job
    size = VERT if c["bucket"] == "vertical" else HORZ
    w, h = size
    try:
        thumb = os.path.join(REVIEW, "thumbs", c["name"] + ".jpg")
        # Resume: names come from the selection order, which is
        # deterministic given the same scored.json, so an existing file
        # is this scene's file. Every output is written via .part and
        # renamed, so anything present is complete -- a clip killed
        # mid-encode leaves a .part, never a truncated mp4.
        if (os.path.exists(dest) and os.path.getsize(dest) > 10000
                and os.path.exists(thumb)):
            c["out"] = os.path.relpath(dest, OUT).replace("\\", "/")
            c["out_bytes"] = os.path.getsize(dest)
            return c
        tmp = dest + ".part"
        if c["kind"] == "image":
            img = cover(Image.open(c["file"]), size)
            img.save(tmp, "JPEG", quality=90, optimize=True)  # writes no exif
            os.replace(tmp, dest)
            thumb_src = img
        else:
            # These loop under a recitation, so a long clip is weight
            # nobody ever sees the end of.
            r = ffmpeg([
                "-i", c["file"], "-t", "12",
                # Video track only. Stock clips routinely carry a `tmcd`
                # timecode track, and ffmpeg copies it by default -- the
                # result is a two-stream mp4 that ffprobe reads happily
                # but Chrome's media stack stalls on forever (readyState
                # stuck at 0, no error). -map_metadata also drops the
                # rotation and creation tags we do not want travelling
                # into the app.
                "-map", "0:v:0", "-map_metadata", "-1", "-map_chapters", "-1",
                "-write_tmcd", "0",
                "-vf", (f"scale={w}:{h}:force_original_aspect_ratio=increase,"
                        f"crop={w}:{h},fps=30"),
                # Capped CRF: quality-driven as before, but never allowed
                # past 2.5 Mbps. Uncapped, detailed drone footage asked
                # for up to 33 MB per 12-second clip -- a half-minute
                # download on mobile data for something the viewer sees
                # behind a verse, and past the per-file limit of most
                # free CDNs. The cap lands them near 4 MB.
                "-an", "-c:v", "libx264", "-crf", "23", "-preset", "medium",
                "-maxrate", "2500k", "-bufsize", "5000k",
                "-pix_fmt", "yuv420p", "-colorspace", "bt709",
                "-color_primaries", "bt709", "-color_trc", "bt709",
                "-movflags", "+faststart", "-f", "mp4", tmp], timeout=420)
            if r.returncode != 0 or not os.path.exists(tmp):
                return None
            os.replace(tmp, dest)
            thumb_src = Image.open(os.path.join(THUMBS, c["id"] + ".jpg"))

        arc = os.path.join(OUT, "_originals", c["bucket"], c["category"])
        os.makedirs(arc, exist_ok=True)
        keep = os.path.join(arc, c["name"] + os.path.splitext(c["file"])[1])
        if not os.path.exists(keep):
            shutil.copyfile(c["file"], keep + ".part")
            os.replace(keep + ".part", keep)

        # Written last, so its presence is what marks a scene complete.
        td = os.path.join(REVIEW, "thumbs")
        os.makedirs(td, exist_ok=True)
        cover(thumb_src, (w // 5, h // 5)).save(
            thumb + ".part", "JPEG", quality=76)  # .part hides the format
        os.replace(thumb + ".part", thumb)
        c["out"] = os.path.relpath(dest, OUT).replace("\\", "/")
        c["out_bytes"] = os.path.getsize(dest)
        return c
    except Exception as e:
        c["error"] = str(e)[:120]
        return None


def build():
    with open(os.path.join(WORK, "scored.json"), encoding="utf-8") as f:
        scored = json.load(f)
    chosen = select(scored)

    # Only now is it worth the bandwidth: scoring ran on head-of-file
    # probes, so every clip that made the cut still needs its complete
    # file before it can be re-encoded.
    sys.path.insert(0, os.path.join(ROOT, "tool"))
    import harvest_scenes
    harvest_scenes.fetch_full(chosen)
    missing = [c for c in chosen
               if not (c.get("file") and os.path.exists(c["file"]))]
    if missing:
        log(f"  {len(missing)} dropped: full file never arrived")
    chosen = [c for c in chosen if c not in missing]

    log(f"\nnormalizing {len(chosen)} chosen scenes into {OUT}")

    jobs, used = [], set()
    for c in chosen:
        d = os.path.join(OUT, c["bucket"], c["category"])
        os.makedirs(d, exist_ok=True)
        ext = ".jpg" if c["kind"] == "image" else ".mp4"
        c["name"] = slug(c, used)
        jobs.append((c, os.path.join(d, c["name"] + ext)))

    built = []
    with futures.ThreadPoolExecutor(max_workers=max(2, (os.cpu_count() or 4) // 2)) as ex:
        for n, r in enumerate(ex.map(build_one, jobs), 1):
            if r:
                built.append(r)
            if n % 25 == 0:
                log(f"  {n}/{len(jobs)}")

    man = [{**{k: c.get(k) for k in
               ("name", "bucket", "category", "kind", "score", "detail",
                "grad", "dur", "source", "page", "out", "out_bytes",
                "src_size")},
            "tab": TAB_OF.get(c["category"], c["category"])}
           for c in built]
    man.sort(key=lambda m: (m["bucket"], m["tab"], m["category"], -m["score"]))
    os.makedirs(REVIEW, exist_ok=True)
    with open(os.path.join(REVIEW, "MANIFEST.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1)
    write_readme(man)
    total = sum(m["out_bytes"] for m in man)
    log(f"\n{len(man)} scenes built, {total / 1e6:.0f} MB -> {OUT}")
    for b in ("vertical", "horizontal"):
        sub = [m for m in man if m["bucket"] == b]
        log(f"  {b:11} {len(sub):3} "
            f"({sum(1 for m in sub if m['kind'] == 'image')} stills, "
            f"{sum(1 for m in sub if m['kind'] == 'video')} clips)")


def recode():
    """Re-encode the library's clips from their archived originals.

    Driven by the manifest, not by `select`, so it cannot resurrect a
    scene that was reviewed out — and sourced from _originals/ so the
    result is still only one compression step from the download, not a
    copy of a copy.

    Use after changing the encode settings. Stills are untouched."""
    man_path = os.path.join(REVIEW, "MANIFEST.json")
    with open(man_path, encoding="utf-8") as f:
        man = json.load(f)
    clips = [m for m in man if m["kind"] == "video"]
    log(f"re-encoding {len(clips)} clips from _originals/")

    def one(m):
        src = os.path.join(OUT, "_originals", m["bucket"], m["category"],
                           m["name"] + ".mp4")
        if not os.path.exists(src):
            log(f"  no original for {m['name']}")
            return None
        dest = os.path.join(OUT, m["out"])
        w, h = VERT if m["bucket"] == "vertical" else HORZ
        tmp = dest + ".part"
        r = ffmpeg([
            "-i", src, "-t", "12",
            "-map", "0:v:0", "-map_metadata", "-1", "-map_chapters", "-1",
            "-write_tmcd", "0",
            "-vf", (f"scale={w}:{h}:force_original_aspect_ratio=increase,"
                    f"crop={w}:{h},fps=30"),
            "-an", "-c:v", "libx264", "-crf", "23", "-preset", "medium",
            "-maxrate", "2500k", "-bufsize", "5000k",
            "-pix_fmt", "yuv420p", "-colorspace", "bt709",
            "-color_primaries", "bt709", "-color_trc", "bt709",
            "-movflags", "+faststart", "-f", "mp4", tmp], timeout=420)
        if r.returncode != 0 or not os.path.exists(tmp):
            log(f"  failed {m['name']}: {r.stderr.decode()[:120]}")
            return None
        os.replace(tmp, dest)
        m["out_bytes"] = os.path.getsize(dest)
        return m

    before = sum(m["out_bytes"] for m in clips)
    done = 0
    with futures.ThreadPoolExecutor(max_workers=max(2, (os.cpu_count() or 4) // 2)) as ex:
        for n, r in enumerate(ex.map(one, clips), 1):
            if r:
                done += 1
            if n % 20 == 0:
                log(f"  {n}/{len(clips)}")
    after = sum(m["out_bytes"] for m in clips)

    with open(man_path, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1)
    write_readme(man)
    gallery()
    log(f"\n{done}/{len(clips)} re-encoded: "
        f"{before / 1e6:.0f} MB -> {after / 1e6:.0f} MB")
    worst = max(clips, key=lambda m: m["out_bytes"])
    log(f"largest clip now {worst['out_bytes'] / 1e6:.1f} MB ({worst['name']})")


def sync():
    """Reconcile the library with a human pass over _originals/.

    Reviewing is done by deleting: whatever is left in _originals/ is
    the library. This drops the framed file and review poster of
    everything that went, rewrites the manifest and README, and leaves
    the candidate pool untouched so a scene can be brought back by
    re-running build."""
    man_path = os.path.join(REVIEW, "MANIFEST.json")
    with open(man_path, encoding="utf-8") as f:
        man = json.load(f)

    kept = set()
    arc = os.path.join(OUT, "_originals")
    for root, _, files in os.walk(arc):
        for fn in files:
            kept.add(os.path.splitext(fn)[0])

    # A scene counts as deleted if either copy of it is gone -- the
    # review can happen in _originals/ or in the framed folders, and
    # whichever the reviewer used, the answer is the same.
    gone = [m for m in man
            if m["name"] not in kept
            or not os.path.exists(os.path.join(OUT, m["out"]))]
    if not gone:
        log("nothing to prune -- library already matches what is on disk")
    for m in gone:
        for p in (os.path.join(OUT, m["out"]),
                  os.path.join(REVIEW, "thumbs", m["name"] + ".jpg")):
            if os.path.exists(p):
                os.remove(p)
    # Filter by the same set that was just deleted -- recomputing the
    # predicate here would let a scene lose its files but keep its
    # manifest entry, which is exactly the state that breaks publishing.
    dropped = {m["name"] for m in gone}
    man = [m for m in man if m["name"] not in dropped]

    # Sweep up category folders that lost every scene.
    for bucket in ("vertical", "horizontal"):
        b = os.path.join(OUT, bucket)
        for cat in os.listdir(b) if os.path.isdir(b) else []:
            d = os.path.join(b, cat)
            if os.path.isdir(d) and not os.listdir(d):
                os.rmdir(d)

    with open(man_path, "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1)
    write_readme(man)
    gallery()

    log(f"\npruned {len(gone)}, {len(man)} scenes remain "
        f"({sum(m['out_bytes'] for m in man) / 1e6:.0f} MB)")
    for bucket in ("vertical", "horizontal"):
        for tab in sorted({m["tab"] for m in man if m["bucket"] == bucket}):
            s = [m for m in man if m["bucket"] == bucket and m["tab"] == tab]
            clips = sum(1 for m in s if m["kind"] == "video")
            flag = "  <- thin" if len(s) < 20 else ""
            log(f"  {bucket:11}/{tab:11} {len(s):3}  "
                f"({len(s) - clips} stills, {clips} clips){flag}")


def clean():
    """Drop the candidate pool once the library is built. Everything that
    made the cut already exists twice over -- framed under its tab folder
    and untouched under _originals/ -- so this only deletes the rejects.
    Re-running `fetch` rebuilds it from candidates.json if needed."""
    raw = os.path.join(WORK, "raw")
    if not os.path.isdir(raw):
        log("nothing to clean")
        return
    n = sum(len(f) for _, _, f in os.walk(raw))
    size = sum(os.path.getsize(os.path.join(d, f))
               for d, _, fs in os.walk(raw) for f in fs)
    shutil.rmtree(raw)
    log(f"removed {n} candidate files ({size / 1e9:.1f} GB) from {raw}")


def write_readme(man):
    def rows(bucket):
        tabs = sorted({m["tab"] for m in man if m["bucket"] == bucket})
        out = []
        for t in tabs:
            sub = [m for m in man if m["bucket"] == bucket and m["tab"] == t]
            cats = ", ".join(sorted({m["category"] for m in sub}))
            out.append(f"| **{t}** | {cats} "
                       f"| {sum(1 for m in sub if m['kind'] == 'image')} "
                       f"| {sum(1 for m in sub if m['kind'] == 'video')} "
                       f"| {sum(m['out_bytes'] for m in sub) / 1e6:.0f} MB "
                       f"| {max(m['score'] for m in sub):.0f} |")
        return "\n".join(out)

    v = [m for m in man if m["bucket"] == "vertical"]
    h = [m for m in man if m["bucket"] == "horizontal"]
    txt = f"""# Ayah Reels — scene library

{len(man)} scenes, {sum(m['out_bytes'] for m in man) / 1e6:.0f} MB.
Open `_review/index.html` in a browser to go through them: it puts the
app's real scrim and a real verse over each one, which is the only
honest way to judge whether a background can carry text.

## Layout

    vertical/<category>/     1080x1920, ready to drop into assets/backgrounds/
    horizontal/<category>/   1920x1080, letterboxed under the verse
    _originals/              the untouched download behind every file above
    _review/                 index.html, thumbs/, MANIFEST.json

Everything under `vertical/` and `horizontal/` is already framed the way
the exporter frames it (fill, centre-crop, EXIF baked in, metadata
stripped) so a scene can move into the app unchanged. `_originals/`
keeps the full frame in case a different crop is wanted later.

## vertical — {len(v)} scenes, verse drawn on top

Scored on readability with the scrim applied: how bright the middle of
the frame is, how hot its brightest patches are, and how busy the
detail is. 100 is a calm dark frame; anything under 55 was dropped.

| tab | folders it merges | stills | clips | size | best |
|---|---|---|---|---|---|
{rows('vertical')}

## horizontal — {len(h)} scenes, verse below the frame

Nothing is written over these, so they are free to be bright and
colourful; they are scored on detail and tonal range instead.

| tab | folders it merges | stills | clips | size | best |
|---|---|---|---|---|---|
{rows('horizontal')}

## Where they came from

{chr(10).join(f'- {s}: {sum(1 for m in man if m["source"] == s)}'
              for s in sorted({m['source'] for m in man}))}

`MANIFEST.json` carries, per scene: its score and the measurements
behind it, the `grad` pair (top/bottom average colour, which is what
`gradientArgb` in `lib/data/fatiha_data.dart` wants), duration for
clips, and a link back to the original page.

Regenerate with `python tool/harvest_scenes.py discover|fetch` then
`python tool/curate_scenes.py score|build|gallery`.
"""
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8") as f:
        f.write(txt)


def gallery():
    """A self-contained review page. The point of it is the preview: it
    puts the app's real scrim and a real verse on top of the real asset,
    because 'is this dark enough' is not a question a thumbnail can
    answer."""
    with open(os.path.join(REVIEW, "MANIFEST.json"), encoding="utf-8") as f:
        man = json.load(f)
    data = json.dumps(man, separators=(",", ":"))
    html = GALLERY_HTML.replace("/*__DATA__*/", data)
    dest = os.path.join(REVIEW, "index.html")
    with open(dest, "w", encoding="utf-8") as f:
        f.write(html)
    font = os.path.join(ROOT, "assets", "fonts", "UthmanicHafs.ttf")
    if os.path.exists(font):
        shutil.copyfile(font, os.path.join(REVIEW, "UthmanicHafs.ttf"))
    log(f"gallery -> {dest}  ({len(man)} scenes)")


GALLERY_HTML = r"""<!doctype html>
<meta charset="utf-8">
<title>Ayah Reels — scene library review</title>
<style>
 @font-face { font-family: Hafs; src: url("UthmanicHafs.ttf"); }
 :root{--bg:#0b0d10;--card:#14171c;--line:#252a32;--txt:#e8eaee;--dim:#8b93a1;
       --gold:#d8b26a;--ok:#3ddc84;--no:#ff5a5a}
 *{box-sizing:border-box}
 body{margin:0;background:var(--bg);color:var(--txt);
      font:14px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}
 header{position:sticky;top:0;z-index:9;background:rgba(11,13,16,.94);
        backdrop-filter:blur(12px);border-bottom:1px solid var(--line);
        padding:14px 20px}
 h1{margin:0 0 10px;font-size:16px;font-weight:600;letter-spacing:.2px}
 h1 span{color:var(--dim);font-weight:400}
 .row{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-top:8px}
 .chip{padding:5px 12px;border:1px solid var(--line);border-radius:999px;
       background:var(--card);color:var(--dim);cursor:pointer;font-size:12.5px;
       user-select:none;white-space:nowrap}
 .chip:hover{border-color:#3a4150;color:var(--txt)}
 .chip.on{background:var(--gold);border-color:var(--gold);color:#1a1408;font-weight:600}
 .grid{display:grid;gap:12px;padding:18px 20px 60px;
       grid-template-columns:repeat(auto-fill,minmax(150px,1fr))}
 .grid.h{grid-template-columns:repeat(auto-fill,minmax(260px,1fr))}
 .card{position:relative;border:1px solid var(--line);border-radius:12px;
       overflow:hidden;background:var(--card);cursor:pointer;aspect-ratio:9/16}
 .grid.h .card{aspect-ratio:16/9}
 .card img{width:100%;height:100%;object-fit:cover;display:block}
 .card.rej{opacity:.28}
 .card.rej:after{content:"✕";position:absolute;inset:0;display:grid;
                 place-items:center;font-size:40px;color:var(--no)}
 .meta{position:absolute;left:0;right:0;bottom:0;padding:16px 8px 6px;
       background:linear-gradient(transparent,rgba(0,0,0,.85));font-size:11px}
 .meta b{font-weight:600}
 .meta i{font-style:normal;color:var(--dim)}
 .badge{position:absolute;top:6px;left:6px;padding:2px 7px;border-radius:6px;
        font-size:10.5px;font-weight:700;background:rgba(0,0,0,.6)}
 .clip{position:absolute;top:6px;right:6px;padding:2px 7px;border-radius:6px;
       font-size:10.5px;background:rgba(0,0,0,.6);color:var(--gold)}
 /* preview */
 #lb{position:fixed;inset:0;background:rgba(4,5,7,.96);z-index:20;display:none;
     grid-template-columns:1fr 300px}
 #lb.open{display:grid}
 #stage{display:grid;place-items:center;padding:24px;overflow:auto}
 #phone{position:relative;height:min(86vh,860px);aspect-ratio:9/16;
        border-radius:22px;overflow:hidden;background:#000;
        box-shadow:0 24px 80px rgba(0,0,0,.7)}
 #phone .bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
 /* horizontal scenes letterbox into the 9:16 canvas, verse underneath */
 #phone.letter .bg{top:14%;height:auto;bottom:auto;object-fit:contain}
 #scrim{position:absolute;inset:0;
        background:linear-gradient(rgba(0,0,0,.15),rgba(0,0,0,.45))}
 #verse{position:absolute;left:0;right:0;top:50%;transform:translateY(-50%);
        padding:0 9%;text-align:center;color:#fff;
        text-shadow:0 2px 18px rgba(0,0,0,.55)}
 #phone.letter #verse{top:auto;bottom:9%;transform:none}
 #ar{font-family:Hafs,serif;font-size:30px;line-height:2.05;direction:rtl}
 #en{margin-top:16px;font-size:14px;color:#e4d9c2;line-height:1.6}
 #side{border-left:1px solid var(--line);padding:20px;overflow:auto;
       background:var(--card)}
 #side h2{font-size:14px;margin:0 0 4px}
 #side dl{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;
          font-size:12.5px;margin:14px 0}
 #side dt{color:var(--dim)}
 #side a{color:var(--gold)}
 .btn{display:block;width:100%;margin-top:8px;padding:10px;border-radius:10px;
      border:1px solid var(--line);background:#1b1f26;color:var(--txt);
      cursor:pointer;font-size:13px}
 .btn.no{border-color:#5a2626;color:#ff8f8f}
 .btn.yes{border-color:#245c3d;color:#7ff0b4}
 .hint{color:var(--dim);font-size:11.5px;margin-top:14px;line-height:1.6}
 textarea{width:100%;height:110px;background:#0d1014;color:var(--dim);
          border:1px solid var(--line);border-radius:8px;font-size:11px;padding:8px}
</style>

<header>
  <h1>Scene library review <span id="count"></span></h1>
  <div class="row" id="buckets"></div>
  <div class="row" id="cats"></div>
  <div class="row">
    <span class="chip" data-act="kind" data-v="all">all types</span>
    <span class="chip" data-act="kind" data-v="image">stills</span>
    <span class="chip" data-act="kind" data-v="video">clips</span>
    <span style="width:16px"></span>
    <span class="chip" data-act="sort" data-v="score">best first</span>
    <span class="chip" data-act="sort" data-v="cat">by tab</span>
    <span style="width:16px"></span>
    <span class="chip" data-act="hide">hide rejected</span>
    <span class="chip on" data-act="verse">verse preview</span>
    <span class="chip" data-act="export">export decisions</span>
  </div>
</header>
<div class="grid" id="grid"></div>

<div id="lb">
  <div id="stage"><div id="phone">
    <img class="bg" id="pimg"><video class="bg" id="pvid" muted loop autoplay playsinline preload="auto"></video>
    <div id="scrim"></div>
    <div id="verse">
      <div id="ar">وَهُوَ ٱلَّذِى يُرْسِلُ ٱلرِّيَـٰحَ بُشْرًۢا بَيْنَ يَدَىْ رَحْمَتِهِۦ</div>
      <div id="en">And it is He who sends the winds as good tidings before His mercy.</div>
    </div>
  </div></div>
  <div id="side">
    <h2 id="sname"></h2>
    <dl id="sdl"></dl>
    <button class="btn yes" data-k="1">Keep &nbsp;<b>K</b></button>
    <button class="btn no"  data-k="0">Reject &nbsp;<b>X</b></button>
    <button class="btn" id="close">Close &nbsp;<b>Esc</b></button>
    <p class="hint">← → move through the library, <b>K</b>/<b>X</b> to keep or
      reject. The scrim and verse are drawn live here, not baked into the
      file — toggle "verse preview" off for the bare frame. Files are already
      cropped to the reel frame; the full uncropped source of every one is
      under <code>_originals/</code>.</p>
    <textarea id="dump" readonly></textarea>
  </div>
</div>

<script>
const DATA = /*__DATA__*/;
const S = {bucket:'vertical', tab:'all', kind:'all', sort:'score', hide:false, verse:true, i:-1};
const dec = JSON.parse(localStorage.getItem('ayah_scene_decisions')||'{}');
const save = ()=>localStorage.setItem('ayah_scene_decisions',JSON.stringify(dec));
const $ = s=>document.querySelector(s);

function view(){
  let v = DATA.filter(d=>d.bucket===S.bucket
      && (S.tab==='all'||d.tab===S.tab)
      && (S.kind==='all'||d.kind===S.kind)
      && (!S.hide||dec[d.name]!==0));
  v.sort(S.sort==='score' ? (a,b)=>b.score-a.score
    : (a,b)=>a.tab.localeCompare(b.tab)||a.category.localeCompare(b.category)||b.score-a.score);
  return v;
}

function chips(){
  $('#buckets').innerHTML = ['vertical','horizontal'].map(b=>{
    const n = DATA.filter(d=>d.bucket===b).length;
    return `<span class="chip ${S.bucket===b?'on':''}" data-act="bucket" data-v="${b}">
      ${b==='vertical'?'▮ vertical (verse on top)':'▬ horizontal (letterbox)'} ${n}</span>`;
  }).join('');
  // These chips are the picker's tabs, so the review screen and the app
  // agree on how the library is carved up.
  const tabs = [...new Set(DATA.filter(d=>d.bucket===S.bucket).map(d=>d.tab))].sort();
  $('#cats').innerHTML = `<span class="chip ${S.tab==='all'?'on':''}" data-act="tab" data-v="all">all</span>`
    + tabs.map(c=>`<span class="chip ${S.tab===c?'on':''}" data-act="tab" data-v="${c}">
        ${c} <i style="opacity:.6">${DATA.filter(d=>d.bucket===S.bucket&&d.tab===c).length}</i></span>`).join('');
  document.querySelectorAll('[data-act]').forEach(el=>{
    const a = el.dataset.act;
    if(['kind','sort'].includes(a)) el.classList.toggle('on', S[a]===el.dataset.v);
    if(a==='hide') el.classList.toggle('on', S.hide);
    if(a==='verse') el.classList.toggle('on', S.verse);
  });
}

function render(){
  chips();
  const v = view();
  const rej = Object.values(dec).filter(x=>x===0).length;
  $('#count').textContent = `— ${DATA.length} scenes, ${v.length} shown, ${rej} rejected`;
  $('#grid').className = 'grid' + (S.bucket==='horizontal'?' h':'');
  $('#grid').innerHTML = v.map((d,i)=>`
    <div class="card ${dec[d.name]===0?'rej':''}" data-i="${i}">
      <img loading="lazy" src="thumbs/${d.name}.jpg">
      <span class="badge" style="color:${d.score>75?'#7ff0b4':d.score>62?'#d8b26a':'#ff9d6e'}">${Math.round(d.score)}</span>
      ${d.kind==='video'?`<span class="clip">▶ ${d.dur}s</span>`:''}
      <div class="meta"><b>${d.tab}</b> <i>${d.category.replace(/_/g,' ')}</i></div>
    </div>`).join('');
}

function open(i){
  const v = view(); if(i<0||i>=v.length) return;
  S.i = i; const d = v[i];
  $('#lb').classList.add('open');
  $('#phone').classList.toggle('letter', d.bucket==='horizontal');
  const img=$('#pimg'), vid=$('#pvid');
  if(d.kind==='image'){ img.style.display=''; vid.style.display='none'; vid.pause();
    img.src="../"+d.out; }
  else { img.style.display='none'; vid.style.display=''; vid.src="../"+d.out;
    // Autoplay is refused until the page has been interacted with; the
    // frame still shows, and clicking the preview starts it.
    vid.play().catch(()=>{}); }
  $('#sname').textContent = d.name;
  $('#sdl').innerHTML = Object.entries({
    score:Math.round(d.score), tab:d.tab, category:d.category, type:d.kind,
    ...(d.dur?{duration:d.dur+'s'}:{}),
    size:(d.out_bytes/1e6).toFixed(2)+' MB', source:d.source,
    ...(d.detail||{})
  }).map(([k,x])=>`<dt>${k}</dt><dd>${x}</dd>`).join('')
    + (d.page?`<dt>link</dt><dd><a href="${d.page}" target="_blank">original</a></dd>`:'');
}

function decide(keep){
  const d = view()[S.i]; if(!d) return;
  dec[d.name] = keep; save(); render(); open(Math.min(S.i, view().length-1));
}

document.addEventListener('click', e=>{
  const chip = e.target.closest('[data-act]');
  if(chip){ const a=chip.dataset.act;
    if(a==='hide') S.hide=!S.hide;
    else if(a==='verse'){ S.verse=!S.verse;
      $('#scrim').style.display = S.verse?'':'none';
      $('#verse').style.display = S.verse?'':'none'; }
    else if(a==='export'){
      const keep = DATA.filter(d=>dec[d.name]!==0).map(d=>d.name);
      $('#dump').value = JSON.stringify({rejected:Object.keys(dec).filter(k=>dec[k]===0),
                                         kept:keep.length}, null, 1);
      $('#lb').classList.add('open'); $('#dump').select();
    }
    else { S[a]=chip.dataset.v; if(a==='bucket') S.tab='all'; }
    render(); return; }
  const card = e.target.closest('.card');
  if(card) open(+card.dataset.i);
  const btn = e.target.closest('[data-k]');
  if(btn) decide(+btn.dataset.k);
  if(e.target.id==='close'||e.target.id==='lb') $('#lb').classList.remove('open');
  if(e.target.id==='pvid'){ const v=$('#pvid'); v.paused ? v.play().catch(()=>{}) : v.pause(); }
});
document.addEventListener('keydown', e=>{
  if(!$('#lb').classList.contains('open')) return;
  if(e.key==='Escape') $('#lb').classList.remove('open');
  if(e.key==='ArrowRight') open(S.i+1);
  if(e.key==='ArrowLeft') open(S.i-1);
  if(e.key.toLowerCase()==='k') decide(1);
  if(e.key.toLowerCase()==='x') decide(0);
});
render();
</script>
"""


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "score"
    {"score": score_all, "build": build, "gallery": gallery,
     "sync": sync, "recode": recode, "clean": clean}[cmd]()
