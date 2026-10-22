#!/usr/bin/env bash
# Scratch: what this research run does, shard by shard.
set -uo pipefail
mkdir -p out
case "$1" in
  calib) python3 -I tool/voices_scratch/screen.py calib 2>&1 | tee out/calib.txt ;;
  s0) python3 -I tool/voices_scratch/screen.py screen 0 3 2>&1 | tee out/screen0.txt ;;
  s1) python3 -I tool/voices_scratch/screen.py screen 1 3 2>&1 | tee out/screen1.txt ;;
  s2) python3 -I tool/voices_scratch/screen.py screen 2 3 2>&1 | tee out/screen2.txt ;;
  luhaidan) python3 -I tool/voices_scratch/luhaidan.py 2>&1 | tee out/luhaidan.txt ;;
esac
