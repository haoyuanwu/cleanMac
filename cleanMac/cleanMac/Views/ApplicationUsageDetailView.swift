import SwiftUI

struct ApplicationUsageDetailView: View {
    let app: ResourceAppDescriptor
    @ObservedObject private var monitor = HighResourceMonitor.shared
    @Environment(\.dismiss) private var dismiss
    private var usage: ApplicationResourceUsage? { monitor.allApplications.first { $0.id == app.id } }
    private var history: [ApplicationUsagePoint] { monitor.usageHistory[app.id] ?? [] }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.title3.bold())
                    Text(app.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TelemetryPanel("最近 5 分钟") {
                        HStack {
                            TelemetryMetric(title: "CPU", value: usage?.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "未读取")
                            TelemetryMetric(title: "内存", value: usage?.sampleAvailable == true ? telemetryBytes(usage?.memory) : "未读取", tint: .pink)
                        }
                        TelemetryChart(values: history.compactMap { point in point.cpu.map { TelemetryLine(date: point.date, value: $0, series: "CPU %") } })
                        TelemetryChart(values: history.map { .init(date: $0.date, value: Double($0.memory) / 1_000_000_000, series: "内存 GB") }, unit: "GB")
                    }
                    TelemetryPanel("状态与提醒") {
                        Text(monitor.applications.first { $0.id == app.id }?.alertReason ?? (usage == nil ? "该运行实例已退出，或暂时不在运行列表中。" : "尚未达到持续确认的异常提醒条件。"))
                            .font(.system(size: 13))
                        Toggle("忽略此应用的异常提醒", isOn: Binding(get: { monitor.ignoredBundleIDs.contains(app.bundleID) }, set: { monitor.setIgnored(app, ignored: $0) }))
                        Text("仅影响异常提醒，不影响数据查看和清理白名单。默认 CPU 持续 60 秒、突增 30 秒；内存需超过阈值并持续明显增长。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("正常退出应用") { monitor.end(app, force: false) }.disabled(!monitor.canEnd(app))
                            Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "") }
                        }
                        if let message = monitor.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    }
                    TelemetryPanel("关联进程 · \(usage?.processCount ?? 0)") {
                        if let usage, !usage.processes.isEmpty {
                            ForEach(usage.processes) { process in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(URL(fileURLWithPath: process.path).lastPathComponent).font(.system(size: 12, weight: .medium))
                                        Text("PID \(process.pid)").font(.caption).foregroundStyle(.secondary)
                                    }.help(process.path)
                                    Spacer()
                                    Text(process.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "待采样").frame(width: 70, alignment: .trailing)
                                    Text(telemetryBytes(process.memory)).frame(width: 90, alignment: .trailing)
                                }.font(.caption).monospacedDigit()
                                Divider().opacity(0.3)
                            }
                        } else { Text("未取得关联进程数据").font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 22)
            }
        }.frame(width: 720, height: 650).background(WorkspaceBackdrop())
    }
}
