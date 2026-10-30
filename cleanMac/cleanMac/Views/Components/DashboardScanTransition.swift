import SwiftUI

enum DashboardHeroPhase: Equatable {
    case ready, scanning, finished, cleaning
}

/// 保持同一个布局容器，以实际扫描状态驱动插画的展开与收起。
struct DashboardHeroArtwork: View {
    let phase: DashboardHeroPhase
    let availableSize: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var scanning: Bool { phase == .scanning }
    private var finished: Bool { phase == .finished }
    private var height: CGFloat {
        scanning ? min(300, max(230, availableSize.height * 0.49)) : finished ? 100 : 156
    }
    private var artTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.85)).combined(with: .offset(y: 10)),
            removal: .opacity.combined(with: .scale(scale: 0.92)).animation(.easeOut(duration: 0.16)))
    }
    var body: some View {
        ZStack {
            // 同一层光晕从首页延续到扫描场景，不同时堆叠两个大背景。
            Circle().fill(Theme.accentGradientSoft)
                .frame(width: scanning ? 245 : finished ? 100 : 156, height: scanning ? 245 : finished ? 100 : 156)
                .opacity(scanning ? 0.25 : 1)
            if scanning {
                OneClickScanAnimation()
                    .frame(width: min(500, max(240, availableSize.width - 56)), height: height)
                    .transition(artTransition)
            } else {
                ZStack {
                    Circle().fill(Theme.accentGradient)
                        .frame(width: finished ? 76 : 112, height: finished ? 76 : 112)
                        .shadow(color: Color.indigo.opacity(0.22), radius: 24, y: 12)
                    Image(systemName: phase == .cleaning ? "sparkle.magnifyingglass" : finished ? "checkmark.shield" : "sparkles")
                        .font(.system(size: finished ? 34 : 44, weight: .medium)).foregroundStyle(.white)
                }
                .transition(artTransition)
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.9), value: phase)
        .accessibilityHidden(true)
    }
}

/// 按钮与进度条使用同一个渐变表面，收拢过渡不依赖延时或动画完成回调。
struct DashboardScanControls: View {
    let scanning: Bool
    let progress: Double
    let title: String
    let disabled: Bool
    let onStart: () -> Void
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fraction: Double { min(1, max(0, progress)) }
    private var fade: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 5)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: scanning ? 3 : 14, style: .continuous)
                    .fill(Theme.accentGradient)
                    .opacity(scanning ? 0.15 : disabled ? 0.45 : 1)
                    .shadow(color: .indigo.opacity(scanning ? 0 : 0.18), radius: 14, y: 6)
                    .accessibilityHidden(true)
                if scanning {
                    ProgressView(value: fraction)
                        .progressViewStyle(DashboardProgressStyle())
                        .accessibilityLabel("扫描进度")
                        .accessibilityValue("\(Int(fraction * 100))%")
                        .transition(.opacity)
                } else {
                    Button(action: onStart) {
                        Label(title, systemImage: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 300, height: 56)
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(WorkspacePressStyle())
                    .disabled(disabled)
                    .transition(fade)
                }
            }
            .frame(width: 300, height: scanning ? 6 : 56)
            if scanning {
                HStack {
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Button("取消扫描", action: onCancel).buttonStyle(.bordered)
                }
                .frame(width: 300)
                .transition(fade)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.9), value: scanning)
    }
}

private struct DashboardProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Capsule().fill(Theme.accentGradient)
                .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
        }
    }
}
