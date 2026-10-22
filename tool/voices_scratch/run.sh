#!/usr/bin/env bash
# Scratch: what this research run does, shard by shard.
set -uo pipefail
mkdir -p out
case "$1" in
  taraweeh) python3 -I tool/voices_scratch/taraweeh.py 2>&1 | tee out/taraweeh.txt ;;
esac
