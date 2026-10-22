import SwiftUI
import Darwin

private struct DeviceMemorySample: Identifiable {
    let id = Date()
    let usedBytes: UInt64
    let totalBytes: UInt64
}

private enum DeviceMemoryReader {
    static func sample() -> DeviceMemorySample? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS,
              host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        let total = ProcessInfo.processInfo.physicalMemory
        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        return DeviceMemorySample(
            usedBytes: min(total, usedPages * UInt64(pageSize)),
            totalBytes: total
        )
    }
}

struct DeviceMemoryTrendCard: View {
    var embedded = false
    @State private var memorySamples: [DeviceMemorySample] = []
    var body: some View {
        memoryCard
        .task {
            memorySamples = []
            while !Task.isCancelled {
                if let sample = DeviceMemoryReader.sample() {
                    memorySamples.append(sample)
                    if memorySamples.count > 30 {
                        memorySamples.removeFirst(memorySamples.count - 30)
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var memoryCard: some View {
        let current = memorySamples.last
        let used = current.map { FileSizeFormatter.string(fromByteCount: Int64($0.usedBytes)) } ?? "读取中…"
        let total = current.map { FileSizeFormatter.string(fromByteCount: Int64($0.totalBytes)) } ?? "—"

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("内存变化趋势", systemImage: "memorychip")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.purple)
                Spacer()
                Text("最近 1 分钟")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(used)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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

            if memorySamples.count < 2 {
                Text("正在采集内存使用量…")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                memoryChart
            }

            if let current, current.totalBytes > 0 {
                ProgressView(value: Double(current.usedBytes) / Double(current.totalBytes))
                    .tint(.purple)
                Text("可用 \(FileSizeFormatter.string(fromByteCount: Int64(current.totalBytes - current.usedBytes)))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text("活跃、有线与压缩内存估算 · 设备页打开后开始采样")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(embedded ? 0 : 14)
        .background(embedded ? Color.clear : Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .frame(height: 100)
        .accessibilityLabel("最近一分钟内存使用趋势，已采集 \(memorySamples.count) 个数据点")
    }

}
