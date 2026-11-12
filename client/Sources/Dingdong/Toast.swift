import AppKit
import SwiftUI

/// 右上角弹出的小卡片（最多叠 3 张；悬停时不消失；error 级别要手动关）
@MainActor
@Observable
final class ToastModel {
    struct Item: Identifiable {
        let id = UUID()
        var message: Message
        var sticky: Bool { message.level == "error" }
    }
    var items: [Item] = []
    var hovering = false
}

@MainActor
final class ToastController {
    private let panel: NSPanel
    private let model = ToastModel()
    private let width: CGFloat = 372
    private let rowHeight: CGFloat = 116
    private let lifetime = 5.5
    private var anchorX: CGFloat?
    var onTap: (() -> Void)?

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let root = ToastStack(model: model, lifetime: lifetime,
                              tap: { [weak self] in self?.tapped() },
                              dismiss: { [weak self] id in self?.dismiss(id) })
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
    }

    var windowNumber: Int { panel.windowNumber }
    func setAppearance(_ a: NSAppearance?) { panel.appearance = a }

    func show(_ m: Message, anchor: NSRect?) {
        position(anchor: anchor)
        panel.orderFrontRegardless()
        // 同一条消息（被合并了）就原地更新次数，不另起一张
        if let i = model.items.firstIndex(where: { $0.message.id == m.id }) {
            withAnimation(Motion.spring(0.4, 0.6)) { model.items[i].message = m }
            return
        }
        let item = ToastModel.Item(message: m)
        withAnimation(Motion.spring(0.55, 0.68)) {
            model.items.insert(item, at: 0)
            if model.items.count > 3 { model.items.removeLast(model.items.count - 3) }
        }
        resize()
        if !item.sticky { scheduleDismiss(item.id, after: lifetime) }
    }

    /// 离线期间漏掉的消息：一张汇总卡
    func showMissed(_ missed: [Message], anchor: NSRect?) {
        if missed.count == 1 { show(missed[0], anchor: anchor); return }
        let titles = missed.prefix(3).map(\.title).joined(separator: "、")
        let summary = Message(
            id: "missed-\(UUID().uuidString)",
            title: "离线期间收到 \(missed.count) 条",
            body: missed.count > 3 ? "\(titles) 等" : titles,
            source: "叮咚",
            level: missed.contains { $0.level == "error" } ? "error" : "info",
            url: nil, count: nil,
            createdAt: missed.map(\.createdAt).max() ?? 0)
        show(summary, anchor: anchor)
    }

    private func scheduleDismiss(_ id: UUID, after: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
            guard let self else { return }
            if self.model.hovering { self.scheduleDismiss(id, after: 1.5); return }
            self.dismiss(id)
        }
    }

    /// 窗口只比卡片大一点，透明区域不挡点击；收缩等动画走完再做
    private func resize() {
        guard let screen = NSScreen.main, let x = anchorX else { return }
        let h = CGFloat(max(model.items.count, 1)) * rowHeight + 40
        let apply = { [weak self] in
            guard let self else { return }
            let h = CGFloat(max(self.model.items.count, 1)) * self.rowHeight + 40
            self.panel.setFrame(NSRect(x: x, y: screen.visibleFrame.maxY - h, width: self.width, height: h), display: true)
        }
        if h >= panel.frame.height { apply() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { apply() } }
    }

    private func dismiss(_ id: UUID) {
        withAnimation(Motion.spring(0.45, 0.85)) {
            model.items.removeAll { $0.id == id }
        }
        resize()
        if model.items.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.model.items.isEmpty == true { self?.panel.orderOut(nil) }
            }
        }
    }

    private func tapped() {
        withAnimation(Motion.spring(0.4, 0.85)) { model.items.removeAll() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.panel.orderOut(nil) }
        onTap?()
    }

    private func position(anchor: NSRect?) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        var x = vf.maxX - width - 8
        if let a = anchor, screen.frame.contains(NSPoint(x: a.midX, y: a.midY)) {
            x = min(max(a.midX - width / 2, vf.minX + 8), vf.maxX - width - 8)
        }
        anchorX = x
        if !panel.isVisible {
            let h = rowHeight + 40
            panel.setFrame(NSRect(x: x, y: vf.maxY - h, width: width, height: h), display: false)
        }
    }
}

private struct ToastStack: View {
    @Bindable var model: ToastModel
    var lifetime: Double
    var tap: () -> Void
    var dismiss: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.items) { item in
                ToastCard(message: item.message, sticky: item.sticky, lifetime: lifetime, close: { dismiss(item.id) })
                    .onTapGesture(perform: tap)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .top).combined(with: .scale(scale: 0.7, anchor: .top)).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { model.hovering = $0 }
    }
}

private struct ToastCard: View {
    let message: Message
    var sticky: Bool
    var lifetime: Double
    var close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var shownAt = Date()
    @State private var tick = 0

    var body: some View {
        let accent = Theme.level(message.level)
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.pink.opacity(0.35), Theme.peach.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RingingCat(tick: tick, size: 34)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.title).font(Theme.rounded(13.5, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    if let c = message.count, c > 1 { CountBadge(count: c, color: accent) }
                    Spacer(minLength: 4)
                    Text(TimeText.of(message.date)).font(Theme.rounded(10.5, .medium)).foregroundStyle(Theme.soft)
                        .opacity(hover ? 0 : 1)
                }
                if !message.body.isEmpty {
                    Text(message.body).font(Theme.rounded(12)).foregroundStyle(Theme.ink.opacity(0.72)).lineLimit(2)
                }
                SourceTag(source: message.source)
            }
        }
        .padding(12)
        .background(
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.bg.opacity(0.9))
                // 底部倒计时小进度条（error 级别不自动消失，没有进度条）
                if !sticky {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                        let p = max(0, 1 - ctx.date.timeIntervalSince(shownAt) / lifetime)
                        GeometryReader { g in
                            Capsule().fill(accent.opacity(0.7))
                                .frame(width: max(0, (g.size.width - 32) * p), height: 3)
                                .offset(x: 16, y: g.size.height - 6)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(accent.opacity(sticky ? 0.8 : 0.35), lineWidth: sticky ? 1.5 : 1))
        .overlay(alignment: .topLeading) {
            if hover || sticky {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .black)).foregroundStyle(Theme.soft)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.card).shadow(color: .black.opacity(0.15), radius: 3, y: 1))
                }
                .buttonStyle(Squishy())
                .offset(x: -5, y: -5)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .scaleEffect(hover ? 1.02 : 1)
        .onHover { h in withAnimation(Motion.spring(0.3, 0.6)) { hover = h } }
        .onChange(of: message.count) { tick += 1 }
    }
}
