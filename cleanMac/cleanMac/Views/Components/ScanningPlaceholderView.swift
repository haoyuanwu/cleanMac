import SwiftUI
import Lottie

/// 扫描页通用占位：动画资源随应用打包，不依赖网络。
struct ScanningPlaceholderView: View {
    let title: String
    let subtitle: String
    var currentPath: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            ScanningFilesAnimation()
                .frame(width: 240, height: 220)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let currentPath {
                Text(currentPath.isEmpty ? "正在准备扫描路径…" : currentPath)
                    .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 460, minHeight: 18)
                    .help(currentPath)
            }
        }
        .accessibilityElement(children: .combine)
    }
}


/// 首页和分类页共用的扫描动效；只在扫描状态挂载，离开页面即停止播放。
struct ScanningFilesAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let animation = LottieAnimation.asset("ScanningFiles")

    var body: some View {
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
        .accessibilityHidden(true)
    }
}
