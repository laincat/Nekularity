# Local HLS subtitle fixture

English | [简体中文](README.md)

This service supports targeted iOS player acceptance. It reads media from the supplied directory; media is not included in this repository, and no real accounts or site media are copied.

```sh
go run scripts/fixtures/hls-subtitles/main.go -root /path/to/hls-subs
```

Existing self-generated media is available in Nekophage `c545212` at `internal/player/testdata/hls-subs`: a master playlist, byte-ranged fMP4 and Chinese/English WebVTT, with Chinese default and English optional. The service binds only `127.0.0.1` on a random port. Its first JSON line contains `source_url`, serving an installable `VideoSource` script that declares the actual service URL and fixed fake Referer. It installs no background service or startup job; stop the owned process when finished.

Every request except `/source.js` must carry `Referer: https://fixture.invalid/`. Each request produces JSON containing its path, method, Referer match, Range, status, response byte count and Content-Range. No real credentials are logged. Go's standard file server handles media byte ranges; playlists and WebVTT receive their corresponding MIME types. Fetching the source script requires no Referer.

The Lead verified the source URL, missing-Referer 403 responses, bilingual playlists and UTF-8 captions, an exact 32-byte Range 206 and out-of-range 416 through actual Windows loopback HTTP. Log: `E:/Temp/nk-ios-hls-evidence/verify.log`. This validates the fixture service, not the iOS player or its interface.

Targeted simulator acceptance should use the dedicated device and local source, observing an actual advancing video/frame, Chinese subtitles, active English text after selection and disappearance after disabling subtitles. Pausing at a cue can prevent the short clip from ending during controls. Record service requests and screenshots; a track name alone does not establish rendering. Later app reopening or cross-process resume requires separate attribution. This media has no audio, so it does not establish speaker, background, PiP or device behavior.
