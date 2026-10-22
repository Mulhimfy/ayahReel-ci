"""Choose the new sceneries from a harvested pool and write the review page.

    python tool/select_new_scenes.py <pool dir> <out dir> [--sheets]

The pool is what tool/harvest_new_scenes.py publishes from the CI
mirror (unpack scenes-pool.tar.gz): every candidate that cleared the
library's floor, with its measurements, detections, CLIP embeddings and
a poster, plus the existing library's hashes and embeddings. This step
needs only numpy and Pillow, so the thresholds below can be tuned and
re-run in seconds, anywhere.

Writes into <out dir>:

    new_sceneries.json   every chosen scene: proposed id, tab, shape,
                         source page, direct media URL, licence, author,
                         sizes, duration, score, gradient
    new_sceneries.html   one self-contained page with every poster
    rejected.json        what was left out, and why
    sheets/              (--sheets) contact sheets of each rejection
                         reason, for checking the thresholds by eye
"""

import base64
import collections
import html as htmlmod
import io
import json
import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FLOOR = {"vertical": 62.0, "horizontal": 68.0}  # curate_scenes.FLOOR
TAB_ORDER = ["sky", "mountains", "desert", "water", "forest", "road", "sacred",
             "abstract", "aerial", "cinematic"]
WIDE_TABS = {"aerial", "cinematic"}

# ── what may not be in the picture ──────────────────────────────────────
# Detector classes (COCO names) -> (min confidence, min share of the frame).
# A person is out at any size: the rule is "no people", and a hiker on a
# ridge is the subject of the photo however small.
DET_RULES = {
    "person": (0.30, 0.0),
    "animal": (0.35, 0.004),
    "bird": (0.45, 0.02),
    "vehicle": (0.35, 0.03),
    "boat": (0.40, 0.10),
    "drink": (0.35, 0.0),
    "gear": (0.50, 0.0),
    "indoor": (0.40, 0.02),
}
DET_CLASS = {
    **{k: "animal" for k in ("dog", "cat", "horse", "sheep", "cow", "elephant", "bear",
                             "zebra", "giraffe")},
    "bird": "bird",
    **{k: "vehicle" for k in ("car", "truck", "bus", "motorcycle", "bicycle", "train",
                              "airplane")},
    "boat": "boat",
    **{k: "drink" for k in ("wine glass", "bottle", "cup")},
    # Things people carry or wear: where they are, a person is. Not "sports
    # ball", "frisbee" or "kite": the detector calls a full moon a ball and
    # a bird against the sky a kite.
    **{k: "gear" for k in ("umbrella", "handbag", "backpack", "suitcase", "tie",
                           "skis", "snowboard", "surfboard", "skateboard",
                           "tennis racket", "baseball bat", "baseball glove", "cell phone",
                           "laptop", "tv", "keyboard", "remote", "book")},
    **{k: "indoor" for k in ("chair", "couch", "bed", "dining table", "toilet", "sink",
                             "refrigerator", "oven", "microwave", "potted plant")},
    "person": "person",
}
# Roads carry traffic and farmland has a tractor in it; there a vehicle is
# only a problem when it fills the frame.
VEHICLE_SHARE = {"road": 0.08, "aerial": 0.06, "cinematic": 0.05}

# CLIP: probability of each "bad:" prompt group, softmaxed against the
# candidate's own tab prompts. The worse of the two crops counts.
CLIP_BAD = {
    "people": 0.40, "religion": 0.25, "vice": 0.30, "music": 0.30, "nudity": 0.25,
    "text": 0.40, "art": 0.45, "offtopic": 0.50,
}
CLIP_BAD_TAB = {("abstract", "art"): 0.70, ("abstract", "offtopic"): 0.65}
CLIP_TAB_MIN = 0.12        # the tab's own prompts, against the bad groups
# On topic: the tab's share among every tab's prompts (mean of the two
# crops). A starry sky over dunes is desert at 0.5-0.99, the same sky over
# a tree is under 0.1. Cinematic is any landscape, so it counts the
# landscape tabs together; sacred has to look sacred outright.
ON_TOPIC = {
    "cinematic": ({"cinematic", "sky", "mountains", "desert", "water", "forest", "aerial"}, 0.60),
    "sacred": ({"sacred"}, 0.45),
}
ON_TOPIC_MIN = 0.20
# A picture a query filed under the wrong tab moves to the tab it plainly
# shows (same shape only) when that tab holds this share of it.
RETAB_MIN = 0.50

# Which category (scene family) each tab prompt pictures, so a moved
# picture gets the family the verse matcher should find it by. Must match
# the prompt texts in harvest_new_scenes.PROMPTS.
PROMPT_CATEGORY = {
    "the northern lights in the sky": "aurora", "an aurora over mountains": "aurora",
    "dramatic clouds at dusk": "clouds", "dark storm clouds": "clouds",
    "clouds seen from above": "clouds",
    "a rocky canyon": "rock", "a cliff face": "rock",
    "a glacier": "snow", "a frozen winter landscape": "snow", "a snowy mountain peak": "snow",
    "the ocean at night": "ocean", "dark ocean waves": "ocean", "a calm sea at dusk": "ocean",
    "moonlight reflecting on the sea": "ocean", "a stormy sea": "ocean",
    "rain drops on a window": "rain", "rain falling on water": "rain",
    "a lone tree in a field": "field", "a wheat field at dusk": "field",
    "a grassy meadow in fog": "field", "rolling green hills": "field",
    "palm trees in a grove": "field",
    "an aerial view of mountains": "aerial_mountain",
    "a drone shot of a coastline": "aerial_coast", "an aerial view of ocean waves": "aerial_coast",
    "an aerial view of a forest": "aerial_forest", "an aerial view of desert dunes": "aerial_desert",
    "an aerial view of a river": "aerial_water", "an aerial view of a waterfall": "aerial_water",
    "an aerial view of a lake": "aerial_water", "an aerial view of farmland": "aerial_land",
    "an aerial view of rice terraces": "aerial_land",
    "a top-down view of a landscape": "aerial_land",
}
TAB_DEFAULT_CATEGORY = {"sky": "sky", "mountains": "mountains", "desert": "desert",
                        "water": "water", "forest": "forest", "road": "road",
                        "sacred": "sacred", "abstract": "abstract", "aerial": "aerial_land",
                        "cinematic": "cinematic"}

# Solid black bands: a frame whose top or bottom fifth, or a run of whole
# columns, is flat black puts the verse over a blank slab. That is why
# sacred_pixabay_03 was withdrawn on 2026-09-04; it is measured here on
# the poster.
BAND_SHARE, BAND_LUMA, BAND_STD = 0.20, 7.0, 3.0

# Near-duplicates, judged on the same pair of pictures by two measures.
# dHash alone is not enough here: dark, smooth frames share most of its
# bits (an orange sunset and a dark rain frame measured 1 bit apart), and
# CLIP alone puts two different full moons at 0.93. Calibrated by eye on
# candidate/library pairs: the same photo shows as CLIP >= 0.90 with
# dHash <= 10, or CLIP >= 0.95 whatever the crop did to the hash.
PAIR_COS, PAIR_HAM, SAME_COS = 0.90, 10, 0.95

# A portrait clip's later frames have to stay near the floor too.
LATE_SLACK = 8.0
# Largest cover-crop upscale accepted for a still (Pixabay's 1280-px
# edition of a portrait photo needs 1.5 for a 1080x1920 frame).
MAX_UPSCALE = 1.6

LICENSES = {
    "pexels": ("Pexels License", "https://www.pexels.com/license/"),
    "pixabay": ("Pixabay Content License", "https://pixabay.com/service/license-summary/"),
    "mixkit": ("Mixkit Stock Video Free License", "https://mixkit.co/license/#videoFree"),
    "cc0": ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
    "pdm": ("Public Domain Mark 1.0", "https://creativecommons.org/publicdomain/mark/1.0/"),
    "pd": ("Public domain", "https://commons.wikimedia.org/wiki/Commons:Licensing"),
}


def log(*a):
    print(*a, flush=True)


def norm(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-9)


def hamming(a, b):
    return bin(int(a) ^ int(b)).count("1")


# ── load ────────────────────────────────────────────────────────────────

def load(pool):
    cands = json.load(open(os.path.join(pool, "candidates.json"), encoding="utf-8"))
    emb = np.load(os.path.join(pool, "emb.npy")).astype(np.float32)
    prompts = json.load(open(os.path.join(pool, "prompts.json")))
    pemb = np.load(os.path.join(pool, "prompt_emb.npy")).astype(np.float32)
    lib = json.load(open(os.path.join(pool, "library.json")))
    lemb = np.load(os.path.join(pool, "library_emb.npy")).astype(np.float32)
    return cands, norm(emb), prompts, norm(pemb), lib, norm(lemb)


def existing_ids():
    """Every id the app has used: the catalog plus the withdrawn set in
    scene_catalog.dart, whose ids must never come back (a patch filters
    them by id, and a device may hold a cached file under that name)."""
    cat = json.load(open(os.path.join(ROOT, "assets", "catalog.json"), encoding="utf-8"))
    ids = {s["id"] for s in cat["scenes"]}
    dart = open(os.path.join(ROOT, "lib", "data", "scene_catalog.dart"), encoding="utf-8").read()
    m = re.search(r"withdrawn\s*=\s*<String>\{(.*?)\};", dart, re.S)
    if m:
        ids |= set(re.findall(r"'([a-z0-9_]+)'", m.group(1)))
    return ids, cat


# ── judging ─────────────────────────────────────────────────────────────

def clip_groups(emb2, prompts, pemb, tab):
    """(tab fit, {bad group: prob}, {tab: share}) for one candidate.

    fit: the tab's own prompts against the "bad:" groups, so a picture of
    something that must not be there loses to them. share: every tab's
    portion of the probability over all tabs' prompts, which says what the
    picture is of. Both are softmaxes at CLIP's own logit scale."""
    groups = prompts["groups"]
    scale = prompts.get("logit_scale", 100.0)
    idx_tab = [i for i, g in enumerate(groups) if g == f"tab:{tab}"]
    idx_bad = [i for i, g in enumerate(groups) if g.startswith("bad:")]
    act = idx_tab + idx_bad
    lg = scale * emb2 @ pemb[act].T                     # (2, A)
    p = np.exp(lg - lg.max(axis=1, keepdims=True))
    p /= p.sum(axis=1, keepdims=True)
    fit = float(p[:, :len(idx_tab)].sum(axis=1).mean())
    bad = {}
    for j, i in enumerate(idx_bad):
        g = groups[i][4:]
        bad[g] = bad.get(g, np.zeros(2)) + p[:, len(idx_tab) + j]
    bad = {g: float(v.max()) for g, v in bad.items()}
    idx_all = [i for i, g in enumerate(groups) if g.startswith("tab:")]
    lg2 = scale * emb2 @ pemb[idx_all].T
    q = np.exp(lg2 - lg2.max(axis=1, keepdims=True))
    q /= q.sum(axis=1, keepdims=True)
    share = collections.defaultdict(float)
    for k, i in enumerate(idx_all):
        share[groups[i][4:]] += float(q[:, k].mean())
    return fit, bad, dict(share)


def on_topic(tab, share):
    tabs, need = ON_TOPIC.get(tab, ({tab}, ON_TOPIC_MIN))
    return sum(share.get(t, 0.0) for t in tabs), need


def best_category(emb2, prompts, pemb, tab):
    """The family a picture belongs to within `tab`, from its closest prompt."""
    if tab == "cinematic":
        return "cinematic"
    groups, texts = prompts["groups"], prompts["texts"]
    idx = [i for i, g in enumerate(groups) if g == f"tab:{tab}"]
    sims = (emb2 @ pemb[idx].T).mean(axis=0)
    text = texts[idx[int(sims.argmax())]]
    return PROMPT_CATEGORY.get(text, TAB_DEFAULT_CATEGORY[tab])


def black_band(pool, c):
    """True for a black slab with a straight edge under or over a lit
    picture, or for black strips down a fifth of its width.

    A picture that is dark all over (a moon on black, a night sky) is not
    this: the library has many and they read well. Nor is a silhouette,
    whose edge wanders; the slab's edge is ruler-straight."""
    p = os.path.join(pool, "posters", c["file_key"] + ".jpg")
    try:
        a = np.asarray(Image.open(p).convert("L"), dtype=float)
    except Exception:
        return False
    h, w = a.shape
    flat = (a.mean(axis=0) < BAND_LUMA) & (a.std(axis=0) < BAND_STD)
    if flat.mean() >= BAND_SHARE and a.mean() > 18:
        return True
    if a.mean() < 18:
        return False
    for arr in (a, a[::-1]):                 # slab at the bottom, then the top
        lit = arr[::-1] > 20                 # row 0 is the edge row
        first = np.where(lit.any(axis=0), lit.argmax(axis=0), h)
        if np.median(first) >= BAND_SHARE * h and first.std() <= 0.02 * h:
            return True
    return False


def det_reason(c):
    for name, conf, area in c.get("det") or []:
        kind = DET_CLASS.get(name)
        if not kind:
            continue
        mc, ma = DET_RULES[kind]
        if kind == "vehicle":
            ma = VEHICLE_SHARE.get(c["tab"], ma)
        if conf >= mc and area >= ma:
            return f"detected:{kind}"
    return None


def upscale(c):
    """How far the still has to be enlarged to cover the frame, from the
    size of the file that would actually be fetched."""
    fw, fh = (1080, 1920) if c["bucket"] == "vertical" else (1920, 1080)
    w, h = c.get("w") or 0, c.get("h") or 0
    if c["kind"] == "video":
        mi = c.get("media_info") or {}
        w, h = mi.get("w") or w, mi.get("h") or h
    elif c["source"] == "pixabay" and w and h:
        edge = 1920 if (c.get("media") or "").endswith("_1920.jpg") else 1280
        k = edge / max(w, h)          # the edition that would be fetched
        w, h = w * min(k, 1), h * min(k, 1)
    elif c["source"] == "pexels" and w and h:
        k = 2400 / (h if c["bucket"] == "vertical" else w)
        w, h = w * min(k, 1), h * min(k, 1)
    elif c.get("fetched"):
        w, h = c["fetched"]
    if not w or not h:
        return 9.9
    return max(fw / w, fh / h)


def judge(c, emb2, prompts, pemb, pool):
    r = det_reason(c)
    if r:
        return r
    if black_band(pool, c):
        return "black-band"
    tab = c["tab"]
    fit, bad, share = clip_groups(emb2, prompts, pemb, tab)
    topic, need = on_topic(tab, share)
    if topic < need:
        # Filed under the wrong tab by its query: move it where it plainly
        # belongs, if that tab has the same shape, and judge it there.
        wide = tab in WIDE_TABS
        others = [t for t in TAB_ORDER if t != tab and (t in WIDE_TABS) == wide]
        scored = sorted(((on_topic(t, share)[0] / on_topic(t, share)[1], t) for t in others),
                        reverse=True)
        if scored:
            ratio, t = scored[0]
            single = share.get(t, 0.0)
            if ratio >= 1.0 and (t == "cinematic" or single >= RETAB_MIN):
                c["retab_from"] = f"{tab}/{c['category']}"
                c["tab"], tab = t, t
                c["category"] = best_category(emb2, prompts, pemb, t)
                fit, bad, share = clip_groups(emb2, prompts, pemb, tab)
                topic, need = on_topic(tab, share)
    c["clip"] = {"fit": round(fit, 3), "topic": round(topic, 3),
                 "looks_like": max(share, key=share.get),
                 **{k: round(v, 3) for k, v in bad.items()}}
    for g, thr in CLIP_BAD.items():
        thr = CLIP_BAD_TAB.get((tab, g), thr)
        if bad.get(g, 0) >= thr:
            return f"clip:{g}"
    if fit < CLIP_TAB_MIN:
        return "clip:off-tab"
    if topic < need:
        return "clip:other-tab"
    if c["kind"] == "video":
        late = c.get("late_scores") or []
        if c["bucket"] == "vertical" and late and min(late) < FLOOR["vertical"] - LATE_SLACK:
            return "late-frames"
        mi = c.get("media_info") or {}
        if not c.get("media"):
            return "no-full-size"
        if min(mi.get("w") or 0, mi.get("h") or 0) < 720:
            return "low-res"
        if (mi.get("streams") or 1) < 1:
            return "no-video"
    elif upscale(c) > MAX_UPSCALE:
        return "low-res"
    return None


# ── choosing ────────────────────────────────────────────────────────────

# Passes over the tabs, as multiples of what each tab holds today: first
# every tab doubles, then each may grow to 1.5x its size, and only if the
# whole is still short of TOTAL_GOAL do the tabs that have more good ones
# go on to 2x. Thin tabs never hold the rest back, and no tab runs away.
PASSES = (1.0, 1.5, 2.0)
TOTAL_GOAL = 1000


def targets(cat):
    """Today's size and clip share per tab. Clips keep roughly today's
    share; the wide tabs keep at least the curation's CLIP_QUOTA of 60%."""
    now = collections.Counter(s["tab"] for s in cat["scenes"])
    clips = collections.Counter(s["tab"] for s in cat["scenes"] if s["video"])
    out = {}
    for t in TAB_ORDER:
        n = now.get(t, 0)
        share = clips.get(t, 0) / n if n else 0.25
        if t in WIDE_TABS:
            share = max(share, 0.6)
        else:
            share = min(max(share, 0.15), 0.35)
        out[t] = {"now": n, "min": n, "max": int(round(n * PASSES[-1])),
                  "clip_share": round(share, 2)}
    return out


def select(cands, emb, lib, lemb, tg):
    """Best first within each tab, round-robin over its categories, clips up
    to their share first; near-duplicates of the library or of anything
    already chosen are skipped."""
    lmean = norm(lemb.mean(axis=1))
    lham = [int(x["dhash"]) for x in lib]
    chosen, kept_emb, kept_hash = [], [], []
    dup = collections.Counter()

    def hashes(c):
        return [int(h) for h in (c.get("dhashes") or [c["dhash"]])[:3]]

    def same(sims, other_hashes, hs):
        """Index of a picture that is the same as this one, or None."""
        for j in np.flatnonzero(sims >= PAIR_COS):
            if sims[j] >= SAME_COS or any(hamming(h, o) <= PAIR_HAM
                                         for h in hs for o in other_hashes(j)):
                return int(j)
        return None

    def is_dup(c):
        m = norm(emb[c["emb"]].mean(axis=0))
        hs = hashes(c)
        if len(lmean) and same(lmean @ m, lambda j: [lham[j]], hs) is not None:
            return "dup:library"
        if kept_emb and same(np.stack(kept_emb) @ m, lambda j: kept_hash[j], hs) is not None:
            return "dup:pool"
        return None

    def take(c):
        chosen.append(c)
        kept_emb.append(norm(emb[c["emb"]].mean(axis=0)))
        kept_hash.append(hashes(c))

    state = {}
    for tab in TAB_ORDER:
        pool = [c for c in cands if c["tab"] == tab and not c.get("reject")]
        by_cat = collections.defaultdict(list)
        for c in sorted(pool, key=lambda c: -c["score"]):
            by_cat[c["category"]].append(c)
        state[tab] = {"pool": pool, "by_cat": by_cat, "got": []}

    def fill(tab, limit, kinds):
        """Round-robin over the tab's categories, best first, until `limit`."""
        st = state[tab]
        got = st["got"]
        queues = {k: [c for c in v if c["kind"] in kinds and not c.get("taken")
                      and not c.get("reject")]
                  for k, v in st["by_cat"].items()}
        while len(got) < limit and any(queues.values()):
            progressed = False
            for cat in sorted(queues):
                if len(got) >= limit:
                    break
                while queues[cat]:
                    c = queues[cat].pop(0)
                    why = is_dup(c)
                    if why:
                        c["reject"] = why
                        dup[why] += 1
                        continue
                    c["taken"] = True
                    take(c)
                    got.append(c)
                    progressed = True
                    break
            if not progressed:
                break

    for k, mult in enumerate(PASSES):
        if k > 0 and mult > 1.5 and len(chosen) >= TOTAL_GOAL:
            break
        for tab in TAB_ORDER:
            t = tg[tab]
            limit = int(round(t["now"] * mult))
            clip_goal = int(round(limit * t["clip_share"]))
            have_clips = sum(1 for c in state[tab]["got"] if c["kind"] == "video")
            fill(tab, len(state[tab]["got"]) + max(0, clip_goal - have_clips), {"video"})
            fill(tab, limit, {"image"})
            fill(tab, limit, {"image", "video"})      # whichever has more left
        log(f"  pass {mult:.1f}x: {len(chosen)} chosen")
    for tab in TAB_ORDER:
        got = state[tab]["got"]
        n_clip = sum(1 for c in got if c["kind"] == "video")
        log(f"  {tab:10} {len(got):4} new  ({len(got) - n_clip} stills, {n_clip} clips; "
            f"today {tg[tab]['now']}, pool {len(state[tab]['pool'])})")
    for c in cands:
        if not c.get("taken") and not c.get("reject"):
            c["reject"] = "over-target"
    return chosen, dup


def assign_ids(chosen, used):
    """`<category>_<source>_<nn>`, numbered after the highest number the
    app has ever used for that category and source."""
    top = collections.Counter()
    for i in used:
        m = re.match(r"^(.*)_(\d+)$", i)
        if m:
            top[m.group(1)] = max(top[m.group(1)], int(m.group(2)))
    for c in sorted(chosen, key=lambda c: (TAB_ORDER.index(c["tab"]), c["category"],
                                           c["source"], -c["score"])):
        base = f"{c['category']}_{c['source']}"
        top[base] += 1
        c["id"] = f"{base}_{top[base]:02d}"
        assert c["id"] not in used
        used.add(c["id"])


def record(c):
    lic = c.get("lic") or c["source"]
    name, url = LICENSES.get(lic, (c.get("license_name") or lic, c.get("license_url")))
    if c["source"] in ("openverse", "commons") and c.get("license_url"):
        url = c["license_url"]
    mi = c.get("media_info") or {}
    media_size = [mi.get("w"), mi.get("h")] if c["kind"] == "video" else None
    return {
        "id": c["id"], "tab": c["tab"], "category": c["category"],
        "wide": c["bucket"] == "horizontal", "video": c["kind"] == "video",
        "ext": "mp4" if c["kind"] == "video" else "jpg",
        "source": c["source"], "provider": c.get("provider"),
        "source_key": c["key"], "source_id": c.get("src_id"),
        "page_url": c.get("page"), "media_url": c.get("media"),
        "license": {"name": name, "url": url},
        "author": c.get("author") or None, "author_url": c.get("author_url"),
        "title": (c.get("title") or c.get("alt") or "")[:160],
        "original_size": [c.get("w") or None, c.get("h") or None],
        "media_size": media_size,
        "duration": c.get("dur") if c["kind"] == "video" else None,
        "fps": mi.get("fps") if c["kind"] == "video" else None,
        "score": c["score"], "measure": c.get("detail"),
        "grad": c["grad"], "dhash": c["dhash"],
        "query": c.get("query"),
        "moved_from": c.get("retab_from"),
        "upscale": round(upscale(c), 2) if c["kind"] == "image" else None,
        "checks": c.get("clip"),
    }


# ── the page ────────────────────────────────────────────────────────────

def poster_uri(pool, c, size):
    p = os.path.join(pool, "posters", c["file_key"] + ".jpg")
    im = Image.open(p).convert("RGB").resize(size, Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, "JPEG", quality=70, optimize=True, progressive=True)
    return "data:image/jpeg;base64," + base64.b64encode(b.getvalue()).decode()


TAB_NAMES = {"sky": "Sky", "mountains": "Mountains", "desert": "Desert", "water": "Water",
             "forest": "Forest", "road": "Road", "sacred": "Sacred", "abstract": "Abstract",
             "aerial": "Aerial", "cinematic": "Cinematic"}
SOURCE_NAMES = {"pexels": "Pexels", "pixabay": "Pixabay", "mixkit": "Mixkit",
                "openverse": "Openverse", "commons": "Wikimedia Commons"}
LICENSE_SHORT = {"Pixabay Content License": "Pixabay License",
                 "Mixkit Stock Video Free License": "Mixkit Free License",
                 "CC0 1.0": "CC0", "Public Domain Mark 1.0": "Public Domain Mark"}


def esc(s):
    return htmlmod.escape(str(s or ""), quote=True)


def fmt(n):
    return f"{n:,}"


def mmss(sec):
    sec = int(round(sec or 0))
    return f"{sec // 60}:{sec % 60:02d}"


def card(r, uri):
    src = SOURCE_NAMES.get(r["source"], r["source"])
    if r["source"] == "openverse" and r.get("provider"):
        src = f"Openverse · {r['provider'].capitalize()}"
    who = f'<span class="by">by {esc(r["author"])}</span>' if r.get("author") else ""
    clip = (f'<span class="play" aria-label="clip, {mmss(r["duration"])}">'
            f'▶ {mmss(r["duration"])}</span>') if r["video"] else ""
    shape = "wide" if r["wide"] else "tall"
    return (
        f'<article class="card {shape}" data-id="{esc(r["id"])}" data-tab="{r["tab"]}" '
        f'data-shape="{shape}" data-kind="{"clip" if r["video"] else "still"}" '
        f'data-src="{r["source"]}">'
        f'<div class="pic"><img src="{uri}" alt="{esc(r["title"] or r["id"])}" '
        f'width="{213 if r["wide"] else 120}" height="{120 if r["wide"] else 213}" decoding="async">'
        f'<span class="veil" aria-hidden="true"><span class="ayah">وَهُوَ ٱلَّذِى يُرْسِلُ ٱلرِّيَـٰحَ</span></span>'
        f'<span class="score" title="Readability score (portrait) or detail score (wide); floor '
        f'{FLOOR["horizontal" if r["wide"] else "vertical"]:.0f}">{r["score"]:.0f}</span>{clip}</div>'
        f'<div class="meta"><code class="id">{esc(r["id"])}</code>'
        f'<span class="links"><a href="{esc(r["page_url"])}" target="_blank" rel="noopener">{esc(src)}</a>'
        f' · <a href="{esc(r["license"]["url"])}" target="_blank" rel="noopener" '
        f'title="{esc(r["license"]["name"])}">'
        f'{esc(LICENSE_SHORT.get(r["license"]["name"], r["license"]["name"]))}</a></span>{who}'
        f'<button type="button" class="drop" aria-pressed="false">Leave out</button></div></article>')


def write_page(pool, out, recs, by_id, stats):
    total = len(recs)
    lib_n = stats["library"]
    wide = sum(1 for r in recs if r["wide"])
    clips = sum(1 for r in recs if r["video"])
    srcs = collections.Counter(r["source"] for r in recs)
    lics = collections.Counter(r["license"]["name"] for r in recs)
    sections, tab_chips = [], []
    for t in TAB_ORDER:
        rs = [r for r in recs if r["tab"] == t]
        if not rs:
            continue
        nclip = sum(1 for r in rs if r["video"])
        now = stats["tabs"][t]["now"]
        cards = []
        for r in rs:
            size = (213, 120) if r["wide"] else (120, 213)
            cards.append(card(r, poster_uri(pool, by_id[r["id"]], size)))
        shape = "Wide, letterboxed, verse below" if t in WIDE_TABS else "Portrait, verse on the picture"
        sections.append(
            f'<section class="tab" id="{t}" data-tab="{t}">'
            f'<header class="tabhead"><h2>{TAB_NAMES[t]}</h2>'
            f'<p class="tabfacts"><span class="n" data-count="{t}">{fmt(len(rs))}</span> new'
            f' · {fmt(len(rs) - nclip)} stills · {fmt(nclip)} clips'
            f' · library {fmt(now)} → {fmt(now + len(rs))} · {shape}</p></header>'
            f'<div class="grid {"wide" if t in WIDE_TABS else "tall"}">{"".join(cards)}</div>'
            f'</section>')
        tab_chips.append(f'<button type="button" class="chip" data-filter="tab" data-value="{t}" '
                         f'aria-pressed="false">{TAB_NAMES[t]} <span>{fmt(len(rs))}</span></button>')
    src_chips = "".join(
        f'<button type="button" class="chip" data-filter="src" data-value="{s}" '
        f'aria-pressed="false">{SOURCE_NAMES.get(s, s)} <span>{fmt(n)}</span></button>'
        for s, n in srcs.most_common())
    lic_list = " · ".join(f"{esc(k)} {fmt(v)}" for k, v in lics.most_common())
    page = (PAGE
            .replace("{{TOTAL}}", fmt(total))
            .replace("{{LIB}}", fmt(lib_n))
            .replace("{{AFTER}}", fmt(lib_n + total))
            .replace("{{TALL}}", fmt(total - wide))
            .replace("{{WIDE}}", fmt(wide))
            .replace("{{STILLS}}", fmt(total - clips))
            .replace("{{CLIPS}}", fmt(clips))
            .replace("{{LICENSES}}", lic_list)
            .replace("{{TABCHIPS}}", "".join(tab_chips))
            .replace("{{SRCCHIPS}}", src_chips)
            .replace("{{SECTIONS}}", "\n".join(sections)))
    path = os.path.join(out, "new_sceneries.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(page)
    log(f"page -> {path} ({os.path.getsize(path) / 1e6:.1f} MB)")


PAGE = r"""<title>New AyahReel sceneries</title>
<meta name="claude:viewport-fit-sides" content="cover">
<meta name="description" content="Proposed new backgrounds for AyahReel, by picker tab, with source and licence for each.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Amiri&family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&family=Reem+Kufi:wght@500;600&display=swap">
<style>
/* Layout: a sticky filter band over one section per picker tab; posters
   sit in grids at the app's own shapes, 9:16 for the portrait tabs and
   16:9 for the letterboxed wide ones. */
:root {
  --bg: #eef1f5;
  --surface: #ffffff;
  --ink: #161b24;
  --muted: #5a6372;
  --line: #d9dfe8;
  --chip: #e3e8ef;
  --gold: #8a6a24;
  --gold-ink: #fffaf0;
  --gold-soft: #efe3c8;
  --over-bg: rgba(8, 10, 14, .66);
  --over-ink: #f4e2b8;
  --scrim-top: rgba(0, 0, 0, .15);
  --scrim-bottom: rgba(0, 0, 0, .45);
  --verse: #f2dfb2;
  --font-display: "Reem Kufi", "Segoe UI", system-ui, sans-serif;
  --font-body: "IBM Plex Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  --font-mono: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  --font-ar: "Amiri", "Noto Naskh Arabic", "Traditional Arabic", serif;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #0b0e13; --surface: #12161d; --ink: #e8ebf0; --muted: #8e97a6;
    --line: #232a35; --chip: #181d26; --gold: #d8b26a; --gold-ink: #1a1408;
    --gold-soft: #2b2416; color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --bg: #0b0e13; --surface: #12161d; --ink: #e8ebf0; --muted: #8e97a6;
  --line: #232a35; --chip: #181d26; --gold: #d8b26a; --gold-ink: #1a1408;
  --gold-soft: #2b2416; color-scheme: dark;
}
* { box-sizing: border-box; }
[hidden] { display: none !important; }
body {
  margin: 0; background: var(--bg); color: var(--ink);
  font: 15px/1.5 var(--font-body);
  padding-left: max(16px, env(safe-area-inset-left, 0px));
  padding-right: max(16px, env(safe-area-inset-right, 0px));
  padding-block: 0 48px;
}
body::before {
  content: ""; position: fixed; inset: 0 0 auto; height: env(safe-area-inset-top, 0px);
  z-index: 10; background: var(--bg);
}
a { color: var(--gold); text-decoration-thickness: 1px; text-underline-offset: 2px; }
:focus-visible { outline: 2px solid var(--gold); outline-offset: 2px; border-radius: 4px; }
.wrap { max-width: 1320px; margin: 0 auto; }
.intro { padding-block: 28px 8px; display: grid; gap: 10px; }
h1 {
  font: 600 clamp(28px, 4vw, 40px)/1.1 var(--font-display); margin: 0;
  letter-spacing: .01em; text-wrap: balance;
}
.lede { margin: 0; color: var(--muted); max-width: 68ch; }
.lede b { color: var(--ink); font-weight: 600; }
.figures { display: flex; flex-wrap: wrap; gap: 8px 28px; margin: 6px 0 0; padding: 0; list-style: none; }
.figures li { display: grid; min-width: 0; }
.figures b {
  font: 600 22px/1.2 var(--font-body); font-variant-numeric: tabular-nums; color: var(--ink);
}
.figures span { font-size: 12px; color: var(--muted); letter-spacing: .04em; text-transform: uppercase; }
.fine { font-size: 13px; color: var(--muted); margin: 0; max-width: 90ch; }
.bar {
  position: sticky; top: env(safe-area-inset-top, 0px); z-index: 5;
  background: var(--bg); border-bottom: 1px solid var(--line);
  padding-block: 10px; display: grid; gap: 8px; margin-top: 12px;
}
.row { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; min-width: 0; }
.row .label {
  font-size: 11px; letter-spacing: .08em; text-transform: uppercase; color: var(--muted);
  margin-right: 4px;
}
.chip {
  font: 500 13px/1 var(--font-body); color: var(--ink); background: var(--chip);
  border: 1px solid transparent; border-radius: 999px; padding: 7px 11px; cursor: pointer;
  font-variant-numeric: tabular-nums;
}
.chip span { color: var(--muted); font-weight: 400; margin-left: 2px; }
.chip:hover { border-color: var(--line); }
.chip[aria-pressed="true"] { background: var(--gold); color: var(--gold-ink); }
.chip[aria-pressed="true"] span { color: var(--gold-ink); opacity: .8; }
.sep { width: 1px; height: 20px; background: var(--line); margin-inline: 6px; }
.shown { margin-left: auto; font-size: 13px; color: var(--muted); font-variant-numeric: tabular-nums; }
.tab { padding-block: 26px 4px; content-visibility: auto; contain-intrinsic-size: auto 900px; }
.tabhead { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 14px; margin-bottom: 12px; }
h2 { font: 600 24px/1.2 var(--font-display); margin: 0; }
.tabfacts { margin: 0; color: var(--muted); font-size: 13.5px; font-variant-numeric: tabular-nums; }
.tabfacts .n { color: var(--ink); font-weight: 600; }
.grid { display: grid; gap: 14px 10px; }
.grid.tall { grid-template-columns: repeat(auto-fill, minmax(136px, 1fr)); }
.grid.wide { grid-template-columns: repeat(auto-fill, minmax(232px, 1fr)); }
.card { display: grid; gap: 6px; min-width: 0; }
.pic {
  position: relative; border-radius: 8px; overflow: hidden; background: var(--surface);
  max-width: 100%;
}
.card.tall .pic { aspect-ratio: 9 / 16; }
.card.wide .pic { aspect-ratio: 16 / 9; }
.pic img { display: block; width: 100%; height: 100%; object-fit: cover; }
.score, .play {
  position: absolute; top: 6px; padding: 2px 6px; border-radius: 5px;
  background: var(--over-bg); color: var(--over-ink);
  font: 500 11px/1.4 var(--font-mono); font-variant-numeric: tabular-nums;
}
.score { left: 6px; }
.play { right: 6px; }
.veil {
  position: absolute; inset: 0; display: none; place-items: center; padding: 0 8%;
  background: linear-gradient(var(--scrim-top), var(--scrim-bottom));
}
.ayah {
  font: 15px/1.9 var(--font-ar); color: var(--verse); direction: rtl; text-align: center;
  text-shadow: 0 1px 8px rgba(0, 0, 0, .55);
}
body.verse .card.tall .veil { display: grid; }
.meta { display: grid; gap: 2px; font-size: 12px; min-width: 0; }
.id { font: 500 11.5px/1.35 var(--font-mono); color: var(--ink); overflow-wrap: anywhere; }
.links { color: var(--muted); overflow-wrap: anywhere; }
.by { color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.drop {
  justify-self: start; font: 500 12px/1.4 var(--font-body); color: var(--muted);
  background: none; border: 0; padding: 2px 0; cursor: pointer;
  text-decoration: underline; text-decoration-color: var(--line); text-underline-offset: 3px;
}
.drop:hover { color: var(--ink); }
.card.out .pic { opacity: .3; }
.card.out .id { text-decoration: line-through; color: var(--muted); }
.card.out .drop { color: var(--gold); text-decoration-color: var(--gold); }
.marked { display: flex; flex-wrap: wrap; gap: 6px 10px; align-items: center; font-size: 13px; color: var(--muted); }
.marked button {
  font: 500 13px/1 var(--font-body); color: var(--ink); background: var(--chip);
  border: 1px solid var(--line); border-radius: 6px; padding: 7px 10px; cursor: pointer;
}
.marked textarea {
  width: min(100%, 520px); height: 90px; font: 12px/1.4 var(--font-mono);
  color: var(--ink); background: var(--surface); border: 1px solid var(--line); border-radius: 6px;
}
.empty { color: var(--muted); padding-block: 40px; text-align: center; }
@media (prefers-reduced-motion: no-preference) { .chip { transition: background-color .15s, color .15s; } }
@media (max-width: 520px) {
  .grid.tall { grid-template-columns: repeat(auto-fill, minmax(118px, 1fr)); }
  .figures b { font-size: 19px; }
  .shown { margin-left: 0; }
}
/* On a phone the filters would cover a third of the screen; there they
   scroll away with the page instead of following it. */
@media (max-width: 720px) {
  .bar { position: static; }
}
</style>

<div class="wrap">
  <section class="intro">
    <h1>New sceneries</h1>
    <p class="lede"><b>{{TOTAL}}</b> backgrounds proposed for AyahReel. With them the library grows
      from {{LIB}} to {{AFTER}}. Each one cleared the readability floor today's sceneries were
      chosen by, passed a face and person detector and a content check, is not a copy of a scenery
      the app already has, and is free to use without credit in the reel.</p>
    <ul class="figures">
      <li><b>{{TOTAL}}</b><span>New</span></li>
      <li><b>{{TALL}}</b><span>Portrait</span></li>
      <li><b>{{WIDE}}</b><span>Wide</span></li>
      <li><b>{{STILLS}}</b><span>Stills</span></li>
      <li><b>{{CLIPS}}</b><span>Clips</span></li>
    </ul>
    <p class="fine">Licences: {{LICENSES}}. The number on each poster is its score against the floor
      (62 portrait, 68 wide). Nothing here is in the app yet.</p>
  </section>

  <nav class="bar" aria-label="Filters">
    <div class="row">
      <span class="label">Tab</span>
      <button type="button" class="chip" data-filter="tab" data-value="all" aria-pressed="true">All <span>{{TOTAL}}</span></button>
      {{TABCHIPS}}
    </div>
    <div class="row">
      <span class="label">Shape</span>
      <button type="button" class="chip" data-filter="shape" data-value="all" aria-pressed="true">Any</button>
      <button type="button" class="chip" data-filter="shape" data-value="tall" aria-pressed="false">Portrait</button>
      <button type="button" class="chip" data-filter="shape" data-value="wide" aria-pressed="false">Wide</button>
      <span class="sep" aria-hidden="true"></span>
      <span class="label">Type</span>
      <button type="button" class="chip" data-filter="kind" data-value="all" aria-pressed="true">Any</button>
      <button type="button" class="chip" data-filter="kind" data-value="still" aria-pressed="false">Stills</button>
      <button type="button" class="chip" data-filter="kind" data-value="clip" aria-pressed="false">Clips</button>
      <span class="sep" aria-hidden="true"></span>
      <button type="button" class="chip" id="verse" aria-pressed="false" title="Draw the app's scrim and a line of verse over the portrait posters">Verse preview</button>
      <span class="shown" id="shown" aria-live="polite"></span>
    </div>
    <div class="row">
      <span class="label">Source</span>
      <button type="button" class="chip" data-filter="src" data-value="all" aria-pressed="true">All</button>
      {{SRCCHIPS}}
    </div>
    <div class="marked" id="marked" hidden>
      <span id="marked-n"></span>
      <button type="button" id="copy">Copy their ids</button>
      <button type="button" id="clear">Clear</button>
      <span id="copied" aria-live="polite"></span>
      <textarea id="ids" readonly hidden aria-label="Ids left out"></textarea>
    </div>
  </nav>

  <main>
{{SECTIONS}}
    <p class="empty" id="empty" hidden>No scenery matches these filters.</p>
  </main>
</div>

<script>
(function () {
  var state = { tab: "all", shape: "all", kind: "all", src: "all" };
  try {
    var saved = JSON.parse(localStorage.getItem("new-sceneries-filters") || "null");
    if (saved) for (var k in state) if (saved[k]) state[k] = saved[k];
  } catch (e) {}
  var cards = Array.prototype.slice.call(document.querySelectorAll(".card"));
  var sections = Array.prototype.slice.call(document.querySelectorAll("section.tab"));
  var shown = document.getElementById("shown");
  var fmt = function (n) { return n.toLocaleString("en-US"); };

  function apply() {
    var total = 0, per = {};
    cards.forEach(function (c) {
      var ok = (state.tab === "all" || c.dataset.tab === state.tab) &&
               (state.shape === "all" || c.dataset.shape === state.shape) &&
               (state.kind === "all" || c.dataset.kind === state.kind) &&
               (state.src === "all" || c.dataset.src === state.src);
      c.hidden = !ok;
      if (ok) { total++; per[c.dataset.tab] = (per[c.dataset.tab] || 0) + 1; }
    });
    sections.forEach(function (s) {
      var n = per[s.dataset.tab] || 0;
      s.hidden = n === 0;
      var el = s.querySelector("[data-count]");
      if (el) el.textContent = fmt(n);
    });
    shown.textContent = "Showing " + fmt(total);
    document.getElementById("empty").hidden = total > 0;
    document.querySelectorAll("[data-filter]").forEach(function (b) {
      b.setAttribute("aria-pressed", String(state[b.dataset.filter] === b.dataset.value));
    });
    try { localStorage.setItem("new-sceneries-filters", JSON.stringify(state)); } catch (e) {}
  }

  // Scenes the reviewer leaves out: kept in this browser only, and handed
  // back as a list of ids to paste wherever the decision goes.
  var out = {};
  try { out = JSON.parse(localStorage.getItem("new-sceneries-left-out") || "{}") || {}; } catch (e) {}
  var ids = function () { return Object.keys(out).filter(function (k) { return out[k]; }).sort(); };
  function syncOut() {
    cards.forEach(function (c) {
      var on = !!out[c.dataset.id];
      c.classList.toggle("out", on);
      var b = c.querySelector(".drop");
      b.setAttribute("aria-pressed", String(on));
      b.textContent = on ? "Left out (undo)" : "Leave out";
    });
    var n = ids().length;
    document.getElementById("marked").hidden = n === 0;
    document.getElementById("marked-n").textContent = fmt(n) + (n === 1 ? " scenery left out" : " sceneries left out");
    try { localStorage.setItem("new-sceneries-left-out", JSON.stringify(out)); } catch (e) {}
  }

  document.addEventListener("click", function (e) {
    var b = e.target.closest("[data-filter]");
    if (b) { state[b.dataset.filter] = b.dataset.value; apply(); return; }
    if (e.target.closest("#verse")) {
      var on = document.body.classList.toggle("verse");
      document.getElementById("verse").setAttribute("aria-pressed", String(on));
      return;
    }
    var d = e.target.closest(".drop");
    if (d) {
      var id = d.closest(".card").dataset.id;
      out[id] = !out[id];
      syncOut();
      return;
    }
    if (e.target.closest("#clear")) { out = {}; syncOut(); return; }
    if (e.target.closest("#copy")) {
      var text = ids().join("\n"), note = document.getElementById("copied");
      var ta = document.getElementById("ids");
      var fallback = function () {
        ta.value = text; ta.hidden = false; ta.focus(); ta.select();
        note.textContent = "Select all and copy from the box.";
      };
      try {
        navigator.clipboard.writeText(text).then(function () {
          note.textContent = "Copied " + fmt(ids().length) + " ids.";
        }, fallback);
      } catch (err) { fallback(); }
    }
  });
  apply();
  syncOut();
})();
</script>
"""


# ── contact sheets for checking the thresholds ──────────────────────────

def sheets(pool, out, cands):
    d = os.path.join(out, "sheets")
    os.makedirs(d, exist_ok=True)
    groups = collections.defaultdict(list)
    for c in cands:
        groups[(c.get("reject") or "chosen").replace(":", "-")
               + ("" if c["bucket"] == "vertical" else "-wide")].append(c)
    for g, cs in groups.items():
        cs = cs[:240]
        wide = g.endswith("-wide")
        tw, th = (160, 90) if wide else (72, 128)
        cols = 12 if wide else 20
        rows = (len(cs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * (tw + 2), rows * (th + 2)), (30, 30, 30))
        for i, c in enumerate(cs):
            p = os.path.join(pool, "posters", c["file_key"] + ".jpg")
            if os.path.exists(p):
                im = Image.open(p).convert("RGB").resize((tw, th))
                sheet.paste(im, ((i % cols) * (tw + 2), (i // cols) * (th + 2)))
        sheet.save(os.path.join(d, f"{g}.jpg"), quality=78)
        with open(os.path.join(d, f"{g}.txt"), "w") as f:
            for i, c in enumerate(cs):
                f.write(f"{i:3d} r{i // cols} c{i % cols} {c['key']} {c['tab']} "
                        f"s={c['score']} {c.get('clip')} {(c.get('title') or c.get('alt') or '')[:70]}\n")


def shots(out):
    """Screenshots of the review page at desktop and phone widths, light and
    dark, for checking the layout where no browser is at hand."""
    from playwright.sync_api import sync_playwright
    page_path = os.path.abspath(os.path.join(out, "new_sceneries.html"))
    d = os.path.join(out, "shots")
    os.makedirs(d, exist_ok=True)
    with sync_playwright() as p:
        b = p.chromium.launch()
        for name, vp, scheme in (("desktop-light", (1280, 900), "light"),
                                 ("desktop-dark", (1280, 900), "dark"),
                                 ("phone-dark", (390, 844), "dark"),
                                 ("phone-light", (390, 844), "light")):
            ctx = b.new_context(viewport={"width": vp[0], "height": vp[1]},
                                color_scheme=scheme, device_scale_factor=1)
            pg = ctx.new_page()
            pg.goto("file://" + page_path, wait_until="load", timeout=120000)
            pg.wait_for_timeout(1500)
            pg.screenshot(path=os.path.join(d, f"{name}-top.png"))
            wide = pg.query_selector("section#aerial") or pg.query_selector("section#cinematic")
            if wide:
                wide.scroll_into_view_if_needed()
                pg.wait_for_timeout(800)
                pg.screenshot(path=os.path.join(d, f"{name}-wide.png"))
            if name == "desktop-dark":
                pg.evaluate("window.scrollTo(0, 0)")
                pg.click("#verse")
                pg.click(".card .drop")
                pg.wait_for_timeout(500)
                pg.screenshot(path=os.path.join(d, f"{name}-verse.png"))
            sw = pg.evaluate("document.documentElement.scrollWidth")
            log(f"  {name}: scrollWidth {sw} vs viewport {vp[0]}")
            ctx.close()
        b.close()


def main():
    if sys.argv[1] == "shots":
        shots(sys.argv[2])
        return
    pool, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    cands, emb, prompts, pemb, lib, lemb = load(pool)
    used, cat = existing_ids()
    log(f"pool: {len(cands)} candidates; library {len(lib)}")
    reasons = collections.Counter()
    for c in cands:
        why = judge(c, emb[c["emb"]], prompts, pemb, pool)
        if why:
            c["reject"] = why
            reasons[why] += 1
    moved = collections.Counter(f"{c['retab_from'].split('/')[0]}->{c['tab']}"
                                for c in cands if c.get("retab_from") and not c.get("reject"))
    if moved:
        log(f"moved to the tab they show: {dict(moved)}")
    log(f"judged: {sum(1 for c in cands if not c.get('reject'))} pass; {dict(reasons)}")
    tg = targets(cat)
    chosen, dup = select(cands, emb, lib, lemb, tg)
    log(f"dupes skipped: {dict(dup)}")
    assign_ids(chosen, set(used))
    recs = [record(c) for c in sorted(chosen, key=lambda c: (TAB_ORDER.index(c["tab"]),
                                                            -c["score"]))]
    by_id = {c["id"]: c for c in chosen}
    stats = {
        "total": len(recs),
        "library": len(cat["scenes"]),
        "tabs": {t: {"n": sum(1 for r in recs if r["tab"] == t),
                     "clips": sum(1 for r in recs if r["tab"] == t and r["video"]),
                     "now": sum(1 for s in cat["scenes"] if s["tab"] == t)}
                 for t in TAB_ORDER},
        "sources": collections.Counter(r["source"] for r in recs),
        "licenses": collections.Counter(r["license"]["name"] for r in recs),
    }
    with open(os.path.join(out, "new_sceneries.json"), "w", encoding="utf-8") as f:
        json.dump({"generated_for": "AyahReel scenery library",
                   "baseUrl_when_published": json.load(open(os.path.join(
                       ROOT, "assets", "catalog.json")))["baseUrl"],
                   "stats": stats, "scenes": recs}, f, indent=1, ensure_ascii=False)
    with open(os.path.join(out, "rejected.json"), "w", encoding="utf-8") as f:
        json.dump([{"key": c["key"], "tab": c["tab"], "why": c["reject"],
                    "score": c["score"], "page": c.get("page"), "clip": c.get("clip")}
                   for c in cands if c.get("reject")], f, indent=0)
    log(f"\n{len(recs)} new sceneries")
    for t in TAB_ORDER:
        s = stats["tabs"][t]
        log(f"  {t:10} {s['n']:4} new ({s['n'] - s['clips']} stills, {s['clips']} clips)"
            f"  library today {s['now']}")
    log(f"  sources  {dict(stats['sources'])}")
    log(f"  licences {dict(stats['licenses'])}")
    if PAGE:
        write_page(pool, out, recs, by_id, stats)
    if "--sheets" in sys.argv:
        sheets(pool, out, cands)


if __name__ == "__main__":
    main()
