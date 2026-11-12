package main

import (
	"encoding/json"
	"os"
	"sync"
	"time"
)

type Message struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Body      string `json:"body"`
	Source    string `json:"source"`
	Level     string `json:"level"`           // info | success | warning | error
	URL       string `json:"url,omitempty"`   // 可选：点击卡片时打开
	Count     int    `json:"count,omitempty"` // 去重合并后的次数（>=2 才有）
	CreatedAt int64  `json:"createdAt"`       // unix 毫秒；合并时更新为最后一次
}

type Event struct {
	Type     string    `json:"type"` // snapshot | message | update | delete | clear
	Message  *Message  `json:"message,omitempty"`
	Messages []Message `json:"messages,omitempty"`
	ID       string    `json:"id,omitempty"`
}

// Hub 负责存储消息并广播给所有在线客户端。msgs 按 CreatedAt 升序。
type Hub struct {
	mu     sync.Mutex
	msgs   []Message
	subs   map[chan []byte]struct{}
	path   string
	keep   int
	maxAge time.Duration
	dedup  time.Duration
	now    func() time.Time
}

func NewHub(path string, keep int, maxAge, dedup time.Duration) *Hub {
	h := &Hub{subs: map[chan []byte]struct{}{}, path: path, keep: keep, maxAge: maxAge, dedup: dedup, now: time.Now}
	if b, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(b, &h.msgs)
	}
	h.pruneLocked()
	return h
}

func (h *Hub) pruneLocked() {
	if h.maxAge > 0 {
		cut := h.now().Add(-h.maxAge).UnixMilli()
		i := 0
		for i < len(h.msgs) && h.msgs[i].CreatedAt < cut {
			i++
		}
		h.msgs = h.msgs[i:]
	}
	if len(h.msgs) > h.keep {
		h.msgs = h.msgs[len(h.msgs)-h.keep:]
	}
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

// Submit 存一条新消息。dedup 窗口内同来源、同内容的消息不新建，只把次数 +1 并顶到最前。
func (h *Hub) Submit(m Message) (Message, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	now := h.now().UnixMilli()
	m.CreatedAt = now
	if h.dedup > 0 {
		for i := len(h.msgs) - 1; i >= 0; i-- {
			o := h.msgs[i]
			if now-o.CreatedAt > h.dedup.Milliseconds() {
				break
			}
			if o.Source == m.Source && o.Title == m.Title && o.Body == m.Body && o.Level == m.Level && o.URL == m.URL {
				o.Count = max(o.Count, 1) + 1
				o.CreatedAt = now
				h.msgs = append(append(h.msgs[:i:i], h.msgs[i+1:]...), o)
				h.saveLocked()
				h.broadcastLocked(Event{Type: "update", Message: &o})
				return o, true
			}
		}
	}
	h.msgs = append(h.msgs, m)
	h.pruneLocked()
	h.saveLocked()
	h.broadcastLocked(Event{Type: "message", Message: &m})
	return m, false
}

func (h *Hub) Delete(id string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for i, m := range h.msgs {
		if m.ID == id {
			h.msgs = append(h.msgs[:i:i], h.msgs[i+1:]...)
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

// List 返回最新的 limit 条，新的在前。
func (h *Hub) List(limit int) []Message {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.listLocked(limit)
}

func (h *Hub) listLocked(limit int) []Message {
	out := make([]Message, 0, min(limit, len(h.msgs)))
	for i := len(h.msgs) - 1; i >= 0 && len(out) < limit; i-- {
		out = append(out, h.msgs[i])
	}
	return out
}

func (h *Hub) Subscribe() (chan []byte, []Message) {
	h.mu.Lock()
	defer h.mu.Unlock()
	ch := make(chan []byte, 32)
	h.subs[ch] = struct{}{}
	return ch, h.listLocked(h.keep)
}

func (h *Hub) Unsubscribe(ch chan []byte) {
	h.mu.Lock()
	delete(h.subs, ch)
	h.mu.Unlock()
}
