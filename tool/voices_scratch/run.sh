#!/usr/bin/env bash
# Scratch: what this research run does.
set -uo pipefail
mkdir -p out
python3 -I tool/voices_scratch/discover2.py 2>&1 | tee out/discover2.txt
