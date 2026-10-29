import SwiftUI

struct HighResourcePopoverView: View {
    @ObservedObject private var monitor = HighResourceMonitor.shared
    @State private var forceTarget: ResourceAppDescriptor?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("应用运行异常", systemImage: "flame").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { ResourceAlertPresenter.shared.close() } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).accessibilityLabel("关闭高占用提醒")
            }
            Text("检测占用突增、持续高占用或疑似无响应；CPU 100% 约为一个核心。")
                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            if let date = monitor.sampledAt { Text("更新于 " + date.formatted(date: .omitted, time: .standard)).font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary) }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if monitor.applications.isEmpty {
                        Text(monitor.enabled ? "异常已恢复，采样间隔约 5 秒。" : "高占用监控已关闭，可在设置中开启。")
                            .font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary).padding(.vertical, 24)
                    }
                    ForEach(monitor.applications) { usage in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: usage.application.path)).resizable().scaledToFit().frame(width: 36, height: 36).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(usage.application.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                    if let reason = usage.alertReason { Text(reason).font(.system(size: 12)).foregroundStyle(.orange) }
                                    Text("CPU \(usage.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "待采样") · 内存 \(FileSizeFormatter.string(fromByteCount: Int64(clamping: usage.memory)))")
                                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.navigationSecondary)
                                }
                                Spacer()
                            }
                            HStack {
                                Text("已读取 \(usage.processCount) 个关联进程").font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                                Spacer()
                                Button("正常退出") { monitor.end(usage.application, force: false) }.font(.system(size: 12))
                                Menu {
                                    Button("强制结束…", role: .destructive) { forceTarget = usage.application }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("\(usage.application.name)的更多操作")
                            }
                        }.padding(12).gradientGlass(cornerRadius: 13)
                    }
                }
            }.frame(maxHeight: 310)
            if let message = monitor.message { Text(message).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary) }
            HStack {
                if let until = monitor.snoozedUntil, until > Date() {
                    Button("恢复提醒") { monitor.resumeAlerts() }
                } else {
                    Button("暂停提醒 30 分钟") { monitor.snooze(); ResourceAlertPresenter.shared.close() }
                }
                Spacer()
                Button("刷新") { monitor.refresh() }.disabled(!monitor.enabled)
            }.font(.system(size: 12))
            Text("内存为可读取进程的占用估算。不会自动结束应用；系统及受保护应用不提供结束操作。")
                .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
        }.padding(18).frame(width: 420, height: 480).background(Theme.reviewCanvas(.orange))
        .alert("强制结束应用？", isPresented: Binding(get: { forceTarget != nil }, set: { if !$0 { forceTarget = nil } })) {
            Button("取消", role: .cancel) { forceTarget = nil }
            Button("强制结束", role: .destructive) { if let target = forceTarget { monitor.end(target, force: true) }; forceTarget = nil }
        } message: { Text("\(forceTarget?.name ?? "此应用")可能丢失未保存的内容。建议先使用“正常退出”。") }
    }
}
