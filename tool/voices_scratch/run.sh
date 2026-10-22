#!/usr/bin/env bash
# Scratch: what this research run does, shard by shard.
set -uo pipefail
mkdir -p out
case "$1" in
  p0) python3 -I tool/voices_scratch/stage2.py pairs 0 2 2>&1 | tee out/pairs0.txt ;;
  p1) python3 -I tool/voices_scratch/stage2.py pairs 1 2 2>&1 | tee out/pairs1.txt ;;
  f0) python3 -I tool/voices_scratch/stage2.py full 0 3 2>&1 | tee out/full0.txt ;;
  f1) python3 -I tool/voices_scratch/stage2.py full 1 3 2>&1 | tee out/full1.txt ;;
  f2) python3 -I tool/voices_scratch/stage2.py full 2 3 2>&1 | tee out/full2.txt ;;
  c0) python3 -I tool/voices_scratch/stage2.py check 0 3 2>&1 | tee out/check0.txt ;;
  c1) python3 -I tool/voices_scratch/stage2.py check 1 3 2>&1 | tee out/check1.txt ;;
  c2) python3 -I tool/voices_scratch/stage2.py check 2 3 2>&1 | tee out/check2.txt ;;
  meta) python3 -I tool/voices_scratch/meta.py tool/voices_scratch/meta_specs.txt 2>&1 | tee out/meta.txt ;;
esac
