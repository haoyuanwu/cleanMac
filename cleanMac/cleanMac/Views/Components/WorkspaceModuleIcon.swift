import SwiftUI

/// 24pt 网格中的功能图标，统一圆角线端和 1.7pt 线宽。
/// 颜色继承导航状态，形状本身区分功能，避免仅靠颜色识别。
struct WorkspaceModuleIcon: View {
    let group: WorkspaceGroup
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.translateBy(x: (size.width - 24 * scale) / 2, y: (size.height - 24 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            func stroke(_ path: Path) {
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            }
            func line(_ points: [CGPoint]) {
                stroke(Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for point in points.dropFirst() { p.addLine(to: point) }
                })
            }
            func poly(_ points: [(CGFloat, CGFloat)]) {
                line(points.map { CGPoint(x: $0.0, y: $0.1) })
            }
            func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat = 2) {
                stroke(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: radius))
            }
            func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
                stroke(Path { p in
                    p.move(to: CGPoint(x: x, y: y-r))
                    p.addQuadCurve(to: CGPoint(x: x+r, y: y), control: CGPoint(x: x, y: y))
                    p.addQuadCurve(to: CGPoint(x: x, y: y+r), control: CGPoint(x: x, y: y))
                    p.addQuadCurve(to: CGPoint(x: x-r, y: y), control: CGPoint(x: x, y: y))
                    p.addQuadCurve(to: CGPoint(x: x, y: y-r), control: CGPoint(x: x, y: y))
                    p.closeSubpath()
                })
            }
            switch group {
            case .overview:
                stroke(Path(ellipseIn: CGRect(x: 2.5, y: 3, width: 14, height: 14)))
                poly([(14.8,15.3), (21,21.5)])
                star(9.5, 10, 3.2)
            case .cleanup:
                // 清扫刷柄、刷头、刷毛和已经擦亮的星光。
                poly([(11,12), (16.5,3.5)])
                stroke(Path { p in
                    p.move(to: CGPoint(x: 8, y: 11))
                    p.addQuadCurve(to: CGPoint(x: 15, y: 15), control: CGPoint(x: 13, y: 11))
                    p.addLine(to: CGPoint(x: 13, y: 21))
                    p.addQuadCurve(to: CGPoint(x: 3, y: 17), control: CGPoint(x: 6, y: 23))
                    p.closeSubpath()
                })
                poly([(8,16), (6,20)])
                poly([(11,17), (10,21)])
                star(20, 10, 2.5)
            case .files:
                stroke(Path { p in
                    p.move(to: CGPoint(x: 3, y: 7))
                    p.addLine(to: CGPoint(x: 3, y: 4))
                    p.addQuadCurve(to: CGPoint(x: 5, y: 2), control: CGPoint(x: 3, y: 2))
                    p.addLine(to: CGPoint(x: 10, y: 2))
                    p.addLine(to: CGPoint(x: 13, y: 5))
                    p.addLine(to: CGPoint(x: 20, y: 5))
                })
                roundRect(2, 8, 20, 13)
                poly([(7,12), (7,17)])
                poly([(11,12), (17,12)])
                poly([(11,16), (15,16)])
            case .applications:
                roundRect(2, 2, 8, 8)
                roundRect(14, 2, 8, 8)
                roundRect(2, 14, 8, 8)
                // 第四格为开发代码，兼顾应用管理和开发数据。
                poly([(16.5,15), (13.5,18), (16.5,21)])
                poly([(20,15), (23,18), (20,21)])
            case .storage:
                stroke(Path { p in
                    p.addArc(center: CGPoint(x: 12, y: 12), radius: 10, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
                })
                poly([(12,2), (12,12), (20,18)])
                poly([(12,12), (3,16)])
                poly([(12,12), (21,7.5)])
            case .preferences:
                // 盾牌包围设置滑杆，表达偏好与保护。
                stroke(Path { p in
                    p.move(to: CGPoint(x: 12, y: 2))
                    p.addLine(to: CGPoint(x: 21, y: 5))
                    p.addLine(to: CGPoint(x: 20, y: 13))
                    p.addQuadCurve(to: CGPoint(x: 12, y: 22), control: CGPoint(x: 19, y: 19))
                    p.addQuadCurve(to: CGPoint(x: 4, y: 13), control: CGPoint(x: 5, y: 19))
                    p.addLine(to: CGPoint(x: 3, y: 5))
                    p.closeSubpath()
                })
                poly([(7,9), (17,9)])
                poly([(7,14), (17,14)])
                poly([(10,7), (10,11)])
                poly([(14,12), (14,16)])
            case .device:
                roundRect(2, 3, 20, 14)
                poly([(9,21), (15,21)])
                poly([(12,17), (12,21)])
                poly([(5,10), (8,10), (10,6), (13,14), (15,10), (19,10)])
            }
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}
