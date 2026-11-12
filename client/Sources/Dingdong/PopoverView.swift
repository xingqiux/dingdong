import SwiftUI

struct PopoverView: View {
    @Environment(Store.self) private var store
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            BubbleBackdrop()

            if showSettings {
                SettingsView(close: { flip(false) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                VStack(spacing: 0) {
                    Header(openSettings: { flip(true) })
                    InboxList()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .frame(width: 360, height: 520)
        .onAppear { if store.token.trimmingCharacters(in: .whitespaces).isEmpty { showSettings = true } }
    }

    private func flip(_ v: Bool) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { showSettings = v }
    }
}

// MARK: - 顶部

private struct Header: View {
    @Environment(Store.self) private var store
    var openSettings: () -> Void
    @State private var confirmClear = false

    var body: some View {
        HStack(spacing: 10) {
            RingingBell(tick: store.ringTick)
            VStack(alignment: .leading, spacing: 2) {
                Text("叮咚").font(Theme.rounded(17, .heavy)).foregroundStyle(Theme.ink)
                StatusPill(status: store.status)
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { confirmClear = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { confirmClear = false }
                        }
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            IconButton(symbol: "gearshape.fill", tint: Theme.soft, help: "设置", action: openSettings)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct RingingBell: View {
    var tick: Int
    var size: CGFloat = 20
    @State private var angle: Double = 0
    @State private var bounce = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Theme.pink, Theme.peach], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 1.9, height: size * 1.9)
                .shadow(color: Theme.pink.opacity(0.45), radius: 8, y: 3)
                .scaleEffect(bounce ? 1.12 : 1)
            Image(systemName: "bell.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(angle), anchor: .top)
        }
        .onChange(of: tick) { ring() }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ring() } }
    }

    private func ring() {
        let seq: [Double] = [-26, 22, -16, 11, -6, 3, 0]
        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { bounce = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { bounce = false }
        }
        for (i, a) in seq.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                withAnimation(.easeInOut(duration: 0.09)) { angle = a }
            }
        }
    }
}

private struct StatusPill: View {
    var status: ConnStatus
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
            Text(status.label)
                .font(Theme.rounded(11, .semibold))
                .foregroundStyle(Theme.soft)
                .contentTransition(.numericText())
        }
        .onAppear {
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
                .rotationEffect(.degrees(hover ? 18 : 0))
                .scaleEffect(hover ? 1.1 : 1)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(Squishy())
        .help(help)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { hover = h } }
    }
}

/// 按下去会“噗”一下
struct Squishy: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

// MARK: - 列表

private struct InboxList: View {
    @Environment(Store.self) private var store

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
                                .transition(.asymmetric(
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.title)
                        .font(Theme.rounded(14, .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
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
        .scaleEffect(hover ? 1.015 : 1)
        .offset(y: appeared ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { hover = h } }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72).delay(min(Double(index), 8) * 0.04)) {
                appeared = true
            }
        }
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

// MARK: - 空状态：睡着的小铃铛

private struct EmptyState: View {
    @State private var float = false
    @State private var z = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Theme.pink, Theme.peach], startPoint: .top, endPoint: .bottom))
                    .rotationEffect(.degrees(float ? -6 : 6), anchor: .top)
                    .offset(y: float ? -6 : 4)
                    .shadow(color: Theme.pink.opacity(0.35), radius: 12, y: 8)
                ForEach(0..<3) { i in
                    Text("z")
                        .font(Theme.rounded(CGFloat(11 + i * 3), .heavy))
                        .foregroundStyle(Theme.lavender)
                        .offset(x: z ? CGFloat(16 + i * 10) : 6, y: z ? CGFloat(-14 - i * 14) : 0)
                        .opacity(z ? 0 : 0.9)
                        .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.6), value: z)
                }
            }
            .frame(height: 80)
            Text("暂时没有消息")
                .font(Theme.rounded(15, .bold))
                .foregroundStyle(Theme.ink)
            Text("AI 一喊你，我就叮咚一下～")
                .font(Theme.rounded(12))
                .foregroundStyle(Theme.soft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -20)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { float = true }
            z = true
        }
    }
}

// MARK: - 背景：慢慢漂的糖果泡泡

struct BubbleBackdrop: View {
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
        .onAppear { withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true } }
    }
}
