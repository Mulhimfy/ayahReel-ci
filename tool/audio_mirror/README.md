# Audio mirror

Every voice's files and published verse tables are copied to the public
repository [Mulhimfy/ayahreel-audio](https://github.com/Mulhimfy/ayahreel-audio),
one release per voice (`voice-<id>`). When a voice's host fails, the app
reads the same bytes from there (`lib/data/audio_mirror.dart`). A file
is read out of its pack with a Range request, so resuming and slicing
work exactly as they do against the host.

Our own timing is never mirrored. That covers the OwnTiming verse tables
(Sobhi, Al-Luhaidan) and the word timing; they stay behind the
key-gated Worker. `manifest.py` lists no table for those voices.

## When the voice list changes

A voice added to `reciters` is looked up in the mirror at once, but it
has no fallback until it is copied:

```sh
python3 tool/audio_mirror/manifest.py > voices.json  # into a clone of ayahreel-audio
git commit voices.json && git push
gh workflow run mirror.yml --repo Mulhimfy/ayahreel-audio -f voices=<id>,<id> -f mode=voice
```

Copying a voice again (because its host changed a file) uploads new packs
under new names, then the new index, then deletes the old packs. A phone
holding the old index meets a 404 on its pack and fetches the index again.

`-f mode=check` reads every file of the listed voices back by range and
checks it against `sums.json`, the hashes taken when the files came from
their hosts.
