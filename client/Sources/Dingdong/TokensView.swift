import AppKit
import SwiftUI

/// 接入 AI：每个 AI 一个只能发通知的令牌，来源固定为令牌名字，随时可以作废。
struct TokensView: View {
    @Environment(Store.self) private var store
    var back: () -> Void

    @State private var name = ""
    @State private var fresh: (name: String, token: String)?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconButton(symbol: "chevron.left", tint: Theme.soft, help: "返回", action: back)
                Text("接入 AI").font(Theme.rounded(17, .heavy)).foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("给每个 AI 发一个令牌：它只能发通知，来源固定显示成令牌的名字，不会冒充别人，也看不到你的消息。不想要了随时作废。")
                        .font(Theme.rounded(11.5))
                        .foregroundStyle(Theme.soft)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.status != .online {
                        Label("先在设置里连上服务器", systemImage: "exclamationmark.circle.fill")
                            .font(Theme.rounded(12, .semibold))
                            .foregroundStyle(Theme.peach)
                    }

                    HStack(spacing: 8) {
                        Field(icon: "pawprint.fill", placeholder: "名字，比如 Claude Code", text: $name, onSubmit: create)
                        PillButton(title: busy ? "…" : "创建", symbol: "plus", color: Theme.pink, action: create)
                            .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let error {
                        Text(error).font(Theme.rounded(11, .semibold)).foregroundStyle(Theme.rose)
                            .transition(.opacity)
                    }

                    if let fresh {
                        FreshTokenCard(name: fresh.name, token: fresh.token,
                                       snippets: store.snippets(for: fresh.token)) {
                            withAnimation(Motion.spring()) { self.fresh = nil }
                        }
                        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                    }

                    if !store.tokens.isEmpty {
                        SettingsSection("已有令牌") {
                            VStack(spacing: 8) {
                                ForEach(store.tokens) { t in
                                    TokenRow(token: t, rotate: { rotate(t.name) }, revoke: { revoke(t.name) })
                                        .transition(.move(edge: .trailing).combined(with: .opacity))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .onAppear { Task { await store.loadTokens() } }
    }

    private func create() { issue(name.trimmingCharacters(in: .whitespaces)) }
    private func rotate(_ n: String) { issue(n) }

    private func issue(_ n: String) {
        guard !n.isEmpty, !busy else { return }
        busy = true
        Task {
            let r = await store.createToken(n)
            busy = false
            withAnimation(Motion.spring()) {
                switch r {
                case .success(let tok):
                    fresh = (n, tok)
                    name = ""
                    error = nil
                case .failure(let e):
                    error = e.code == 0 ? "连不上服务器" : (e.code == 403 || e.code == 401 ? "客户端 token 没有管理权限" : "创建失败（\(e.code)）")
                }
            }
        }
    }

    private func revoke(_ n: String) {
        if fresh?.name == n { fresh = nil }
        Task { await store.revokeToken(n) }
    }
}

private struct FreshTokenCard: View {
    var name: String
    var token: String
    var snippets: [(String, String)]
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("「\(name)」的新令牌", systemImage: "sparkles")
                    .font(Theme.rounded(12.5, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .black)).foregroundStyle(Theme.soft)
                }
                .buttonStyle(Squishy())
            }
            Text(token)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.bg))
            Text("只显示这一次，关掉就看不到了。复制一种接入方式给 AI：")
                .font(Theme.rounded(10.5))
                .foregroundStyle(Theme.soft)
            FlowRow(spacing: 6) {
                CopyChip(title: "令牌", text: token)
                ForEach(snippets, id: \.0) { s in CopyChip(title: s.0, text: s.1) }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.pink.opacity(0.5), lineWidth: 1.5))
                .shadow(color: Theme.pink.opacity(0.2), radius: 10, y: 4)
        )
    }
}

private struct TokenRow: View {
    let token: SenderToken
    var rotate: () -> Void
    var revoke: () -> Void
    @State private var hover = false
    @State private var confirm = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.source(token.name)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(token.name).font(Theme.rounded(13, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(detail).font(Theme.rounded(10.5)).foregroundStyle(Theme.soft).lineLimit(1)
            }
            Spacer()
            if hover || confirm {
                HStack(spacing: 4) {
                    SmallIcon(symbol: "arrow.triangle.2.circlepath", tint: Theme.lavender, help: "轮换（旧令牌立即失效）", action: rotate)
                    SmallIcon(symbol: confirm ? "checkmark" : "trash.fill", tint: Theme.rose,
                              help: confirm ? "再点一下确认作废" : "作废") {
                        if confirm { revoke() } else {
                            withAnimation(Motion.spring(0.3, 0.6)) { confirm = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { confirm = false } }
                        }
                    }
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card)
            .shadow(color: .black.opacity(hover ? 0.08 : 0.04), radius: hover ? 6 : 3, y: 2))
        .onHover { h in withAnimation(Motion.spring(0.3, 0.65)) { hover = h } }
    }

    private var detail: String {
        var parts = ["\(token.prefix)…"]
        if let t = token.lastUsedAt {
            parts.append("上次 " + TimeText.of(Date(timeIntervalSince1970: TimeInterval(t) / 1000)))
        } else {
            parts.append("还没用过")
        }
        parts.append("\(token.count) 条")
        return parts.joined(separator: " · ")
    }
}

private struct SmallIcon: View {
    var symbol: String
    var tint: Color
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.gradient))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(Squishy())
        .help(help)
    }
}

struct CopyChip: View {
    var title: String
    var text: String
    @State private var copied = false
    @State private var hover = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(Motion.spring(0.3, 0.5)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc.fill")
                    .font(.system(size: 9, weight: .black))
                    .contentTransition(.symbolEffect(.replace))
                Text(copied ? "已复制" : title).font(Theme.rounded(11, .bold))
            }
            .foregroundStyle(copied ? .white : Theme.pink)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(copied ? AnyShapeStyle(Theme.mint.gradient) : AnyShapeStyle(Theme.pink.opacity(hover ? 0.2 : 0.12))))
        }
        .buttonStyle(Squishy())
        .help(text)
        .onHover { h in withAnimation(Motion.spring(0.3, 0.6)) { hover = h } }
    }
}

/// 简单的自动换行横排
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxW), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
