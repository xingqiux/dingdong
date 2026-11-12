// Dingdong server: AI 带 token 发通知，菜单栏客户端通过 SSE 实时接收。
package main

import (
	"flag"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var version = "dev" // 发布时用 -ldflags "-X main.version=x.y.z" 写入

func main() {
	addr := flag.String("addr", envOr("DINGDONG_ADDR", "127.0.0.1:8787"), "监听地址")
	dataDir := flag.String("data", envOr("DINGDONG_DATA", "./data"), "数据目录")
	keep := flag.Int("keep", 200, "最多保留多少条消息")
	days := flag.Int("days", 30, "消息最多保留多少天（0 表示不限）")
	rate := flag.Int("rate", 30, "每个发送方每分钟最多几条（0 表示不限）")
	burst := flag.Int("burst", 10, "限流桶容量：短时间内最多连发几条")
	dedup := flag.Duration("dedup", 2*time.Minute, "多长时间内的重复通知合并成一条（0 表示不合并）")
	flag.Parse()

	if err := os.MkdirAll(*dataDir, 0o700); err != nil {
		log.Fatal(err)
	}
	admin, generated := loadOrCreateAdminToken(*dataDir)
	app := &App{
		hub:     NewHub(filepath.Join(*dataDir, "messages.json"), *keep, time.Duration(*days)*24*time.Hour, *dedup),
		tokens:  NewTokens(admin, filepath.Join(*dataDir, "tokens.json")),
		limiter: NewLimiter(*rate, *burst),
		keep:    *keep,
		now:     time.Now,
	}

	log.Printf("🔔 Dingdong server %s listening on http://%s", version, *addr)
	log.Printf("   data: %s", *dataDir)
	if generated {
		// 只在第一次生成时打印完整 token，之后日志里不再出现
		log.Printf("   admin token (只显示这一次): %s", admin)
		if pub := os.Getenv("DINGDONG_PUBLIC_URL"); pub != "" {
			log.Printf("   一键连接: dingdong://connect?url=%s&token=%s", url.QueryEscape(pub), url.QueryEscape(admin))
		}
	} else {
		log.Printf("   admin token: %s…（完整值见 DINGDONG_TOKEN 或数据目录的 token 文件）", admin[:min(6, len(admin))])
	}
	log.Printf("   senders: %d · rate %d/min · dedup %s · keep %d / %dd", len(app.tokens.List()), *rate, *dedup, *keep, *days)

	srv := &http.Server{Addr: *addr, Handler: app.routes(), ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

func loadOrCreateAdminToken(dataDir string) (string, bool) {
	if t := strings.TrimSpace(os.Getenv("DINGDONG_TOKEN")); t != "" {
		return t, false
	}
	p := filepath.Join(dataDir, "token")
	if b, err := os.ReadFile(p); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		return strings.TrimSpace(string(b)), false
	}
	t := "dd_" + randomHex(18)
	_ = os.WriteFile(p, []byte(t+"\n"), 0o600)
	return t, true
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
