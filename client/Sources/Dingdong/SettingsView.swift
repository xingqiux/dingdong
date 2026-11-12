import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    var close: () -> Void

    @State private var url = ""
    @State private var token = ""
    @State private var reveal = false
    @State private var testState: TestState = .idle
    @State private var copied = false
    @State private var login = false

    enum TestState { case idle, sending, ok, fail }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconButton(symbol: "chevron.left", tint: Theme.soft, help: "返回") { save(); close() }
                Text("设置").font(Theme.rounded(17, .heavy)).foregroundStyle(Theme.ink)
                Spacer()
                IconButton(symbol: "power", tint: Theme.soft, help: "退出叮咚") { NSApp.terminate(nil) }
            }

            Section("服务器") {
                Field(icon: "server.rack", placeholder: "http://127.0.0.1:8787", text: $url)
                HStack(spacing: 6) {
                    Field(icon: "key.fill", placeholder: "Token", text: $token, secure: !reveal)
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

            Section("提醒") {
                Toggle(isOn: $store.toastOn) { Label("右上角弹出卡片", systemImage: "rectangle.stack.fill") }
                Toggle(isOn: $store.soundOn) { Label("叮咚音效", systemImage: "speaker.wave.2.fill") }
                Toggle(isOn: $login) { Label("开机自动启动", systemImage: "sunrise.fill") }
                    .onChange(of: login) { _, v in store.launchAtLogin = v }
            }
            .toggleStyle(CandyToggle())

            Section("给 AI 用的调用方式") {
                Text(store.curlExample)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .lineLimit(5)
                    .padding(10)
                    .padding(.trailing, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(store.curlExample, forType: .string)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
                        } label: {
                            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(copied ? Theme.mint : Theme.pink)
                                .contentTransition(.symbolEffect(.replace))
                                .padding(8)
                        }
                        .buttonStyle(Squishy())
                        .help("复制")
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .onAppear {
            url = store.serverURL
            token = store.token
            login = store.launchAtLogin
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { testState = ok ? .ok : .fail }
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

private struct Section<Content: View>: View {
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

private struct Field: View {
    var icon: String
    var placeholder: String
    @Binding var text: String
    var secure = false
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
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: focused)
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
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { hover = h } }
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { configuration.isOn.toggle() }
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
