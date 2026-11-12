import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class Store {
    var messages: [Message] = []
    var status: ConnStatus = .unconfigured
    var unread = 0
    /// 每来一条新消息 +1，视图用它触发铃铛摇摆
    var ringTick = 0
    var popoverOpen = false { didSet { if popoverOpen { unread = 0; onUnreadChange?(0) } } }

    var serverURL: String { didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") } }
    var token: String { didSet { UserDefaults.standard.set(token, forKey: "token") } }
    var soundOn: Bool { didSet { UserDefaults.standard.set(soundOn, forKey: "soundOn") } }
    var toastOn: Bool { didSet { UserDefaults.standard.set(toastOn, forKey: "toastOn") } }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("launch at login: \(error)") }
        }
    }

    var onNew: ((Message) -> Void)?
    var onUnreadChange: ((Int) -> Void)?
    var onStatusChange: ((ConnStatus) -> Void)?

    private var task: Task<Void, Never>?
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 45 // 服务端每 15s 心跳
        c.timeoutIntervalForResource = 60 * 60 * 24 * 365
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    init() {
        let d = UserDefaults.standard
        serverURL = d.string(forKey: "serverURL") ?? "http://127.0.0.1:8787"
        token = d.string(forKey: "token") ?? ""
        soundOn = d.object(forKey: "soundOn") as? Bool ?? true
        toastOn = d.object(forKey: "toastOn") as? Bool ?? true

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.connect() } }
    }

    private var base: URL? {
        let s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s.hasSuffix("/") ? String(s.dropLast()) : s),
              u.scheme == "http" || u.scheme == "https" else { return nil }
        return u
    }

    private func setStatus(_ s: ConnStatus) {
        guard status != s else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { status = s }
        onStatusChange?(s)
    }

    // MARK: - 连接

    func connect() {
        task?.cancel()
        task = Task { [weak self] in await self?.runLoop() }
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

            do {
                let (bytes, resp) = try await session.bytes(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 401 {
                    setStatus(.unauthorized)
                    return // 等用户改 token 后再连
                }
                guard code == 200 else { throw URLError(.badServerResponse) }
                setStatus(.online)
                backoff = 1
                for try await line in bytes.lines {
                    guard line.hasPrefix("data:") else { continue }
                    handle(Data(line.dropFirst(5).utf8))
                }
            } catch {
                if Task.isCancelled { return }
            }
            setStatus(.offline)
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
        }
    }

    private func handle(_ data: Data) {
        guard let ev = try? JSONDecoder().decode(StreamEvent.self, from: data) else { return }
        let spring = Animation.spring(response: 0.5, dampingFraction: 0.72)
        switch ev.type {
        case "snapshot":
            withAnimation(spring) { messages = ev.messages ?? [] }
        case "message":
            guard let m = ev.message, !messages.contains(where: { $0.id == m.id }) else { return }
            withAnimation(spring) { messages.insert(m, at: 0) }
            ringTick += 1
            if !popoverOpen {
                unread += 1
                onUnreadChange?(unread)
            }
            if soundOn { NSSound(named: "Pop")?.play() }
            onNew?(m)
        case "delete":
            withAnimation(spring) { messages.removeAll { $0.id == ev.id } }
        case "clear":
            withAnimation(spring) { messages.removeAll() }
        default: break
        }
    }

    // MARK: - 操作

    func delete(_ m: Message) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { messages.removeAll { $0.id == m.id } }
        send("DELETE", "api/messages/\(m.id)")
    }

    func clearAll() {
        // 从上往下依次飞走
        for (i, m) in messages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) { [weak self] in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self?.messages.removeAll { $0.id == m.id }
                }
            }
        }
        send("DELETE", "api/messages")
    }

    private func send(_ method: String, _ path: String) {
        guard let base else { return }
        var req = URLRequest(url: base.appending(path: path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        Task { _ = try? await URLSession.shared.data(for: req) }
    }

    /// 给自己发一条测试通知
    func sendTest() async -> Bool {
        guard let base else { return false }
        var req = URLRequest(url: base.appending(path: "api/notify"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let samples: [[String: String]] = [
            ["title": "叮咚～连上啦", "body": "以后 AI 有事找你，就会从这里冒出来 ✿", "source": "Dingdong", "level": "success"],
            ["title": "这是一条测试通知", "body": "标题、内容、来源、时间，就这四样。", "source": "测试", "level": "info"],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: samples.randomElement()!)
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 201
    }

    var curlExample: String {
        """
        curl -X POST \(serverURL.trimmingCharacters(in: .whitespaces))/api/notify \\
          -H "Authorization: Bearer \(token)" \\
          -H "Content-Type: application/json" \\
          -d '{"title":"任务完成","body":"简短内容","source":"Claude"}'
        """
    }
}
