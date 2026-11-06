# hls-subs

[简体中文](hls-subs.md) | English

The HLS fixture for the interface case `testHLSPlaysAndSwitchesSubtitles`: a master playlist with two WebVTT subtitle groups (Chinese default, English alternate) over fMP4 byte-range segments, no audio track. The files are byte-identical to Nekophage's `internal/player/testdata/hls-subs` (`stream.mp4` md5 `d321224cce67c39a7f30eb9a90e1dfec`).

- The picture is adapted from **Big Buck Bunny**, © 2008 Blender Foundation, [peach.blender.org](https://peach.blender.org/), [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). The source is `clip.mp4` in this folder; the changes are scaling, compression and audio-less HLS packaging.
- The subtitles are test text.

The test process serves these files under `/hls/` on loopback and answers 403 to any request without the source's declared `Referer`.
