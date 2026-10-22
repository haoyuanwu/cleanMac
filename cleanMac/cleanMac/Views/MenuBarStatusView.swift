import SwiftUI
import AppKit
import Darwin
import Combine

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
    @ObservedObject private var mainViewModel = MainViewModel.shared
    @State private var status: DeviceQuickStatus?
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            ChargeReminderBanner()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if let status {
                        storageCard(status)
                    }
                    NetworkSpeedCard(compact: true)

                    HStack(alignment: .top, spacing: 10) {
                        trashCard
                        batteryCard(status)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        bluetoothCard(status)
                        statusCard(
                            title: "Wi‑Fi",
                            icon: "wifi",
                            tint: .cyan,
                            value: status?.wifiState ?? "读取中…",
                            subtitle: status == nil ? "正在读取设备状态" : (status?.wifiName ?? "网络名称未提供"),
                            height: 116
                        )
                    }
                }
                .padding(16)
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(Theme.reviewCanvas(.blue))
        }
        .frame(width: 330, height: 570)
        .background(Theme.reviewCanvas(.blue))
        .background(MenuBarPopupWindowReader(holder: popupWindowHolder))
        .onReceive(BatteryAlertMonitor.shared.$latestStatus.compactMap { $0 }) { status in
            self.status = status
        }
        .task {
            await refresh()
            await trashMonitor.refresh()
        }

    }

    private var header: some View {
        HStack(spacing: 11) {
            Button(action: openMainWindow) {
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

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开 cleanMac 主页面")
            .accessibilityLabel("打开 cleanMac 主页面")

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
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("废纸篓", systemImage: "trash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red)
                Spacer()
                if trashMonitor.isScanning || trashMonitor.isCleaning {
                    ProgressView().controlSize(.small)
                }
            }

            if let status = trashMonitor.status {
                Text(FileSizeFormatter.string(fromByteCount: status.bytes))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

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
                    .frame(height: 5)
                }

                Text(status.error != nil ? "部分项目无法读取"
                    : trashMonitor.actionMessage
                        ?? (trashMonitor.isOverLimit ? "\(status.itemCount) 项 · 已超警戒"
                            : "\(status.itemCount) 项 · 警戒 \(trashMonitor.limit.title)"))
                    .font(.system(size: 10))
                    .foregroundColor(status.error != nil ? .orange : trashMonitor.isOverLimit ? .red : .secondary)
                    .lineLimit(2)
                    .help(status.error == nil
                        ? (trashMonitor.actionMessage ?? "警戒值：\(trashMonitor.limit.title)")
                        : "部分废纸篓无法读取，请检查磁盘访问权限。")
            } else {
                Text("计算中…")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("正在读取废纸篓")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                Task { await trashMonitor.emptyTrash() }
            } label: {
                Label(trashMonitor.isCleaning ? "清空中…" : "清空废纸篓", systemImage: "trash.slash")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .help("立即永久删除废纸篓中可访问的项目")
            .disabled(trashMonitor.isScanning || trashMonitor.isCleaning || trashMonitor.status == nil || trashMonitor.status?.itemCount == 0 || trashMonitor.status?.error != nil)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 156, alignment: .top)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke))
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

    private func statusCard(title: String, icon: String, tint: Color, value: String, subtitle: String, height: CGFloat) -> some View {
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
        .frame(height: height, alignment: .top)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke))
    }

    private func batteryCard(_ status: DeviceQuickStatus?) -> some View {
        let level = status?.batteryLevel.map { Int(($0 * 100).rounded()) }
        let low = level.map { $0 < 20 } ?? false
        let needsCharge = low && status?.batteryState == "使用电池"
        let charging = status?.batteryState == "正在充电"
        let subtitle: String
        if needsCharge, let level {
            subtitle = level <= 5 ? "电量告急，请立即充电" : level <= 10 ? "电量很低，请充电" : "电量低，请充电"
        } else if charging {
            subtitle = status?.chargingTimeEstimate.map {
                $0 == "正在估算…" ? "正在估算充满时间…" : "充满还需\($0)"
            } ?? "正在估算充满时间…"
        } else {
            subtitle = status?.batteryState ?? "正在读取设备状态"
        }
        return statusCard(
            title: "电池",
            icon: charging ? "battery.100percent.bolt" : low ? (level ?? 100) <= 5 ? "battery.0percent" : "battery.25percent" : "battery.100percent",
            tint: needsCharge ? (level ?? 100) <= 10 ? .red : .orange : .green,
            value: level.map { "\($0)%" } ?? "读取中…",
            subtitle: subtitle,
            height: 156
        )
    }

    private func bluetoothCard(_ status: DeviceQuickStatus?) -> some View {
        let chargingDevice = status?.connectedBluetoothDevices.first { $0.isCharging == true }
        let lowBatteryDevices = (status?.connectedBluetoothDevices ?? []).compactMap { device -> (name: String, level: Int)? in
            guard device.needsCharge, let level = device.batteryLevel else { return nil }
            return (device.name, level)
        }
        let chargePrompt: String? = lowBatteryDevices.first.map { first in
            lowBatteryDevices.count == 1
                ? "\(first.name) \(first.level)% · 请充电"
                : "\(lowBatteryDevices.count) 台设备低电量 · 请充电"
        }
        let warningTint: Color = (lowBatteryDevices.map(\.level).min() ?? 100) <= 10 ? .red : .orange

        return VStack(alignment: .leading, spacing: 8) {
            Label("蓝牙", systemImage: "wave.3.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.indigo)

            if let chargingDevice {
                ChargingBatteryBadge(device: chargingDevice, fontSize: 22)
                Text(chargingDevice.name)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(chargingDevice.name)
            } else {
                Text(status.map { $0.bluetoothState == "已开启" ? "已连接 \($0.connectedBluetoothDevices.count) 台" : $0.bluetoothState } ?? "读取中…")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)

                if let chargePrompt {
                    Label(chargePrompt, systemImage: "battery.25percent")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(warningTint)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(lowBatteryDevices.map { "\($0.name)：\($0.level)% · 请充电" }.joined(separator: "\n"))
                } else {
                    Text(status?.connectedBluetoothDevices.sorted {
                        ($0.isCharging == true ? 0 : 1) < ($1.isCharging == true ? 0 : 1)
                    }.first.map { "\($0.name) · \($0.batteryDescription)" }
                        ?? (status == nil ? "正在读取设备状态" : "当前没有已连接设备"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 116, alignment: .top)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(lowBatteryDevices.isEmpty ? Theme.cardStroke : warningTint.opacity(0.55)))
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
                    openMainWindow()
                } label: {
                    Label("扫描清理", systemImage: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help("打开 cleanMac 并扫描清理项目")

                Button {
                    AppActionCoordinator.shared.requestDeepScan()
                    openMainWindow()
                } label: {
                    Label("深度清理", systemImage: "sparkle.magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help("打开 cleanMac 并开始深度清理")
                .disabled(mainViewModel.isScanning || mainViewModel.isCleaning)
                .opacity(mainViewModel.isScanning || mainViewModel.isCleaning ? 0.5 : 1)
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
        await BatteryAlertMonitor.shared.poll()
        status = BatteryAlertMonitor.shared.latestStatus
        isRefreshing = false
    }

    private func openMainWindow() {
        dismiss()
        popupWindowHolder.window?.orderOut(nil)
        AppActionCoordinator.shared.showMainWindow { openWindow(id: "main") }
    }

}

struct MenuBarRootView: View {
    var body: some View {
        MenuBarStatusView()
    }
}
