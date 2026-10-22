import SwiftUI

struct ChargingBatteryBadge: View {
    let device: BluetoothConnectedDevice
    var fontSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: fontSize * 0.65, weight: .bold))
            if let level = device.batteryLevel {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(level)")
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: fontSize * 0.6, weight: .semibold))
                }
            } else {
                Image(systemName: "battery.100percent.bolt")
                    .font(.system(size: fontSize, weight: .semibold))
            }
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.1), in: Capsule())
        .fixedSize()
        .help(device.batteryDescription)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name)，\(device.batteryDescription)")
    }
}
