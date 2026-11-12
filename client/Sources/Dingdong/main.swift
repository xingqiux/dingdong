import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private var bar: StatusBarController!
    private var toast: ToastController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        bar = StatusBarController(store: store)
        toast = ToastController()
        toast.onTap = { [weak self] in self?.bar.show() }

        store.onNew = { [weak self] m in
            guard let self else { return }
            self.bar.ring()
            if self.store.toastOn && !self.store.popoverOpen {
                self.toast.show(m, anchor: self.bar.anchorFrame)
            }
        }
        store.connect()
        if store.token.trimmingCharacters(in: .whitespaces).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.bar.show() }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // 只在顶部栏，不进 Dock
    app.run()
}
