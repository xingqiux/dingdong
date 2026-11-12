import AppKit
import SwiftUI

/// 顶部栏：铃铛图标（来消息会摇）、未读数、弹出面板
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: Store
    private var wiggleTimer: Timer?
    private var status: ConnStatus = .unconfigured
    private var unread = 0

    init(store: Store) {
        self.store = store
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.contentViewController = NSHostingController(rootView: PopoverView().environment(store))

        if let b = item.button {
            b.imagePosition = .imageLeft
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        render(angle: 0)

        store.onUnreadChange = { [weak self] n in self?.unread = n; self?.render(angle: 0) }
        store.onStatusChange = { [weak self] s in self?.status = s; self?.render(angle: 0) }
    }

    // MARK: - 图标

    private func render(angle: CGFloat) {
        guard let b = item.button else { return }
        let offline = status == .offline || status == .unauthorized
        b.image = Self.bell(angle: angle, slashed: offline, filled: unread > 0)
        b.font = .systemFont(ofSize: 12, weight: .semibold).rounded
        b.title = unread > 0 ? (unread > 99 ? " 99+" : " \(unread)") : ""
    }

    static func bell(angle: CGFloat, slashed: Bool, filled: Bool) -> NSImage {
        let name = slashed ? "bell.slash" : (filled ? "bell.fill" : "bell")
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "Dingdong")!
            .withSymbolConfiguration(cfg)!
        let size = NSSize(width: 20, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let bs = base.size
            // 绕铃铛顶部摆动
            let pivot = CGPoint(x: rect.midX, y: rect.midY + bs.height / 2 - 1)
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: angle * .pi / 180)
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
            base.draw(in: NSRect(x: rect.midX - bs.width / 2, y: rect.midY - bs.height / 2,
                                 width: bs.width, height: bs.height))
            return true
        }
        img.isTemplate = true
        return img
    }

    /// 叮～叮～ 衰减摆动
    func ring() {
        wiggleTimer?.invalidate()
        let start = Date()
        let duration = 1.1
        wiggleTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let p = Date().timeIntervalSince(start) / duration
                if p >= 1 {
                    t.invalidate()
                    self.render(angle: 0)
                    return
                }
                let angle = 24 * sin(p * .pi * 7) * pow(1 - p, 1.6)
                self.render(angle: angle)
            }
        }
    }

    // MARK: - 点击

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let test = NSMenuItem(title: "发一条测试通知", action: #selector(sendTest), keyEquivalent: "")
            test.target = self
            menu.addItem(test)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "退出叮咚", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        toggle()
    }

    @objc private func sendTest() { Task { _ = await store.sendTest() } }

    func toggle() { popover.isShown ? popover.performClose(nil) : show() }

    func show() {
        guard let b = item.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverWillShow(_ notification: Notification) { store.popoverOpen = true }
    func popoverDidClose(_ notification: Notification) { store.popoverOpen = false }

    /// 气泡要停在铃铛正下方
    var anchorFrame: NSRect? { item.button?.window?.frame }
}

extension NSFont {
    var rounded: NSFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
