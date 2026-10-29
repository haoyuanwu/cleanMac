import SwiftUI

struct DeviceMemoryTrendCard: View {
    var embedded = false
    var compact = false
    @ObservedObject private var monitor = DeviceMemoryMonitor.shared
    private var memorySamples: [DeviceMemorySample] { monitor.history }
    var body: some View {
        memoryCard
    }

    private var memoryCard: some View {
        let current = memorySamples.last
        let used = current.map { FileSizeFormatter.string(fromByteCount: Int64($0.usedBytes)) } ?? "读取中…"
        let total = current.map { FileSizeFormatter.string(fromByteCount: Int64($0.totalBytes)) } ?? "—"

        return VStack(alignment: .leading, spacing: compact ? 9 : PerformanceMonitorLayout.spacing) {
            HStack {
                Label("实时内存", systemImage: "memorychip")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.purple)
                Spacer()
                Text("每秒刷新")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(height: compact ? nil : PerformanceMonitorLayout.headerHeight)

            VStack(alignment: .leading, spacing: 4) {
                if !compact {
                    Text("已用内存")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(used)
                        .font(.system(size: compact ? 20 : 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("/ \(total)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    if let current, current.totalBytes > 0 {
                        Text("\(Int((Double(current.usedBytes) / Double(current.totalBytes) * 100).rounded()))%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.purple)
                    }
                }
                .frame(height: compact ? nil : 32, alignment: .leading)
            }
            .padding(compact ? 0 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: compact ? nil : PerformanceMonitorLayout.readoutHeight)
            .background(compact ? Color.clear : Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

            if memorySamples.count < 2 {
                Text("正在采集内存使用量…")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: compact ? 44 : PerformanceMonitorLayout.chartHeight)
            } else {
                memoryChart
            }

            HStack(spacing: 8) {
                if let current, current.totalBytes > 0 {
                    ProgressView(value: Double(current.usedBytes) / Double(current.totalBytes))
                        .tint(.purple)
                    Text("可用 \(FileSizeFormatter.string(fromByteCount: Int64(current.totalBytes - current.usedBytes)))")
                        .fixedSize()
                } else {
                    Text("可用内存读取中…")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(height: compact ? nil : PerformanceMonitorLayout.footerHeight)

            Text("活跃、有线与压缩内存估算 · 后台持续采样 · 每秒更新")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: compact ? nil : PerformanceMonitorLayout.footerHeight)
        }
        .padding(embedded ? 0 : 14)
        .gradientGlass(cornerRadius: 14, enabled: !embedded)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(embedded ? Color.clear : Theme.cardStroke))
    }

    private var memoryChart: some View {
        let values = memorySamples.map { Double($0.usedBytes) / 1_000_000_000 }
        let lower = max(0, (values.min() ?? 0) - 0.25)
        let upper = (values.max() ?? 0) + 0.25
        let span = max(upper - lower, 0.5)

        return GeometryReader { geometry in
            ZStack {
                ForEach(0..<3) { index in
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 1)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * CGFloat(index) / 2)
                }
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geometry.size.height * (1 - CGFloat((value - lower) / span))
                        let point = CGPoint(x: x, y: y)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: compact ? 44 : PerformanceMonitorLayout.chartHeight)
        .accessibilityLabel("最近一分钟内存使用趋势，已采集 \(memorySamples.count) 个数据点")
    }

}
