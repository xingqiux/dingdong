import AppKit
import SwiftUI

/// 叮咚的小三花猫。所有坐标都在 100×100 的设计空间里，按实际尺寸缩放。
struct CatFace: View {
    var sleeping = false
    var earTwitch: Double = 0   // 右耳抖动角度
    var bellSwing: Double = 0   // 铃铛摆动角度
    var outline = true

    static let ink = Color(red: 0x4A / 255, green: 0x35 / 255, blue: 0x50 / 255)
    static let fur = Color(red: 1, green: 0xF8 / 255, blue: 0xF1 / 255)
    static let patch = Color(red: 1, green: 0xB0 / 255, blue: 0x66 / 255)
    static let pink = Color(red: 1, green: 0x8F / 255, blue: 0xB8 / 255)
    static let gold = Color(red: 1, green: 0xD4 / 255, blue: 0x5C / 255)

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height) / 100
            let lw = 2.4 * s
            ZStack {
                // 耳朵（左耳是橘色的）
                Ear(left: true).fill(Self.patch)
                    .overlay(Ear(left: true).stroke(Self.ink, style: StrokeStyle(lineWidth: outline ? lw : 0, lineJoin: .round)))
                InnerEar(left: true).fill(Self.pink.opacity(0.85))
                Group {
                    Ear(left: false).fill(Self.fur)
                        .overlay(Ear(left: false).stroke(Self.ink, style: StrokeStyle(lineWidth: outline ? lw : 0, lineJoin: .round)))
                    InnerEar(left: false).fill(Self.pink.opacity(0.85))
                }
                .rotationEffect(.degrees(earTwitch), anchor: UnitPoint(x: 0.66, y: 0.36))

                // 脑袋 + 橘色花斑
                Head().fill(Self.fur)
                Ellipse().fill(Self.patch)
                    .frame(width: 30 * s, height: 22 * s)
                    .position(x: 32 * s, y: 38 * s)
                    .mask(Head().fill(.black))
                Head().stroke(Self.ink, lineWidth: outline ? lw : 0)

                // 腮红
                ForEach([29.0, 71.0], id: \.self) { x in
                    Ellipse().fill(Self.pink.opacity(0.45))
                        .frame(width: 11 * s, height: 6 * s)
                        .position(x: x * s, y: 68 * s)
                }

                // 眼睛
                if sleeping {
                    ClosedEyes().stroke(Self.ink, style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
                } else {
                    ForEach([37.0, 63.0], id: \.self) { x in
                        ZStack {
                            Ellipse().fill(Self.ink).frame(width: 9.5 * s, height: 11.5 * s)
                            Circle().fill(.white).frame(width: 3.6 * s).offset(x: 1.6 * s, y: -2.2 * s)
                        }
                        .position(x: x * s, y: 58 * s)
                    }
                }

                // 鼻子、嘴、胡子
                Nose().fill(Self.pink)
                Mouth().stroke(Self.ink, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round))
                Whiskers().stroke(Self.ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))

                // 项圈 + 铃铛
                Collar().fill(Self.pink)
                    .overlay(Collar().stroke(Self.ink, lineWidth: outline ? lw * 0.8 : 0))
                Bell(s: s, outline: outline)
                    .rotationEffect(.degrees(bellSwing), anchor: UnitPoint(x: 0.5, y: 0.86))
            }
            .frame(width: 100 * s, height: 100 * s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct Bell: View {
    var s: CGFloat
    var outline: Bool
    var body: some View {
        ZStack {
            Circle().fill(CatFace.gold)
                .overlay(Circle().stroke(CatFace.ink, lineWidth: outline ? 2 * s : 0))
                .frame(width: 12 * s)
            Capsule().fill(CatFace.ink).frame(width: 6 * s, height: 1.6 * s).offset(y: 1.4 * s)
            Circle().fill(CatFace.ink).frame(width: 2.2 * s).offset(y: 3.4 * s)
            Circle().fill(.white.opacity(0.8)).frame(width: 2.6 * s).offset(x: -2.4 * s, y: -2.4 * s)
        }
        .position(x: 50 * s, y: 93 * s)
    }
}

// MARK: - 形状（100×100 设计空间）

private extension CGRect {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: minX + x / 100 * width, y: minY + y / 100 * height)
    }
}

private struct Head: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.p(50, 27))
        p.addCurve(to: r.p(87, 60), control1: r.p(74, 27), control2: r.p(87, 40))
        p.addCurve(to: r.p(50, 89), control1: r.p(87, 79), control2: r.p(72, 89))
        p.addCurve(to: r.p(13, 60), control1: r.p(28, 89), control2: r.p(13, 79))
        p.addCurve(to: r.p(50, 27), control1: r.p(13, 40), control2: r.p(26, 27))
        p.closeSubpath()
        return p
    }
}

private struct Ear: Shape {
    var left: Bool
    func path(in r: CGRect) -> Path {
        func x(_ v: CGFloat) -> CGFloat { left ? v : 100 - v }
        var p = Path()
        p.move(to: r.p(x(16), 50))
        p.addQuadCurve(to: r.p(x(24), 13), control: r.p(x(14), 26))
        p.addQuadCurve(to: r.p(x(30), 12), control: r.p(x(26), 9))
        p.addQuadCurve(to: r.p(x(48), 32), control: r.p(x(40), 20))
        p.closeSubpath()
        return p
    }
}

private struct InnerEar: Shape {
    var left: Bool
    func path(in r: CGRect) -> Path {
        func x(_ v: CGFloat) -> CGFloat { left ? v : 100 - v }
        var p = Path()
        p.move(to: r.p(x(22), 38))
        p.addQuadCurve(to: r.p(x(27), 19), control: r.p(x(21), 26))
        p.addQuadCurve(to: r.p(x(40), 31), control: r.p(x(34), 24))
        p.closeSubpath()
        return p
    }
}

private struct ClosedEyes: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for cx: CGFloat in [37, 63] {
            p.move(to: r.p(cx - 5.5, 57))
            p.addQuadCurve(to: r.p(cx + 5.5, 57), control: r.p(cx, 63))
        }
        return p
    }
}

private struct Nose: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.p(46.5, 65))
        p.addQuadCurve(to: r.p(53.5, 65), control: r.p(50, 63.6))
        p.addQuadCurve(to: r.p(50, 69), control: r.p(53, 67.5))
        p.addQuadCurve(to: r.p(46.5, 65), control: r.p(47, 67.5))
        p.closeSubpath()
        return p
    }
}

private struct Mouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.p(43.5, 70))
        p.addQuadCurve(to: r.p(50, 70), control: r.p(46.5, 75))
        p.addQuadCurve(to: r.p(56.5, 70), control: r.p(53.5, 75))
        return p
    }
}

private struct Whiskers: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (a, b) in [((22.0, 64.0), (8.0, 60.0)), ((22.0, 69.0), (7.0, 70.0))] {
            p.move(to: r.p(a.0, a.1)); p.addLine(to: r.p(b.0, b.1))
            p.move(to: r.p(100 - a.0, a.1)); p.addLine(to: r.p(100 - b.0, b.1))
        }
        return p
    }
}

private struct Collar: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.p(31, 83))
        p.addQuadCurve(to: r.p(69, 83), control: r.p(50, 91))
        p.addQuadCurve(to: r.p(68, 88.5), control: r.p(70.5, 86))
        p.addQuadCurve(to: r.p(32, 88.5), control: r.p(50, 96))
        p.addQuadCurve(to: r.p(31, 83), control: r.p(29.5, 86))
        p.closeSubpath()
        return p
    }
}

// MARK: - App 图标

struct AppIconView: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let side = w * 0.805 // macOS 图标的圆角矩形占画布约 80%
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.80, blue: 0.87), Color(red: 1, green: 0.74, blue: 0.62)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        ZStack {
                            Circle().fill(.white.opacity(0.35)).frame(width: side * 0.55).offset(x: -side * 0.28, y: -side * 0.3).blur(radius: side * 0.06)
                            Circle().fill(Color(red: 1, green: 0.95, blue: 0.7).opacity(0.5)).frame(width: side * 0.4).offset(x: side * 0.32, y: side * 0.3).blur(radius: side * 0.07)
                            Sparkle().fill(.white).frame(width: side * 0.09, height: side * 0.09).offset(x: side * 0.33, y: -side * 0.31)
                            Sparkle().fill(.white.opacity(0.85)).frame(width: side * 0.055, height: side * 0.055).offset(x: -side * 0.36, y: side * 0.2)
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.225, style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: side * 0.008))
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.22), radius: w * 0.02, y: w * 0.012)
                CatFace(bellSwing: -8)
                    .frame(width: side * 0.8, height: side * 0.8)
                    .offset(y: side * 0.02)
                    .shadow(color: CatFace.ink.opacity(0.18), radius: w * 0.012, y: w * 0.008)
            }
            .frame(width: w, height: g.size.height)
        }
    }
}

struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: CGPoint(x: c.x, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.maxY), control: c)
        p.addQuadCurve(to: CGPoint(x: r.minX, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: r.minY), control: c)
        return p
    }
}

/// 来消息时：蹦一下、右耳抖两下、铃铛摇起来
struct RingingCat: View {
    var tick: Int
    var size: CGFloat = 38
    var sleeping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bell: Double = 0
    @State private var ear: Double = 0
    @State private var hop = false

    var body: some View {
        CatFace(sleeping: sleeping, earTwitch: ear, bellSwing: bell)
            .frame(width: size, height: size)
            .offset(y: hop ? -size * 0.12 : 0)
            .scaleEffect(hop ? 1.06 : 1)
            .onChange(of: tick) { ring() }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ring() } }
    }

    private func ring() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { hop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { hop = false }
        }
        for (i, a) in [-28.0, 24, -18, 12, -7, 3, 0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                withAnimation(.easeInOut(duration: 0.09)) { bell = a }
            }
        }
        for (i, a) in [-16.0, 0, -12, 0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + Double(i) * 0.08) {
                withAnimation(.easeInOut(duration: 0.08)) { ear = a }
            }
        }
    }
}

// MARK: - 菜单栏小猫（单色模板图，系统自动适配深浅色）

enum MenubarCat {
    enum Mood { case idle, unread, sleeping, offline }

    /// 头 + 两只耳朵合成一个剪影
    private static let silhouette: CGPath = {
        let r = CGRect(x: 0, y: 0, width: 100, height: 100)
        return Head().path(in: r).cgPath
            .union(Ear(left: true).path(in: r).cgPath)
            .union(Ear(left: false).path(in: r).cgPath)
    }()

    static func image(_ mood: Mood, angle: CGFloat = 0) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let img = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // 设计空间里剪影大约占 x 8…92、y 9…90，等比缩放进图标
            let s: CGFloat = 16.4 / 84
            let ox = (rect.width - 84 * s) / 2 - 8 * s
            let oy = (rect.height - 81 * s) / 2 - 9 * s
            // 来消息时绕下巴左右歪头
            ctx.translateBy(x: rect.midX, y: rect.maxY - 1)
            ctx.rotate(by: angle * .pi / 180)
            ctx.translateBy(x: -rect.midX, y: -(rect.maxY - 1))
            ctx.translateBy(x: ox, y: oy)
            ctx.scaleBy(x: s, y: s)

            let ink = NSColor.black.cgColor
            ctx.setFillColor(ink)
            ctx.setStrokeColor(ink)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            if mood == .offline { ctx.setAlpha(0.55) }

            if mood == .unread {
                ctx.addPath(silhouette)
                ctx.fillPath()
                ctx.setBlendMode(.clear) // 眼睛挖空
                for x: CGFloat in [37, 63] { ctx.fillEllipse(in: CGRect(x: x - 6, y: 52, width: 12, height: 13)) }
                return true
            }

            ctx.setLineWidth(1.45 / s)
            ctx.addPath(silhouette)
            ctx.strokePath()
            ctx.setLineWidth(1.25 / s)
            switch mood {
            case .sleeping:
                for x: CGFloat in [37, 63] {
                    ctx.move(to: CGPoint(x: x - 7, y: 56))
                    ctx.addQuadCurve(to: CGPoint(x: x + 7, y: 56), control: CGPoint(x: x, y: 64))
                }
                ctx.strokePath()
            case .offline:
                for x: CGFloat in [37, 63] {
                    ctx.move(to: CGPoint(x: x - 5, y: 53)); ctx.addLine(to: CGPoint(x: x + 5, y: 63))
                    ctx.move(to: CGPoint(x: x + 5, y: 53)); ctx.addLine(to: CGPoint(x: x - 5, y: 63))
                }
                ctx.strokePath()
            default:
                for x: CGFloat in [37, 63] { ctx.fillEllipse(in: CGRect(x: x - 5.5, y: 52, width: 11, height: 12)) }
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
