import SwiftUI

struct PopupCardHeading: View {
    let title: String
    let symbol: String
    var tint: Color = .indigo
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint).frame(width: 16)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.actionInk)
        }.frame(height: 16, alignment: .leading)
    }
}

/// 同排卡片共用标题、数值、说明、操作四条基线。
struct MenuBarResourceCards: View {
    let onOpenMemory: () -> Void
    let onOpenCPU: () -> Void
    @ObservedObject private var memory = DeviceMemoryMonitor.shared
    @ObservedObject private var cpu = DeviceTelemetryMonitor.shared
    @State private var client = UUID()
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "采样中…" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            tile(title: "内存", symbol: "memorychip", tint: .purple,
                 value: memory.history.last.map { FileSizeFormatter.string(fromByteCount: Int64($0.usedBytes)) } ?? "读取中…",
                 detail: memory.history.last.map { "可用 " + FileSizeFormatter.string(fromByteCount: Int64($0.totalBytes - $0.usedBytes)) } ?? "正在采集…",
                 action: onOpenMemory) {
                MemoryMaintenanceButton(compact: true)
            }
            tile(title: "CPU", symbol: "cpu", tint: .indigo, value: percent(cpu.current?.cpu?.used),
                 detail: "热状态 · " + cpu.thermalDescription, action: onOpenCPU) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("用户 " + percent(cpu.current?.cpu?.user))
                    Text("系统 " + percent(cpu.current?.cpu?.system))
                }.font(.system(size: 10)).monospacedDigit().foregroundStyle(Theme.navigationSecondary)
            }
        }.onAppear { cpu.retain(client) }.onDisappear { cpu.release(client) }
    }

    private func tile<Footer: View>(title: String, symbol: String, tint: Color, value: String,
                                    detail: String, action: @escaping () -> Void,
                                    @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 8) {
                    PopupCardHeading(title: title, symbol: symbol, tint: tint)
                    Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75).frame(height: 27, alignment: .leading)
                    Text(detail).font(.system(size: 10)).foregroundStyle(Theme.navigationSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8).frame(height: 14, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("打开" + title + "详情")
            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer().frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
        }.popupCard()
    }
}
