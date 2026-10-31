"""Split the reviewed library into what ships and what streams.

    python tool/publish_scenes.py stage     -> assets/ + videos/_release/
    python tool/publish_scenes.py upload    -> GitHub repo + release

The app bundles three things: a starter set of full scenes so it works
with no network at all, a poster for *every* scene so the picker grid is
complete and instant offline, and the catalog that describes them. The
remaining full-size files live on a GitHub release and are fetched the
first time a scene is chosen.

Posters are the reason this works. 381 of them at 216x384 cost about
4 MB, which buys a grid that never shows an empty tile -- only the file
behind a chosen scene has to travel.
"""

import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.environ.get("SCENE_OUT",
                     r"C:\Users\dell\OneDrive\Videos\test\don't touch")
REVIEW = os.path.join(LIB, "_review")

ASSETS = os.path.join(ROOT, "assets")
BUNDLED_DIR = os.path.join(ASSETS, "backgrounds")
THUMB_DIR = os.path.join(ASSETS, "scene_thumbs")
STAGE = os.path.join(ROOT, "videos", "_release")

REPO = os.environ.get("SCENE_REPO", "Mulhimfy/ayah-reels-scenes")
TAG = os.environ.get("SCENE_TAG", "v1")
BASE_URL = f"https://github.com/{REPO}/releases/download/{TAG}"

# Scenes shipped inside the app. Small enough not to matter to the
# download size, wide enough that every tab has something usable before
# the phone has ever seen a network.
BUNDLE_STILLS_PER_TAB = 2
BUNDLE_CLIPS = 4


def log(*a):
    print(*a, flush=True)


def load():
    with open(os.path.join(REVIEW, "MANIFEST.json"), encoding="utf-8") as f:
        return json.load(f)


def pick_bundle(man):
    """Best-scoring stills spread over every tab, plus a few small clips
    so the moving and letterboxed formats are represented offline too."""
    by_score = sorted(man, key=lambda m: -m["score"])
    out, per_tab = [], {}
    for m in by_score:
        if m["kind"] != "image":
            continue
        k = (m["bucket"], m["tab"])
        if per_tab.get(k, 0) >= BUNDLE_STILLS_PER_TAB:
            continue
        per_tab[k] = per_tab.get(k, 0) + 1
        out.append(m)
    # Cheapest clips that still score well: a bundled clip is pure
    # download weight, so pay for the smallest ones that earn a place.
    clips = [m for m in by_score if m["kind"] == "video" and m["score"] >= 80]
    clips.sort(key=lambda m: m["out_bytes"])
    out += clips[:BUNDLE_CLIPS]
    return out


def stage():
    man = load()
    bundle = pick_bundle(man)
    bundled = {m["name"] for m in bundle}

    for d in (BUNDLED_DIR, THUMB_DIR, STAGE):
        os.makedirs(d, exist_ok=True)

    # 1. bundled full scenes
    for m in bundle:
        ext = os.path.splitext(m["out"])[1]
        shutil.copyfile(os.path.join(LIB, m["out"]),
                        os.path.join(BUNDLED_DIR, m["name"] + ext))

    # 2. a poster for every scene, bundled or not
    for m in man:
        shutil.copyfile(os.path.join(REVIEW, "thumbs", m["name"] + ".jpg"),
                        os.path.join(THUMB_DIR, m["name"] + ".jpg"))

    # 3. everything not bundled, flattened for release upload
    remote = [m for m in man if m["name"] not in bundled]
    for m in remote:
        ext = os.path.splitext(m["out"])[1]
        src = os.path.join(LIB, m["out"])
        dest = os.path.join(STAGE, m["name"] + ext)
        # Size, not mere existence: a re-encode keeps the name and
        # changes the bytes, and a stale copy here would be published.
        if (not os.path.exists(dest)
                or os.path.getsize(dest) != os.path.getsize(src)):
            shutil.copyfile(src, dest)

    # 4. the catalog the app reads
    catalog = {
        "version": 1,
        "baseUrl": BASE_URL,
        "scenes": [{
            "id": m["name"],
            "tab": m["tab"],
            "wide": m["bucket"] == "horizontal",
            "video": m["kind"] == "video",
            "ext": os.path.splitext(m["out"])[1].lstrip("."),
            "bytes": m["out_bytes"],
            "grad": m["grad"],
            "bundled": m["name"] in bundled,
        } for m in sorted(man, key=lambda m: (m["bucket"], m["tab"],
                                              -m["score"]))],
    }
    with open(os.path.join(ASSETS, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, separators=(",", ":"))

    bsize = sum(m["out_bytes"] for m in bundle)
    tsize = sum(os.path.getsize(os.path.join(THUMB_DIR, f))
                for f in os.listdir(THUMB_DIR))
    rsize = sum(m["out_bytes"] for m in remote)
    log(f"bundled  {len(bundle):3} scenes   {bsize / 1e6:6.1f} MB")
    log(f"posters  {len(man):3} scenes   {tsize / 1e6:6.1f} MB")
    log(f"catalog  {len(man):3} entries  "
        f"{os.path.getsize(os.path.join(ASSETS, 'catalog.json')) / 1e3:6.1f} KB")
    log(f"  -> app grows by ~{(bsize + tsize) / 1e6:.0f} MB")
    log(f"streamed {len(remote):3} scenes   {rsize / 1e6:6.1f} MB  -> {STAGE}")


def run(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def upload():
    files = sorted(os.path.join(STAGE, f) for f in os.listdir(STAGE))
    if not files:
        log("nothing staged -- run `stage` first")
        return

    if run("gh", "repo", "view", REPO).returncode != 0:
        log(f"creating {REPO}")
        r = run("gh", "repo", "create", REPO, "--public",
                "--description",
                "Scenery library for Ayah Reels (backgrounds served to the app)")
        if r.returncode != 0:
            log(r.stderr.strip())
            return
    else:
        log(f"{REPO} already exists")

    # A release cannot be cut against an empty repository, and a repo
    # made by `gh repo create` has no commits. Seed one through the API
    # so no git clone/push dance is needed.
    if run("gh", "api", f"repos/{REPO}/contents/README.md").returncode != 0:
        log("seeding initial commit")
        import base64
        readme = base64.b64encode(f"""# Ayah Reels — scene library

Backgrounds served to the [Ayah Reels](https://github.com/{REPO}) app.

The app bundles a starter set and a poster for every scene; the
full-size files live in the releases here and are fetched the first
time a scene is chosen, then cached on the device.

Files are named `<id>.<jpg|mp4>` and are addressed directly:

    {BASE_URL}/<id>.<ext>

Portrait scenes are 1080x1920 and carry the verse on top; wide scenes
are 1920x1080 and are letterboxed with the verse below.
""".encode()).decode()
        r = run("gh", "api", f"repos/{REPO}/contents/README.md", "-X", "PUT",
                "-f", "message=Add scene library readme",
                "-f", f"content={readme}")
        if r.returncode != 0:
            log(r.stderr.strip()[:300])
            return

    if run("gh", "release", "view", TAG, "--repo", REPO).returncode != 0:
        log(f"creating release {TAG}")
        r = run("gh", "release", "create", TAG, "--repo", REPO,
                "--title", f"Scene library {TAG}",
                "--notes", f"{len(files)} scenes served to the app on demand.")
        if r.returncode != 0:
            log(r.stderr.strip())
            return

    # Skip what is already up there at the same size. Re-publishing after
    # an encode change touches a handful of files; re-uploading all 355
    # to find that out would take an hour of bandwidth for nothing.
    r = run("gh", "release", "view", TAG, "--repo", REPO,
            "--json", "assets")
    if r.returncode == 0:
        try:
            remote = {a["name"]: a["size"]
                      for a in json.loads(r.stdout)["assets"]}
            fresh = [f for f in files
                     if remote.get(os.path.basename(f)) != os.path.getsize(f)]
            if len(fresh) != len(files):
                log(f"{len(files) - len(fresh)} already uploaded unchanged; "
                    f"sending {len(fresh)}")
            files = fresh
        except Exception as e:
            log(f"could not read existing assets ({e}); uploading all")
    if not files:
        log("release already matches the library")
        log(f"\ndone -> {BASE_URL}/<id>.<ext>")
        return

    # Uploaded in batches: one `gh` call per file is a process launch
    # each time, and one call for all of them overruns the Windows
    # command-line limit.
    done, batch = 0, 20
    for i in range(0, len(files), batch):
        chunk = files[i:i + batch]
        r = run("gh", "release", "upload", TAG, *chunk,
                "--repo", REPO, "--clobber")
        if r.returncode != 0:
            log(f"  batch {i // batch + 1} failed: {r.stderr.strip()[:200]}")
        else:
            done += len(chunk)
        log(f"  uploaded {done}/{len(files)}")
    log(f"\ndone -> {BASE_URL}/<id>.<ext>")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "stage"
    {"stage": stage, "upload": upload}[cmd]()
