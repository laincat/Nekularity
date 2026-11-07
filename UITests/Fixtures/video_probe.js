// A video source that answers without a site, so the player can be tested.
//
// The clip is served by the test runner on loopback — the same trick the reader
// uses for a page image — and the server refuses the request unless it carries
// this source's `Referer`. That is the point: a video source's headers are part
// of what it declares, and a client that drops them plays nothing on the sites
// that check. If this test fails, either the client's path from `video.loadPlay`
// to the engine is broken, or the headers never left the client.
class VideoProbe extends VideoSource {
    name = "Video Probe"
    key = "video_probe"
    version = "1.0.0"

    search = {
        load: async () => ({
            videos: [
                {id: "clip", title: "Probe Clip", subtitle: "loopback"},
                // HLS with two subtitle groups (中文 default, English alternate).
                {id: "hls", title: "Probe HLS", subtitle: "loopback hls"},
                // 30 s, no subtitles: a save point at 7 s is far from the end.
                {id: "resume", title: "Probe Resume", subtitle: "loopback resume"},
                // 30 s with two subtitle groups: long enough that picking a
                // track mid-playback cannot run into the end of the clip.
                {id: "hls30", title: "Probe HLS 30", subtitle: "loopback hls 30s"},
            ],
            maxPage: 1,
        }),
    }

    video = {
        loadInfo: async (id) => ({
            id: id,
            title: id === "hls" ? "Probe HLS" : id === "resume" ? "Probe Resume"
                : id === "hls30" ? "Probe HLS 30" : "Probe Clip",
            description: "a clip served by the test runner",
            lines: [
                {id: "line1", name: "Line 1", episodes: [{id: "ep1", title: "Episode 1"}]},
            ],
        }),
        // The episode id alone does not say which video it belongs to, so the
        // play answer branches on the video id.
        loadPlay: async (videoId) => videoId === "hls30" ? {
            url: "http://127.0.0.1:18731/hls/resume/master30.m3u8",
            format: "hls",
            headers: {Referer: "http://127.0.0.1:18731/"},
        } : videoId === "resume" ? {
            url: "http://127.0.0.1:18731/hls/resume/master.m3u8",
            format: "hls",
            headers: {Referer: "http://127.0.0.1:18731/"},
        } : videoId === "hls" ? {
            url: "http://127.0.0.1:18731/hls/resume/master30.m3u8",
            format: "hls",
            headers: {Referer: "http://127.0.0.1:18731/"},
        } : ({
            url: "http://127.0.0.1:18731/clip.mp4",
            format: "mp4",
            // The runner answers 403 without this header.
            headers: {Referer: "http://127.0.0.1:18731/"},
        }),
    }
}
