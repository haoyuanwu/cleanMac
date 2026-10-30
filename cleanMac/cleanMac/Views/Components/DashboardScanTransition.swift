import SwiftUI

enum DashboardHeroPhase: Equatable {
    case ready, scanning, finished, cleaning
}

/// 主图本身承载唯一主操作；扫描时在原位置展开动画。
struct DashboardHeroArtwork: View {
    let phase: DashboardHeroPhase
    let availableSize: CGSize
    let title: String
    let subtitle: String
    let recommendation: String?
    let disabled: Bool
    let onActivate: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var scanning: Bool { phase == .scanning }
    private var finished: Bool { phase == .finished }
    private var height: CGFloat {
        scanning ? min(350, max(280, availableSize.height * 0.59))
            : min(330, max(280, availableSize.height * 0.57))
    }
    private var artworkWidth: CGFloat {
        scanning ? min(500, max(240, availableSize.width - 56)) : 300
    }
    var body: some View {
        // 维持同一个绘图视图，点击后原地放大并启动，避免用两张插画交叉切换。
        Button(action: onActivate) {
            VStack(spacing: 0) {
                OneClickScanAnimation(isAnimating: scanning)
                    .frame(width: artworkWidth, height: scanning ? height - 48 : finished ? 170 : 195)
                if let recommendation {
                    Text(recommendation).font(.system(size: 29, weight: .bold, design: .rounded))
                        .monospacedDigit().padding(.top, -4)
                    Text("推荐项目 · 逻辑大小").font(.system(size: 11)).padding(.top, 3)
                    Label("智能一键清理", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold)).padding(.top, 14)
                } else {
                    Text(title).font(.system(size: scanning ? 20 : 25, weight: .bold, design: .rounded))
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12)).padding(.top, 7)
                    }
                }
            }
            .foregroundStyle(.primary)
            .frame(width: artworkWidth, height: scanning ? height : finished && recommendation != nil ? 300 : 268)
            .contentShape(RoundedRectangle(cornerRadius: 52, style: .continuous))
        }
        .buttonStyle(DashboardHeroButtonStyle(scanning: scanning))
        .disabled(disabled)
        .accessibilityLabel(recommendation == nil ? title : "智能一键清理")
        .accessibilityValue(recommendation.map { "推荐项目逻辑大小 \($0)" } ?? "")
        .accessibilityHint(scanning ? "扫描进行中" : finished ? "进入清理清单，检查并确认项目" : "扫描可清理项目，完成后由你确认清理")
        .help(scanning ? "正在扫描" : finished ? "检查清单后确认清理" : "点击开始扫描")
        .frame(maxWidth: .infinity).frame(height: height)
        .animation(reduceMotion ? nil : .spring(response: 0.58, dampingFraction: 0.88), value: phase)
    }
}

private struct DashboardHeroButtonStyle: ButtonStyle {
    let scanning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 52, style: .continuous)
                    .fill(.ultraThinMaterial).opacity(scanning ? 0 : 0.55)
            }
            .overlay(RoundedRectangle(cornerRadius: 52, style: .continuous)
                .strokeBorder(Color.indigo.opacity(scanning ? 0 : hovered && isEnabled ? 0.5 : 0.12), lineWidth: hovered && isEnabled ? 2 : 1))
            .shadow(color: .indigo.opacity(scanning ? 0 : hovered && isEnabled ? 0.24 : 0.08), radius: hovered ? 24 : 16, y: 8)
            .opacity(scanning ? 1 : isEnabled ? configuration.isPressed ? 0.82 : 1 : 0.65)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 扫描阶段只呈现真实进度及取消操作，避免首页重复主操作。
struct DashboardScanProgress: View {
    let progress: Double
    let onCancel: () -> Void
    private var fraction: Double { min(1, max(0, progress)) }
    var body: some View {
        VStack(spacing: 14) {
            ProgressView(value: fraction).progressViewStyle(DashboardProgressStyle())
                .frame(width: 300, height: 6)
                .background(Color.indigo.opacity(0.15), in: Capsule())
                .accessibilityLabel("扫描进度").accessibilityValue("\(Int(fraction * 100))%")
            HStack {
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer()
                Button("取消扫描", action: onCancel).buttonStyle(.bordered)
            }.frame(width: 300)
        }
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
