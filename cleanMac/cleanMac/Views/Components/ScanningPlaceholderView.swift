import SwiftUI

/// 所有完整扫描页共用矢量动画，路径反馈与插画下方说明合并展示。
struct ScanningPlaceholderView: View {
    let title: String
    let subtitle: String
    var currentPath: String? = nil
    var animationHeight: CGFloat = 280
    var diagnostics: ScanDiagnostics? = nil
    var collector: ScanDiagnosticsCollector? = nil

    var body: some View {
        VStack(spacing: 12) {
            GeneralScanAnimation()
                .frame(maxWidth: 440).frame(height: animationHeight)
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary)
                .multilineTextAlignment(.center)
            ScanProgressFeedback(currentPath: currentPath, diagnostics: diagnostics, collector: collector)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 扫描页面共用的路径与时间反馈；计时由任务起点决定，页面重建不重置。
struct ScanProgressFeedback: View {
    var currentPath: String? = nil
    var diagnostics: ScanDiagnostics? = nil
    var collector: ScanDiagnosticsCollector? = nil
    var startedAt: Date? = nil
    @State private var mountedAt = Date()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let snapshot = collector?.snapshot() ?? diagnostics
            let path = snapshot?.currentPath ?? currentPath ?? ""
            VStack(spacing: 12) {
                Text(path.isEmpty ? "正在准备扫描路径…" : path)
                    .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 500, minHeight: 18)
                    .help(path)
                HStack(spacing: 20) {
                    Label("已用时 \(Int(max(0, timeline.date.timeIntervalSince(startedAt ?? snapshot?.startedAt ?? mountedAt)))) 秒", systemImage: "clock")
                    Label(snapshot.map { "已检查 \($0.visitedCount) 次" } ?? "等待统计", systemImage: "doc.text.magnifyingglass")
                }.font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.navigationSecondary)
            }
        }
    }
}
