import SwiftUI

/// App 图标的矢量源，背景保持纯色。
enum CleanMacBrand {
    static let background = Color(red: 0.955, green: 0.965, blue: 0.99)
    static let ink = Color(red: 0.10, green: 0.15, blue: 0.29)
    static let spectrum = LinearGradient(
        colors: [Color(red: 0.08, green: 0.78, blue: 0.91),
                 Color(red: 0.23, green: 0.49, blue: 0.99),
                 Color(red: 0.55, green: 0.32, blue: 0.96),
                 Color(red: 0.94, green: 0.35, blue: 0.67)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// 简化笔记本轮廓与三颗四角星，小尺寸仍保留屏幕、底座和清洁语义。
struct CleanMacLaptopMark: View {
    var colorBlocked = false

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.065, style: .continuous)
                    .fill(CleanMacBrand.spectrum)
                    .overlay {
                        if colorBlocked {
                            LaptopColorPanels()
                                .clipShape(RoundedRectangle(cornerRadius: side * 0.065, style: .continuous))
                        }
                    }
                    .frame(width: side * 0.76, height: side * 0.53)
                    .offset(y: -side * 0.055)
                RoundedRectangle(cornerRadius: side * 0.027, style: .continuous)
                    .fill(CleanMacBrand.ink)
                    .frame(width: side * 0.646, height: side * 0.416)
                    .offset(y: -side * 0.055)
                LaptopBase().fill(CleanMacBrand.spectrum)
                    .overlay {
                        if colorBlocked {
                            LaptopColorPanels(base: true).clipShape(LaptopBase())
                        }
                    }
                    .frame(width: side * 0.94, height: side * 0.11)
                    .offset(y: side * 0.255)
                Capsule().fill(CleanMacBrand.ink.opacity(0.4))
                    .frame(width: side * 0.19, height: side * 0.018)
                    .offset(y: side * 0.224)
                CleaningStar().fill(.white)
                    .frame(width: side * 0.20, height: side * 0.24)
                    .offset(x: side * 0.025, y: -side * 0.035)
                CleaningStar().fill(Color(red: 0.55, green: 0.95, blue: 1))
                    .frame(width: side * 0.09, height: side * 0.11)
                    .offset(x: -side * 0.16, y: -side * 0.12)
                CleaningStar().fill(Color(red: 1, green: 0.78, blue: 0.94))
                    .frame(width: side * 0.07, height: side * 0.085)
                    .offset(x: side * 0.18, y: side * 0.055)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct CleanMacLogo: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: geometry.size.width * 0.225, style: .continuous)
                    .fill(CleanMacBrand.background)
                CleanMacLaptopMark(colorBlocked: true).padding(geometry.size.width * 0.08)
            }
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

/// App 图标使用边界清晰的对角拼色区域。
private struct LaptopColorPanels: View {
    var base = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Color(red: 0.10, green: 0.78, blue: 0.90)
                Path { p in
                    p.move(to: CGPoint(x: width * 0.48, y: 0))
                    p.addLine(to: CGPoint(x: width, y: 0))
                    p.addLine(to: CGPoint(x: width, y: height))
                    p.addLine(to: CGPoint(x: width * 0.30, y: height))
                    p.closeSubpath()
                }.fill(Color(red: 0.48, green: 0.36, blue: 0.94))
                if base {
                    Path { p in
                        p.move(to: CGPoint(x: width * 0.66, y: 0))
                        p.addLine(to: CGPoint(x: width, y: 0))
                        p.addLine(to: CGPoint(x: width, y: height))
                        p.addLine(to: CGPoint(x: width * 0.58, y: height))
                        p.closeSubpath()
                    }.fill(Color(red: 0.97, green: 0.43, blue: 0.66))
                }
            }
        }
    }
}

private struct LaptopBase: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.width * 0.10, y: 0))
            p.addLine(to: CGPoint(x: rect.width * 0.90, y: 0))
            p.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.55))
            p.addQuadCurve(to: CGPoint(x: rect.width * 0.93, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
            p.addLine(to: CGPoint(x: rect.width * 0.07, y: rect.height))
            p.addQuadCurve(to: CGPoint(x: 0, y: rect.height * 0.55), control: CGPoint(x: 0, y: rect.height))
            p.closeSubpath()
        }
    }
}

private struct CleaningStar: Shape {
    nonisolated func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: 0))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.width * 0.57, y: r.height * 0.43))
            p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.width * 0.57, y: r.height * 0.57))
            p.addQuadCurve(to: CGPoint(x: 0, y: r.midY), control: CGPoint(x: r.width * 0.43, y: r.height * 0.57))
            p.addQuadCurve(to: CGPoint(x: r.midX, y: 0), control: CGPoint(x: r.width * 0.43, y: r.height * 0.43))
            p.closeSubpath()
        }
    }
}
