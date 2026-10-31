#!/usr/bin/env python3
"""Which CocoaPods version would make this Podfile.lock the release's?

`shorebird patch ios` refuses when the patch's ios/Podfile.lock hashes
differently from the release's. Podfile.lock isn't committed, so each build
writes its own, and its last line names the CocoaPods that wrote it: a
runner with a newer CocoaPods than the release's builder fails the check
even though the pods themselves are identical.

    python3 tool/podfile_lock_match.py 1.0.7+9 ios/Podfile.lock

Fetches the release's podfile_lock_hash from Shorebird (SHOREBIRD_TOKEN),
then tries every published CocoaPods version on the `COCOAPODS:` line. On a
byte-for-byte match it prints that version and exits 0; otherwise exits 1,
meaning the pods differ and this is a native change, not a version line.
"""
import hashlib
import json
import os
import re
import sys
import urllib.request

API = "https://api.shorebird.dev/api/v1"


def get(url, token=None):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers)) as r:
        return json.load(r)


def main():
    release, lock_path = sys.argv[1], sys.argv[2]
    token = os.environ["SHOREBIRD_TOKEN"]
    app_id = re.search(r"^app_id:\s*(\S+)", open("shorebird.yaml").read(), re.M)[1]
    releases = get(f"{API}/apps/{app_id}/releases", token)["releases"]
    rid = next(r["id"] for r in releases if r["version"] == release)
    arts = get(f"{API}/apps/{app_id}/releases/{rid}/artifacts?platform=ios", token)
    want = next(a["podfile_lock_hash"] for a in arts["artifacts"]
                if a.get("podfile_lock_hash"))
    lock = open(lock_path, "rb").read()
    have = hashlib.sha256(lock).hexdigest()
    print(f"release {release}: {want}\nthis lock:     {have}", file=sys.stderr)
    if have == want:
        current = re.search(rb"^COCOAPODS: (\S+)", lock, re.M)
        print(current[1].decode() if current else "")
        return 0
    versions = [v["number"] for v in
                get("https://rubygems.org/api/v1/versions/cocoapods.json")]
    for v in versions:
        candidate = re.sub(rb"^COCOAPODS: \S+", b"COCOAPODS: " + v.encode(),
                           lock, flags=re.M)
        if hashlib.sha256(candidate).hexdigest() == want:
            print(v)
            return 0
    print("No CocoaPods version reproduces the release's Podfile.lock.",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
