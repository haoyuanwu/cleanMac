import SwiftUI

struct DeviceCPUTrendCard: View {
    var summaryOnly = false
    var embedded = false
    @ObservedObject private var monitor = DeviceTelemetryMonitor.shared
    @State private var client = UUID()
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "采样中…" }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(summaryOnly ? "CPU" : "实时 CPU", systemImage: "cpu").font(.system(size: 12, weight: .semibold)).foregroundStyle(.indigo)
                Spacer()
                if !summaryOnly { Text("每 2 秒刷新").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(percent(monitor.current?.cpu?.used)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                Spacer()
                if !summaryOnly { Text("全部核心 · 100% 上限").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            if summaryOnly {
                Text("热状态：" + monitor.thermalDescription).font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                TelemetryChart(values: monitor.history.compactMap { sample in
                    sample.cpu.map { TelemetryLine(date: sample.date, value: $0.used, series: "总使用率") }
                }, upper: 100, compact: true)
                HStack {
                    Text("用户 " + percent(monitor.current?.cpu?.user))
                    Spacer()
                    Text("系统 " + percent(monitor.current?.cpu?.system))
                }.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }.padding(embedded ? 0 : 14).gradientGlass(cornerRadius: 14, enabled: !embedded)
            .onAppear { monitor.retain(client) }.onDisappear { monitor.release(client) }
    }
}
