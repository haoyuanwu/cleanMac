import SwiftUI

/// 两个入口共享关闭状态；电量进一步降低时再次提示。
struct ChargeReminderBanner: View {
    var horizontalPadding: CGFloat = 16
    @ObservedObject private var monitor = BatteryAlertMonitor.shared

    private var tint: Color {
        (monitor.visibleChargeWarnings.map(\.level).min() ?? 100) <= 10 ? .red : .orange
    }

    var body: some View {
        if !monitor.visibleChargeWarnings.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "battery.25percent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    Text("该充电了")
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(monitor.visibleChargeWarnings) { warning in
                        Text("\(warning.name) · \(warning.level)%")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("请及时连接电源，避免使用中断。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    monitor.dismissChargeWarnings()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭充电提醒")
                .accessibilityLabel("关闭充电提醒")
            }
            .padding(12)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
        }
    }
}
