package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	maxTitle  = 80
	maxBody   = 500
	maxSource = 40
	maxURL    = 1000
)

var validLevels = map[string]bool{"info": true, "success": true, "warning": true, "error": true}

type App struct {
	hub     *Hub
	tokens  *Tokens
	limiter *Limiter
	keep    int
	now     func() time.Time
}

type NotifyInput struct {
	Title   string `json:"title"`
	Body    string `json:"body"`
	Content string `json:"content"` // body 的别名
	Source  string `json:"source"`
	Level   string `json:"level"`
	URL     string `json:"url"`
}

type apiError struct {
	code  int
	msg   string
	retry time.Duration
}

func (e *apiError) Error() string { return e.msg }

// submit 是 HTTP 和 MCP 共用的发通知逻辑。
func (a *App) submit(p Principal, in NotifyInput, fallbackSource string) (Message, bool, error) {
	if ok, wait := a.limiter.Allow(p.key(), a.now()); !ok {
		return Message{}, false, &apiError{429, fmt.Sprintf("rate limited, retry in %ds", int(math.Ceil(wait.Seconds()))), wait}
	}
	if in.Body == "" {
		in.Body = in.Content
	}
	m := Message{
		ID:    strconv.FormatInt(a.now().UnixMilli(), 36) + randomHex(4),
		Title: clip(in.Title, maxTitle),
		Body:  clip(in.Body, maxBody),
		Level: strings.ToLower(strings.TrimSpace(in.Level)),
		URL:   clip(in.URL, maxURL),
	}
	if m.Title == "" {
		return Message{}, false, &apiError{code: 400, msg: "title is required"}
	}
	// 发送方令牌的来源固定是令牌名字，没法冒充别人
	if p.Admin {
		m.Source = clip(in.Source, maxSource)
		if m.Source == "" {
			m.Source = clip(fallbackSource, maxSource)
		}
		if m.Source == "" {
			m.Source = "未知来源"
		}
	} else {
		m.Source = p.Name
	}
	if !validLevels[m.Level] {
		m.Level = "info"
	}
	if m.URL != "" && !strings.HasPrefix(m.URL, "http://") && !strings.HasPrefix(m.URL, "https://") {
		m.URL = ""
	}
	m, deduped := a.hub.Submit(m)
	if !p.Admin {
		a.tokens.Touch(p.Name)
	}
	if deduped {
		log.Printf("notify  %-12s %s (×%d)", m.Source, m.Title, m.Count)
	} else {
		log.Printf("notify  %-12s %s", m.Source, m.Title)
	}
	return m, deduped, nil
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

func writeErr(w http.ResponseWriter, err error) {
	if e, ok := err.(*apiError); ok {
		if e.retry > 0 {
			w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(e.retry.Seconds()))))
		}
		writeJSON(w, e.code, map[string]any{"ok": false, "error": e.msg})
		return
	}
	writeJSON(w, 500, map[string]any{"ok": false, "error": err.Error()})
}

func tokenFrom(r *http.Request) string {
	if a := r.Header.Get("Authorization"); strings.HasPrefix(a, "Bearer ") {
		return strings.TrimSpace(a[7:])
	}
	if t := r.Header.Get("X-Token"); t != "" {
		return strings.TrimSpace(t)
	}
	return r.URL.Query().Get("token")
}

type handler func(http.ResponseWriter, *http.Request, Principal)

// auth：adminOnly 的接口（读消息、删消息、管理令牌）发送方令牌不能用。
func (a *App) auth(adminOnly bool, next handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		p, ok := a.tokens.Identify(tokenFrom(r))
		if !ok {
			writeJSON(w, 401, map[string]any{"ok": false, "error": "invalid token"})
			return
		}
		if adminOnly && !p.Admin {
			writeJSON(w, 403, map[string]any{"ok": false, "error": "this token can only send notifications"})
			return
		}
		next(w, r, p)
	}
}

func (a *App) routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]any{"ok": true, "version": version})
	})

	notify := a.auth(false, func(w http.ResponseWriter, r *http.Request, p Principal) {
		var in NotifyInput
		r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
		if strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
			if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
				writeJSON(w, 400, map[string]any{"ok": false, "error": "invalid json"})
				return
			}
		} else {
			_ = r.ParseForm()
			f := r.Form
			in = NotifyInput{Title: f.Get("title"), Body: f.Get("body"), Content: f.Get("content"),
				Source: f.Get("source"), Level: f.Get("level"), URL: f.Get("url")}
		}
		m, deduped, err := a.submit(p, in, r.Header.Get("X-Source"))
		if err != nil {
			writeErr(w, err)
			return
		}
		code := 201
		if deduped {
			code = 200
		}
		writeJSON(w, code, map[string]any{"ok": true, "id": m.ID, "deduped": deduped})
	})
	mux.HandleFunc("POST /api/notify", notify)
	mux.HandleFunc("GET /api/notify", notify)

	mux.HandleFunc("GET /api/messages", a.auth(true, func(w http.ResponseWriter, r *http.Request, _ Principal) {
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		if limit <= 0 || limit > a.keep {
			limit = 50
		}
		writeJSON(w, 200, map[string]any{"ok": true, "messages": a.hub.List(limit)})
	}))

	mux.HandleFunc("DELETE /api/messages/{id}", a.auth(true, func(w http.ResponseWriter, r *http.Request, _ Principal) {
		ok := a.hub.Delete(r.PathValue("id"))
		log.Printf("delete  %s ok=%v", r.PathValue("id"), ok)
		writeJSON(w, 200, map[string]any{"ok": ok})
	}))

	mux.HandleFunc("DELETE /api/messages", a.auth(true, func(w http.ResponseWriter, r *http.Request, _ Principal) {
		a.hub.Clear()
		log.Printf("clear all")
		writeJSON(w, 200, map[string]any{"ok": true})
	}))

	// 发送方令牌管理（只有客户端的管理员 token 能用）
	mux.HandleFunc("GET /api/tokens", a.auth(true, func(w http.ResponseWriter, r *http.Request, _ Principal) {
		writeJSON(w, 200, map[string]any{"ok": true, "tokens": a.tokens.List()})
	}))
	mux.HandleFunc("POST /api/tokens", a.auth(true, func(w http.ResponseWriter, r *http.Request, _ Principal) {
		var in struct {
			Name string `json:"name"`
		}
		r.Body = http.MaxBytesReader(w, r.Body, 4<<10)
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeJSON(w, 400, map[string]any{"ok": false, "error": "invalid json"})
			return
		}
		tok, v, err := a.tokens.Create(in.Name)
		if err != nil {
			writeJSON(w, 400, map[string]any{"ok": false, "error": err.Error()})
			return
		}
		log.Printf("token   created %s (%s…)", v.Name, v.Prefix)
		writeJSON(w, 201, map[string]any{"ok": true, "token": tok, "info": v})
	}))
	mux.HandleFunc("DELETE /api/tokens/{name}", a.auth(true, func(w http.ResponseWriter, r *http.Request, _ Principal) {
		ok := a.tokens.Revoke(r.PathValue("name"))
		log.Printf("token   revoked %s ok=%v", r.PathValue("name"), ok)
		writeJSON(w, 200, map[string]any{"ok": ok})
	}))

	// 客户端订阅：先发一份 snapshot，之后实时推送；每 15 秒心跳
	mux.HandleFunc("GET /api/stream", a.auth(true, func(w http.ResponseWriter, r *http.Request, _ Principal) {
		fl, ok := w.(http.Flusher)
		if !ok {
			http.Error(w, "streaming unsupported", 500)
			return
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-cache")
		w.Header().Set("X-Accel-Buffering", "no") // nginx 反代时别缓冲

		ch, snap := a.hub.Subscribe()
		defer a.hub.Unsubscribe(ch)
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

	// MCP（Streamable HTTP，无状态）：给支持 MCP 的 AI 客户端一个 notify 工具
	mux.HandleFunc("POST /mcp", a.auth(false, a.handleMCP))
	mux.HandleFunc("GET /mcp", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Allow", "POST")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	})

	return mux
}
