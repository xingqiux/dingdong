package main

import (
	"bufio"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const adminTok = "dd_test_admin"

type clock struct{ t time.Time }

func (c *clock) now() time.Time { return c.t }

func newTestApp(t *testing.T, rate, burst int, dedup time.Duration) (*App, *clock) {
	t.Helper()
	dir := t.TempDir()
	c := &clock{t: time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)}
	hub := NewHub(filepath.Join(dir, "messages.json"), 200, 30*24*time.Hour, dedup)
	hub.now = c.now
	toks := NewTokens(adminTok, filepath.Join(dir, "tokens.json"))
	toks.now = c.now
	return &App{hub: hub, tokens: toks, limiter: NewLimiter(rate, burst), keep: 200, now: c.now}, c
}

func do(t *testing.T, h http.Handler, method, path, token, body string) (int, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out
}

func createSender(t *testing.T, h http.Handler, name string) string {
	t.Helper()
	code, out := do(t, h, "POST", "/api/tokens", adminTok, `{"name":"`+name+`"}`)
	if code != 201 {
		t.Fatalf("create token: %d %v", code, out)
	}
	return out["token"].(string)
}

func TestNotifyAuthAndSourceBinding(t *testing.T) {
	app, _ := newTestApp(t, 0, 0, 0)
	h := app.routes()

	if code, _ := do(t, h, "POST", "/api/notify", "", `{"title":"x"}`); code != 401 {
		t.Fatalf("no token: want 401, got %d", code)
	}
	if code, _ := do(t, h, "POST", "/api/notify", "wrong", `{"title":"x"}`); code != 401 {
		t.Fatalf("bad token: want 401, got %d", code)
	}
	if code, _ := do(t, h, "POST", "/api/notify", adminTok, `{"body":"no title"}`); code != 400 {
		t.Fatalf("missing title: want 400, got %d", code)
	}
	if code, _ := do(t, h, "POST", "/api/notify", adminTok, `{"title":"admin msg","source":"Me"}`); code != 201 {
		t.Fatalf("admin notify: want 201, got %d", code)
	}

	tok := createSender(t, h, "Claude Code")
	if code, _ := do(t, h, "POST", "/api/notify", tok, `{"title":"hi","source":"Pretender"}`); code != 201 {
		t.Fatalf("sender notify: want 201, got %d", code)
	}
	msgs := app.hub.List(10)
	if msgs[0].Source != "Claude Code" {
		t.Fatalf("sender source must be bound to token name, got %q", msgs[0].Source)
	}
	if msgs[1].Source != "Me" {
		t.Fatalf("admin source should be taken from body, got %q", msgs[1].Source)
	}
}

func TestSenderCannotReadOrManage(t *testing.T) {
	app, _ := newTestApp(t, 0, 0, 0)
	h := app.routes()
	tok := createSender(t, h, "bot")
	for _, c := range []struct{ m, p string }{
		{"GET", "/api/messages"}, {"GET", "/api/stream"}, {"DELETE", "/api/messages"},
		{"GET", "/api/tokens"}, {"POST", "/api/tokens"}, {"DELETE", "/api/tokens/bot"},
	} {
		if code, _ := do(t, h, c.m, c.p, tok, ""); code != 403 {
			t.Errorf("%s %s with sender token: want 403, got %d", c.m, c.p, code)
		}
	}
}

func TestRevokeAndRotate(t *testing.T) {
	app, _ := newTestApp(t, 0, 0, 0)
	h := app.routes()
	old := createSender(t, h, "bot")
	fresh := createSender(t, h, "bot") // 同名即轮换
	if code, _ := do(t, h, "POST", "/api/notify", old, `{"title":"x"}`); code != 401 {
		t.Fatalf("rotated token should be invalid, got %d", code)
	}
	if code, _ := do(t, h, "POST", "/api/notify", fresh, `{"title":"x"}`); code != 201 {
		t.Fatalf("new token should work, got %d", code)
	}
	_, out := do(t, h, "GET", "/api/tokens", adminTok, "")
	list := out["tokens"].([]any)
	if len(list) != 1 || list[0].(map[string]any)["count"].(float64) != 1 {
		t.Fatalf("want one token with count 1, got %v", list)
	}
	if strings.Contains(mustJSON(out), "hash") {
		t.Fatal("token list must not expose hashes")
	}
	do(t, h, "DELETE", "/api/tokens/bot", adminTok, "")
	if code, _ := do(t, h, "POST", "/api/notify", fresh, `{"title":"x"}`); code != 401 {
		t.Fatalf("revoked token should be invalid, got %d", code)
	}
}

func TestDedupMergesRepeats(t *testing.T) {
	app, clk := newTestApp(t, 0, 0, 2*time.Minute)
	h := app.routes()
	body := `{"title":"build failed","body":"same","source":"CI"}`
	do(t, h, "POST", "/api/notify", adminTok, body)
	clk.t = clk.t.Add(30 * time.Second)
	code, out := do(t, h, "POST", "/api/notify", adminTok, body)
	if code != 200 || out["deduped"] != true {
		t.Fatalf("second identical notify should dedup: %d %v", code, out)
	}
	msgs := app.hub.List(10)
	if len(msgs) != 1 || msgs[0].Count != 2 {
		t.Fatalf("want 1 message with count 2, got %+v", msgs)
	}
	clk.t = clk.t.Add(5 * time.Minute)
	do(t, h, "POST", "/api/notify", adminTok, body)
	if n := len(app.hub.List(10)); n != 2 {
		t.Fatalf("outside window should create new message, got %d", n)
	}
}

func TestRateLimit(t *testing.T) {
	app, clk := newTestApp(t, 6, 2, 0)
	h := app.routes()
	tok := createSender(t, h, "spammer")
	for i := 0; i < 2; i++ {
		if code, _ := do(t, h, "POST", "/api/notify", tok, `{"title":"x`+string(rune('a'+i))+`"}`); code != 201 {
			t.Fatalf("burst %d: want 201, got %d", i, code)
		}
	}
	req := httptest.NewRequest("POST", "/api/notify", strings.NewReader(`{"title":"z"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+tok)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != 429 || rec.Header().Get("Retry-After") == "" {
		t.Fatalf("want 429 with Retry-After, got %d", rec.Code)
	}
	// 其他发送方不受影响
	if code, _ := do(t, h, "POST", "/api/notify", adminTok, `{"title":"admin"}`); code != 201 {
		t.Fatalf("admin should have its own bucket, got %d", code)
	}
	clk.t = clk.t.Add(10 * time.Second) // 6/min => 10s 回 1 个
	if code, _ := do(t, h, "POST", "/api/notify", tok, `{"title":"later"}`); code != 201 {
		t.Fatalf("after refill: want 201, got %d", code)
	}
}

func TestPruneByAge(t *testing.T) {
	app, clk := newTestApp(t, 0, 0, 0)
	h := app.routes()
	do(t, h, "POST", "/api/notify", adminTok, `{"title":"old"}`)
	clk.t = clk.t.Add(31 * 24 * time.Hour)
	do(t, h, "POST", "/api/notify", adminTok, `{"title":"new"}`)
	msgs := app.hub.List(10)
	if len(msgs) != 1 || msgs[0].Title != "new" {
		t.Fatalf("old message should be pruned, got %+v", msgs)
	}
}

func TestClip(t *testing.T) {
	if got := clip("  你好世界  ", 3); got != "你好…" {
		t.Fatalf("clip: %q", got)
	}
	if got := clip("abc", 3); got != "abc" {
		t.Fatalf("clip: %q", got)
	}
}

func TestMCP(t *testing.T) {
	app, _ := newTestApp(t, 0, 0, 0)
	h := app.routes()
	tok := createSender(t, h, "Codex")

	code, out := do(t, h, "POST", "/mcp", tok, `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}`)
	if code != 200 || out["result"].(map[string]any)["protocolVersion"] != "2025-03-26" {
		t.Fatalf("initialize: %d %v", code, out)
	}
	if code, _ := do(t, h, "POST", "/mcp", tok, `{"jsonrpc":"2.0","method":"notifications/initialized"}`); code != 202 {
		t.Fatalf("notification should get 202, got %d", code)
	}
	_, out = do(t, h, "POST", "/mcp", tok, `{"jsonrpc":"2.0","id":2,"method":"tools/list"}`)
	if !strings.Contains(mustJSON(out), `"notify"`) {
		t.Fatalf("tools/list missing notify: %v", out)
	}
	_, out = do(t, h, "POST", "/mcp", tok, `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"notify","arguments":{"title":"MCP 你好","body":"b","level":"success"}}}`)
	if out["result"].(map[string]any)["isError"] != false {
		t.Fatalf("tools/call failed: %v", out)
	}
	m := app.hub.List(1)[0]
	if m.Title != "MCP 你好" || m.Source != "Codex" || m.Level != "success" {
		t.Fatalf("unexpected message %+v", m)
	}
	_, out = do(t, h, "POST", "/mcp", tok, `{"jsonrpc":"2.0","id":4,"method":"nope"}`)
	if out["error"].(map[string]any)["code"].(float64) != -32601 {
		t.Fatalf("unknown method: %v", out)
	}
	if code, _ := do(t, h, "POST", "/mcp", "", `{"jsonrpc":"2.0","id":1,"method":"ping"}`); code != 401 {
		t.Fatalf("mcp without token: want 401, got %d", code)
	}
}

func TestStreamDeliversSnapshotThenLive(t *testing.T) {
	app, _ := newTestApp(t, 0, 0, 0)
	srv := httptest.NewServer(app.routes())
	defer srv.Close()
	do(t, app.routes(), "POST", "/api/notify", adminTok, `{"title":"before"}`)

	req, _ := http.NewRequest("GET", srv.URL+"/api/stream", nil)
	req.Header.Set("Authorization", "Bearer "+adminTok)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	rd := bufio.NewReader(resp.Body)
	next := func() Event {
		for {
			line, err := rd.ReadString('\n')
			if err != nil {
				t.Fatal(err)
			}
			if strings.HasPrefix(line, "data: ") {
				var ev Event
				_ = json.Unmarshal([]byte(line[6:]), &ev)
				return ev
			}
		}
	}
	if ev := next(); ev.Type != "snapshot" || len(ev.Messages) != 1 {
		t.Fatalf("want snapshot with 1 message, got %+v", ev)
	}
	go func() {
		r, _ := http.NewRequest("POST", srv.URL+"/api/notify", strings.NewReader(`{"title":"live"}`))
		r.Header.Set("Authorization", "Bearer "+adminTok)
		r.Header.Set("Content-Type", "application/json")
		res, _ := http.DefaultClient.Do(r)
		io.Copy(io.Discard, res.Body)
		res.Body.Close()
	}()
	if ev := next(); ev.Type != "message" || ev.Message.Title != "live" {
		t.Fatalf("want live message, got %+v", ev)
	}
}

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}
