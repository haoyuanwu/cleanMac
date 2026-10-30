import SwiftUI

/// 所有完整扫描页共用矢量动画，路径反馈与插画下方说明合并展示。
struct ScanningPlaceholderView: View {
    let title: String
    let subtitle: String
    var currentPath: String? = nil
    var animationHeight: CGFloat = 280

    var body: some View {
        VStack(spacing: 12) {
            GeneralScanAnimation()
                .frame(maxWidth: 440).frame(height: animationHeight)
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary)
                .multilineTextAlignment(.center)
            if let currentPath {
                Text(currentPath.isEmpty ? "正在准备扫描路径…" : currentPath)
                    .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 500, minHeight: 18)
                    .help(currentPath)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
