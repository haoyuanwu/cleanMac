import SwiftUI

/// 仅卡片内的摘要响应采样，避免重建整个卡片网格。
struct DeviceFeatureSummary: View {
    let destination: WorkspaceDestination
    @ObservedObject private var device = DeviceStatusMonitor.shared
    @ObservedObject private var memory = DeviceMemoryMonitor.shared
    @ObservedObject private var apps = HighResourceMonitor.shared
    @ObservedObject private var telemetry = DeviceTelemetryMonitor.shared
    @ObservedObject private var network = NetworkSpeedMonitor.shared
    private var summary: String {
        switch destination {
        case .page(.applicationUsage): return apps.allApplications.isEmpty ? "正在读取运行应用" : "\(apps.allApplications.count) 个运行应用"
        case .page(.deviceCPU): return telemetry.current?.cpu.map { String(format: "CPU %.0f%% · 热状态%@", $0.used, telemetry.thermalDescription) } ?? "正在积累 CPU 采样"
        case .page(.deviceMemory):
            switch memory.history.last?.pressure { case 1: return "内存压力正常"; case 2: return "内存压力偏高"; case 4: return "内存压力严重"; default: return "压力数据读取中" }
        case .page(.deviceConnections): return "↓ \(network.throughput.downloadText) · ↑ \(network.throughput.uploadText)"
        case .page(.deviceBattery): return device.snapshot?.batteryLevel.map { "电量 \(Int(($0 * 100).rounded()))%" } ?? "电源状态读取中"
        case .page(.deviceStorage): return device.snapshot.map { "可用 " + $0.storageInfo.freeFormatted } ?? "容量读取中"
        case .page(.deviceInfo): return device.snapshot?.device.first { $0.label == "芯片" }?.value ?? "设备档案读取中"
        default: return "查看详情"
        }
    }
    var body: some View { Text(summary).lineLimit(1).truncationMode(.middle).monospacedDigit().help(summary); Spacer(minLength: 0) }
}
