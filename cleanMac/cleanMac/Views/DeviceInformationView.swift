import SwiftUI
import AppKit
import CoreLocation

struct DeviceInformationView: View {
    @ObservedObject var viewModel: DeviceInformationViewModel
    @State private var copiedFieldID: String?
    @State private var showSystemDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let snapshot = viewModel.snapshot {
                    overviewCard(snapshot)
                }
                ApplicationResourceCard()
                if let snapshot = viewModel.snapshot {
                    categoryColumns(snapshot)

                    Text("最近更新：\(snapshot.capturedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ProgressView("正在读取设备信息…")
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")

        .onAppear {
            viewModel.updateLocationStatus()
            viewModel.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.updateLocationStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image("SidebarInfo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .frame(width: 23, height: 23)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .elevatedShadow()

            VStack(alignment: .leading, spacing: 4) {
                Text("设备信息")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("硬件、软件、电池与连接状态")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在刷新设备信息")
            }
            DetailTextButton(title: "刷新", systemImage: "arrow.clockwise") {
                viewModel.refresh()
            }
            .disabled(viewModel.isLoading)
        }
    }

    private func overviewCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value(for: "设备名称", in: snapshot.device))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(value(for: "机型标识", in: snapshot.device))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Label("实时监测", systemImage: "waveform.path")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 14) {
                identityMetric("芯片", value: value(for: "芯片", in: snapshot.device))
                identityMetric("物理内存", value: value(for: "内存", in: snapshot.device))
                identityMetric("可用存储", value: value(for: "可用空间", in: snapshot.storage))
                identityMetric("电源状态", value: value(for: "状态", in: snapshot.battery))
            }
        }
        .padding(.vertical, 8)
    }

    private func identityMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(Theme.accentGradient).frame(width: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryColumns(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            sectionTitle("实时性能", subtitle: "最近一分钟 · 随设备状态更新")
            dashboardBand {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        networkSpeedCard(snapshot)
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1, height: PerformanceMonitorLayout.height)
                        DeviceMemoryTrendCard(embedded: true).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minWidth: 620)
                    VStack(spacing: 24) {
                        networkSpeedCard(snapshot)
                        Divider()
                        DeviceMemoryTrendCard(embedded: true)
                    }
                }
            }
            sectionTitle("能量与空间", subtitle: "电池状态与磁盘容量")
            dashboardBand {
                dashboardPair {
                    batteryCard(snapshot)
                } right: {
                    storageCard(snapshot)
                }
            }
            sectionTitle("连接状态", subtitle: "无线网络与已连接外设")
            dashboardBand {
                dashboardPair {
                    wifiCard(snapshot)
                } right: {
                    bluetoothCard(snapshot)
                }
            }
            DisclosureGroup(isExpanded: $showSystemDetails) {
                dashboardBand {
                    dashboardPair {
                        infoCard("硬件信息", icon: "desktopcomputer", tint: .blue, fields: snapshot.device)
                    } right: {
                        infoCard("软件信息", icon: "app.badge", tint: .purple, fields: snapshot.software)
                    }
                }
                .padding(.top, 12)
            } label: {
                sectionTitle("系统档案", subtitle: "查看硬件与软件明细")
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .bold))
            Spacer(minLength: 8)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func dashboardBand<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gradientGlass(cornerRadius: 18)
    }

    private func dashboardPair<Left: View, Right: View>(
        @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                left().frame(maxWidth: .infinity, alignment: .topLeading)
                right().frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 600)
            VStack(alignment: .leading, spacing: 24) {
                left()
                Divider()
                right()
            }
        }
    }

    private func batteryCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        let level = snapshot.batteryLevel.map { Int(($0 * 100).rounded()) }
        let isLow = level.map { $0 < 20 } ?? false
        let isOnBattery = snapshot.battery.first(where: { $0.label == "状态" })?.value == "使用电池"
        let isCharging = snapshot.battery.first(where: { $0.label == "状态" })?.value == "正在充电"
        let warningTint: Color = (level ?? 100) <= 10 ? .red : .orange
        let tint: Color = isLow && isOnBattery ? warningTint : .green

        return VStack(alignment: .leading, spacing: 10) {
            cardHeader("电池", icon: isCharging ? "battery.100percent.bolt" : isLow ? "battery.25percent" : "battery.100percent", tint: tint)
            if let level = snapshot.batteryLevel {
                DeviceCapacityGauge(fraction: level, tint: tint, title: isCharging ? "正在充电" : isOnBattery ? "使用电池" : "电源已连接", subtitle: snapshot.battery.first { $0.label == "充满还需" }.map { "充满还需\($0.value)" } ?? "当前剩余电量")
            }
            if isLow && isOnBattery {
                Label((level ?? 100) <= 5 ? "电脑电量告急，请立即充电" : "电脑电量低，请及时充电", systemImage: "battery.25percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(warningTint)
            }
            fieldList(snapshot.battery.filter { $0.label != "电量" }, section: "电池")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func storageCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("存储", icon: "internaldrive.fill", tint: .orange)
            if let fraction = snapshot.storageUsedFraction {
                DeviceCapacityGauge(fraction: fraction, tint: .orange, title: "磁盘已使用", subtitle: "剩余空间 \(value(for: "可用空间", in: snapshot.storage))")
            }
            fieldList(snapshot.storage, section: "存储")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func networkSpeedCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        NetworkSpeedCard(
            embedded: true,
            downloadedTotal: value(for: "累计下载", in: snapshot.network),
            uploadedTotal: value(for: "累计上传", in: snapshot.network)
        )
    }

    private func wifiCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("Wi‑Fi", icon: "wifi", tint: .cyan)
            fieldList(snapshot.wifi, section: "Wi‑Fi")
            if snapshot.wifi.contains(where: { $0.label == "网络名称" && $0.value == "未提供" }) {
                wifiNameHelp
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var wifiNameHelp: some View {
        if !CLLocationManager.locationServicesEnabled() {
            wifiNameMessage("系统定位服务已关闭，打开后才能读取当前 Wi‑Fi 名称。")
            Button("打开定位设置", action: openLocationSettings)
                .buttonStyle(.link)
        } else {
            switch viewModel.locationStatus {
            case .notDetermined:
                wifiNameMessage(viewModel.locationRequestIssue ?? (viewModel.didRequestWiFiNameAccess
                    ? "已请求系统授权。请在弹窗中允许；若未弹出，请检查定位设置。"
                    : "macOS 需要定位授权才能显示当前 Wi‑Fi 名称。"))
                Button(viewModel.didRequestWiFiNameAccess ? "重新请求授权" : "允许读取网络名称") {
                    viewModel.requestWiFiNameAccess()
                }
                    .buttonStyle(.link)
                if viewModel.didRequestWiFiNameAccess {
                    Button("打开定位设置", action: openLocationSettings)
                        .buttonStyle(.link)
                }
            case .denied, .restricted:
                wifiNameMessage("cleanMac 的定位权限未开启，无法读取网络名称。")
                Button("打开定位设置", action: openLocationSettings)
                    .buttonStyle(.link)
            case .authorizedAlways:
                wifiNameMessage("已获得权限。请确认设备已连接 Wi‑Fi，然后重试。")
                Button("重新读取") { viewModel.refresh() }
                    .buttonStyle(.link)
            @unknown default:
                wifiNameMessage("当前无法读取网络名称。")
            }
        }
    }

    private func wifiNameMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }

    private func openLocationSettings() {
        let destinations = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ]
        for destination in destinations {
            if let url = URL(string: destination), NSWorkspace.shared.open(url) { return }
        }
    }

    private func bluetoothCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        let lowCount = snapshot.connectedBluetoothDevices.filter(\.needsCharge).count

        return VStack(alignment: .leading, spacing: 10) {
            cardHeader("蓝牙", icon: "wave.3.right", tint: .indigo)
            if lowCount > 0 {
                Label("\(lowCount) 台已连接设备电量低，请充电", systemImage: "battery.25percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }
            fieldList(snapshot.bluetooth, section: "蓝牙")
            connectedDeviceList(snapshot.connectedBluetoothDevices)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func infoCard(_ title: String, icon: String, tint: Color, fields: [DeviceInfoField]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(title, icon: icon, tint: tint)
            fieldList(fields, section: title)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func cardHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private func fieldList(_ fields: [DeviceInfoField], section: String) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                fieldRow(field, section: section)
            }
        }
    }

    private func fieldRow(_ field: DeviceInfoField, section: String) -> some View {
        let id = "\(section):\(field.label)"
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(field.label)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(field.value)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .textSelection(.enabled)
            if canCopy(field, section: section) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(field.value, forType: .string)
                    copiedFieldID = id
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        if copiedFieldID == id { copiedFieldID = nil }
                    }
                } label: {
                    Image(systemName: copiedFieldID == id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(copiedFieldID == id ? .green : .secondary)
                .help("复制\(field.label)")
                .accessibilityLabel("复制\(field.label)")
            }
        }
        .font(.system(size: 12))
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
    }

    private func canCopy(_ field: DeviceInfoField, section: String) -> Bool {
        guard field.value != "未提供", !field.value.hasPrefix("未检测到") else { return false }
        switch (section, field.label) {
        case ("硬件信息", "设备名称"), ("硬件信息", "机型标识"),
             ("硬件信息", "序列号"), ("软件信息", "系统版本号"),
             ("Wi‑Fi", "网络名称"):
            return true
        default:
            return false
        }
    }

    private func connectedDeviceList(_ devices: [BluetoothConnectedDevice]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已连接设备")
                .font(.system(size: 12, weight: .semibold))

            if devices.isEmpty {
                Text("当前没有已连接设备")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .gradientGlass(cornerRadius: 10)
            } else {
                ForEach(devices) { device in
                    let isLow = device.needsCharge
                    let tint: Color = (device.batteryLevel ?? 100) <= 10 ? .red : .orange
                    HStack(spacing: 10) {
                        Image(systemName: "hifispeaker.fill")
                            .foregroundColor(isLow ? tint : .indigo)
                            .frame(width: 28, height: 28)
                            .background((isLow ? tint : .indigo).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        Text(device.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if device.isCharging == true {
                            ChargingBatteryBadge(device: device)
                        } else if device.batteryLevel != nil || device.isConnectedViaUSB {
                            Label(device.batteryDescription, systemImage: device.isCharging == true ? "battery.100percent.bolt" : isLow ? "battery.25percent" : "battery.100percent")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(isLow ? tint : .green)
                        } else {
                            Text("电量未提供")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .gradientGlass(cornerRadius: 10)
                }
            }
        }
    }

    private func value(for label: String, in fields: [DeviceInfoField]) -> String {
        fields.first(where: { $0.label == label })?.value ?? "未提供"
    }

}
