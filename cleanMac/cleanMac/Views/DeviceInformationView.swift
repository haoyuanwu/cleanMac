import SwiftUI
import AppKit
import CoreLocation

struct DeviceInformationView: View {
    @ObservedObject var viewModel: DeviceInformationViewModel
    @State private var copiedFieldID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let snapshot = viewModel.snapshot {
                    overviewCard(snapshot)
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
        .background(Theme.reviewCanvas(.blue))
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
        let name = value(for: "设备名称", in: snapshot.device)
        let model = value(for: "机型标识", in: snapshot.device)
        let chip = value(for: "芯片", in: snapshot.device)

        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(model)  ·  \(chip)")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.43, blue: 0.91), Color(red: 0.32, green: 0.62, blue: 0.87)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .elevatedShadow()
    }

    private func categoryColumns(_ snapshot: DeviceInfoSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                categoryColumnLeft(snapshot)
                categoryColumnRight(snapshot)
            }
            .frame(minWidth: 620)

            VStack(spacing: 14) {
                categoryColumnLeft(snapshot)
                categoryColumnRight(snapshot)
            }
        }
    }

    private func categoryColumnLeft(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(spacing: 14) {
            infoCard("硬件信息", icon: "desktopcomputer", tint: .blue, fields: snapshot.device)
            batteryCard(snapshot)
            wifiCard(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func categoryColumnRight(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(spacing: 14) {
            infoCard("软件信息", icon: "app.badge", tint: .purple, fields: snapshot.software)
            storageCard(snapshot)
            bluetoothCard(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func batteryCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("电池", icon: "battery.100percent", tint: .green)
            if let level = snapshot.batteryLevel {
                progressSummary(value: "\(Int((level * 100).rounded()))%", fraction: level, tint: .green)
            }
            fieldList(snapshot.battery.filter { $0.label != "电量" }, section: "电池")
        }
        .modifier(InfoCardStyle())
    }

    private func storageCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("存储", icon: "internaldrive.fill", tint: .orange)
            if let fraction = snapshot.storageUsedFraction {
                progressSummary(value: "已用 \(Int((fraction * 100).rounded()))%", fraction: fraction, tint: .orange)
            }
            fieldList(snapshot.storage, section: "存储")
        }
        .modifier(InfoCardStyle())
    }

    private func wifiCard(_ snapshot: DeviceInfoSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("Wi‑Fi", icon: "wifi", tint: .cyan)
            fieldList(snapshot.wifi, section: "Wi‑Fi")
            if snapshot.wifi.contains(where: { $0.label == "网络名称" && $0.value == "未提供" }) {
                wifiNameHelp
            }
        }
        .modifier(InfoCardStyle())
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
                wifiNameMessage("macOS 需要定位授权才能显示当前 Wi‑Fi 名称。")
                Button("允许读取网络名称") { viewModel.requestWiFiNameAccess() }
                    .buttonStyle(.link)
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
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("蓝牙", icon: "wave.3.right", tint: .indigo)
            fieldList(snapshot.bluetooth, section: "蓝牙")
            connectedDeviceList(snapshot.connectedBluetoothDevices)
        }
        .modifier(InfoCardStyle())
    }

    private func infoCard(_ title: String, icon: String, tint: Color, fields: [DeviceInfoField]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader(title, icon: icon, tint: tint)
            fieldList(fields, section: title)
        }
        .modifier(InfoCardStyle())
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

    private func progressSummary(value: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
            GeometryReader { geometry in
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint.gradient)
                            .frame(width: geometry.size.width * min(1, max(0, fraction)))
                    }
            }
            .frame(height: 6)
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
                    .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: 10))
            } else {
                ForEach(devices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: "hifispeaker.fill")
                            .foregroundColor(.indigo)
                            .frame(width: 28, height: 28)
                            .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        Text(device.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if let level = device.batteryLevel {
                            Label("\(level)%", systemImage: "battery.100percent")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(level <= 20 ? .orange : .green)
                        } else {
                            Text("电量未提供")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func value(for label: String, in fields: [DeviceInfoField]) -> String {
        fields.first(where: { $0.label == label })?.value ?? "未提供"
    }

}

private struct InfoCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardStroke))
    }
}
