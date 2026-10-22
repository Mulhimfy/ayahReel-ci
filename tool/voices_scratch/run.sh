#!/usr/bin/env bash
# Scratch: what this research run does, shard by shard.
set -uo pipefail
mkdir -p out
case "$1" in
  taraweeh) python3 -I tool/voices_scratch/verse1.py \
      "surah https://download.quranicaudio.com/quran/mishaari_california SSS qul 95" \
      ghamdi salimi toure 2>&1 | tee out/verse1.txt ;;
esac
