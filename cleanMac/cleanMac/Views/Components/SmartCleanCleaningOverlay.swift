import SwiftUI
import Lottie

/// 智能清理执行期间的全屏状态占位，阻止用户在清理过程中操作其他页面。
struct SmartCleanCleaningOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let animation = LottieAnimation.asset("ScanningFiles")

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Group {
                    if !reduceMotion, let animation = Self.animation {
                        LottieView(animation: animation)
                            .configuration(LottieConfiguration(renderingEngine: .mainThread))
                            .resizable()
                            .looping()
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 58, weight: .light))
                            .foregroundStyle(Theme.warmGradient)
                    }
                }
                .frame(width: 240, height: 220)
                .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text("正在智能清理")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("正在安全处理已确认的缓存、日志和应用残留")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.surfaceRaised.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .elevatedShadow()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在智能清理，请稍候")
    }
}
