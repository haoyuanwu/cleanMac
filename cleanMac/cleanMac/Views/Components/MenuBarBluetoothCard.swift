import SwiftUI

/// 紧凑设备列表：所有文字沿同一左边缘排列，电量使用统一的尾部列。
struct MenuBarBluetoothCard: View {
    let devices: [BluetoothConnectedDevice]?
    let state: String?
    private var warning: Bool { devices?.contains(where: \.needsCharge) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                PopupCardHeading(title: "蓝牙", symbol: "wave.3.right", tint: .indigo)
                Spacer(minLength: 8)
                Text(devices.map { "已连接 \($0.count) 台" } ?? "读取中…")
                    .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary).monospacedDigit()
            }
            if let devices {
                if devices.isEmpty {
                    Text(state == "已开启" ? "当前没有已连接设备" : state ?? "当前没有已连接设备")
                        .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                } else {
                    ForEach(devices) { device in
                        HStack(alignment: .center, spacing: 10) {
                            Text(device.name).font(.system(size: 12, weight: .medium))
                                .lineLimit(2).truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(device.name)
                            if device.isCharging == true {
                                ChargingBatteryBadge(device: device, fontSize: 12, compact: true)
                            } else {
                                HStack(spacing: 5) {
                                    Image(systemName: batterySymbol(device.batteryLevel))
                                        .font(.system(size: 12, weight: .semibold)).frame(width: 22)
                                    Text(device.batteryLevel.map { "\($0)%" } ?? "—%")
                                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                        .frame(width: 38, alignment: .trailing)
                                }.foregroundStyle(device.needsCharge ? (device.batteryLevel ?? 100) <= 10 ? Color.red : Color.orange : Theme.actionInk)
                                    .fixedSize().help(device.batteryDescription)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(device.name + "，" + device.batteryDescription)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("正在读取蓝牙设备…").font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).popupCard()
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(warning ? Color.orange.opacity(0.55) : Color.clear))
    }

    private func batterySymbol(_ level: Int?) -> String {
        guard let level else { return "questionmark" }
        switch level {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

#Preview("蓝牙设备列表") {
    MenuBarBluetoothCard(devices: [
        .init(id: "keyboard", name: "无线键盘", batteryLevel: 82, isCharging: false, isConnectedViaUSB: false),
        .init(id: "mouse", name: "无线鼠标", batteryLevel: 47, isCharging: true, isConnectedViaUSB: true),
        .init(id: "headphones", name: "蓝牙耳机", batteryLevel: 9, isCharging: false, isConnectedViaUSB: false),
        .init(id: "unknown", name: "未提供电量的设备", batteryLevel: nil, isCharging: nil, isConnectedViaUSB: false)
    ], state: "已开启").padding(16).frame(width: 350)
        .background(Theme.reviewCanvas(.blue))
}
