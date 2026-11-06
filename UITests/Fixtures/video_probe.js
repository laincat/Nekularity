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
            ],
            maxPage: 1,
        }),
    }

    video = {
        loadInfo: async (id) => ({
            id: id,
            title: id === "hls" ? "Probe HLS" : "Probe Clip",
            description: "a clip served by the test runner",
            lines: [
                {id: "line1", name: "Line 1", episodes: [{id: "ep1", title: "Episode 1"}]},
            ],
        }),
        // The episode id alone does not say which video it belongs to, so the
        // play answer branches on the video id.
        loadPlay: async (videoId) => videoId === "hls" ? {
            url: "http://127.0.0.1:18731/hls/master.m3u8",
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
