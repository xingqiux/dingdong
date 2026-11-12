import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

enum Motion {
    /// 系统设置里开了「减少动态效果」
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static func spring(_ response: Double = 0.5, _ damping: Double = 0.72) -> Animation {
        reduced ? .easeOut(duration: 0.15) : .spring(response: response, dampingFraction: damping)
    }
}

@MainActor
@Observable
final class Store {
    var messages: [Message] = []
    var status: ConnStatus = .unconfigured
    /// 每来一条新消息 +1，视图用它触发小猫/铃铛动画
    var ringTick = 0
    var tokens: [SenderToken] = []
    var popoverOpen = false {
        didSet { if popoverOpen { markAllSeen() } }
    }

    var serverURL: String { didSet { defaults.set(serverURL, forKey: "serverURL") } }
    var token: String { didSet { defaults.set(token, forKey: "token") } }
    var soundOn: Bool { didSet { defaults.set(soundOn, forKey: "soundOn") } }
    var toastOn: Bool { didSet { defaults.set(toastOn, forKey: "toastOn") } }
    var quietOn: Bool { didSet { defaults.set(quietOn, forKey: "quietOn"); onQuietChange?() } }
    var quietStart: Int { didSet { defaults.set(quietStart, forKey: "quietStart"); onQuietChange?() } }
    var quietEnd: Int { didSet { defaults.set(quietEnd, forKey: "quietEnd"); onQuietChange?() } }
    var snoozeUntil: Date? { didSet { defaults.set(snoozeUntil, forKey: "snoozeUntil"); onQuietChange?() } }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("launch at login: \(error)") }
        }
    }

    /// 看过的最新一条的时间：比它新的算未读（重启后也记得）
    private var lastSeenAt: Int64 { didSet { defaults.set(lastSeenAt, forKey: "lastSeenAt") } }
    /// 已经提醒过的最新一条的时间：重连后比它新的就是离线期间漏掉的
    private var lastAlertedAt: Int64 { didSet { defaults.set(lastAlertedAt, forKey: "lastAlertedAt") } }

    var unread: Int { messages.lazy.filter { $0.createdAt > self.lastSeenAt }.count }

    var onNew: ((Message) -> Void)?
    var onMissed: (([Message]) -> Void)?
    var onUnreadChange: ((Int) -> Void)?
    var onStatusChange: ((ConnStatus) -> Void)?
    var onQuietChange: (() -> Void)?

    /// 演示模式：不联网，用假数据（截图用）
    let demo: Bool
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private static func makeSession() -> URLSession {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 45 // 连上之后的空闲超时：服务端每 15s 心跳
        c.timeoutIntervalForResource = 60 * 60 * 24 * 365
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }

    init(demo: Bool = false) {
        self.demo = demo
        // 演示模式用单独的配置，不碰真实设置
        let d = demo ? (UserDefaults(suiteName: "local.dingdong.demo") ?? .standard) : .standard
        defaults = d
        serverURL = d.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
        token = d.string(forKey: "token") ?? ""
        soundOn = d.object(forKey: "soundOn") as? Bool ?? true
        toastOn = d.object(forKey: "toastOn") as? Bool ?? true
        quietOn = d.object(forKey: "quietOn") as? Bool ?? false
        quietStart = d.object(forKey: "quietStart") as? Int ?? 23
        quietEnd = d.object(forKey: "quietEnd") as? Int ?? 8
        snoozeUntil = d.object(forKey: "snoozeUntil") as? Date
        lastSeenAt = (d.object(forKey: "lastSeenAt") as? NSNumber)?.int64Value ?? 0
        lastAlertedAt = (d.object(forKey: "lastAlertedAt") as? NSNumber)?.int64Value ?? 0

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.connect() } }
    }

    // MARK: - 勿扰

    /// 安静时段或临时勿扰：不响、不弹（error 级别仍然弹，但不响）
    var isQuiet: Bool {
        if let s = snoozeUntil, s > .now { return true }
        guard quietOn else { return false }
        let h = Calendar.current.component(.hour, from: .now)
        return quietStart <= quietEnd ? (h >= quietStart && h < quietEnd) : (h >= quietStart || h < quietEnd)
    }

    func shouldToast(_ m: Message) -> Bool { toastOn && !popoverOpen && (!isQuiet || m.level == "error") }

    // MARK: - 连接

    private var base: URL? {
        let s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s.hasSuffix("/") ? String(s.dropLast()) : s),
              u.scheme == "http" || u.scheme == "https" else { return nil }
        return u
    }

    var baseString: String { base?.absoluteString ?? serverURL }

    private func setStatus(_ s: ConnStatus) {
        guard status != s else { return }
        withAnimation(Motion.spring(0.4, 0.7)) { status = s }
        onStatusChange?(s)
    }

    func connect() {
        task?.cancel()
        if demo { setStatus(.online); return }
        task = Task { [weak self] in await self?.runLoop() }
    }

    /// 错开发起的连接尝试（秒）：前一个迟迟没回音，就再开一个全新的连接一起等，谁先收到数据用谁
    private let attemptDelays: [Double] = [0, 3, 6]
    /// 所有尝试都没收到第一份数据就整体放弃重来（服务端连上会立刻发 snapshot）
    private let connectTimeout: Double = 12

    @MainActor private final class Race {
        var winner: Int?
        var tasks: [Task<Int, Never>] = []
        func win(_ k: Int) {
            guard winner == nil else { return }
            winner = k
            for (j, t) in tasks.enumerated() where j != k { t.cancel() }
        }
        func cancelAll() { tasks.forEach { $0.cancel() } }
    }

    private func runLoop() async {
        var backoff: Double = 1
        while !Task.isCancelled {
            let tok = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let base, !tok.isEmpty else { setStatus(.unconfigured); return }

            setStatus(.connecting)
            var req = URLRequest(url: base.appending(path: "api/stream"))
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            let race = Race()
            for (k, delay) in attemptDelays.enumerated() {
                race.tasks.append(Task { @MainActor [weak self] () -> Int in
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    guard let self, race.winner == nil, !Task.isCancelled else { return -1 }
                    let session = Self.makeSession() // 每次尝试用独立的连接池，避开卡住的连接
                    defer { session.invalidateAndCancel() }
                    do {
                        let (bytes, resp) = try await session.bytes(for: req)
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        guard code == 200 else { return code }
                        for try await line in bytes.lines {
                            guard line.hasPrefix("data:") else { continue }
                            if race.winner == nil {
                                race.win(k)
                                self.setStatus(.online)
                            }
                            guard race.winner == k else { return -1 }
                            self.handle(Data(line.dropFirst(5).utf8))
                        }
                        return 200
                    } catch {
                        return 0
                    }
                })
            }
            let watchdog = Task { @MainActor [connectTimeout] in
                try? await Task.sleep(for: .seconds(connectTimeout))
                if race.winner == nil { race.cancelAll() }
            }
            var codes: [Int] = []
            await withTaskCancellationHandler {
                for t in race.tasks { codes.append(await t.value) }
            } onCancel: {
                Task { @MainActor in race.cancelAll() }
            }
            watchdog.cancel()
            if Task.isCancelled { return }

            if codes.contains(401) || codes.contains(403) {
                setStatus(.unauthorized)
                return // 等用户改 token 后再连
            }
            if race.winner != nil {
                backoff = 1 // 正常连过一阵子才断的，马上重连
            } else if !codes.contains(where: { $0 > 0 && $0 != 200 }) {
                // 都卡在连接阶段：多半是网络抖动（代理、TUN），不是服务器挂了，马上再来
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            setStatus(.offline)
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
        }
    }

    private func handle(_ data: Data) {
        guard let ev = try? JSONDecoder().decode(StreamEvent.self, from: data) else { return }
        switch ev.type {
        case "snapshot":
            withAnimation(Motion.spring()) { messages = ev.messages ?? [] }
            catchUp()
        case "message", "update":
            guard let m = ev.message else { return }
            withAnimation(Motion.spring()) {
                messages.removeAll { $0.id == m.id }
                messages.insert(m, at: 0)
            }
            if popoverOpen { lastSeenAt = max(lastSeenAt, m.createdAt) }
            lastAlertedAt = max(lastAlertedAt, m.createdAt)
            alert()
            onNew?(m)
        case "delete":
            withAnimation(Motion.spring()) { messages.removeAll { $0.id == ev.id } }
        case "clear":
            withAnimation(Motion.spring()) { messages.removeAll() }
        default: break
        }
        onUnreadChange?(unread)
    }

    /// 重连后检查离线期间漏掉的消息
    private func catchUp() {
        let newest = messages.map(\.createdAt).max() ?? 0
        defer { lastAlertedAt = max(lastAlertedAt, newest) }
        guard lastAlertedAt > 0 else {
            // 第一次用：历史消息不当作未读，也不提醒
            lastSeenAt = max(lastSeenAt, newest)
            return
        }
        let missed = messages.filter { $0.createdAt > lastAlertedAt }
        guard !missed.isEmpty else { return }
        alert()
        onMissed?(missed)
    }

    private func alert() {
        ringTick += 1
        if soundOn && !isQuiet { NSSound(named: "Pop")?.play() }
    }

    private func markAllSeen() {
        lastSeenAt = max(lastSeenAt, messages.map(\.createdAt).max() ?? 0)
        onUnreadChange?(0)
    }

    // MARK: - 消息操作

    func delete(_ m: Message) {
        withAnimation(Motion.spring(0.4, 0.8)) { messages.removeAll { $0.id == m.id } }
        Task { _ = await request("DELETE", "api/messages/\(m.id)") }
    }

    func clearAll() {
        // 从上往下依次飞走
        for (i, m) in messages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.reduced ? 0 : Double(i) * 0.05)) { [weak self] in
                withAnimation(Motion.spring(0.35, 0.8)) { self?.messages.removeAll { $0.id == m.id } }
            }
        }
        Task { _ = await request("DELETE", "api/messages") }
    }

    /// 给自己发一条测试通知
    func sendTest() async -> Bool {
        let samples: [[String: String]] = [
            ["title": "叮咚～连上啦", "body": "以后 AI 有事找你，小猫就会从这里冒出来 ✿", "source": "Dingdong", "level": "success"],
            ["title": "这是一条测试通知", "body": "标题、内容、来源、时间，就这四样。", "source": "测试", "level": "info"],
        ]
        let (_, code) = await request("POST", "api/notify", json: samples.randomElement()!)
        return code == 201 || code == 200
    }

    // MARK: - AI 令牌

    func loadTokens() async {
        guard !demo else { return }
        let (data, code) = await request("GET", "api/tokens")
        guard code == 200, let data,
              let r = try? JSONDecoder().decode(TokenList.self, from: data) else { return }
        withAnimation(Motion.spring()) { tokens = r.tokens.sorted { $0.createdAt > $1.createdAt } }
    }

    /// 新建（或同名轮换）一个令牌，返回明文；只有这一次能看到
    func createToken(_ name: String) async -> Result<String, TokenError> {
        let (data, code) = await request("POST", "api/tokens", json: ["name": name])
        guard code == 201, let data,
              let r = try? JSONDecoder().decode(TokenCreated.self, from: data) else {
            return .failure(TokenError(code: code))
        }
        await loadTokens()
        return .success(r.token)
    }

    func revokeToken(_ name: String) async {
        withAnimation(Motion.spring()) { tokens.removeAll { $0.name == name } }
        let path = "api/tokens/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(.init(charactersIn: "/"))) ?? name)
        _ = await request("DELETE", path)
        await loadTokens()
    }

    struct TokenError: Error { let code: Int }
    private struct TokenList: Decodable { let tokens: [SenderToken] }
    private struct TokenCreated: Decodable { let token: String }

    private func request(_ method: String, _ path: String, json: [String: String]? = nil) async -> (Data?, Int) {
        guard let base, !demo else { return (nil, 0) }
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (nil, 0) }
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    // MARK: - 给 AI 的接入片段

    func snippets(for tok: String) -> [(String, String)] {
        let u = baseString
        return [
            ("curl", """
            curl -X POST \(u)/api/notify \\
              -H "Authorization: Bearer \(tok)" \\
              -H "Content-Type: application/json" \\
              -d '{"title":"任务完成","body":"简短内容"}'
            """),
            ("MCP", "claude mcp add --transport http --scope user dingdong \(u)/mcp --header \"Authorization: Bearer \(tok)\""),
            ("Claude Code 钩子", "curl -fsSL https://raw.githubusercontent.com/xingqiux/dingdong/main/integrations/claude-code/install.sh | bash -s -- \(u) \(tok)"),
        ]
    }

    // MARK: - 演示数据

    func loadDemo() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        func m(_ i: Int, _ t: String, _ b: String, _ s: String, _ l: String, ago: Int64, count: Int? = nil) -> Message {
            Message(id: "demo\(i)", title: t, body: b, source: s, level: l, url: nil, count: count, createdAt: now - ago * 1000)
        }
        messages = [
            m(1, "代码审查完成", "PR #42 没发现严重问题，有 3 处小建议已经写在评论里了。", "Claude Code", "success", ago: 20),
            m(2, "构建失败", "iOS target 编译报错：缺少签名证书", "CI", "error", ago: 240, count: 3),
            m(3, "记得喝水 💧", "已经连续工作两个小时啦", "小助手", "warning", ago: 1800),
            m(4, "数据导出好了", "共 1,284 行，已保存到桌面 report.xlsx", "Codex", "info", ago: 7200),
        ]
        tokens = [
            SenderToken(name: "Claude Code", prefix: "dds_8f2a", createdAt: now - 86_400_000, lastUsedAt: now - 20_000, count: 128),
            SenderToken(name: "Codex", prefix: "dds_c41e", createdAt: now - 3 * 86_400_000, lastUsedAt: now - 7_200_000, count: 37),
            SenderToken(name: "CI", prefix: "dds_07bd", createdAt: now - 9 * 86_400_000, lastUsedAt: now - 240_000, count: 512),
        ]
        lastSeenAt = now - 300_000
        lastAlertedAt = now
    }
}
