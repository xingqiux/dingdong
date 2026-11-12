import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let args = CommandLine.arguments
    private lazy var demo = args.contains("--demo")
    private lazy var store = Store(demo: demo)
    private var bar: StatusBarController!
    private var toast: ToastController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        bar = StatusBarController(store: store)
        toast = ToastController()
        toast.onTap = { [weak self] in self?.bar.show() }

        store.onNew = { [weak self] m in
            guard let self else { return }
            self.bar.ring()
            if self.store.shouldToast(m) { self.toast.show(m, anchor: self.bar.anchorFrame) }
        }
        store.onMissed = { [weak self] missed in
            guard let self else { return }
            self.bar.ring()
            let shown = missed.filter { self.store.shouldToast($0) }
            if !shown.isEmpty { self.toast.showMissed(shown, anchor: self.bar.anchorFrame) }
        }

        if demo { runDemo(); return }
        store.connect()
        if store.token.trimmingCharacters(in: .whitespaces).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.bar.show() }
        }
    }

    // MARK: - dingdong://connect?url=…&token=…

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { handle(u) }
    }

    private func handle(_ u: URL) {
        guard u.scheme == "dingdong", u.host == "connect",
              let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems,
              let server = items.first(where: { $0.name == "url" })?.value,
              let token = items.first(where: { $0.name == "token" })?.value,
              let su = URL(string: server), su.scheme == "http" || su.scheme == "https" else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "连接到这个叮咚服务器？"
        alert.informativeText = "\(server)\n\n会替换当前的服务器地址和 token。只连接你自己信任的服务器。"
        alert.addButton(withTitle: "连接")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.serverURL = server
        store.token = token
        store.connect()
        bar.show(page: .inbox)
    }

    // MARK: - 演示模式（README 截图用）：--demo [--dark] [--page settings|tokens] [--toasts] [--winfile path]

    private func runDemo() {
        let look: NSAppearance? = args.contains("--dark") ? NSAppearance(named: .darkAqua)
            : args.contains("--light") ? NSAppearance(named: .aqua) : nil
        NSApp.appearance = look
        bar.setAppearance(look)
        toast.setAppearance(look)
        store.loadDemo()
        store.connect()
        let page: Page? = args.contains("settings") ? .settings : args.contains("tokens") ? .tokens : nil
        if args.contains("--toasts") {
            let ms = store.messages
            for (i, m) in ms.prefix(3).reversed().enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 0.4) {
                    self.toast.show(m, anchor: self.bar.anchorFrame)
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.bar.show(page: page) }
        }
        if let i = args.firstIndex(of: "--winfile"), i + 1 < args.count {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let s = "popover=\(self.bar.popoverWindowNumber ?? 0)\ntoast=\(self.toast.windowNumber)\n"
                try? s.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }
}

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
        let size = i + 2 < args.count ? CGFloat(Double(args[i + 2]) ?? 1024) : 1024
        exit(Render.png(AppIconView(), size: size, to: args[i + 1]) ? 0 : 1)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // 只在顶部栏，不进 Dock
    app.run()
}
