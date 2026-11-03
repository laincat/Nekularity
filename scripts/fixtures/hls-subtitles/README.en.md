# Local HLS subtitle fixture

English | [简体中文](README.md)

This service supports targeted iOS player acceptance and reads media from the supplied directory. The repository includes the media30/ resume test clip; bilingual subtitle media is still supplied from an external directory. Attribution and licensing are below. No real accounts or credentials are included.

```sh
go run scripts/fixtures/hls-subtitles/main.go -root /path/to/hls-subs
```

Existing test media is available in Nekophage `c545212` at `internal/player/testdata/hls-subs`: a master playlist, byte-ranged fMP4 and Chinese/English WebVTT, with Chinese default and English optional. The picture is adapted from Big Buck Bunny, © 2008 Blender Foundation, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), resized, compressed and packaged as audio-free HLS; captions are test text. The service binds only `127.0.0.1` on a random port. Its first JSON line contains `source_url`, serving an installable `VideoSource` script that declares the actual service URL and fixed fake Referer. It installs no background service or startup job; stop the owned process when finished.

Every request except `/source.js` must carry `Referer: https://fixture.invalid/`. Each request produces JSON containing its path, method, Referer match, Range, status, response byte count and Content-Range. No real credentials are logged. Go's standard file server handles media byte ranges; playlists and WebVTT receive their corresponding MIME types. Fetching the source script requires no Referer.

The Lead verified the source URL, missing-Referer 403 responses, bilingual playlists and UTF-8 captions, an exact 32-byte Range 206 and out-of-range 416 through actual Windows loopback HTTP. Log: `E:/Temp/nk-ios-hls-evidence/verify.log`. This validates the fixture service, not the iOS player or its interface.

## Thirty-second resume media

`media30/` repeats the same licensed clip three times and repackages it as thirty-second HLS, with video only and no audio or subtitles. Supply that directory as `-root` to reuse the service; retain the original ten-second bilingual media for subtitle cases. Seven seconds now sits well before the end and satisfies the client’s strict greater-than-five-second resume rule. Playing the original ten-second clip from seven seconds for about 2.7 seconds reaches its tail; pressing play afterward can legitimately rewind the engine. A later zero position alone does not establish failure of the initial resume.

Windows FFmpeg actually decoded 900 frames, playlist duration totals 30 seconds, and frame digests at zero and seven seconds differ; evidence: `E:/Temp/nk-hls-resume-30-evidence/`. iOS must still verify persisted and reopened positions. Do not inject progress or require this media to validate subtitles. Picture attribution remains Blender Foundation/CC BY 3.0 above; changes are repetition and lossless repackaging.

Targeted simulator acceptance should use the dedicated device and local source, observing an actual advancing video/frame, Chinese subtitles, active English text after selection and disappearance after disabling subtitles. Pausing at a cue can prevent the short clip from ending during controls. Record service requests and screenshots; a track name alone does not establish rendering. Later app reopening or cross-process resume requires separate attribution. This media has no audio, so it does not establish speaker, background, PiP or device behavior.
