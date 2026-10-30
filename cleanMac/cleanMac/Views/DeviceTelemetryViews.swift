import SwiftUI
import Charts

struct CPUStatusView: View {
    @ObservedObject private var monitor = DeviceTelemetryMonitor.shared
    @State private var client = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DeviceFeatureHeader(destination: .page(.deviceCPU), isRefreshing: monitor.isRefreshing) { monitor.refresh() }
                TelemetryPanel("整机 CPU · 最近一分钟") {
                    HStack {
                        TelemetryMetric(title: "总使用率", value: percent(monitor.current?.cpu?.used))
                        TelemetryMetric(title: "用户", value: percent(monitor.current?.cpu?.user), tint: .indigo)
                        TelemetryMetric(title: "系统", value: percent(monitor.current?.cpu?.system), tint: .cyan)
                        TelemetryMetric(title: "空闲", value: percent(monitor.current?.cpu?.idle), tint: .green)
                    }
                    TelemetryChart(values: monitor.history.flatMap { sample -> [TelemetryLine] in
                        guard let cpu = sample.cpu else { return [] }
                        return [.init(date: sample.date, value: cpu.user, series: "用户"), .init(date: sample.date, value: cpu.system, series: "系统")]
                    }, upper: 100)
                    Text("整机按全部核心归一化为 100%；应用列表以单核心 100% 计量，因此两者数值不同。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TelemetryPanel("运行状态") {
                    HStack {
                        TelemetryMetric(title: "系统热状态", value: monitor.thermalDescription, tint: monitor.thermalState == .nominal ? .green : .orange)
                        TelemetryMetric(title: "逻辑核心", value: "\(ProcessInfo.processInfo.activeProcessorCount) 个")
                        TelemetryMetric(title: "运行时间", value: duration(ProcessInfo.processInfo.systemUptime), tint: .cyan)
                    }
                    Text("热状态由 macOS 提供，表示系统的散热压力，不是传感器温度。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28).frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }.onAppear { monitor.retain(client) }.onDisappear { monitor.release(client) }
    }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "采样中" }
    private func duration(_ seconds: TimeInterval) -> String { "\(Int(seconds) / 3600) 小时 \(Int(seconds) / 60 % 60) 分钟" }
}

struct MemoryPressurePanel: View {
    @ObservedObject private var monitor = DeviceMemoryMonitor.shared
    private var sample: DeviceMemorySample? { monitor.history.last }
    private func label(_ pressure: Int32?) -> String {
        switch pressure { case 1: "正常"; case 2: "偏高"; case 4: "严重"; default: "未读取" }
    }
    var body: some View {
        TelemetryPanel("内存压力与分配") {
            HStack {
                TelemetryMetric(title: "系统内存压力", value: label(sample?.pressure), tint: sample?.pressure == nil ? .secondary : sample?.pressure == 1 ? .green : .orange)
                TelemetryMetric(title: "压缩内存", value: telemetryBytes(sample?.compressedBytes), tint: .indigo)
                TelemetryMetric(title: "联动内存", value: telemetryBytes(sample?.wiredBytes))
                TelemetryMetric(title: "交换空间", value: telemetryBytes(sample?.swapBytes), tint: .cyan)
            }
            TelemetryChart(values: monitor.history.flatMap { point -> [TelemetryLine] in
                var rows = [TelemetryLine(date: point.id, value: Double(point.compressedBytes) / 1_000_000_000, series: "压缩 GB")]
                if let swap = point.swapBytes { rows.append(.init(date: point.id, value: Double(swap) / 1_000_000_000, series: "交换 GB")) }
                return rows
            }, unit: "GB")
            Text("压力等级读取系统状态；交换空间不为零或内存占比高，不直接代表异常。此处不会强制释放内存。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct NetworkDiagnosticPanel: View {
    @StateObject private var session = NetworkDiagnosticSession()
    var body: some View {
        TelemetryPanel("网络诊断") {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("按需检查默认路由、网关、DNS 和外网连接。").font(.system(size: 13))
                    Text("点击后会探测本地网关，并向 Apple 测试端点发起一次 HTTPS 请求；不上传设备报告。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if session.running {
                    ProgressView().controlSize(.small)
                    Button("取消") { session.cancel() }
                } else { Button(session.checks.isEmpty ? "开始诊断" : "重新诊断") { session.start() } }
            }
            ForEach(session.checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.succeeded == true ? "checkmark.circle.fill" : check.succeeded == false ? "exclamationmark.circle" : "info.circle")
                        .foregroundStyle(check.succeeded == true ? Color.green : check.succeeded == false ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(check.title).font(.system(size: 13, weight: .medium))
                        Text(check.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            if let date = session.completedAt { Text("诊断完成 · " + date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary) }
        }.onDisappear { if session.running { session.cancel() } }
    }
}

struct BatteryHistoryPanel: View {
    @ObservedObject private var monitor = BatteryHistoryMonitor.shared
    var body: some View {
        let values = monitor.history
        let segments = BatteryHistoryPolicy.segmentIDs(values)
        TelemetryPanel("电量曲线 · 最近 24 小时实际记录") {
            HStack {
                TelemetryMetric(title: "当前电量", value: values.last.map { "\(Int(($0.level * 100).rounded()))%" } ?? "未读取", tint: .green)
                TelemetryMetric(title: "当前状态下电量变化", value: BatteryHistoryPolicy.hourlyChange(values).map { String(format: "%+.1f%% / 小时", $0) } ?? "积累 5 分钟后显示", tint: .cyan)
            }
            if values.count >= 2 {
                Chart(Array(values.enumerated()), id: \.element.id) { index, point in
                    LineMark(x: .value("时间", point.date), y: .value("电量", point.level * 100), series: .value("采样段", segments[index]))
                        .foregroundStyle(.green)
                }.chartYScale(domain: 0...100).frame(height: 170)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.hour().minute()); AxisGridLine() } }
                    .accessibilityLabel("最近24小时实际采集电量，共\(values.count)个点")
            } else { ContentUnavailableTelemetry(text: "记录将在运行期间逐步积累，无历史数据时不推算曲线。") }
            Text("每分钟记录一次，供电状态变化时补记；睡眠或退出期间留空，不连接为连续使用。变化速度根据同一状态下连续记录估算，不代表额定续航。")
                .font(.caption).foregroundStyle(.secondary)
            let events = Array(BatteryHistoryPolicy.events(values).suffix(12).reversed())
            if !events.isEmpty {
                Divider()
                Text("充放电记录").font(.system(size: 13, weight: .medium))
                ForEach(events) { event in
                    HStack {
                        Text(event.state)
                        Spacer()
                        Text("\(Int((event.level * 100).rounded()))% · " + event.date.formatted(date: .omitted, time: .shortened))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StorageActivityPanel: View {
    @ObservedObject private var monitor = DeviceTelemetryMonitor.shared
    @State private var client = UUID()
    let onOpen: (WorkspaceDestination) -> Void
    var body: some View {
        VStack(spacing: 24) {
            TelemetryPanel("实时磁盘读写") {
                HStack {
                    TelemetryMetric(title: "读取", value: monitor.current?.disk.map { NetworkThroughput.format(bytesPerSecond: $0.read) } ?? "未读取", tint: .cyan)
                    TelemetryMetric(title: "写入", value: monitor.current?.disk.map { NetworkThroughput.format(bytesPerSecond: $0.written) } ?? "未读取", tint: .pink)
                }
                TelemetryChart(values: monitor.history.flatMap { point -> [TelemetryLine] in
                    guard let disk = point.disk else { return [] }
                    return [.init(date: point.date, value: disk.read / 1_000_000, series: "读取 MB/s"), .init(date: point.date, value: disk.written / 1_000_000, series: "写入 MB/s")]
                }, unit: "MB/s")
                Text("可读取的块存储驱动累计计数差分，覆盖多个设备；不代表某个卷或应用的专属读写。驱动未提供数据时显示未读取。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("打开磁盘地图") { onOpen(.page(.diskMap)) }
                    Button("查看占用变化") { onOpen(.page(.timeline)) }
                }
            }
            TelemetryPanel("本地磁盘与外接卷") {
                if monitor.volumes.isEmpty { Text("暂未读取到可显示的本地磁盘卷").font(.caption).foregroundStyle(.secondary) }
                ForEach(monitor.volumes) { volume in
                    HStack(spacing: 12) {
                        Image(systemName: volume.internalVolume == true ? "internaldrive" : "externaldrive").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(volume.name).font(.system(size: 13, weight: .medium))
                            Text(volume.internalVolume == true ? "内置卷" : volume.internalVolume == false ? "外接卷" : "类型未提供").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(volume.free.map { FileSizeFormatter.string(fromByteCount: $0) + " 可用" } ?? "容量未读取").font(.caption)
                        Text(volume.total.map { "/ " + FileSizeFormatter.string(fromByteCount: $0) } ?? "").font(.caption).foregroundStyle(.secondary)
                        Button("打开") { NSWorkspace.shared.open(volume.url) }
                    }.padding(.vertical, 4)
                }
                Text("APFS 卷可能共享容器空间，容量不可直接相加。每 15 秒更新卷列表。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { monitor.retain(client) }.onDisappear { monitor.release(client) }
    }
}

struct SystemExtrasPanel: View {
    let snapshot: DeviceInfoSnapshot
    @State private var query = ""
    @State private var message: String?
    @State private var displays: [DisplayDeviceInfo] = []
    var body: some View {
        VStack(spacing: 24) {
            TelemetryPanel("搜索设备字段") {
                TextField("搜索芯片、版本、序列号等", text: $query).textFieldStyle(.plain).padding(10).gradientGlass(cornerRadius: 10)
                if !query.isEmpty {
                    let matches = (snapshot.device + snapshot.software).filter { $0.label.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
                    if matches.isEmpty { Text("没有匹配的设备字段").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(matches.enumerated()), id: \.offset) { _, field in
                        HStack { Text(field.label).foregroundStyle(.secondary); Spacer(); Text(field.value).textSelection(.enabled) }.font(.system(size: 12))
                    }
                }
            }
            TelemetryPanel("显示器") {
                if displays.isEmpty { Text("未读取到显示器信息").font(.caption).foregroundStyle(.secondary) }
                ForEach(displays) { display in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(display.name, systemImage: display.builtIn ? "laptopcomputer" : "display").font(.system(size: 13, weight: .medium))
                        Text("逻辑分辨率 \(display.logicalWidth) × \(display.logicalHeight) · 像素 \(display.pixelWidth) × \(display.pixelHeight)").font(.caption)
                        Text(display.refreshRate.map { String(format: "当前模式 %.1f Hz", $0) } ?? "刷新率：系统未提供固定值，可能使用可变刷新模式").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            TelemetryPanel("脱敏设备报告") {
                Text("只导出机型、芯片、系统版本、容量、电源和显示模式；省略设备名称、序列号、网络标识及用户路径。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button("复制报告") { DeviceReportService.copy(DeviceReportService.report(snapshot)); message = "已复制脱敏报告" }
                    Button("导出文本…") { message = DeviceReportService.export(DeviceReportService.report(snapshot)) }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }.onAppear { displays = DeviceReportService.displays() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in displays = DeviceReportService.displays() }
    }
}
