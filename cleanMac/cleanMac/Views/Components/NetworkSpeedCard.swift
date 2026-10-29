import SwiftUI

/// 实时性能两列共用的纵向节奏，保证数值与曲线的起止位置一致。
enum PerformanceMonitorLayout {
    static let spacing: CGFloat = 12
    static let headerHeight: CGFloat = 18
    static let readoutHeight: CGFloat = 68
    static let chartHeight: CGFloat = 110
    static let footerHeight: CGFloat = 14
    static let height = headerHeight + readoutHeight + chartHeight + footerHeight * 2 + spacing * 4
}

struct NetworkSpeedCard: View {
    var compact = false
    var embedded = false
    var downloadedTotal: String?
    var uploadedTotal: String?
    @ObservedObject private var monitor = NetworkSpeedMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PerformanceMonitorLayout.spacing) {
            HStack {
                Label("实时网速", systemImage: "network")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("每秒刷新")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(height: compact ? nil : PerformanceMonitorLayout.headerHeight)
            HStack(spacing: 12) {
                NetworkSpeedReadout(title: "下载", value: monitor.throughput.downloadText, color: .blue, icon: "arrow.down", compact: compact)
                NetworkSpeedReadout(title: "上传", value: monitor.throughput.uploadText, color: .green, icon: "arrow.up", compact: compact)
            }
            .frame(height: compact ? nil : PerformanceMonitorLayout.readoutHeight)
            GeometryReader { geometry in
                let scale = max(1024, monitor.history.map { max($0.downloadBytesPerSecond, $0.uploadBytesPerSecond) }.max() ?? 1024)
                ZStack {
                    ForEach(0..<3) { row in
                        Path { path in
                            let y = geometry.size.height * CGFloat(row) / 2
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                    line(monitor.history.map(\.downloadBytesPerSecond), scale: scale, size: geometry.size)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    line(monitor.history.map(\.uploadBytesPerSecond), scale: scale, size: geometry.size)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if monitor.history.count < 2 {
                        Text("正在采集网速趋势…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: compact ? 44 : PerformanceMonitorLayout.chartHeight)
            .accessibilityLabel("最近一分钟下载和上传速度趋势")
            HStack {
                Text("最近 1 分钟")
                Spacer()
                Text("下载 / 上传 · 自动缩放")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(height: compact ? nil : PerformanceMonitorLayout.footerHeight)
            if let downloadedTotal, let uploadedTotal {
                HStack {
                    Text("累计下载 \(downloadedTotal)")
                    Spacer(minLength: 6)
                    Text("累计上传 \(uploadedTotal)")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: compact ? nil : PerformanceMonitorLayout.footerHeight)
            } else if !compact {
                Color.clear.frame(height: PerformanceMonitorLayout.footerHeight)
            }
        }
        .padding(embedded ? 0 : 14)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 196 : nil, alignment: .top)
        .gradientGlass(cornerRadius: 14, enabled: !embedded)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(embedded ? Color.clear : Theme.cardStroke))
    }

    private func line(_ values: [Double], scale: Double, size: CGSize) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(NetworkSpeedMonitor.historyLimit - values.count + index) / CGFloat(NetworkSpeedMonitor.historyLimit - 1)
                let y = 2 + (size.height - 4) * (1 - CGFloat(min(1, max(0, value / scale))))
                let point = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

struct NetworkSpeedReadout: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    var compact = false

    var body: some View {
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        return VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts.first ?? "0")
                    .font(.system(size: compact ? 19 : 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(parts.count > 1 ? parts[1] : "B/s")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .foregroundStyle(color)
            .frame(height: compact ? 25 : 32, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .frame(height: compact ? nil : PerformanceMonitorLayout.readoutHeight)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}
