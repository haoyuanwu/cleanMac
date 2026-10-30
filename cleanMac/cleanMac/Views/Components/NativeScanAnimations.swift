import SwiftUI

/// 扫描插画全部使用矢量绘制；时间线随扫描视图挂载，仅前台更新，不创建常驻计时器。
struct OneClickScanAnimation: View {
    var isAnimating = true
    var body: some View { NativeScanAnimation(style: .inspector, isAnimating: isAnimating) }
}

struct GeneralScanAnimation: View {
    var isAnimating = true
    var body: some View { NativeScanAnimation(style: .files, isAnimating: isAnimating) }
}

private struct NativeScanAnimation: View {
    enum Style { case inspector, files }
    let style: Style
    let isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !isAnimating || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let scale = min(size.width / 480, size.height / 300)
                context.translateBy(x: (size.width - 480 * scale) / 2, y: (size.height - 300 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                let time = reduceMotion || !isAnimating ? 1.2 : timeline.date.timeIntervalSince(startedAt)
                let art = ScanIllustration(dark: colorScheme == .dark)
                art.backdrop(&context)
                switch style {
                case .inspector: art.inspector(&context, time: time)
                case .files: art.files(&context, time: time)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScanIllustration {
    let dark: Bool
    private var ink: Color { dark ? .white : .indigo }

    func backdrop(_ context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: 70, y: 15, width: 340, height: 270)), with: .radialGradient(
            Gradient(colors: [.cyan.opacity(dark ? 0.12 : 0.16), .indigo.opacity(0.05), .clear]),
            center: CGPoint(x: 240, y: 158), startRadius: 5, endRadius: 170))
        context.fill(Path(ellipseIn: CGRect(x: 130, y: 254, width: 230, height: 18)), with: .color(.indigo.opacity(dark ? 0.18 : 0.09)))
        context.stroke(Path(ellipseIn: CGRect(x: 86, y: 49, width: 306, height: 206)),
                       with: .color(ink.opacity(0.10)), style: StrokeStyle(lineWidth: 1, dash: [3, 8]))
        star(&context, x: 100, y: 148, size: 6, color: .cyan.opacity(0.7))
        star(&context, x: 371, y: 76, size: 7, color: .purple.opacity(0.7))
        star(&context, x: 372, y: 240, size: 5, color: .indigo.opacity(0.6))
        circle(&context, x: 137, y: 61, radius: 3, color: .pink.opacity(0.6))
        circle(&context, x: 406, y: 178, radius: 3, color: .cyan.opacity(0.6))
    }

    func inspector(_ context: inout GraphicsContext, time: Double) {
        // 文档围绕巡检路线排布，小巡检员的目光跟随放大镜。
        document(&context, center: CGPoint(x: 133, y: 115), angle: -0.22, width: 52, checked: true, tint: .cyan)
        document(&context, center: CGPoint(x: 235, y: 65), angle: 0.10, width: 48, checked: false, tint: .purple)
        document(&context, center: CGPoint(x: 341, y: 105), angle: 0.20, width: 46, checked: true, tint: .pink)

        let bob = sin(time * 1.8) * 3
        var robot = context
        robot.translateBy(x: 0, y: bob)
        rounded(&robot, rect: CGRect(x: 205, y: 232, width: 25, height: 18), radius: 7, colors: [.indigo, .blue])
        rounded(&robot, rect: CGRect(x: 253, y: 232, width: 25, height: 18), radius: 7, colors: [.indigo, .blue])
        line(&robot, from: CGPoint(x: 240, y: 134), to: CGPoint(x: 240, y: 112), color: .indigo.opacity(0.7), width: 4)
        circle(&robot, x: 240, y: 109, radius: 7, color: .cyan)
        circle(&robot, x: 240, y: 109, radius: 12 + sin(time * 2) * 2, color: .cyan.opacity(0.12))
        rounded(&robot, rect: CGRect(x: 162, y: 171, width: 20, height: 37), radius: 9, colors: [.cyan, .blue])
        rounded(&robot, rect: CGRect(x: 301, y: 171, width: 20, height: 37), radius: 9, colors: [.blue, .indigo])
        rounded(&robot, rect: CGRect(x: 177, y: 132, width: 128, height: 109), radius: 29, colors: [.cyan, .blue, .indigo])
        rounded(&robot, rect: CGRect(x: 189, y: 146, width: 104, height: 61), radius: 20,
                colors: [Color(red: 0.08, green: 0.16, blue: 0.34), Color(red: 0.13, green: 0.12, blue: 0.32)])
        let blink = time.truncatingRemainder(dividingBy: 5.2) < 0.16
        let look = sin(time * 0.95) * 3
        for x in [218.0, 264] {
            let rect = CGRect(x: x - 5 + look, y: blink ? 174 : 166, width: 10, height: blink ? 3 : 17)
            robot.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(.cyan.opacity(0.95)))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: 233, y: 188))
        smile.addQuadCurve(to: CGPoint(x: 249, y: 188), control: CGPoint(x: 241, y: 196))
        robot.stroke(smile, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        rounded(&robot, rect: CGRect(x: 220, y: 220, width: 41, height: 6), radius: 3, colors: [.white.opacity(0.6), .cyan.opacity(0.6)])
        lens(&context, center: CGPoint(x: 322 + sin(time * 0.95) * 25, y: 172 + cos(time * 0.95) * 18), radius: 34)
    }

    func files(_ context: inout GraphicsContext, time: Double) {
        document(&context, center: CGPoint(x: 173, y: 120), angle: -0.27, width: 54, checked: false, tint: .cyan)
        document(&context, center: CGPoint(x: 238, y: 95), angle: 0.06, width: 60, checked: true, tint: .purple)
        document(&context, center: CGPoint(x: 303, y: 128), angle: 0.26, width: 49, checked: false, tint: .pink)
        rounded(&context, rect: CGRect(x: 155, y: 134, width: 78, height: 34), radius: 12, colors: [.cyan, .blue])
        rounded(&context, rect: CGRect(x: 155, y: 149, width: 170, height: 91), radius: 16, colors: [.blue, .indigo])
        let front = Path(roundedRect: CGRect(x: 147, y: 162, width: 186, height: 84), cornerRadius: 17)
        context.fill(front, with: .linearGradient(Gradient(colors: [.cyan.opacity(0.95), .blue, .indigo]),
                     startPoint: CGPoint(x: 150, y: 162), endPoint: CGPoint(x: 333, y: 246)))
        context.stroke(front, with: .color(.white.opacity(0.45)), lineWidth: 1)
        var sweep = context
        sweep.clip(to: front)
        let scanY = 163 + (sin(time * 1.2) + 1) * 39
        let beam = CGRect(x: 148, y: scanY - 19, width: 184, height: 20)
        sweep.fill(Path(beam), with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.20)]),
                   startPoint: CGPoint(x: 240, y: beam.minY), endPoint: CGPoint(x: 240, y: beam.maxY)))
        line(&sweep, from: CGPoint(x: 150, y: scanY), to: CGPoint(x: 330, y: scanY), color: .white.opacity(0.55), width: 1.5)
        for index in 0..<3 {
            circle(&context, x: 177 + Double(index) * 11, y: 224, radius: 2, color: .white.opacity(0.6))
        }
        lens(&context, center: CGPoint(x: 302 + sin(time * 0.8) * 29, y: 165 + cos(time * 0.8) * 27), radius: 38)
    }

    private func document(_ context: inout GraphicsContext, center: CGPoint, angle: Double, width: Double, checked: Bool, tint: Color) {
        var card = context
        card.translateBy(x: center.x, y: center.y)
        card.rotate(by: .radians(angle))
        let rect = CGRect(x: -width / 2, y: -width * 0.66, width: width, height: width * 1.32)
        let shape = Path(roundedRect: rect, cornerRadius: 9)
        card.fill(shape, with: .linearGradient(Gradient(colors: [dark ? Color.white.opacity(0.24) : .white.opacity(0.94), tint.opacity(dark ? 0.18 : 0.14)]), startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        card.stroke(shape, with: .color(.white.opacity(dark ? 0.4 : 0.85)), lineWidth: 1)
        rounded(&card, rect: CGRect(x: rect.minX + 10, y: rect.minY + 13, width: 17, height: 17), radius: 5, colors: [tint.opacity(0.8), tint.opacity(0.5)])
        for index in 0..<3 {
            let y = rect.minY + 40 + Double(index) * 7
            line(&card, from: CGPoint(x: rect.minX + 10, y: y), to: CGPoint(x: rect.maxX - (index == 2 ? 20 : 10), y: y), color: ink.opacity(0.20), width: 2)
        }
        if checked {
            circle(&card, x: rect.maxX - 2, y: rect.maxY - 3, radius: 10, color: .mint)
            var tick = Path()
            tick.move(to: CGPoint(x: rect.maxX - 7, y: rect.maxY - 3))
            tick.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.maxY + 1))
            tick.addLine(to: CGPoint(x: rect.maxX + 3, y: rect.maxY - 6))
            card.stroke(tick, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func lens(_ context: inout GraphicsContext, center: CGPoint, radius: Double) {
        line(&context, from: CGPoint(x: center.x + radius * 0.68, y: center.y + radius * 0.68),
             to: CGPoint(x: center.x + radius * 1.38, y: center.y + radius * 1.38), color: .indigo, width: 15)
        let rim = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(rim, with: .linearGradient(Gradient(colors: [.cyan.opacity(0.30), .white.opacity(dark ? 0.13 : 0.45)]),
                     startPoint: CGPoint(x: center.x - radius, y: center.y - radius), endPoint: CGPoint(x: center.x + radius, y: center.y + radius)))
        context.stroke(rim, with: .linearGradient(Gradient(colors: [.cyan, .indigo]), startPoint: CGPoint(x: center.x - radius, y: center.y - radius), endPoint: CGPoint(x: center.x + radius, y: center.y + radius)), lineWidth: 7)
        var shine = Path()
        shine.addArc(center: center, radius: radius - 9, startAngle: .degrees(205), endAngle: .degrees(266), clockwise: false)
        context.stroke(shine, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        line(&context, from: CGPoint(x: center.x - 7, y: center.y), to: CGPoint(x: center.x + 7, y: center.y), color: .white.opacity(0.8), width: 2)
        line(&context, from: CGPoint(x: center.x, y: center.y - 7), to: CGPoint(x: center.x, y: center.y + 7), color: .white.opacity(0.8), width: 2)
    }

    private func rounded(_ context: inout GraphicsContext, rect: CGRect, radius: Double, colors: [Color]) {
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        context.fill(shape, with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        context.stroke(shape, with: .color(.white.opacity(0.2)), lineWidth: 1)
    }
    private func circle(_ context: inout GraphicsContext, x: Double, y: Double, radius: Double, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
    }
    private func line(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: Double) {
        var path = Path(); path.move(to: from); path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
    private func star(_ context: inout GraphicsContext, x: Double, y: Double, size: Double, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: y - size))
        path.addQuadCurve(to: CGPoint(x: x + size, y: y), control: CGPoint(x: x + 1, y: y - 1))
        path.addQuadCurve(to: CGPoint(x: x, y: y + size), control: CGPoint(x: x + 1, y: y + 1))
        path.addQuadCurve(to: CGPoint(x: x - size, y: y), control: CGPoint(x: x - 1, y: y + 1))
        path.addQuadCurve(to: CGPoint(x: x, y: y - size), control: CGPoint(x: x - 1, y: y - 1))
        context.fill(path, with: .color(color))
    }
}
