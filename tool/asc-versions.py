"""What version records App Store Connect already holds for AyahReel.

Run this BEFORE choosing the `version:` line in pubspec.yaml. Apple's two
version rules can only be checked against ASC's own state, and both fail
at the very end of a ~20 minute build — after the IPA is built, signed
and handed to the uploader:

    90062  CFBundleShortVersionString must be higher than the previously
           approved version
    90186  Invalid Pre-Release Train. The train version 'X' is closed for
           new build submissions

The second is the harsher one and is not about build numbers at all: a
version that has been RELEASED closes its TestFlight train for good, so
no build of that version can ever be uploaded again, however high its
CFBundleVersion.

**The train that closes is the BINARY's version, not the store label.**
Those are two different fields and on this app they have drifted apart:
the record shown as `0.1.2` ships build 3, whose
CFBundleShortVersionString is `1.0.1`, so releasing `0.1.2` closed the
`1.0.1` train. Reading the labels alone said `1.0.1` was free; a build
was cut against it on 2026-08-11 and died on 90186 after twenty minutes.
So this script follows each released version to its build and reports
the build's train, which is the number that is actually spent.

Pick the next `version:` above every closed train AND above every
released label.

Read-only — it issues GETs and changes nothing.

    python tool/asc-versions.py

Needs `cryptography` (for the ES256 signature) and the private key named
below, which is deliberately not in this repo; see the store-credentials
notes for where it lives. Key ID and Issuer ID are not secrets and are
already in codemagic.yaml.
"""
import base64
import json
import os
import time
import urllib.error
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

KEY_ID = "PCCGPRB5YD"
ISSUER = "db2e1474-4b8c-4a69-b318-7fa020ce74ff"
APP_ID = "6794389870"  # the ASC record for com.ayahReel.app

KEY_PATH = os.path.expanduser(
    os.environ.get(
        "ASC_KEY_PATH",
        r"~\.appstoreconnect\private_keys\AuthKey_PCCGPRB5YD.p8",
    )
)


def _b64(raw):
    """base64url, unpadded — what JWT uses."""
    return base64.urlsafe_b64encode(raw).rstrip(b"=")


def _token():
    """A 20-minute ES256 token. Apple caps the lifetime at 20 minutes."""
    with open(KEY_PATH, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)

    now = int(time.time())
    header = _b64(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    payload = _b64(
        json.dumps(
            {
                "iss": ISSUER,
                "iat": now,
                "exp": now + 1200,
                "aud": "appstoreconnect-v1",
            }
        ).encode()
    )
    signed = header + b"." + payload

    # `cryptography` signs to DER; JOSE wants the bare r||s pair, each
    # left-padded to the curve size. Skipping this yields a 401 that
    # says nothing about why.
    r, s = utils.decode_dss_signature(key.sign(signed, ec.ECDSA(hashes.SHA256())))
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return (signed + b"." + _b64(raw)).decode()


def _get(path, token):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        headers={"Authorization": "Bearer " + token},
    )
    with urllib.request.urlopen(req) as res:
        return json.load(res)


def _build_and_train(version_id, token):
    """The build a version record ships, and that build's own version.

    Two hops, because the store label and the binary's
    CFBundleShortVersionString are different fields: version -> build
    gives the CFBundleVersion, build -> preReleaseVersion gives the
    train. The train is what a release closes. Returns (None, None) for
    a record with no build attached yet.
    """
    try:
        b = _get(f"/v1/appStoreVersions/{version_id}/build", token)["data"]
        if not b:
            return None, None
        pre = _get(f"/v1/builds/{b['id']}/preReleaseVersion", token)["data"]
        return b["attributes"]["version"], pre and pre["attributes"]["version"]
    except urllib.error.HTTPError:
        return None, None


def main():
    if not os.path.exists(KEY_PATH):
        raise SystemExit(
            f"No App Store Connect key at {KEY_PATH}.\n"
            "Set ASC_KEY_PATH to the .p8, or see the store-credentials notes."
        )

    token = _token()

    print("=== App Store versions ===")
    print("    LABEL is what buyers see. TRAIN is the binary's own version,")
    print("    and is the one that closes when the version is released.")
    print("    They are separate fields and they have drifted here.\n")
    print(f"  {'LABEL':<10} {'STATE':<26} {'BUILD':<7} TRAIN")
    versions = _get(f"/v1/apps/{APP_ID}/appStoreVersions?limit=50", token)["data"]
    closed_trains = []
    for v in versions:
        a = v["attributes"]
        build, train = _build_and_train(v["id"], token)
        if a["appStoreState"] == "READY_FOR_SALE" and train:
            closed_trains.append(train)
        print(
            f"  {a['versionString']:<10} {a['appStoreState']:<26} "
            f"{str(build or '-'):<7} {train or '-'}"
        )

    print("\n=== TestFlight trains ===")
    for v in _get(f"/v1/apps/{APP_ID}/preReleaseVersions?limit=50", token)["data"]:
        print(f"  {v['attributes']['version']}")

    print("\n=== Builds (newest first) ===")
    print("    CFBundleVersion, which CI derives as max(seen) + 1.\n")
    for b in _get(f"/v1/apps/{APP_ID}/builds?limit=10", token)["data"]:
        a = b["attributes"]
        print(
            f"  build {a['version']:<5} {a['processingState']:<12} "
            f"expired={str(a['expired']):<5} {a.get('uploadedDate') or ''}"
        )

    labels = [
        v["attributes"]["versionString"]
        for v in versions
        if v["attributes"]["appStoreState"] == "READY_FOR_SALE"
    ]
    print("\n=== What pubspec.yaml `version:` must clear ===\n")
    if closed_trains:
        print("  CLOSED TRAINS - no build of these can ever upload again")
        print("  (90186). This is the list that actually bites, and it is")
        print("  NOT the labels above:")
        print("      " + ", ".join(sorted(set(closed_trains))))
    if labels:
        print("\n  RELEASED LABELS - the next record must be above these")
        print("  (90062):")
        print("      " + ", ".join(labels))
    print("\n  Pick a `version:` that is above the released labels and is")
    print("  not any closed train.")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        raise SystemExit(f"App Store Connect returned {e.code}: {e.read().decode()}")
