"""Harvest a large scenery library for Ayah Reels.

Three phases, each a subcommand so a failure never costs the earlier work:

    python tool/harvest_scenes.py discover   -> videos/_work/candidates.json
    python tool/harvest_scenes.py fetch      -> videos/_work/raw/*
    python tool/harvest_scenes.py curate     -> videos/{vertical,horizontal}/<category>/*

Two buckets, because they are used differently in the reel:

  vertical    9:16, fills the frame, the verse is laid ON it. Must be dark
              and quiet or the gold/white text stops being readable.
  horizontal  16:9, letterboxed into the 9:16 canvas with the verse BELOW
              it. Nothing is written over the picture, so these may be as
              bright and colourful as they like -- drone/cinematic shots.

No API keys anywhere: every source here answers to a plain browser request.
"""

import concurrent.futures as futures
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "videos")
WORK = os.path.join(OUT, "_work")
RAW = os.path.join(WORK, "raw")

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
HDRS = {
    "User-Agent": UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-Dest": "document",
}

# ── what to look for ────────────────────────────────────────────────────
# (category, [queries]). Queries are deliberately over-specified toward
# dark, empty, person-free frames -- the curation pass throws away what
# still comes back bright, but a good query wastes less bandwidth.

VERTICAL = {
    "desert": ["desert dunes night", "sahara sand dunes dusk", "sand dune silhouette",
               "desert night sky", "dark sand dunes", "desert dusk minimal"],
    "mountains": ["dark mountains fog", "mountain silhouette dusk", "misty mountain range",
                  "himalaya twilight", "mountain peak clouds dark", "foggy valley mountains"],
    "ocean": ["dark ocean waves", "calm sea dusk", "ocean horizon night",
              "deep water surface dark", "sea foam long exposure", "moody seascape"],
    "forest": ["misty forest fog", "dark pine forest", "foggy woods morning",
               "forest silhouette dusk", "rainforest mist dark", "birch forest fog"],
    "road": ["lonely road", "empty highway night", "desert road vanishing",
             "misty road forest", "country road dusk", "mountain road fog"],
    "sky": ["milky way night sky", "starry night sky", "storm clouds dark",
            "moon behind clouds", "dramatic clouds dusk", "night sky stars minimal"],
    "rain": ["rain on window", "raindrops glass dark", "rainy night bokeh",
             "wet window blur", "rain drops water surface"],
    "snow": ["snowy mountains fog", "winter forest snow fog", "snow landscape minimal",
             "arctic ice dark", "snowfall night"],
    "water": ["still lake reflection", "lake mist morning", "waterfall long exposure",
              "river fog forest", "reflection water calm dark"],
    "rock": ["canyon walls shadow", "rock formation desert dusk", "cliff face dark",
             "stone texture dark", "cave opening light"],
    "clouds": ["above the clouds aerial", "sea of clouds sunrise", "cloud layer dusk",
               "fog over valley", "cloudscape dark"],
    "sacred": ["mosque at night", "mosque dome interior", "islamic architecture pattern",
               "minaret silhouette dusk", "mosque lantern night", "arabic geometric pattern dark",
               "kaaba mecca", "medina mosque night"],
    "field": ["wheat field wind dusk", "grass field fog", "lavender field dusk",
              "meadow mist morning", "prairie sunset silhouette"],
    "abstract": ["dark gradient texture", "gold bokeh dark background", "smoke on black",
                 "silk fabric dark", "ink in water dark", "particles dark background",
                 "candle flame dark", "lantern night bokeh"],
    "aurora": ["northern lights aurora", "aurora borealis mountains"],
}

HORIZONTAL = {
    "aerial_mountain": ["aerial mountain range", "drone mountain valley", "aerial alps snow",
                        "drone shot mountain river", "aerial mountain autumn"],
    "aerial_coast": ["aerial coastline cliffs", "drone ocean beach", "aerial island sea",
                     "drone coastal cliffs", "aerial turquoise sea"],
    "aerial_forest": ["aerial forest autumn", "drone forest river", "aerial autumn trees",
                      "drone pine forest snow", "aerial green forest"],
    "aerial_desert": ["aerial desert dunes", "drone sahara", "aerial canyon river",
                      "drone desert road"],
    "aerial_water": ["aerial waterfall", "drone lake mountains", "aerial river delta",
                     "drone river valley"],
    "aerial_land": ["aerial green hills", "drone countryside fields", "aerial rice terraces",
                    "drone village valley", "aerial road landscape", "aerial train landscape"],
    "cinematic": ["cinematic landscape", "landscape time lapse clouds",
                  "sunrise over mountains landscape", "epic nature landscape"],
}


def log(*a):
    print(*a, flush=True)


def get(url, timeout=30, binary=False, hdrs=None):
    req = urllib.request.Request(url, headers=hdrs or HDRS)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def polite():
    time.sleep(random.uniform(0.6, 1.6))


# Wikimedia asks bulk clients to identify themselves and throttles the
# ones that don't; a browser UA at eight threads gets most requests
# refused. Openverse serves a lot of Wikimedia-hosted files too, so this
# is keyed on the host rather than the source.
WIKI_UA = ("AyahReelsSceneHarvester/1.0 "
           "(https://github.com/ayah-reels; contact 244372596+Mulhimfy@users.noreply.github.com)")


def _ua_for(url):
    return WIKI_UA if "wikimedia.org" in url or "wikipedia.org" in url else UA


# ── discovery: one function per source, each returns candidate dicts ────

def _cand(source, kind, bucket, category, url, ident, page=None, w=0, h=0):
    return {
        "id": f"{source}_{ident}",
        "source": source, "kind": kind, "bucket": bucket,
        "category": category, "url": url, "page": page, "w": w, "h": h,
    }


# How many results each source may contribute per query. Every source
# will happily return hundreds; without a cap one popular query drowns
# out the twenty niche ones that give the library its range.
CAP = {
    "pexels_images": 22, "pixabay_images": 22, "openverse_images": 14,
    "commons_images": 12, "wallhaven_images": 12,
    # Clips cost ~30x an image to fetch. Horizontal gets the bigger share:
    # drone footage is the whole point of that bucket.
    "pixabay_videos": {"vertical": 3, "horizontal": 6},
    "pexels_videos": {"vertical": 3, "horizontal": 6},
}


def _cap(fn_name, bucket):
    c = CAP.get(fn_name, 20)
    return c[bucket] if isinstance(c, dict) else c


def pexels_images(query, bucket, category):
    """Pexels search HTML -> photo ids. The CDN crops server-side, so we
    ask it for exactly the frame we want and never download the 6 MB
    original."""
    orient = "portrait" if bucket == "vertical" else "landscape"
    out = []
    for page in (1, 2):
        u = (f"https://www.pexels.com/search/{urllib.parse.quote(query)}/"
             f"?orientation={orient}&size=large&page={page}")
        try:
            html = get(u)
        except Exception as e:
            log(f"    pexels img {query!r} p{page}: {e}")
            return out
        ids = re.findall(r"images\.pexels\.com/photos/(\d+)/", html)
        seen = []
        for i in ids:
            if i in seen:
                continue
            seen.append(i)
            wh = "w=1080&h=1920" if bucket == "vertical" else "w=1920&h=1080"
            src = (f"https://images.pexels.com/photos/{i}/pexels-photo-{i}.jpeg"
                   f"?auto=compress&cs=tinysrgb&fit=crop&{wh}")
            out.append(_cand("pexels", "image", bucket, category, src, i,
                             page=f"https://www.pexels.com/photo/{i}/"))
        if len(seen) < 10:
            break
        polite()
    return out


def pexels_videos(query, bucket, category):
    orient = "portrait" if bucket == "vertical" else "landscape"
    u = (f"https://www.pexels.com/search/videos/{urllib.parse.quote(query)}/"
         f"?orientation={orient}")
    try:
        html = get(u)
    except Exception as e:
        log(f"    pexels vid {query!r}: {e}")
        return []
    out, seen = [], set()
    want = "1080_1920" if bucket == "vertical" else "1920_1080"
    for m in re.finditer(r"https://videos\.pexels\.com/video-files/(\d+)/[\w-]+\.mp4", html):
        url, vid = m.group(0), m.group(1)
        if vid in seen:
            continue
        seen.add(vid)
        # The listing links a small preview; swap in the full-size rendition
        # and let the fetch phase fall back if that exact size is absent.
        out.append(_cand("pexels", "video", bucket, category,
                         re.sub(r"_\d+_\d+_\d+\.mp4$", f"_{want}_30fps.mp4", url), vid,
                         page=f"https://www.pexels.com/video/{vid}/"))
        out[-1]["url_fallback"] = url
    return out


def pixabay_images(query, bucket, category):
    orient = "vertical" if bucket == "vertical" else "horizontal"
    out, seen = [], set()
    for page in (1, 2):
        u = (f"https://pixabay.com/images/search/{urllib.parse.quote(query)}/"
             f"?orientation={orient}&pagi={page}")
        try:
            html = get(u)
        except Exception as e:
            log(f"    pixabay img {query!r} p{page}: {e}")
            return out
        found = re.findall(r"https://cdn\.pixabay\.com/photo/[\d/]+/[\w-]+_1280\.jpg", html)
        new = 0
        for url in found:
            key = url.rsplit("/", 1)[-1]
            if key in seen:
                continue
            seen.add(key)
            new += 1
            out.append(_cand("pixabay", "image", bucket, category, url,
                             key.replace("_1280.jpg", "")))
        if new < 10:
            break
        polite()
    return out


def pixabay_videos(query, bucket, category):
    orient = "vertical" if bucket == "vertical" else "horizontal"
    u = (f"https://pixabay.com/videos/search/{urllib.parse.quote(query)}/"
         f"?orientation={orient}")
    try:
        html = get(u)
    except Exception as e:
        log(f"    pixabay vid {query!r}: {e}")
        return []
    out, seen = [], set()
    for url in re.findall(r"https://cdn\.pixabay\.com/video/[\d/]+/[\w-]+_tiny\.mp4", html):
        key = url.rsplit("/", 1)[-1].replace("_tiny.mp4", "")
        if key in seen:
            continue
        seen.add(key)
        c = _cand("pixabay", "video", bucket, category,
                  url.replace("_tiny.mp4", "_large.mp4"), key)
        c["url_fallback"] = url.replace("_tiny.mp4", "_medium.mp4")
        out.append(c)
    return out


def openverse_images(query, bucket, category):
    aspect = "tall" if bucket == "vertical" else "wide"
    u = ("https://api.openverse.org/v1/images/?"
         + urllib.parse.urlencode({
             "q": query, "aspect_ratio": aspect, "size": "large",
             "page_size": 20, "mature": "false"}))
    try:
        data = json.loads(get(u, hdrs={"User-Agent": UA, "Accept": "application/json"}))
    except Exception as e:
        log(f"    openverse {query!r}: {e}")
        return []
    out = []
    for r in data.get("results", []):
        url = r.get("url") or ""
        if not url:
            continue
        # Flickr hands out 1024px by default; _k is the 2048px rendition.
        if "staticflickr.com" in url:
            url = re.sub(r"_[a-z]\.jpg$", "_k.jpg", url)
        out.append(_cand("openverse", "image", bucket, category, url,
                         r.get("id", "")[:12], page=r.get("foreign_landing_url"),
                         w=r.get("width") or 0, h=r.get("height") or 0))
    return out


def commons_images(query, bucket, category):
    """Wikimedia Commons: the deepest well of real aerial/landscape
    photography that answers without a key, and it will resize to any
    width for us."""
    width = 1400 if bucket == "vertical" else 2000
    u = ("https://commons.wikimedia.org/w/api.php?"
         + urllib.parse.urlencode({
             "action": "query", "format": "json", "generator": "search",
             "gsrsearch": query, "gsrnamespace": 6, "gsrlimit": 25,
             "prop": "imageinfo", "iiprop": "url|size",
             "iiurlwidth": width}))
    try:
        data = json.loads(get(u, hdrs={"User-Agent": UA, "Accept": "application/json"}))
    except Exception as e:
        log(f"    commons {query!r}: {e}")
        return []
    out = []
    for pid, p in (data.get("query", {}).get("pages", {}) or {}).items():
        ii = (p.get("imageinfo") or [{}])[0]
        url, w, h = ii.get("thumburl"), ii.get("width", 0), ii.get("height", 0)
        if not url or not url.lower().split("?")[0].endswith((".jpg", ".jpeg", ".png")):
            continue
        if bucket == "vertical" and w > h * 1.1:
            continue           # too wide to crop to 9:16 without losing it
        if bucket == "horizontal" and h > w * 0.8:
            continue
        out.append(_cand("commons", "image", bucket, category, url, pid,
                         page=f"https://commons.wikimedia.org/?curid={pid}", w=w, h=h))
    return out


def coverr_videos(query, bucket, category):
    u = ("https://coverr.co/api/videos?"
         + urllib.parse.urlencode({"query": query, "page_size": 20, "urls": "true"}))
    try:
        data = json.loads(get(u, hdrs={"User-Agent": UA, "Accept": "application/json"}))
    except Exception as e:
        log(f"    coverr {query!r}: {e}")
        return []
    out = []
    for h in data.get("hits", []) or data.get("results", []):
        urls = h.get("urls") or {}
        url = urls.get("mp4_download") or urls.get("mp4") or urls.get("mp4_preview")
        if not url:
            continue
        vert = bool(h.get("is_vertical"))
        if vert != (bucket == "vertical"):
            continue
        out.append(_cand("coverr", "video", bucket, category, url,
                         str(h.get("id") or h.get("objectID"))[:12],
                         page=f"https://coverr.co/videos/{h.get('slug', '')}"))
    return out


def wallhaven_images(query, bucket, category):
    """Wallhaven's search API needs no key and its top-list is already
    curated for wallpaper use -- i.e. exactly our composition: a subject
    that survives a hard crop and a lot of empty sky."""
    ratios = "9x16,10x16,2x3" if bucket == "vertical" else "16x9,16x10"
    u = ("https://wallhaven.cc/api/v1/search?"
         + urllib.parse.urlencode({
             "q": query, "categories": "100", "purity": "100",
             "ratios": ratios, "sorting": "relevance", "order": "desc"}))
    try:
        data = json.loads(get(u, hdrs={"User-Agent": UA, "Accept": "application/json"}))
    except Exception as e:
        log(f"    wallhaven {query!r}: {e}")
        return []
    out = []
    for r in data.get("data", []):
        out.append(_cand("wallhaven", "image", bucket, category, r["path"],
                         r["id"], page=r.get("url"),
                         w=r.get("dimension_x", 0), h=r.get("dimension_y", 0)))
    return out


def mixkit_videos(query, bucket, category):
    """Mixkit publishes flat category pages with direct mp4s; the listing
    links the 360p proxy, and the same id serves 1080p."""
    slug = query.strip().lower().replace(" ", "-")
    u = f"https://mixkit.co/free-stock-video/{urllib.parse.quote(slug)}/"
    try:
        html = get(u)
    except Exception:
        return []
    out, seen = [], set()
    for m in re.finditer(r"https://assets\.mixkit\.co/videos/(\d+)/[\w-]+-360\.mp4", html):
        vid = m.group(1)
        if vid in seen:
            continue
        seen.add(vid)
        c = _cand("mixkit", "video", bucket, category,
                  m.group(0).replace("-360.mp4", "-1080.mp4"), vid, page=u)
        c["url_fallback"] = m.group(0).replace("-360.mp4", "-720.mp4")
        out.append(c)
    return out


IMAGE_SOURCES = [pexels_images, pixabay_images, openverse_images,
                 commons_images, wallhaven_images]
VIDEO_SOURCES = [pixabay_videos, pexels_videos]


def discover():
    os.makedirs(WORK, exist_ok=True)
    cands, seen = [], set()

    def add(items):
        for c in items:
            key = c["url"].split("?")[0]
            if key in seen:
                continue
            seen.add(key)
            cands.append(c)

    plan = ([("vertical", cat, q) for cat, qs in VERTICAL.items() for q in qs]
            + [("horizontal", cat, q) for cat, qs in HORIZONTAL.items() for q in qs])
    log(f"discovering across {len(plan)} queries x "
        f"{len(IMAGE_SOURCES) + len(VIDEO_SOURCES)} sources")

    for n, (bucket, cat, q) in enumerate(plan, 1):
        before = len(cands)
        srcs = IMAGE_SOURCES + VIDEO_SOURCES
        with futures.ThreadPoolExecutor(max_workers=4) as ex:
            for res in ex.map(lambda f: _safe(f, q, bucket, cat), srcs):
                add(res)
        log(f"[{n}/{len(plan)}] {bucket}/{cat}: {q!r} -> +{len(cands) - before} "
            f"(total {len(cands)})")
        with open(os.path.join(WORK, "candidates.json"), "w", encoding="utf-8") as f:
            json.dump(cands, f, indent=1)
        polite()

    # Mixkit is organised by category page, not by free-text search, so it
    # gets its own sweep rather than a slot in the per-query fan-out.
    for slug, bucket, cat in [
            ("nature", "horizontal", "cinematic"),
            ("landscape", "horizontal", "cinematic"),
            ("aerial", "horizontal", "aerial_land"),
            ("drone", "horizontal", "aerial_land"),
            ("mountain", "horizontal", "aerial_mountain"),
            ("ocean", "horizontal", "aerial_coast"),
            ("forest", "horizontal", "aerial_forest"),
            ("desert", "horizontal", "aerial_desert"),
            ("sky", "vertical", "sky"), ("clouds", "vertical", "clouds"),
            ("rain", "vertical", "rain"), ("night", "vertical", "sky"),
            ("water", "vertical", "water"), ("snow", "vertical", "snow")]:
        before = len(cands)
        add(mixkit_videos(slug, bucket, cat)[:10])
        log(f"[mixkit] {bucket}/{cat}: {slug} -> +{len(cands) - before}")
        polite()

    with open(os.path.join(WORK, "candidates.json"), "w", encoding="utf-8") as f:
        json.dump(cands, f, indent=1)
    log(f"\n{len(cands)} candidates -> {os.path.join(WORK, 'candidates.json')}")


def _safe(fn, q, bucket, cat):
    try:
        return fn(q, bucket, cat)[:_cap(fn.__name__, bucket)]
    except Exception as e:
        log(f"    {fn.__name__} {q!r}: {e}")
        return []


# ── fetch ───────────────────────────────────────────────────────────────

# Clips run 10-40 MB apiece and most lose to a still anyway, so the
# scoring pass takes only the head of each one. mp4s written with
# +faststart carry their moov atom up front, which means the first few
# megabytes are enough for ffmpeg to report the duration and decode the
# opening seconds -- all the scorer looks at.
PROBE_BYTES = 3_500_000


def _path_for(c, probe=False):
    ext = (".probe.mp4" if probe else ".mp4") if c["kind"] == "video" else ".jpg"
    name = f"{c['bucket']}__{c['category']}__{c['id']}"
    return os.path.join(RAW, re.sub(r"[^A-Za-z0-9_.-]", "", name)[:110] + ext)


def _dl(c, probe=True):
    """Fetch one candidate. Videos come down as a head-of-file probe
    unless `probe` is off, in which case the whole clip is pulled."""
    is_probe = probe and c["kind"] == "video"
    path = _path_for(c, is_probe)
    key = "probe_file" if is_probe else "file"
    if os.path.exists(path) and os.path.getsize(path) > 20000:
        c[key] = path
        return "cached"
    hdrs = {"User-Agent": _ua_for(c["url"]), "Accept": "*/*",
            "Referer": "https://www.google.com/"}
    if is_probe:
        hdrs["Range"] = f"bytes=0-{PROBE_BYTES - 1}"
    for url in (c["url"], c.get("url_fallback")):
        if not url:
            continue
        try:
            data = get(url, timeout=180, binary=True, hdrs=hdrs)
            if len(data) < 20000:
                continue
            with open(path, "wb") as f:
                f.write(data)
            c[key] = path
            c["probe_bytes" if is_probe else "bytes"] = len(data)
            c["url_used"] = url
            return "ok"
        except Exception:
            continue
    return "fail"


def _uncropped(c):
    """The library archives whole frames, not pre-cropped ones. Pexels'
    CDN is asked for a large edition of the full photo instead of the
    9:16 cut, so the framing decision stays open until a scene is
    actually adopted into the app."""
    if c["source"] == "pexels" and c["kind"] == "image":
        long_edge = "h=2400" if c["bucket"] == "vertical" else "w=2400"
        c["url"] = re.sub(r"fit=crop&w=\d+&h=\d+", long_edge, c["url"])
    return c


VIDEO_BUDGET = 700


def _trim_videos(cands):
    """A clip costs ~30x a still to pull and most of them lose to a still
    anyway. Spend the video budget round-robin across categories so no
    single popular one eats it, rather than first-come-first-served."""
    vids, rest = [], []
    for c in cands:
        (vids if c["kind"] == "video" else rest).append(c)
    if len(vids) <= VIDEO_BUDGET:
        return cands
    by_cat = {}
    for c in vids:
        by_cat.setdefault((c["bucket"], c["category"]), []).append(c)
    keep, order = [], sorted(by_cat)
    while len(keep) < VIDEO_BUDGET and any(by_cat[k] for k in order):
        for k in order:
            if by_cat[k] and len(keep) < VIDEO_BUDGET:
                keep.append(by_cat[k].pop(0))
    log(f"video budget: keeping {len(keep)} of {len(vids)} clips")
    return rest + keep


def fetch():
    os.makedirs(RAW, exist_ok=True)
    with open(os.path.join(WORK, "candidates.json"), encoding="utf-8") as f:
        cands = _trim_videos([_uncropped(c) for c in json.load(f)])
    log(f"fetching {len(cands)} candidates into {RAW}")
    tally = {"ok": 0, "cached": 0, "fail": 0}
    with futures.ThreadPoolExecutor(max_workers=8) as ex:
        for n, r in enumerate(ex.map(_dl, cands), 1):
            tally[r] += 1
            if n % 50 == 0:
                log(f"  {n}/{len(cands)}  {tally}")
    log(f"done: {tally}")
    # Written separately so candidates.json stays the full discovery
    # record and a re-run can revisit anything the budget skipped.
    with open(os.path.join(WORK, "fetched.json"), "w", encoding="utf-8") as f:
        json.dump([c for c in cands if c.get("file")], f, indent=1)


def retry_wikimedia():
    """Second pass for the Wikimedia-hosted files the parallel fetch lost
    to throttling: two threads, identified UA, a pause between requests."""
    with open(os.path.join(WORK, "candidates.json"), encoding="utf-8") as f:
        cands = json.load(f)
    todo = [c for c in cands
            if "wikimedia.org" in c["url"] or "wikipedia.org" in c["url"]]
    todo = [c for c in todo if not (os.path.exists(_path_for(c))
                                    and os.path.getsize(_path_for(c)) > 20000)]
    log(f"retrying {len(todo)} throttled Wikimedia files")
    got = 0
    for n, c in enumerate(todo, 1):
        if _dl(c) in ("ok", "cached"):
            got += 1
        time.sleep(0.25)
        if n % 100 == 0:
            log(f"  {n}/{len(todo)}  recovered {got}")
    log(f"recovered {got}/{len(todo)}")
    path = os.path.join(WORK, "fetched.json")
    have = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else []
    names = {c["id"] for c in have}
    have += [c for c in todo if c.get("file") and c["id"] not in names]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(have, f, indent=1)
    log(f"fetched.json now holds {len(have)}")


def fetch_full(cands):
    """Pull the complete clip for candidates that survived curation.
    Called from the build step, not the command line."""
    vids = [c for c in cands if c["kind"] == "video"]
    if not vids:
        return
    log(f"fetching {len(vids)} full clips")
    with futures.ThreadPoolExecutor(max_workers=6) as ex:
        list(ex.map(lambda c: _dl(c, probe=False), vids))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "discover"
    {"discover": discover, "fetch": fetch,
     "retry": retry_wikimedia}[cmd]()
