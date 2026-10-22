#!/usr/bin/env bash
# Scratch: what this research run does, shard by shard.
set -uo pipefail
mkdir -p out
case "$1" in
  taraweeh) python3 -I tool/voices_scratch/taraweeh2.py 2>&1 | tee out/taraweeh2.txt ;;
esac
