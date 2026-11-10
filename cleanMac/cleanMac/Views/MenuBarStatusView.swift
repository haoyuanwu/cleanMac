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
    static let popupSize = NSSize(width: 350, height: 570)
    var onOpenMainWindow: (() -> Void)? = nil
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var popupWindowHolder = MenuBarPopupWindowHolder()
    @ObservedObject private var trashMonitor = TrashMonitor.shared
    @ObservedObject private var mainViewModel = MainViewModel.shared
    @ObservedObject private var networkMonitor = NetworkSpeedMonitor.shared
    @ObservedObject private var deviceMonitor = DeviceStatusMonitor.shared
    private var status: DeviceQuickStatus? { deviceMonitor.snapshot?.quickStatus }
    private var isRefreshing: Bool { deviceMonitor.isRefreshing || trashMonitor.isScanning || trashMonitor.isCleaning }

    var body: some View {
        VStack(spacing: 0) {
            ChargeReminderBanner()
            VStack(spacing: 12) {
                header
                quickActions
            }.padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let status {
                        detailCard(.storage, title: "存储空间") { storageCard(status) }
                    }
                    trashCard
                    MenuBarResourceCards(onOpenMemory: { openDetail(.memory) }, onOpenCPU: { openDetail(.cpu) })
                    detailCard(.connections, title: "网络与连接") { networkSummary }
                    HStack(alignment: .top, spacing: 10) {
                        detailCard(.battery, title: "电池与电源") { batteryCard(status) }
                        detailCard(.connections, title: "网络与连接") {
                            statusCard(title: "Wi‑Fi", icon: "wifi", tint: .cyan,
                                       value: status?.wifiState ?? "读取中…",
                                       subtitle: status?.wifiName ?? (status == nil ? "正在读取设备状态" : "网络名称未提供"))
                        }
                    }
                    detailCard(.connections, title: "网络与连接") { bluetoothCard(status) }

                }
                .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 12)
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .frame(width: Self.popupSize.width, height: Self.popupSize.height)
        .background(Theme.reviewCanvas(.blue))
        .background(MenuBarPopupWindowReader(holder: popupWindowHolder))
        .task {
            // 打开即读取新数据；可见时轮询也能覆盖 Finder 中的移入、恢复和清空。
            while !Task.isCancelled {
                await trashMonitor.refresh(force: true)
                do { try await Task.sleep(for: .seconds(5)) }
                catch { break }
            }
        }

    }

    /// 只包裹只读卡片，保持原组件尺寸；避免嵌套清空等独立操作按钮。
    private func detailCard<Content: View>(_ page: AppActionCoordinator.DeviceDetailPage, title: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        Button {
            openDetail(page)
        } label: {
            content().contentShape(Rectangle())
        }
        .buttonStyle(WorkspacePressStyle())
        .help("打开" + title + "详情")
        .accessibilityLabel("打开" + title + "详情")
    }

    private var header: some View {
        HStack(spacing: 11) {
            Button(action: openMainWindow) {
                HStack(spacing: 11) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .moduleIconPlate(tint: .indigo, size: 38, radius: 11)

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

            Group {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在刷新")
            } else {
                Button {
                    Task {
                        async let deviceRefresh: Void = refresh()
                        async let trashRefresh: Void = trashMonitor.refresh(force: true)
                        _ = await (deviceRefresh, trashRefresh)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(ReadableControlButtonStyle(iconOnly: true))
                .help("刷新设备状态")
                .accessibilityLabel("刷新设备状态")
            }
            }.frame(width: 36, height: 36)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 13, weight: .semibold))
            }.buttonStyle(ReadableControlButtonStyle(iconOnly: true, tint: .orange))
                .help("退出 cleanMac").accessibilityLabel("退出 cleanMac")
        }
    }

    private var trashCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                AppActionCoordinator.shared.requestTrashReview()
                openMainWindow()
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        PopupCardHeading(title: "废纸篓", symbol: "trash.fill", tint: .red)
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

                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("打开废纸篓详情")
                .accessibilityLabel("打开废纸篓详情")

            Spacer(minLength: 0)

            Button(role: .destructive) {
                Task { await trashMonitor.emptyTrash() }
            } label: {
                Label(trashMonitor.isCleaning ? "清空中…" : "清空废纸篓", systemImage: "trash.slash")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(ReadableControlButtonStyle())
            .controlSize(.small)
            .tint(.red)
            .help("立即永久删除废纸篓中可访问的项目")
            .disabled(trashMonitor.isScanning || trashMonitor.isCleaning || trashMonitor.status == nil || trashMonitor.status?.itemCount == 0 || trashMonitor.status?.error != nil)
        }
        .popupCard()
    }

    private func storageCard(_ status: DeviceQuickStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                PopupCardHeading(title: "可用空间", symbol: "internaldrive", tint: .blue)
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
        .popupCard()
    }

    private func statusCard(title: String, icon: String, tint: Color, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PopupCardHeading(title: title, symbol: icon, tint: tint)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.75).frame(height: 25, alignment: .leading)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2).frame(height: 28, alignment: .topLeading)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popupCard()
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
            subtitle: subtitle
        )
    }

    private func bluetoothCard(_ status: DeviceQuickStatus?) -> some View {
        MenuBarBluetoothCard(devices: status?.connectedBluetoothDevices, state: status?.bluetoothState)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button {
                AppActionCoordinator.shared.requestOverviewScan()
                openMainWindow()
            } label: {
                Label("扫描清理", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
            }.buttonStyle(ReadableControlButtonStyle(prominent: true))
                .disabled(mainViewModel.isScanning || mainViewModel.isCleaning)
            Button {
                AppActionCoordinator.shared.requestDeepScan()
                openMainWindow()
            } label: {
                Label("深度清理", systemImage: "sparkle.magnifyingglass").frame(maxWidth: .infinity)
            }.buttonStyle(ReadableControlButtonStyle())
                .disabled(mainViewModel.isScanning || mainViewModel.isCleaning)
        }
    }

    private var networkSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            PopupCardHeading(title: "实时网速", symbol: "network", tint: .blue)
            HStack(spacing: 14) {
                Label(networkMonitor.isActive ? networkMonitor.throughput.downloadText : "采样中…", systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Spacer(minLength: 0)
                Label(networkMonitor.isActive ? networkMonitor.throughput.uploadText : "采样中…", systemImage: "arrow.up")
                    .foregroundStyle(.purple)
            }.font(.system(size: 14, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }.popupCard()
    }

    private var footer: some View {
        HStack {
            Text(status.map { "更新于 " + $0.capturedAt.formatted(date: .omitted, time: .shortened) } ?? "正在更新设备状态…")
                .font(.system(size: 10)).foregroundStyle(Theme.navigationSecondary)
            Spacer()
        }
    }

    private func openDetail(_ page: AppActionCoordinator.DeviceDetailPage) {
        AppActionCoordinator.shared.requestDeviceDetail(page)
        openMainWindow()
    }

    private func refresh() async {
        await deviceMonitor.refresh()
    }

    private func openMainWindow() {
        if let onOpenMainWindow { onOpenMainWindow(); return }
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

#Preview("状态栏速览") {
    MenuBarStatusView()
        .task { await DeviceStatusMonitor.shared.refresh() }
}
