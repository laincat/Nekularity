# Source seed for the interface tests

[简体中文](README.md) | English

`plugins.json` is the client's own source store, holding the two fixture sources that live in this repository: `video_probe` (video) and `callback_probe` (comic callbacks). CI's interface-test step writes it into the simulator's app container before the run, so the cases that need sources no longer skip.

To regenerate it (from the desktop repository):

```sh
go run ./cmd/seedgen plugins.json \
  ../Nekularity/UITests/Fixtures/video_probe.js \
  ../Nekularity/UITests/Fixtures/callback_probe.js
```

`scripts/check-seed.sh` checks byte for byte that `callback_probe` matches the repository fixture; after changing a fixture, regenerate this seed or the check fails.

Sources for real sites (such as `nhentai` and `Komiic`) are other people's scripts and do not live here, so the cases that depend on them still skip.
