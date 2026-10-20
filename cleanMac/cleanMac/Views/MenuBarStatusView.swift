import SwiftUI
import AppKit

@MainActor
private final class MenuBarPopupWindowHolder {
    weak var window: NSWindow?
}

private struct MenuBarPopupWindowReader: NSViewRepresentable {
    let holder: MenuBarPopupWindowHolder

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(holder: holder)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {}

    final class TrackingView: NSView {
        weak var holder: MenuBarPopupWindowHolder?

        init(holder: MenuBarPopupWindowHolder) {
            self.holder = holder
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            holder?.window = window
        }
    }
}

/// 菜单栏中的设备与空间速览。
struct MenuBarStatusView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var popupWindowHolder = MenuBarPopupWindowHolder()
    @ObservedObject private var trashMonitor = TrashMonitor.shared
    @State private var status: DeviceQuickStatus?
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let status {
                    storageCard(status)
                }
                trashCard

                if let status {
                    HStack(spacing: 10) {
                        statusCard(
                            title: "电池",
                            icon: "battery.100percent",
                            tint: .green,
                            value: status.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "未检测到",
                            subtitle: status.batteryState
                        )
                        statusCard(
                            title: "Wi‑Fi",
                            icon: "wifi",
                            tint: .cyan,
                            value: status.wifiState,
                            subtitle: status.wifiName ?? "网络名称未提供"
                        )
                    }
                    bluetoothCard(status)
                } else {
                    ProgressView("正在读取设备状态…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }

                footer
            }
            .padding(16)
        }
        .frame(width: 330, height: 570)
        .background(Theme.reviewCanvas(.blue))
        .background(MenuBarPopupWindowReader(holder: popupWindowHolder))
        .task {
            await refresh()
            await trashMonitor.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text("cleanMac")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(status?.deviceName ?? "设备速览")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在刷新")
            } else {
                Button {
                    Task {
                        await refresh()
                        await trashMonitor.refresh(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                .help("刷新设备状态")
                .accessibilityLabel("刷新设备状态")
            }
        }
    }

    private var trashCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("废纸篓", systemImage: "trash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                Spacer()
                if trashMonitor.isScanning || trashMonitor.isCleaning {
                    ProgressView().controlSize(.small)
                }
            }

            if let status = trashMonitor.status {
                HStack(alignment: .firstTextBaseline) {
                    Text(FileSizeFormatter.string(fromByteCount: status.bytes))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text(status.error == nil ? (trashMonitor.percentage.map { "\($0)%" } ?? "不限") : "—")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(trashMonitor.isOverLimit ? .red : .secondary)
                }

                if let percent = trashMonitor.percentage {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.red.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(trashMonitor.isOverLimit ? Color.red : Color.orange)
                                    .frame(width: geometry.size.width * min(1, Double(percent) / 100))
                            }
                    }
                    .frame(height: 7)
                }

                HStack {
                    Text("\(status.itemCount) 项")
                    Spacer()
                    Text("警戒值：\(trashMonitor.limit.title)")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)

                if trashMonitor.isOverLimit {
                    Label("已超过警戒值，请清理废纸篓", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                }
                if status.error != nil {
                    Text("部分废纸篓无法读取，请检查磁盘访问权限。")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            } else {
                Text("正在计算废纸篓占用…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Button {
                Task { await trashMonitor.emptyTrash() }
            } label: {
                Label(trashMonitor.isCleaning ? "正在清空…" : "清空废纸篓", systemImage: "trash.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help("立即永久删除废纸篓中可访问的项目")
            .disabled(trashMonitor.isScanning || trashMonitor.isCleaning || trashMonitor.status == nil || trashMonitor.status?.itemCount == 0 || trashMonitor.status?.error != nil)

            if let message = trashMonitor.actionMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardStroke))
    }

    private func storageCard(_ status: DeviceQuickStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("可用空间")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(status.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: status.freeBytes) : "未提供")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(Color.blue.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.accentGradient)
                            .frame(width: geometry.size.width * status.usedFraction)
                    }
            }
            .frame(height: 8)

            HStack {
                Text("已用 \(status.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: status.totalBytes - status.freeBytes) : "—")")
                Spacer()
                Text("总容量 \(status.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: status.totalBytes) : "—")")
            }
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardStroke))
    }

    private func statusCard(title: String, icon: String, tint: Color, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke))
    }

    private func bluetoothCard(_ status: DeviceQuickStatus) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("蓝牙", systemImage: "wave.3.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.indigo)
                Spacer()
                Text(status.bluetoothState == "已开启" ? "已连接 \(status.connectedBluetoothDevices.count) 台" : status.bluetoothState)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if status.connectedBluetoothDevices.isEmpty {
                Text("当前没有已连接设备")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(status.connectedBluetoothDevices.prefix(2))) { device in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(device.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(device.batteryLevel.map { "\($0)%" } ?? "电量未提供")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                if status.connectedBluetoothDevices.count > 2 {
                    Text("另有 \(status.connectedBluetoothDevices.count - 2) 台设备，可在设备信息中查看")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke))
    }

    private var footer: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出 App", systemImage: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.cardStroke))
                }
                .buttonStyle(.plain)
                .help("退出 cleanMac")

                Button {
                    AppActionCoordinator.shared.requestOverviewScan()
                    dismiss()
                    popupWindowHolder.window?.orderOut(nil)
                    AppActionCoordinator.shared.showMainWindow { openWindow(id: "main") }
                } label: {
                    Label("扫描清理", systemImage: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help("打开 cleanMac 并扫描清理项目")
            }

            if let status {
                Text("更新于 \(status.capturedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        status = await Task.detached(priority: .utility) { DeviceInformationService.quickStatus() }.value
        isRefreshing = false
    }

}

struct MenuBarRootView: View {
    var body: some View {
        MenuBarStatusView()
    }
}
