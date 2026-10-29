#!/usr/bin/env python3
"""Blanks secrets out of CI logs before they are uploaded as artifacts.

The CI mirror, Mulhimfy/ayahReel-ci, is public, and so are its artifacts:
anyone signed in to GitHub can download them. GitHub masks secrets in a
job's own log, never in a file the job writes. `shorebird --verbose`
writes the whole environment into its log (Xcode lists every variable
among its build settings), and on 2026-10-13 the iOS patch log of
gipatch-1.0.9+11 carried the Shorebird token, the App Store Connect key
and the signing certificate's key that way. All three were replaced.

  REDACT_VARS="SHOREBIRD_TOKEN ..." python3 tool/redact_logs.py <file>...

Every value of the variables named in REDACT_VARS, and every line of a
multi-line one (a PEM key), becomes ***. Files that don't exist are
skipped, so a workflow can list every log it might have written. A file
that still holds a secret afterwards is deleted rather than uploaded.
tool/public_mirror.sh refuses a workflow that uploads logs without this.
"""
import os
import sys


def secrets():
    found = set()
    for name in os.environ.get('REDACT_VARS', '').split():
        value = os.environ.get(name, '')
        for part in [value, *value.splitlines()]:
            part = part.strip()
            # Shorter pieces are PEM padding or ids too common to blank.
            if len(part) >= 8:
                found.add(part.encode())
    # Longest first, so a whole value goes before the lines inside it.
    return sorted(found, key=len, reverse=True)


def main(paths):
    values = secrets()
    for path in paths:
        if not os.path.isfile(path):
            continue
        with open(path, 'rb') as f:
            data = f.read()
        hits = 0
        for value in values:
            hits += data.count(value)
            data = data.replace(value, b'***')
        if any(value in data for value in values):
            os.remove(path)
            print(f'redact: {path} still held a secret; deleted, not uploaded')
            continue
        with open(path, 'wb') as f:
            f.write(data)
        print(f'redact: {path}: {hits} secret(s) blanked')


if __name__ == '__main__':
    main(sys.argv[1:])
