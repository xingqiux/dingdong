import AppKit
import SwiftUI

/// 命令行渲染：生成 App 图标 PNG（Dingdong --render-icon out.png [size]）
@MainActor
enum Render {
    static func png<V: View>(_ view: V, size: CGFloat, to path: String) -> Bool {
        let r = ImageRenderer(content: view.frame(width: size, height: size))
        r.scale = 1
        r.isOpaque = false
        guard let cg = r.cgImage else { return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
