package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"slices"
)

type rpcReq struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type rpcErr struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type rpcResp struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   *rpcErr         `json:"error,omitempty"`
}

var mcpVersions = []string{"2025-06-18", "2025-03-26", "2024-11-05"}

const mcpInstructions = "叮咚（Dingdong）把通知推到用户 Mac 的菜单栏。" +
	"在长任务完成、需要用户确认或做决定、遇到阻塞时调用 notify。标题一句话，内容不超过两句。" +
	" / Dingdong pushes a notification to the user's Mac menu bar. Call notify when a long task finishes, " +
	"when you need the user's confirmation or decision, or when you are blocked. Keep the title to one line and the body to two sentences."

var notifyTool = map[string]any{
	"name":        "notify",
	"title":       "发通知到菜单栏",
	"description": mcpInstructions,
	"inputSchema": map[string]any{
		"type": "object",
		"properties": map[string]any{
			"title": map[string]any{"type": "string", "maxLength": maxTitle, "description": "一句话标题 / one-line title"},
			"body":  map[string]any{"type": "string", "maxLength": maxBody, "description": "简短内容，最多两句 / short body, up to two sentences"},
			"level": map[string]any{"type": "string", "enum": []string{"info", "success", "warning", "error"}, "description": "默认 info；error 的卡片不会自动消失"},
			"url":   map[string]any{"type": "string", "description": "可选，点击卡片时打开的 http(s) 链接"},
		},
		"required": []string{"title"},
	},
}

func (a *App) handleMCP(w http.ResponseWriter, r *http.Request, p Principal) {
	raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 64<<10))
	if err != nil {
		writeJSON(w, 413, rpcResp{JSONRPC: "2.0", ID: json.RawMessage("null"), Error: &rpcErr{-32600, "request too large"}})
		return
	}
	raw = bytes.TrimSpace(raw)
	var reqs []rpcReq
	batch := len(raw) > 0 && raw[0] == '['
	if batch {
		err = json.Unmarshal(raw, &reqs)
	} else {
		var one rpcReq
		err = json.Unmarshal(raw, &one)
		reqs = []rpcReq{one}
	}
	if err != nil {
		writeJSON(w, 400, rpcResp{JSONRPC: "2.0", ID: json.RawMessage("null"), Error: &rpcErr{-32700, "parse error"}})
		return
	}

	var out []rpcResp
	for _, q := range reqs {
		if len(q.ID) == 0 || string(q.ID) == "null" {
			continue // 通知类消息（如 notifications/initialized）不用回
		}
		res, e := a.mcpCall(p, q)
		out = append(out, rpcResp{JSONRPC: "2.0", ID: q.ID, Result: res, Error: e})
	}
	switch {
	case len(out) == 0:
		w.WriteHeader(http.StatusAccepted)
	case batch:
		writeJSON(w, 200, out)
	default:
		writeJSON(w, 200, out[0])
	}
}

func (a *App) mcpCall(p Principal, q rpcReq) (any, *rpcErr) {
	switch q.Method {
	case "initialize":
		var params struct {
			ProtocolVersion string `json:"protocolVersion"`
		}
		_ = json.Unmarshal(q.Params, &params)
		v := mcpVersions[0]
		if slices.Contains(mcpVersions, params.ProtocolVersion) {
			v = params.ProtocolVersion
		}
		return map[string]any{
			"protocolVersion": v,
			"capabilities":    map[string]any{"tools": map[string]any{}},
			"serverInfo":      map[string]any{"name": "dingdong", "title": "叮咚 Dingdong", "version": version},
			"instructions":    mcpInstructions,
		}, nil
	case "ping":
		return map[string]any{}, nil
	case "tools/list":
		return map[string]any{"tools": []any{notifyTool}}, nil
	case "tools/call":
		var params struct {
			Name      string      `json:"name"`
			Arguments NotifyInput `json:"arguments"`
		}
		if err := json.Unmarshal(q.Params, &params); err != nil {
			return nil, &rpcErr{-32602, "invalid params"}
		}
		if params.Name != "notify" {
			return nil, &rpcErr{-32602, "unknown tool: " + params.Name}
		}
		params.Arguments.Source = ""
		m, deduped, err := a.submit(p, params.Arguments, "MCP")
		if err != nil {
			return toolText(true, "没发出去："+err.Error()), nil
		}
		msg := fmt.Sprintf("已通知用户（id %s）", m.ID)
		if deduped {
			msg = fmt.Sprintf("同样的通知刚发过，已合并（第 %d 次）", m.Count)
		}
		return toolText(false, msg), nil
	default:
		return nil, &rpcErr{-32601, "method not found: " + q.Method}
	}
}

func toolText(isErr bool, s string) map[string]any {
	return map[string]any{"content": []any{map[string]any{"type": "text", "text": s}}, "isError": isErr}
}
