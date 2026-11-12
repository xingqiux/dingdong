import SwiftUI

enum Page { case inbox, settings, tokens }

struct PopoverView: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page = .inbox

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            BubbleBackdrop()

            switch page {
            case .inbox:
                VStack(spacing: 0) {
                    Header(go: go)
                    InboxList()
                }
                .transition(slide(.leading))
            case .settings:
                SettingsView(go: go)
                    .transition(slide(page == .tokens ? .leading : .trailing))
            case .tokens:
                TokensView(back: { go(.settings) })
                    .transition(slide(.trailing))
            }
        }
        .frame(width: 360, height: 520)
        .onAppear { if !store.demo && store.token.trimmingCharacters(in: .whitespaces).isEmpty { page = .settings } }
        .onReceive(NotificationCenter.default.publisher(for: .dingdongShowPage)) { n in
            if let p = n.object as? Page { page = p }
        }
    }

    private func slide(_ edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    private func go(_ p: Page) {
        withAnimation(Motion.spring(0.45, 0.82)) { page = p }
    }
}

extension Notification.Name {
    static let dingdongShowPage = Notification.Name("dingdongShowPage")
}

// MARK: - 顶部

private struct Header: View {
    @Environment(Store.self) private var store
    var go: (Page) -> Void
    @State private var confirmClear = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.pink.opacity(0.35), Theme.peach.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                RingingCat(tick: store.ringTick, size: 40, sleeping: store.isQuiet)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("叮咚").font(Theme.rounded(17, .heavy)).foregroundStyle(Theme.ink)
                StatusPill(status: store.status, quiet: store.isQuiet)
            }
            Spacer()
            if !store.messages.isEmpty {
                IconButton(symbol: confirmClear ? "checkmark" : "sparkles",
                           tint: confirmClear ? Theme.rose : Theme.soft,
                           help: confirmClear ? "再点一下确认清空" : "清空全部") {
                    if confirmClear {
                        store.clearAll()
                        confirmClear = false
                    } else {
                        withAnimation(Motion.spring(0.3, 0.6)) { confirmClear = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { confirmClear = false }
                        }
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            IconButton(symbol: "gearshape.fill", tint: Theme.soft, help: "设置") { go(.settings) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

private struct StatusPill: View {
    var status: ConnStatus
    var quiet: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(status.color.opacity(0.35))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.2 : 0.5)
                    .opacity(pulse ? 0 : 1)
                Circle().fill(status.color).frame(width: 6, height: 6)
            }
            .frame(width: 12, height: 12)
            Text(quiet && status == .online ? "在线 · 勿扰中" : status.label)
                .font(Theme.rounded(11, .semibold))
                .foregroundStyle(Theme.soft)
                .contentTransition(.interpolate)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct IconButton: View {
    var symbol: String
    var tint: Color
    var help: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(hover ? Theme.pink : tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.card).shadow(color: .black.opacity(0.06), radius: 4, y: 2))
                .rotationEffect(.degrees(hover && !Motion.reduced ? 18 : 0))
                .scaleEffect(hover ? 1.1 : 1)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(Squishy())
        .help(help)
        .onHover { h in withAnimation(Motion.spring(0.3, 0.55)) { hover = h } }
    }
}

/// 按下去会“噗”一下
struct Squishy: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(Motion.spring(0.25, 0.5), value: configuration.isPressed)
    }
}

// MARK: - 列表

private struct InboxList: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if store.messages.isEmpty {
                EmptyState()
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { i, m in
                            MessageCard(message: m, index: i)
                                .transition(reduceMotion ? .opacity : .asymmetric(
                                    insertion: .scale(scale: 0.6, anchor: .top)
                                        .combined(with: .opacity)
                                        .combined(with: .offset(y: -24)),
                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct MessageCard: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: Message
    var index: Int
    @State private var appeared = false
    @State private var hover = false

    var body: some View {
        let accent = Theme.level(message.level)
        HStack(alignment: .top, spacing: 0) {
            // 左边一条糖果色的小胶囊，表示级别
            Capsule()
                .fill(accent.gradient)
                .frame(width: 4)
                .padding(.vertical, 2)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(message.title)
                        .font(Theme.rounded(14, .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let c = message.count, c > 1 { CountBadge(count: c, color: accent) }
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(TimeText.of(message.date, now: ctx.date))
                            .font(Theme.rounded(11, .medium))
                            .foregroundStyle(Theme.soft)
                            .monospacedDigit()
                    }
                    .opacity(hover ? 0 : 1)
                }
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(Theme.rounded(12.5))
                        .foregroundStyle(Theme.ink.opacity(0.72))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SourceTag(source: message.source)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .shadow(color: accent.opacity(hover ? 0.28 : 0.12), radius: hover ? 12 : 6, y: hover ? 5 : 2)
        )
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { store.delete(message) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.rose))
                }
                .buttonStyle(Squishy())
                .help("删掉")
                .padding(9)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let u = message.link { NSWorkspace.shared.open(u) } }
        .contextMenu {
            Button("复制内容") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString([message.title, message.body].filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string)
            }
            if let u = message.link { Button("打开链接") { NSWorkspace.shared.open(u) } }
            Button("删掉", role: .destructive) { store.delete(message) }
        }
        .scaleEffect(hover ? 1.015 : 1)
        .offset(y: appeared || reduceMotion ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .onHover { h in withAnimation(Motion.spring(0.3, 0.65)) { hover = h } }
        .onAppear {
            withAnimation(Motion.spring().delay(reduceMotion ? 0 : min(Double(index), 8) * 0.04)) {
                appeared = true
            }
        }
    }
}

struct CountBadge: View {
    var count: Int
    var color: Color
    var body: some View {
        Text("×\(count)")
            .font(Theme.rounded(10, .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.gradient))
            .contentTransition(.numericText())
            .fixedSize()
    }
}

struct SourceTag: View {
    var source: String
    var body: some View {
        let c = Theme.source(source)
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(source).font(Theme.rounded(10.5, .semibold)).lineLimit(1)
        }
        .foregroundStyle(c)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(c.opacity(0.14)))
    }
}

// MARK: - 空状态：睡着的小猫

private struct EmptyState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var z = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                CatFace(sleeping: true)
                    .frame(width: 92, height: 92)
                    .scaleEffect(x: breathe ? 1.03 : 1, y: breathe ? 0.97 : 1, anchor: .bottom)
                    .shadow(color: Theme.pink.opacity(0.3), radius: 12, y: 8)
                if !reduceMotion {
                    ForEach(0..<3) { i in
                        Text("z")
                            .font(Theme.rounded(CGFloat(11 + i * 3), .heavy))
                            .foregroundStyle(Theme.lavender)
                            .offset(x: z ? CGFloat(10 + i * 10) : 0, y: z ? CGFloat(-10 - i * 14) : 6)
                            .opacity(z ? 0 : 0.9)
                            .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.6), value: z)
                    }
                }
            }
            .frame(height: 100)
            Text("暂时没有消息")
                .font(Theme.rounded(15, .bold))
                .foregroundStyle(Theme.ink)
            Text("小猫先睡一会儿，AI 一喊它就醒～")
                .font(Theme.rounded(12))
                .foregroundStyle(Theme.soft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -20)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
            z = true
        }
    }
}

// MARK: - 背景：慢慢漂的糖果泡泡

struct BubbleBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    var body: some View {
        ZStack {
            Circle().fill(Theme.pink.opacity(0.13)).frame(width: 220).blur(radius: 30)
                .offset(x: drift ? 120 : 90, y: drift ? -230 : -200)
            Circle().fill(Theme.sky.opacity(0.12)).frame(width: 200).blur(radius: 34)
                .offset(x: drift ? -140 : -100, y: drift ? 200 : 240)
            Circle().fill(Theme.lemon.opacity(0.10)).frame(width: 160).blur(radius: 30)
                .offset(x: drift ? -60 : -110, y: drift ? -40 : 10)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
