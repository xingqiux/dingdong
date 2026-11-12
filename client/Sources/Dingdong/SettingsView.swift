import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    var go: (Page) -> Void

    @State private var url = ""
    @State private var token = ""
    @State private var reveal = false
    @State private var testState: TestState = .idle
    @State private var login = false

    enum TestState { case idle, sending, ok, fail }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconButton(symbol: "chevron.left", tint: Theme.soft, help: "返回") { save(); go(.inbox) }
                Text("设置").font(Theme.rounded(17, .heavy)).foregroundStyle(Theme.ink)
                Spacer()
                IconButton(symbol: "power", tint: Theme.soft, help: "退出叮咚") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSection("服务器") {
                        Field(icon: "server.rack", placeholder: "https://ding.example.com", text: $url)
                        HStack(spacing: 6) {
                            Field(icon: "key.fill", placeholder: "客户端 Token（服务端的管理员 token）", text: $token, secure: !reveal)
                            IconButton(symbol: reveal ? "eye.slash.fill" : "eye.fill", tint: Theme.soft, help: "显示/隐藏") {
                                reveal.toggle()
                            }
                        }
                        HStack(spacing: 8) {
                            PillButton(title: "保存并连接", symbol: "bolt.fill", color: Theme.pink) { save() }
                            PillButton(title: testTitle, symbol: testSymbol, color: testColor) { test() }
                                .disabled(testState == .sending)
                        }
                    }

                    SettingsSection("提醒") {
                        Toggle(isOn: $store.toastOn) { Label("右上角弹出卡片", systemImage: "rectangle.stack.fill") }
                        Toggle(isOn: $store.soundOn) { Label("叮咚音效", systemImage: "speaker.wave.2.fill") }
                        Toggle(isOn: $store.quietOn) { Label("安静时段", systemImage: "moon.zzz.fill") }
                        if store.quietOn {
                            HStack(spacing: 6) {
                                HourPicker(hour: $store.quietStart)
                                Text("到").foregroundStyle(Theme.soft)
                                HourPicker(hour: $store.quietEnd)
                                Spacer()
                                Text("不响不弹，error 照常弹")
                                    .font(Theme.rounded(10.5)).foregroundStyle(Theme.soft)
                            }
                            .padding(.leading, 22)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        Toggle(isOn: $login) { Label("开机自动启动", systemImage: "sunrise.fill") }
                            .onChange(of: login) { _, v in store.launchAtLogin = v }
                    }
                    .toggleStyle(CandyToggle())
                    .animation(Motion.spring(0.35, 0.8), value: store.quietOn)

                    SettingsSection("接入 AI") {
                        NavRow(icon: "pawprint.fill", title: "AI 令牌与接入方式",
                               detail: store.tokens.isEmpty ? "给每个 AI 发一个只能发通知的令牌" : "已有 \(store.tokens.count) 个令牌") {
                            save()
                            go(.tokens)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .onAppear {
            url = store.serverURL
            token = store.token
            login = store.launchAtLogin
            Task { await store.loadTokens() }
        }
    }

    private func save() {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard u != store.serverURL || t != store.token || store.status != .online else { return }
        store.serverURL = u
        store.token = t
        store.connect()
    }

    private func test() {
        save()
        withAnimation { testState = .sending }
        Task {
            let ok = await store.sendTest()
            withAnimation(Motion.spring(0.35, 0.5)) { testState = ok ? .ok : .fail }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { testState = .idle }
        }
    }

    private var testTitle: String {
        switch testState { case .idle: "测试一下"; case .sending: "发送中…"; case .ok: "成功！"; case .fail: "失败了" }
    }
    private var testSymbol: String {
        switch testState { case .idle: "paperplane.fill"; case .sending: "ellipsis"; case .ok: "checkmark"; case .fail: "xmark" }
    }
    private var testColor: Color {
        switch testState { case .ok: Theme.mint; case .fail: Theme.rose; default: Theme.lavender }
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.rounded(11, .bold)).foregroundStyle(Theme.soft)
            content
        }
        .font(Theme.rounded(12.5, .medium))
        .foregroundStyle(Theme.ink)
    }
}

private struct HourPicker: View {
    @Binding var hour: Int
    var body: some View {
        Menu {
            ForEach(0..<24, id: \.self) { h in Button(String(format: "%02d:00", h)) { hour = h } }
        } label: {
            Text(String(format: "%02d:00", hour)).font(Theme.rounded(12, .bold)).monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.card))
    }
}

struct NavRow: View {
    var icon: String
    var title: String
    var detail: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.pink.gradient))
                    .rotationEffect(.degrees(hover && !Motion.reduced ? -10 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.rounded(13, .bold)).foregroundStyle(Theme.ink)
                    Text(detail).font(Theme.rounded(11)).foregroundStyle(Theme.soft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.soft)
                    .offset(x: hover ? 3 : 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card)
                .shadow(color: Theme.pink.opacity(hover ? 0.2 : 0.06), radius: hover ? 8 : 4, y: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(Squishy())
        .onHover { h in withAnimation(Motion.spring(0.3, 0.6)) { hover = h } }
    }
}

struct Field: View {
    var icon: String
    var placeholder: String
    @Binding var text: String
    var secure = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(focused ? Theme.pink : Theme.soft)
                .frame(width: 14)
            Group {
                if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .textFieldStyle(.plain)
            .font(Theme.rounded(12.5, .medium))
            .focused($focused)
            .onSubmit(onSubmit)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focused ? Theme.pink.opacity(0.7) : Theme.hairline, lineWidth: focused ? 1.5 : 1))
        )
        .scaleEffect(focused ? 1.01 : 1)
        .animation(Motion.spring(0.3, 0.6), value: focused)
    }
}

struct PillButton: View {
    var title: String
    var symbol: String
    var color: Color
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .black))
                    .contentTransition(.symbolEffect(.replace))
                Text(title).font(Theme.rounded(12, .bold)).contentTransition(.interpolate)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(color.gradient).shadow(color: color.opacity(hover ? 0.5 : 0.3), radius: hover ? 8 : 4, y: 2))
            .scaleEffect(hover ? 1.05 : 1)
        }
        .buttonStyle(Squishy())
        .onHover { h in withAnimation(Motion.spring(0.3, 0.6)) { hover = h } }
    }
}

/// 糖果色的果冻开关
struct CandyToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.labelStyle(CandyLabel())
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(Theme.pink.gradient) : AnyShapeStyle(Theme.hairline))
                    .frame(width: 38, height: 22)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .onTapGesture {
                withAnimation(Motion.spring(0.3, 0.55)) { configuration.isOn.toggle() }
            }
        }
    }
}

private struct CandyLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.pink).frame(width: 14)
            configuration.title
        }
    }
}
