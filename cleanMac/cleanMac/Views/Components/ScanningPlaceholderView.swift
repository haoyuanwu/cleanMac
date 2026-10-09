import SwiftUI
import Lottie

/// 扫描页通用占位：动画资源随应用打包，不依赖网络。
struct ScanningPlaceholderView: View {
    let title: String
    let subtitle: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let animation = LottieAnimation.asset("ScanningFiles")

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if !reduceMotion, let animation = Self.animation {
                    LottieView(animation: animation)
                        .configuration(LottieConfiguration(renderingEngine: .mainThread))
                        .resizable()
                        .looping()
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 68, weight: .light))
                        .foregroundStyle(Theme.accentGradient)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 240, height: 220)
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}
