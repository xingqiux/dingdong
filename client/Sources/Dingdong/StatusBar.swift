import AppKit
import SwiftUI

/// 顶部栏：小猫图标（来消息会歪头晃一晃）、未读数、弹出面板
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: Store
    private var wiggleTimer: Timer?
    private var quietTimer: Timer?

    init(store: Store) {
        self.store = store
        super.init()

        popover.behavior = .transient
        popover.animates = !Motion.reduced
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

        store.onUnreadChange = { [weak self] _ in self?.render(angle: 0) }
        store.onStatusChange = { [weak self] _ in self?.render(angle: 0) }
        store.onQuietChange = { [weak self] in self?.render(angle: 0) }
        // 安静时段的开始/结束要自己刷新图标
        quietTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render(angle: 0) }
        }
    }

    // MARK: - 图标

    private func render(angle: CGFloat) {
        guard let b = item.button else { return }
        let unread = store.unread
        let mood: MenubarCat.Mood
        switch true {
        case store.status == .offline || store.status == .unauthorized: mood = .offline
        case store.isQuiet: mood = .sleeping
        case unread > 0: mood = .unread
        default: mood = .idle
        }
        b.image = MenubarCat.image(mood, angle: angle)
        b.font = .systemFont(ofSize: 12, weight: .semibold).rounded
        b.title = unread > 0 ? (unread > 99 ? " 99+" : " \(unread)") : ""
    }

    /// 叮～叮～ 衰减摆动
    func ring() {
        render(angle: 0)
        guard !Motion.reduced, !store.isQuiet else { return }
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
                self.render(angle: 16 * sin(p * .pi * 7) * pow(1 - p, 1.6))
            }
        }
    }

    // MARK: - 点击

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            item.menu = buildMenu()
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        toggle()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector, key: String = "") {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            i.target = self
            menu.addItem(i)
        }
        if let s = store.snoozeUntil, s > .now {
            add("取消勿扰（到 \(s.formatted(date: .omitted, time: .shortened))）", #selector(unsnooze))
        } else {
            add("勿扰 1 小时", #selector(snooze))
        }
        add("发一条测试通知", #selector(sendTest))
        add("接入 AI…", #selector(openTokens))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出叮咚", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func sendTest() { Task { _ = await store.sendTest() } }
    @objc private func snooze() { store.snoozeUntil = Date().addingTimeInterval(3600) }
    @objc private func unsnooze() { store.snoozeUntil = nil }
    @objc private func openTokens() { show(page: .tokens) }

    func toggle() { popover.isShown ? popover.performClose(nil) : show() }

    func show(page: Page? = nil) {
        guard let b = item.button else { return }
        if !popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        if let page { NotificationCenter.default.post(name: .dingdongShowPage, object: page) }
    }

    func popoverWillShow(_ notification: Notification) { store.popoverOpen = true }
    func popoverDidClose(_ notification: Notification) { store.popoverOpen = false }

    /// 弹卡要停在铃铛正下方
    var anchorFrame: NSRect? { item.button?.window?.frame }
    func setAppearance(_ a: NSAppearance?) { popover.appearance = a }
    var popoverWindowNumber: Int? { popover.contentViewController?.view.window?.windowNumber }
}

extension NSFont {
    var rounded: NSFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
