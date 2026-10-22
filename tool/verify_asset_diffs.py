#!/usr/bin/env python3
"""Whether a patch's asset differences from a PC-built release are only
the PC's own way of writing the same files. Exit 0 if so, 1 if not.

Android releases built on the user's Windows PC differ from any build
on Codemagic in two assets, and in nothing about their content:
  - base/assets/quran_verses.json, the home widget's verses: the PC's
    checkout writes it with CRLF;
  - base/assets/flutter_assets/NOTICES.Z, the licences: Flutter gzips
    them on the machine that builds, and the gzip header records that
    machine's OS, so a Mac's file never equals a Windows one; the PC's
    checkout of Flutter also gives some licences CRLF, which Flutter
    then lists apart from their LF twins.
A patch never carries assets: phones keep the release's copies. So the
user allowed (2026-10-05) these two, and only these two, to differ, as
long as this script finds the same content in them as in the release.
Anything else, or different content, is refused.

Usage: verify_asset_diffs.py <dry-run.log>
"""
import glob
import os
import sys
import zipfile
import zlib
from pathlib import Path

BUILT = Path('build/app/outputs/bundle/release/app-release.aab')
NOTICES = 'base/assets/flutter_assets/NOTICES.Z'
VERSES = 'base/assets/quran_verses.json'
ALLOWED = {NOTICES, VERSES}
SEP = '\n' + '-' * 80 + '\n'


def release_aab():
    """The release's own bundle, which Shorebird downloads to compare: a
    file named `artifact` in a fresh temp folder."""
    roots = {os.environ.get('TMPDIR', ''), '/tmp', '/var/folders'}
    found = {}
    for r in filter(None, roots):
        for p in glob.glob(os.path.join(r, '**', 'artifact'), recursive=True):
            p = Path(p)
            try:
                if (p.is_file() and p.stat().st_size > 5_000_000
                        and zipfile.is_zipfile(p)
                        and NOTICES in zipfile.ZipFile(p).namelist()):
                    found[p.resolve()] = p
            except (OSError, zipfile.BadZipFile):
                pass
    found = sorted(found.values(), key=lambda p: p.stat().st_mtime, reverse=True)
    for p in found:
        print(f'release bundle: {p} ({p.stat().st_size} bytes)')
    return found[0] if found else None


def changed(log):
    out, on = [], False
    for line in Path(log).read_text(errors='replace').splitlines():
        if 'Changed files:' in line:
            on = True
            continue
        if on:
            s = line.strip()
            if not s.startswith('base/'):
                on = False
                continue
            if s not in out:
                out.append(s)
    return out


def licences(text):
    """Each licence text, with every package it covers: the same map
    however the entries were grouped, and whatever the line endings."""
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    out = {}
    for entry in text.split(SEP):
        entry = entry.strip('\n')
        if not entry:
            continue
        names, _, body = entry.partition('\n\n')
        out.setdefault(body.strip(), set()).update(
            n.strip() for n in names.split('\n') if n.strip())
    return out


def main(log):
    entries = changed(log)
    print('changed:', entries or 'none')
    if not entries:
        print('VERDICT: nothing to judge')
        return 1
    extra = [e for e in entries if e not in ALLOWED]
    if extra:
        print('VERDICT: refused, changed beyond the two allowed:', extra)
        return 1
    rel_path = release_aab()
    if rel_path is None or not BUILT.is_file():
        print('VERDICT: refused, no release bundle or no build to compare')
        return 1
    rel, new = zipfile.ZipFile(rel_path), zipfile.ZipFile(BUILT)
    for e in entries:
        a, b = rel.read(e), new.read(e)
        if e == VERSES:
            ok = a.replace(b'\r\n', b'\n') == b.replace(b'\r\n', b'\n')
            print(f'{e}: {"same content, line endings apart" if ok else "DIFFERENT content"}')
        else:
            ta = zlib.decompress(a, 47).decode('utf-8')
            tb = zlib.decompress(b, 47).decode('utf-8')
            la, lb = licences(ta), licences(tb)
            ok = la == lb
            print(f'{e}: gzip OS byte release {a[9] if len(a) > 9 else "?"}, build '
                  f'{b[9] if len(b) > 9 else "?"}; {len(la)} vs {len(lb)} licences; '
                  f'{"same licences" if ok else "DIFFERENT licences"}')
            if not ok:
                for body in set(la) ^ set(lb):
                    print('  only in', 'release' if body in la else 'build', ':',
                          sorted(la.get(body) or lb.get(body))[:6])
        if not ok:
            print('VERDICT: refused, content differs')
            return 1
    print('VERDICT: same content; only the PC\'s bytes differ')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
