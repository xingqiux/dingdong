package main

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// Principal 是一次请求的身份：管理员（客户端用）或某个发送方（一个 AI 一个）。
type Principal struct {
	Admin bool
	Name  string
}

func (p Principal) key() string {
	if p.Admin {
		return "\x00admin"
	}
	return p.Name
}

// Sender 是一个只能发通知的令牌。只存哈希，明文只在创建时返回一次。
type Sender struct {
	Name       string `json:"name"`
	Hash       string `json:"hash"`
	Prefix     string `json:"prefix"`
	CreatedAt  int64  `json:"createdAt"`
	LastUsedAt int64  `json:"lastUsedAt,omitempty"`
	Count      int64  `json:"count"`
}

type SenderView struct {
	Name       string `json:"name"`
	Prefix     string `json:"prefix"`
	CreatedAt  int64  `json:"createdAt"`
	LastUsedAt int64  `json:"lastUsedAt,omitempty"`
	Count      int64  `json:"count"`
}

type Tokens struct {
	mu      sync.Mutex
	admin   string
	senders []Sender
	path    string
	now     func() time.Time
}

func NewTokens(admin, path string) *Tokens {
	t := &Tokens{admin: admin, path: path, now: time.Now}
	if b, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(b, &t.senders)
	}
	return t
}

func hashToken(tok string) string {
	s := sha256.Sum256([]byte(tok))
	return hex.EncodeToString(s[:])
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (t *Tokens) Identify(tok string) (Principal, bool) {
	if tok == "" {
		return Principal{}, false
	}
	if subtle.ConstantTimeCompare([]byte(tok), []byte(t.admin)) == 1 {
		return Principal{Admin: true}, true
	}
	h := []byte(hashToken(tok))
	t.mu.Lock()
	defer t.mu.Unlock()
	for _, s := range t.senders {
		if subtle.ConstantTimeCompare(h, []byte(s.Hash)) == 1 {
			return Principal{Name: s.Name}, true
		}
	}
	return Principal{}, false
}

func (t *Tokens) saveLocked() {
	b, _ := json.MarshalIndent(t.senders, "", "  ")
	tmp := t.path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err == nil {
		_ = os.Rename(tmp, t.path)
	}
}

func (t *Tokens) Touch(name string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	for i := range t.senders {
		if t.senders[i].Name == name {
			t.senders[i].LastUsedAt = t.now().UnixMilli()
			t.senders[i].Count++
			t.saveLocked()
			return
		}
	}
}

var errBadName = errors.New("name must be 1-40 characters")

// Create 新建发送令牌；同名的已存在就轮换（旧令牌立即失效）。
func (t *Tokens) Create(name string) (string, SenderView, error) {
	name = strings.TrimSpace(name)
	if name == "" || utf8.RuneCountInString(name) > maxSource {
		return "", SenderView{}, errBadName
	}
	tok := "dds_" + randomHex(20)
	s := Sender{Name: name, Hash: hashToken(tok), Prefix: tok[:8], CreatedAt: t.now().UnixMilli()}
	t.mu.Lock()
	defer t.mu.Unlock()
	for i := range t.senders {
		if strings.EqualFold(t.senders[i].Name, name) {
			s.Count = t.senders[i].Count
			t.senders[i] = s
			t.saveLocked()
			return tok, view(s), nil
		}
	}
	t.senders = append(t.senders, s)
	t.saveLocked()
	return tok, view(s), nil
}

func (t *Tokens) Revoke(name string) bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	for i := range t.senders {
		if t.senders[i].Name == name {
			t.senders = append(t.senders[:i:i], t.senders[i+1:]...)
			t.saveLocked()
			return true
		}
	}
	return false
}

func (t *Tokens) List() []SenderView {
	t.mu.Lock()
	defer t.mu.Unlock()
	out := make([]SenderView, 0, len(t.senders))
	for _, s := range t.senders {
		out = append(out, view(s))
	}
	return out
}

func view(s Sender) SenderView {
	return SenderView{Name: s.Name, Prefix: s.Prefix, CreatedAt: s.CreatedAt, LastUsedAt: s.LastUsedAt, Count: s.Count}
}

// Limiter 是按发送方计的令牌桶：每分钟 perMin 条，最多攒 burst 条。
type Limiter struct {
	mu      sync.Mutex
	perMin  float64
	burst   float64
	buckets map[string]*bucket
}

type bucket struct {
	tokens float64
	last   time.Time
}

func NewLimiter(perMin, burst int) *Limiter {
	return &Limiter{perMin: float64(perMin), burst: float64(burst), buckets: map[string]*bucket{}}
}

func (l *Limiter) Allow(key string, now time.Time) (bool, time.Duration) {
	if l.perMin <= 0 {
		return true, 0
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	b, ok := l.buckets[key]
	if !ok {
		b = &bucket{tokens: l.burst, last: now}
		l.buckets[key] = b
	}
	b.tokens = min(l.burst, b.tokens+now.Sub(b.last).Minutes()*l.perMin)
	b.last = now
	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	wait := time.Duration((1 - b.tokens) / l.perMin * float64(time.Minute))
	return false, wait
}
