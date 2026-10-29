import SwiftUI

/// 视觉令牌：连续多色画布 + 渐变强调 + 分层阴影 + 克制动效
enum Theme {
    /// 导航卡片的小字号说明文本，分别适配浅色和深色表面。
    static let navigationSecondary = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 0.36, green: 0.39, blue: 0.45, alpha: 1),
        dark: NSColor(srgbRed: 0.72, green: 0.75, blue: 0.81, alpha: 1)
    ))
    // MARK: - Surface
    static let cardFill = Color.primary.opacity(0.035)
    static let cardStroke = Color.primary.opacity(0.06)
    static let hairline = Color.primary.opacity(0.07)

    // MARK: - Canvas / Sidebar（非纯白，冷调雾灰蓝）
    /// 主内容画布
    static let canvas = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 0.957, green: 0.969, blue: 0.984, alpha: 1), // #F4F7FB
        dark: NSColor(srgbRed: 0.105, green: 0.118, blue: 0.145, alpha: 1)   // #1B1E25
    ))
    /// 侧边栏
    static let sidebar = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 0.918, green: 0.937, blue: 0.965, alpha: 1), // #EAEFF6
        dark: NSColor(srgbRed: 0.125, green: 0.141, blue: 0.176, alpha: 1)   // #20242D
    ))
    /// 侧边栏顶部略深，形成轻微纵深
    static let sidebarTop = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 0.890, green: 0.914, blue: 0.949, alpha: 1), // #E3E9F2
        dark: NSColor(srgbRed: 0.110, green: 0.125, blue: 0.155, alpha: 1)
    ))
    /// 列表行 / 凹陷区域
    static let surfaceSunk = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 0.933, green: 0.949, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.145, green: 0.161, blue: 0.196, alpha: 1)
    ))
    /// 浮起面板（比画布更亮一点）
    static let surfaceRaised = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 0.980, green: 0.986, blue: 0.994, alpha: 1),
        dark: NSColor(srgbRed: 0.165, green: 0.184, blue: 0.220, alpha: 1)
    ))

    /// 页面内轻量控件透出共享渐变；弹窗继续使用独立实底。
    static let inlineSurface = surfaceRaised.opacity(0.32)

    /// 主区顶部冷色紫蓝洗染，产品仪表盘纵深
    static let canvasWash = LinearGradient(
        colors: [
            Color(red: 0.55, green: 0.65, blue: 0.98).opacity(0.22),
            Color(red: 0.72, green: 0.58, blue: 0.95).opacity(0.10),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .center
    )

    /// 审查工具详情页共用的浅色渐变画布。
    static func reviewCanvas(_ accent: Color) -> some View {
        ZStack {
            canvas
            LinearGradient(
                colors: [
                    accent.opacity(0.18),
                    Color(red: 0.60, green: 0.67, blue: 0.98).opacity(0.10),
                    accent.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    /// 侧边栏渐变底
    static let sidebarGradient = LinearGradient(
        colors: [sidebarTop, sidebar],
        startPoint: .top,
        endPoint: .bottom
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: - Accent gradients
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.22, green: 0.52, blue: 1.0),
            Color(red: 0.48, green: 0.32, blue: 0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradientSoft = LinearGradient(
        colors: [
            Color(red: 0.22, green: 0.52, blue: 1.0).opacity(0.22),
            Color(red: 0.48, green: 0.32, blue: 0.98).opacity(0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.58, blue: 0.22),
            Color(red: 1.0, green: 0.32, blue: 0.42)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let successGradient = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.80, blue: 0.54),
            Color(red: 0.12, green: 0.62, blue: 0.78)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static func categoryGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.95), color.opacity(0.55)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 环形图角度渐变
    static func ringGradient(_ colors: [Color]) -> AngularGradient {
        AngularGradient(colors: colors + [colors.first ?? .accentColor], center: .center)
    }

    // MARK: - Shadow
    static func cardShadow() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(0.10), 20, 8)
    }

    static func elevatedShadow() -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(0.18), 36, 16)
    }

    // MARK: - Motion
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var spring: Animation {
        prefersReducedMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.82)
    }
    static var springSnappy: Animation {
        prefersReducedMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.78)
    }
    static var ease: Animation {
        prefersReducedMotion ? .easeInOut(duration: 0.08) : .easeInOut(duration: 0.22)
    }
    static var easeSlow: Animation {
        prefersReducedMotion ? .easeInOut(duration: 0.12) : .easeInOut(duration: 0.42)
    }
    static var scanPulse: Animation {
        prefersReducedMotion
            ? .easeInOut(duration: 0.2)
            : .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
    }
}

// MARK: - 分层阴影
extension View {
    func cardShadow() -> some View {
        let s = Theme.cardShadow()
        return self
            .shadow(color: s.color.opacity(0.5), radius: s.radius * 0.4, y: 2)
            .shadow(color: s.color, radius: s.radius, y: s.y)
    }

    func elevatedShadow() -> some View {
        let s = Theme.elevatedShadow()
        return self
            .shadow(color: Color(red: 0.35, green: 0.40, blue: 0.95).opacity(0.22), radius: 24, y: 8)
            .shadow(color: s.color.opacity(0.45), radius: s.radius * 0.35, y: 3)
            .shadow(color: s.color, radius: s.radius, y: s.y)
    }
}

// MARK: - 比例条（扁平 + 渐变填充）
struct ProportionBar: View {
    var progress: Double
    var gradient: LinearGradient = Theme.accentGradient
    var height: CGFloat = 6
    var trackOpacity: Double = 0.08

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(trackOpacity))
                Capsule()
                    .fill(gradient)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(Theme.ease, value: progress)
    }
}

// MARK: - 大号渐变环
struct GradientRing: View {
    var progress: Double
    var colors: [Color] = [
        Color(red: 0.29, green: 0.56, blue: 1.0),
        Color(red: 0.45, green: 0.38, blue: 0.98),
        Color(red: 1.0, green: 0.42, blue: 0.48)
    ]
    var lineWidth: CGFloat = 12
    var showsCenter: Bool = true
    var centerTitle: String = "已使用"
    var centerValue: String = ""

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(
                    Theme.ringGradient(colors),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if showsCenter {
                VStack(spacing: 2) {
                    Text(centerTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(centerValue)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .animation(Theme.easeSlow, value: progress)
    }
}

// MARK: - 圆环扇区路径（便于加粗命中测试）
struct RingSectorShape: Shape {
    var startFraction: Double
    var endFraction: Double

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(0, min(rect.width, rect.height) / 2)
        let start = Angle.degrees(startFraction * 360 - 90)
        let end = Angle.degrees(endFraction * 360 - 90)
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}

// MARK: - 存储 × 扫描 一体主控件（大圆环）
/// 外环：空闲=磁盘占用，扫描后=分类扇区；环心：操作钮 / 悬停信息
struct ScanHeroControl: View {
    struct Segment: Identifiable, Equatable {
        let id: String
        let name: String
        let color: Color
        let fraction: Double
        let detail: String
        /// 环心展示用图标资源名（SF Symbol 或 Asset）
        var iconAsset: String = ""
        var usesAssetIcon: Bool = true

        var percentText: String {
            String(format: "%.0f%%", max(0, fraction) * 100)
        }
    }

    enum Phase: Equatable {
        case idle
        case scanning(progress: Double)
        case finished
    }

    var phase: Phase
    var storageUsed: Double = 0
    var storageUsedText: String = ""
    var storageTotalText: String = ""
    var segments: [Segment] = []
    var cleanableText: String = ""
    var smartCleanText: String = ""
    var scanningTitle: String? = nil
    var scanningSubtitle: String? = nil
    var finishedTitle: String? = nil
    var finishedSubtitle: String? = nil
    var isEnabled: Bool = true
    var isSmartCleanEnabled: Bool = false
    var primaryActionTitle = "开始扫描"
    var action: () -> Void
    var onSmartClean: (() -> Void)? = nil
    var onSegmentTap: ((Segment) -> Void)? = nil

    @State private var isCenterHovered = false
    @State private var isPressed = false
    @State private var ringPulse = false
    @State private var hoveredSegmentID: String?
    @State private var isStorageHovered = false
    /// 完成态扇区展开动画 0...1
    @State private var segmentExpand: Double = 0

    private var scanProgress: Double {
        if case .scanning(let p) = phase { return p }
        return phase == .finished ? 1 : 0
    }

    private var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    private var showSegments: Bool {
        phase == .finished && !segments.isEmpty
    }

    private var hoveredSegment: Segment? {
        segments.first { $0.id == hoveredSegmentID }
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .opacity((isCenterHovered || hoveredSegment != nil || isStorageHovered) ? 0.28 : 0.14)
                    .frame(width: 460, height: 460)
                    .blur(radius: 36)
                    .scaleEffect(ringPulse ? 1.06 : 1)
                    .animation(Theme.scanPulse, value: ringPulse)
                    .allowsHitTesting(false)

                // 外环视觉
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: ringThickness)
                        .allowsHitTesting(false)

                    if showSegments {
                        segmentRing
                    } else {
                        storageRing
                    }
                }
                .frame(width: ringDiameter, height: ringDiameter)
                .allowsHitTesting(false)

                // 内环：扫描进度
                ZStack {
                    if isScanning {
                        Circle()
                            .stroke(Color.primary.opacity(0.06), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1, max(0, scanProgress))))
                            .stroke(
                                Theme.accentGradient,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(Theme.easeSlow, value: scanProgress)
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    }
                }
                .frame(width: 236, height: 236)
                .allowsHitTesting(false)

                centerContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)

                // 环带命中层：按角度反查扇区（盖在视觉之上、环心之下）
                ringHitZone
                    .zIndex(0)
            }
            .frame(width: 420, height: 420)
            .animation(Theme.spring, value: hoveredSegmentID)
            .animation(Theme.spring, value: isStorageHovered)

            VStack(spacing: 6) {
                if phase == .finished && hoveredSegment == nil && !isStorageHovered,
                   let onSmartClean {
                    Button(action: onSmartClean) {
                        Label(
                            isSmartCleanEnabled
                                ? "智能清理 · 预计可释放 \(smartCleanText)"
                                : "暂无推荐清理项目",
                            systemImage: "wand.and.stars"
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(
                            Capsule().fill(
                                isSmartCleanEnabled
                                    ? AnyShapeStyle(Theme.accentGradient)
                                    : AnyShapeStyle(Color.secondary.opacity(0.5))
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSmartCleanEnabled)
                    .help("查看低风险推荐清理项目")
                } else {
                    Text(titleText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(titleGradient)
                        .monospacedDigit()
                        .animation(Theme.spring, value: titleText)
                }

                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .animation(Theme.spring, value: subtitleText)
            }
        }
        .onAppear {
            ringPulse = true
            if showSegments {
                segmentExpand = 0
                withAnimation(Theme.easeSlow) { segmentExpand = 1 }
            }
        }
        .onChange(of: showSegments) { show in
            if show {
                segmentExpand = 0
                withAnimation(Theme.easeSlow) { segmentExpand = 1 }
            } else {
                withAnimation(Theme.ease) { segmentExpand = 0 }
            }
        }
    }

    // MARK: - 尺寸
    private var ringDiameter: CGFloat { 340 }
    private var ringThickness: CGFloat { 30 }
    private var activeThickness: CGFloat { 38 }
    private var hitThickness: CGFloat { 64 }
    private var activeLift: CGFloat { 10 }

    // MARK: - 环带命中（连续追踪鼠标角度）
    private var ringHitZone: some View {
        Circle()
            .stroke(Color.primary.opacity(0.001), lineWidth: hitThickness)
            .frame(width: ringDiameter, height: ringDiameter)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updateHover(at: location)
                case .ended:
                    withAnimation(Theme.spring) {
                        hoveredSegmentID = nil
                        isStorageHovered = false
                    }
                }
            }
            .onTapGesture {
                if let segment = hoveredSegment {
                    onSegmentTap?(segment)
                }
            }
    }

    private func updateHover(at location: CGPoint) {
        let center = CGPoint(x: ringDiameter / 2, y: ringDiameter / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let bandInner = ringDiameter / 2 - hitThickness / 2
        let bandOuter = ringDiameter / 2 + hitThickness / 2

        // 不在环带内则清空
        guard distance >= bandInner, distance <= bandOuter else {
            if hoveredSegmentID != nil || isStorageHovered {
                withAnimation(Theme.spring) {
                    hoveredSegmentID = nil
                    isStorageHovered = false
                }
            }
            return
        }

        // 0 点在正上方，顺时针 0...1
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let fraction = degrees / 360

        if showSegments {
            let matched = segmentArcs.first { arc in
                fraction >= arc.start && fraction < arc.end
            }?.segment.id
            if hoveredSegmentID != matched {
                withAnimation(Theme.spring) {
                    hoveredSegmentID = matched
                    isStorageHovered = false
                }
            }
        } else {
            let onUsed = fraction <= min(1, max(0, storageUsed))
            if isStorageHovered != onUsed {
                withAnimation(Theme.spring) {
                    isStorageHovered = onUsed
                    hoveredSegmentID = nil
                }
            }
        }
    }

    // MARK: - 磁盘占用环
    private var storageRing: some View {
        let used = CGFloat(min(1, max(0, storageUsed)))

        return ZStack {
            RingSectorShape(startFraction: 0, endFraction: Double(used))
                .stroke(
                    Theme.ringGradient([
                        Color(red: 0.29, green: 0.56, blue: 1.0),
                        Color(red: 0.45, green: 0.38, blue: 0.98),
                        Color(red: 0.36, green: 0.72, blue: 0.92)
                    ]),
                    style: StrokeStyle(lineWidth: isStorageHovered ? activeThickness : ringThickness, lineCap: .round)
                )
                .scaleEffect(isStorageHovered ? 1.03 : 1)
                .opacity(isScanning ? 0.35 : 1)
                .animation(Theme.spring, value: isStorageHovered)
        }
    }

    // MARK: - 分类扇区环
    private struct SegmentArc: Identifiable {
        let segment: Segment
        let start: Double
        let end: Double
        var id: String { segment.id }
    }

    private var segmentArcs: [SegmentArc] {
        var cursor = 0.0
        return segments.map { segment in
            let start = cursor
            let end = cursor + max(0, segment.fraction) * segmentExpand
            cursor = end
            return SegmentArc(segment: segment, start: start, end: end)
        }
    }

    private var segmentRing: some View {
        let gap = segments.count > 1 ? 0.004 : 0.0

        return ZStack {
            ForEach(segmentArcs) { arc in
                let isActive = hoveredSegmentID == arc.segment.id
                let s = arc.start + gap / 2
                let e = max(s, arc.end - gap / 2)
                let mid = (s + e) / 2
                // 指向时向外偏移
                let radians = mid * 2 * .pi - .pi / 2
                let offsetX = isActive ? cos(radians) * activeLift : 0
                let offsetY = isActive ? sin(radians) * activeLift : 0

                RingSectorShape(startFraction: s, endFraction: e)
                    .stroke(
                        isActive
                            ? AnyShapeStyle(arc.segment.color)
                            : AnyShapeStyle(arc.segment.color.opacity(0.9)),
                        style: StrokeStyle(lineWidth: isActive ? activeThickness : ringThickness, lineCap: .butt)
                    )
                    .offset(x: offsetX, y: offsetY)
                    .scaleEffect(isActive ? 1.04 : 1)
                    .shadow(
                        color: isActive ? arc.segment.color.opacity(0.35) : .clear,
                        radius: 10,
                        y: 2
                    )
                    .animation(Theme.spring, value: hoveredSegmentID)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 环心内容
    @ViewBuilder
    private var centerContent: some View {
        if let segment = hoveredSegment {
            hoverInfo(
                color: segment.color,
                iconAsset: segment.iconAsset,
                usesAssetIcon: segment.usesAssetIcon,
                title: segment.name,
                value: segment.detail,
                caption: "\(segment.percentText) · 点按进入"
            )
            .id(segment.id)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else if isStorageHovered && !showSegments {
            hoverInfo(
                color: Color(red: 0.29, green: 0.56, blue: 1.0),
                iconAsset: "internaldrive.fill",
                usesAssetIcon: false,
                title: "磁盘占用",
                value: storageUsedText.isEmpty ? "\(Int(storageUsed * 100))%" : storageUsedText,
                caption: storageTotalText.isEmpty ? "外环长度 = 已用比例" : "总容量 \(storageTotalText)"
            )
            .id("storage")
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else {
            centerButton
        }
    }

    private func hoverInfo(
        color: Color,
        iconAsset: String,
        usesAssetIcon: Bool,
        title: String,
        value: String,
        caption: String
    ) -> some View {
        VStack(spacing: 10) {
            // 放大的类别图标
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                if usesAssetIcon {
                    Image(iconAsset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(color)
                        .frame(width: 38, height: 38)
                } else {
                    Image(systemName: iconAsset)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(color)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(color.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: color.opacity(0.25), radius: 12, y: 4)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.warmGradient)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .padding(12)
        .frame(width: 230, height: 230)
        .contentShape(Circle())
        .onTapGesture {
            if let segment = hoveredSegment {
                onSegmentTap?(segment)
            }
        }
    }

    // MARK: - 环心：操作钮
    private var centerButton: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonGradient)
                    .frame(width: buttonDiameter, height: buttonDiameter)

                // 顶部高光，增强球体质感
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.32), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(width: buttonDiameter, height: buttonDiameter)

                Circle()
                    .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                    .frame(width: buttonDiameter - 10, height: buttonDiameter - 10)

                VStack(spacing: 4) {
                    icon
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    if isScanning {
                        Text("\(Int(scanProgress * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                    } else {
                        Text(primaryActionTitle)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
            }
            .scaleEffect(isPressed ? 0.94 : (isCenterHovered && isEnabled ? 1.04 : 1))
            .elevatedShadow()
            .animation(Theme.springSnappy, value: isCenterHovered)
            .animation(Theme.springSnappy, value: isPressed)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .onHover { hovering in
            withAnimation(Theme.spring) { isCenterHovered = hovering && isEnabled }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var buttonDiameter: CGFloat { isScanning ? 140 : 148 }

    private var buttonGradient: LinearGradient {
        if isScanning || !isEnabled {
            return Theme.accentGradient
        }
        switch phase {
        case .finished: return Theme.successGradient
        default: return Theme.accentGradient
        }
    }

    private var titleGradient: LinearGradient {
        if hoveredSegment != nil {
            return Theme.warmGradient
        }
        switch phase {
        case .finished: return Theme.warmGradient
        default: return Theme.accentGradient
        }
    }

    private var titleText: String {
        if let segment = hoveredSegment {
            return "\(segment.detail) · \(segment.percentText)"
        }
        if isStorageHovered && !showSegments {
            return storageUsedText.isEmpty ? "已使用 \(Int(storageUsed * 100))%" : "已使用 \(storageUsedText)"
        }
        switch phase {
        case .idle: return "扫描垃圾缓存"
        case .scanning: return scanningTitle ?? "正在扫描垃圾…"
        case .finished:
            return finishedTitle ?? (cleanableText.isEmpty ? "重新扫描" : "预计可释放 \(cleanableText)")
        }
    }

    private var subtitleText: String {
        if let segment = hoveredSegment {
            return "指向「\(segment.name)」· 点按进入"
        }
        if isStorageHovered && !showSegments {
            return "外环 = 磁盘已用 · 悬停查看容量"
        }
        switch phase {
        case .idle:
            return "扫描系统缓存、应用缓存、浏览器缓存、日志、应用残留与废纸篓"
        case .scanning:
            return scanningSubtitle ?? "清理扫描进行中 · 完成后可再次扫描"
        case .finished:
            return finishedSubtitle ?? (showSegments
                ? "外环为可清理构成 · 悬停查看 · 点按进入"
                : "再扫一次，更新可清理项目")
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .idle:
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .scaleEffect(isCenterHovered && isEnabled ? 1.06 : 1)
        case .scanning:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 32, weight: .semibold))
                .modifier(SpinPulseModifier())
        case .finished:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 30, weight: .semibold))
        }
    }
}

private struct SpinPulseModifier: ViewModifier {
    @State private var spinning = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(
                Animation.linear(duration: 1.6).repeatForever(autoreverses: false),
                value: spinning
            )
            .onAppear { spinning = true }
    }
}

// MARK: - 渐变主按钮（详情空态 / 分析页）
struct GradientButtonStyleCompact: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accentGradient)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .elevatedShadow()
            .animation(Theme.springSnappy, value: configuration.isPressed)
    }
}

// MARK: - 统计指标（仪表盘数字卡）
struct MetricTile: View {
    let title: String
    let value: String
    var subtitle: String?
    var gradient: LinearGradient = Theme.accentGradient
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .kerning(0.4)
            Text(value)
                .font(.system(size: compact ? 20 : 28, weight: .bold, design: .rounded))
                .foregroundStyle(gradient)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.accentGradientSoft.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
    }
}


/// 仅在主窗口绘制一次。导航、页头和页面使用透明底，避免渐变在分区边缘重新起算。
struct WorkspaceBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geometry in
            let span = max(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(
                    colors: isDark ? [
                        Color(red: 0.13, green: 0.14, blue: 0.30),
                        Color(red: 0.20, green: 0.13, blue: 0.29),
                        Color(red: 0.08, green: 0.20, blue: 0.25)
                    ] : [
                        Color(red: 0.81, green: 0.84, blue: 0.98),
                        Color(red: 0.91, green: 0.83, blue: 0.94),
                        Color(red: 0.79, green: 0.92, blue: 0.94)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(red: 0.40, green: 0.46, blue: 1.0).opacity(isDark ? 0.25 : 0.20), .clear],
                    center: UnitPoint(x: 0.05, y: 0.18), startRadius: 0, endRadius: span * 0.72
                )
                RadialGradient(
                    colors: [Color(red: 0.98, green: 0.48, blue: 0.69).opacity(isDark ? 0.16 : 0.23), .clear],
                    center: UnitPoint(x: 0.90, y: 0.08), startRadius: 0, endRadius: span * 0.62
                )
                RadialGradient(
                    colors: [Color(red: 0.14, green: 0.77, blue: 0.86).opacity(isDark ? 0.18 : 0.24), .clear],
                    center: UnitPoint(x: 0.74, y: 0.95), startRadius: 0, endRadius: span * 0.62
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


/// 统一渐变玻璃表面：材质柔化背景，冷暖洗色与边缘高光建立层次。
struct GradientGlassSurface: View {
    var cornerRadius: CGFloat = 18
    var highlighted = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency { shape.fill(Theme.surfaceRaised) }
            else {
                shape.fill(.ultraThinMaterial)
                shape.fill(LinearGradient(
                    colors: [Color.indigo.opacity(scheme == .dark ? 0.18 : 0.10), Color.pink.opacity(0.06), Color.cyan.opacity(scheme == .dark ? 0.13 : 0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            shape.fill(LinearGradient(
                colors: [.white.opacity(highlighted ? (scheme == .dark ? 0.07 : 0.16) : 0), Color.cyan.opacity(highlighted ? 0.07 : 0)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(LinearGradient(
                colors: [.white.opacity(highlighted ? (scheme == .dark ? 0.42 : 0.88) : (scheme == .dark ? 0.22 : 0.60)),
                         .white.opacity(highlighted ? 0.22 : 0.08), Color.indigo.opacity(highlighted ? 0.30 : 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct GradientGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let enabled: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                if enabled {
                    GradientGlassSurface(cornerRadius: cornerRadius, highlighted: hovered)
                        .shadow(color: Color.indigo.opacity(hovered ? 0.13 : 0.025), radius: hovered ? 16 : 5, y: hovered ? 6 : 2)
                        .animation(reduceMotion ? nil : .easeOut(duration: hovered ? 0.18 : 0.24), value: hovered)
                }
            }
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}

extension View {
    func gradientGlass(cornerRadius: CGFloat = 18, enabled: Bool = true) -> some View {
        modifier(GradientGlassCardModifier(cornerRadius: cornerRadius, enabled: enabled))
    }
}
