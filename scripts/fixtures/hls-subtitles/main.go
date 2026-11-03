// A loopback-only HLS fixture for the iOS player. Media stays outside this repo.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
)

const referer = "https://fixture.invalid/"

type responseLog struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (w *responseLog) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *responseLog) Write(data []byte) (int, error) {
	if w.status == 0 {
		w.WriteHeader(http.StatusOK)
	}
	n, err := w.ResponseWriter.Write(data)
	w.bytes += n
	return n, err
}

func main() {
	root := flag.String("root", "", "directory containing master.m3u8 and the local HLS/subtitle media")
	flag.Parse()
	if *root == "" {
		log.Fatal("-root is required")
	}
	if info, err := os.Stat(filepath.Join(*root, "master.m3u8")); err != nil || info.IsDir() {
		log.Fatal("media root must contain master.m3u8")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatal(err)
	}
	base := "http://" + listener.Addr().String()
	var mu sync.Mutex
	record := func(event any) {
		mu.Lock()
		defer mu.Unlock()
		if err := json.NewEncoder(os.Stdout).Encode(event); err != nil {
			log.Print(err)
		}
	}
	media := http.FileServer(http.Dir(*root))
	play, err := json.Marshal(map[string]any{
		"url": base + "/master.m3u8", "format": "hls",
		"headers": map[string]string{"Referer": referer},
	})
	if err != nil {
		log.Fatal(err)
	}
	source := fmt.Sprintf(`class LocalSubtitleProbe extends VideoSource {
  name = "Local Subtitle Probe";
  key = "local_subtitle_probe";
  version = "1.0.0";
  search = { load: async () => ({videos:[{id:"clip",title:"Local Subtitle Clip"}],maxPage:1}) };
  video = {
    loadInfo: async () => ({id:"clip",title:"Local Subtitle Clip",lines:[{id:"local",name:"Local",episodes:[{id:"ep1",title:"Subtitle episode"}]}]}),
    loadPlay: async () => (%s)
  };
}
`, play)
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		written := &responseLog{ResponseWriter: w}
		authorized := r.Header.Get("Referer") == referer
		defer func() {
			record(map[string]any{"event": "request", "method": r.Method, "path": r.URL.Path,
				"referer_ok": authorized, "range": r.Header.Get("Range"),
				"status": written.status, "bytes": written.bytes,
				"content_range": written.Header().Get("Content-Range")})
		}()
		written.Header().Set("Cache-Control", "no-store")
		if r.URL.Path == "/source.js" {
			written.Header().Set("Content-Type", "application/javascript; charset=utf-8")
			_, _ = written.Write([]byte(source))
			return
		}
		if !authorized {
			http.Error(written, "fixture requires its declared Referer", http.StatusForbidden)
			return
		}
		switch filepath.Ext(r.URL.Path) {
		case ".m3u8":
			written.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
		case ".vtt":
			written.Header().Set("Content-Type", "text/vtt; charset=utf-8")
		case ".mp4":
			written.Header().Set("Content-Type", "video/mp4")
		}
		media.ServeHTTP(written, r)
	})
	record(map[string]any{"event": "ready", "base_url": base, "source_url": base + "/source.js"})
	log.Fatal(http.Serve(listener, handler))
}
