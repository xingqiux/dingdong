// Dingdong server: AI 带 token 发通知，菜单栏客户端通过 SSE 实时接收。
package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

type Message struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Body      string `json:"body"`
	Source    string `json:"source"`
	Level     string `json:"level"`         // info | success | warning | error
	URL       string `json:"url,omitempty"` // 可选：点击卡片时打开
	CreatedAt int64  `json:"createdAt"`     // unix 毫秒
}

type Event struct {
	Type     string    `json:"type"` // snapshot | message | delete | clear
	Message  *Message  `json:"message,omitempty"`
	Messages []Message `json:"messages,omitempty"`
	ID       string    `json:"id,omitempty"`
}

const (
	maxTitle  = 80
	maxBody   = 500
	maxSource = 40
	maxURL    = 1000
)

var validLevels = map[string]bool{"info": true, "success": true, "warning": true, "error": true}

// ---------- Hub：存储 + 广播 ----------

type Hub struct {
	mu   sync.Mutex
	msgs []Message // 按时间升序
	subs map[chan []byte]struct{}
	path string
	max  int
}

func NewHub(path string, max int) *Hub {
	h := &Hub{subs: map[chan []byte]struct{}{}, path: path, max: max}
	if b, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(b, &h.msgs)
	}
	return h
}

func (h *Hub) saveLocked() {
	b, _ := json.Marshal(h.msgs)
	tmp := h.path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err == nil {
		_ = os.Rename(tmp, h.path)
	}
}

func (h *Hub) broadcastLocked(ev Event) {
	b, _ := json.Marshal(ev)
	for ch := range h.subs {
		select {
		case ch <- b:
		default: // 客户端太慢就丢，它重连时会拿到 snapshot
		}
	}
}

func (h *Hub) Add(m Message) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.msgs = append(h.msgs, m)
	if len(h.msgs) > h.max {
		h.msgs = h.msgs[len(h.msgs)-h.max:]
	}
	h.saveLocked()
	h.broadcastLocked(Event{Type: "message", Message: &m})
}

func (h *Hub) Delete(id string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for i, m := range h.msgs {
		if m.ID == id {
			h.msgs = append(h.msgs[:i], h.msgs[i+1:]...)
			h.saveLocked()
			h.broadcastLocked(Event{Type: "delete", ID: id})
			return true
		}
	}
	return false
}

func (h *Hub) Clear() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.msgs = nil
	h.saveLocked()
	h.broadcastLocked(Event{Type: "clear"})
}

func (h *Hub) List(limit int) []Message {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := make([]Message, 0, len(h.msgs))
	for i := len(h.msgs) - 1; i >= 0 && len(out) < limit; i-- {
		out = append(out, h.msgs[i])
	}
	return out // 新的在前
}

func (h *Hub) Subscribe() (chan []byte, []Message) {
	h.mu.Lock()
	ch := make(chan []byte, 32)
	h.subs[ch] = struct{}{}
	h.mu.Unlock()
	return ch, h.List(h.max)
}

func (h *Hub) Unsubscribe(ch chan []byte) {
	h.mu.Lock()
	delete(h.subs, ch)
	h.mu.Unlock()
}

// ---------- 工具 ----------

func newID() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return strconv.FormatInt(time.Now().UnixMilli(), 36) + hex.EncodeToString(b)
}

func clip(s string, n int) string {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)
	return string(r[:n-1]) + "…"
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func tokenFrom(r *http.Request) string {
	if a := r.Header.Get("Authorization"); strings.HasPrefix(a, "Bearer ") {
		return strings.TrimSpace(a[7:])
	}
	if t := r.Header.Get("X-Token"); t != "" {
		return t
	}
	return r.URL.Query().Get("token")
}

func loadOrCreateToken(dataDir string) string {
	if t := os.Getenv("DINGDONG_TOKEN"); t != "" {
		return t
	}
	p := filepath.Join(dataDir, "token")
	if b, err := os.ReadFile(p); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		return strings.TrimSpace(string(b))
	}
	b := make([]byte, 18)
	_, _ = rand.Read(b)
	t := "dd_" + hex.EncodeToString(b)
	_ = os.WriteFile(p, []byte(t+"\n"), 0o600)
	return t
}

// ---------- main ----------

func main() {
	addr := flag.String("addr", envOr("DINGDONG_ADDR", "127.0.0.1:8787"), "监听地址")
	dataDir := flag.String("data", envOr("DINGDONG_DATA", "./data"), "数据目录")
	keep := flag.Int("keep", 200, "最多保留多少条消息")
	flag.Parse()

	if err := os.MkdirAll(*dataDir, 0o700); err != nil {
		log.Fatal(err)
	}
	token := loadOrCreateToken(*dataDir)
	hub := NewHub(filepath.Join(*dataDir, "messages.json"), *keep)

	auth := func(next http.HandlerFunc) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			if subtle.ConstantTimeCompare([]byte(tokenFrom(r)), []byte(token)) != 1 {
				writeJSON(w, 401, map[string]any{"ok": false, "error": "invalid token"})
				return
			}
			next(w, r)
		}
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]any{"ok": true})
	})

	// 发通知：POST JSON / POST 表单 / GET query 都行，方便各种 AI 调用
	notify := auth(func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Title   string `json:"title"`
			Body    string `json:"body"`
			Content string `json:"content"`
			Source  string `json:"source"`
			Level   string `json:"level"`
			URL     string `json:"url"`
		}
		r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
		if strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
			if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
				writeJSON(w, 400, map[string]any{"ok": false, "error": "invalid json"})
				return
			}
		} else {
			_ = r.ParseForm()
			in.Title, in.Body, in.Source = r.Form.Get("title"), r.Form.Get("body"), r.Form.Get("source")
			in.Level, in.URL, in.Content = r.Form.Get("level"), r.Form.Get("url"), r.Form.Get("content")
		}
		if in.Body == "" {
			in.Body = in.Content // 兼容 content 字段名
		}
		m := Message{
			ID:        newID(),
			Title:     clip(in.Title, maxTitle),
			Body:      clip(in.Body, maxBody),
			Source:    clip(in.Source, maxSource),
			Level:     strings.ToLower(strings.TrimSpace(in.Level)),
			URL:       clip(in.URL, maxURL),
			CreatedAt: time.Now().UnixMilli(),
		}
		if m.Title == "" {
			writeJSON(w, 400, map[string]any{"ok": false, "error": "title is required"})
			return
		}
		if m.Source == "" {
			m.Source = clip(r.Header.Get("X-Source"), maxSource)
		}
		if m.Source == "" {
			m.Source = "未知来源"
		}
		if !validLevels[m.Level] {
			m.Level = "info"
		}
		if m.URL != "" && !strings.HasPrefix(m.URL, "http://") && !strings.HasPrefix(m.URL, "https://") {
			m.URL = ""
		}
		hub.Add(m)
		log.Printf("notify  %-12s %s", m.Source, m.Title)
		writeJSON(w, 201, map[string]any{"ok": true, "id": m.ID})
	})
	mux.HandleFunc("POST /api/notify", notify)
	mux.HandleFunc("GET /api/notify", notify)

	mux.HandleFunc("GET /api/messages", auth(func(w http.ResponseWriter, r *http.Request) {
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		if limit <= 0 || limit > *keep {
			limit = 50
		}
		writeJSON(w, 200, map[string]any{"ok": true, "messages": hub.List(limit)})
	}))

	mux.HandleFunc("DELETE /api/messages/{id}", auth(func(w http.ResponseWriter, r *http.Request) {
		ok := hub.Delete(r.PathValue("id"))
		log.Printf("delete  %s ok=%v", r.PathValue("id"), ok)
		writeJSON(w, 200, map[string]any{"ok": ok})
	}))

	mux.HandleFunc("DELETE /api/messages", auth(func(w http.ResponseWriter, r *http.Request) {
		hub.Clear()
		log.Printf("clear all")
		writeJSON(w, 200, map[string]any{"ok": true})
	}))

	// 客户端订阅：先发一份 snapshot，之后实时推送；每 15 秒心跳
	mux.HandleFunc("GET /api/stream", auth(func(w http.ResponseWriter, r *http.Request) {
		fl, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming unsupported", 500)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("X-Accel-Buffering", "no") // nginx 反代时别缓冲

		ch, snap := hub.Subscribe()
		defer hub.Unsubscribe(ch)
		sort.SliceStable(snap, func(i, j int) bool { return snap[i].CreatedAt > snap[j].CreatedAt })
		b, _ := json.Marshal(Event{Type: "snapshot", Messages: snap})
		fmt.Fprintf(w, "data: %s\n\n", b)
		fl.Flush()
		log.Printf("client connected   %s", r.RemoteAddr)
		defer log.Printf("client disconnected %s", r.RemoteAddr)

		tick := time.NewTicker(15 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-r.Context().Done():
				return
			case b := <-ch:
				fmt.Fprintf(w, "data: %s\n\n", b)
				fl.Flush()
			case <-tick.C:
				fmt.Fprint(w, ": ping\n\n")
				fl.Flush()
			}
		}
	}))

	log.Printf("🔔 Dingdong server listening on http://%s", *addr)
	log.Printf("   token: %s", token)
	log.Printf("   data:  %s", *dataDir)
	srv := &http.Server{Addr: *addr, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
