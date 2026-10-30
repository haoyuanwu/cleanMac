import Foundation

nonisolated struct CPUTicks: Sendable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}
nonisolated struct CPUUsage: Sendable {
    let user: Double
    let system: Double
    let idle: Double
    var used: Double { user + system }
    static func between(_ old: CPUTicks, _ new: CPUTicks) -> CPUUsage? {
        let u = Double(new.user &- old.user) + Double(new.nice &- old.nice)
        let s = Double(new.system &- old.system), i = Double(new.idle &- old.idle)
        let total = u + s + i
        guard total > 0 else { return nil }
        return CPUUsage(user: u / total * 100, system: s / total * 100, idle: i / total * 100)
    }
}
nonisolated struct DiskByteCounter: Sendable {
    let read: UInt64
    let written: UInt64
}
nonisolated struct DiskTransferRate: Sendable {
    let read: Double
    let written: Double
    static func between(_ old: [UInt64: DiskByteCounter], _ new: [UInt64: DiskByteCounter], seconds: Double) -> Self? {
        guard seconds > 0, seconds <= 8 else { return nil }
        var read: Double = 0, written: Double = 0, matched = false
        for (id, next) in new {
            guard let previous = old[id], next.read >= previous.read, next.written >= previous.written else { continue }
            matched = true; read += Double(next.read - previous.read); written += Double(next.written - previous.written)
        }
        return matched ? Self(read: read / seconds, written: written / seconds) : nil
    }
}
nonisolated struct TelemetryPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let cpu: CPUUsage?
    let disk: DiskTransferRate?
}
nonisolated struct MountedDeviceVolume: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
    let internalVolume: Bool?
    let total: Int64?
    let free: Int64?
}
nonisolated struct BatteryHistoryPoint: Codable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let level: Double
    let state: String
}
nonisolated enum BatteryHistoryPolicy {
    static func retained(_ values: [BatteryHistoryPoint], now: Date) -> [BatteryHistoryPoint] {
        // 不接受未来、无效电量或无界数据；排序和去重后保留最近 24 小时。
        var seen = Set<Date>()
        return Array(values.filter { $0.date <= now && now.timeIntervalSince($0.date) <= 86400 && $0.level.isFinite && (0...1).contains($0.level) }
            .sorted { $0.date < $1.date }.filter { seen.insert($0.date).inserted }.suffix(2160))
    }
    static func hourlyChange(_ values: [BatteryHistoryPoint]) -> Double? {
        guard let last = values.last else { return nil }
        var window = [last]
        for value in values.dropLast().reversed() {
            guard value.state == last.state, let previous = window.last,
                  previous.date.timeIntervalSince(value.date) <= 180,
                  last.date.timeIntervalSince(value.date) <= 1800 else { break }
            window.append(value)
        }
        guard let first = window.last, last.date.timeIntervalSince(first.date) >= 300 else { return nil }
        return (last.level - first.level) / last.date.timeIntervalSince(first.date) * 3600 * 100
    }
    static func events(_ values: [BatteryHistoryPoint]) -> [BatteryHistoryPoint] {
        zip(values, values.dropFirst()).compactMap { old, new in
            new.state != old.state && new.date.timeIntervalSince(old.date) <= 180 ? new : nil
        }
    }
    static func segmentIDs(_ values: [BatteryHistoryPoint]) -> [Int] {
        var segment = 0
        return values.enumerated().map { index, value in
            if index > 0, value.date.timeIntervalSince(values[index - 1].date) > 180 { segment += 1 }
            return segment
        }
    }
}
nonisolated struct DisplayDeviceInfo: Identifiable, Sendable {
    let id: UInt32
    let name: String
    let logicalWidth: Int
    let logicalHeight: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double?
    let builtIn: Bool
}
nonisolated enum DeviceReportRedactor {
    static func render(sections: [(String, [(String, String)])], date: Date) -> String {
        let excluded = ["设备名称", "序列号", "网络名称", "SSID", "IP", "MAC", "挂载路径", "用户名"]
        var lines = ["cleanMac 设备报告（已脱敏）", "生成于：\(date.formatted(date: .numeric, time: .shortened))", "已省略设备名称、序列号、网络标识、用户与文件路径。", ""]
        for (name, fields) in sections {
            lines.append("## " + name)
            for (label, value) in fields where !excluded.contains(where: { label.localizedCaseInsensitiveContains($0) }) {
                guard !value.contains("/Users/"), !value.contains("/Volumes/") else { continue }
                lines.append("\(label)：\(value)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
