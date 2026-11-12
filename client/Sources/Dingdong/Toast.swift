import AppKit
import SwiftUI

/// 右上角弹出的小卡片（最多叠 3 张，悬停时不消失）
@MainActor
@Observable
final class ToastModel {
    struct Item: Identifiable { let id = UUID(); let message: Message }
    var items: [Item] = []
    var hovering = false
}

@MainActor
final class ToastController {
    private let panel: NSPanel
    private let model = ToastModel()
    private let width: CGFloat = 340
    private let rowHeight: CGFloat = 118
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

        let root = ToastStack(model: model,
                              tap: { [weak self] in self?.tapped() },
                              dismiss: { [weak self] id in self?.dismiss(id) })
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
    }

    func show(_ m: Message, anchor: NSRect?) {
        position(anchor: anchor)
        panel.orderFrontRegardless()
        let item = ToastModel.Item(message: m)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
            model.items.insert(item, at: 0)
            if model.items.count > 3 { model.items.removeLast(model.items.count - 3) }
        }
        resize()
        scheduleDismiss(item.id, after: 5.5)
    }

    /// 窗口只比卡片大一点，透明区域不挡点击；收缩等动画走完再做
    private func resize() {
        guard let screen = NSScreen.main, let x = anchorX else { return }
        let vf = screen.visibleFrame
        let h = CGFloat(max(model.items.count, 1)) * rowHeight + 16
        if h >= panel.frame.height {
            panel.setFrame(NSRect(x: x, y: vf.maxY - h, width: width, height: h), display: true)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, let screen = NSScreen.main else { return }
                let h = CGFloat(max(self.model.items.count, 1)) * self.rowHeight + 16
                let vf = screen.visibleFrame
                self.panel.setFrame(NSRect(x: x, y: vf.maxY - h, width: self.width, height: h), display: true)
            }
        }
    }

    private func scheduleDismiss(_ id: UUID, after: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
            guard let self else { return }
            if self.model.hovering { self.scheduleDismiss(id, after: 1.5); return }
            self.dismiss(id)
        }
    }

    private func dismiss(_ id: UUID) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { model.items.removeAll() }
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
            let h = rowHeight + 16
            panel.setFrame(NSRect(x: x, y: vf.maxY - h, width: width, height: h), display: false)
        }
    }
}

private struct ToastStack: View {
    @Bindable var model: ToastModel
    var tap: () -> Void
    var dismiss: (UUID) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.items) { item in
                ToastCard(message: item.message, close: { dismiss(item.id) })
                    .onTapGesture(perform: tap)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .scale(scale: 0.7, anchor: .top)).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { model.hovering = $0 }
    }
}

private struct ToastCard: View {
    let message: Message
    var close: () -> Void
    @State private var hover = false
    @State private var progress: CGFloat = 1
    @State private var wiggle = false

    var body: some View {
        let accent = Theme.level(message.level)
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.pink, Theme.peach], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(wiggle ? 14 : -14), anchor: .top)
            }
            .frame(width: 32, height: 32)
            .shadow(color: Theme.pink.opacity(0.4), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.title).font(Theme.rounded(13.5, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
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
                // 底部倒计时小进度条
                GeometryReader { g in
                    Capsule().fill(accent.opacity(0.7))
                        .frame(width: max(0, (g.size.width - 32) * progress), height: 3)
                        .offset(x: 16, y: g.size.height - 6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent.opacity(0.35), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            if hover {
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
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { hover = h } }
        .onAppear {
            withAnimation(.linear(duration: 5.5)) { progress = 0 }
            withAnimation(.easeInOut(duration: 0.12).repeatCount(7, autoreverses: true)) { wiggle = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { wiggle = false }
            }
        }
    }
}
