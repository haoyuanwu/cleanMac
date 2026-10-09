import Foundation

/// 占用变化页面的当前日、周、月、年视图。
enum StoragePeriod: String, CaseIterable, Identifiable {
    case today = "当天"
    case week = "当周"
    case month = "当月"
    case year = "当年"

    var id: Self { self }

    var calendarComponent: Calendar.Component {
        switch self {
        case .today: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    var bucketComponent: Calendar.Component {
        switch self {
        case .today: return .hour
        case .week, .month: return .day
        case .year: return .month
        }
    }

    var bucketDescription: String {
        switch self {
        case .today: return "按小时"
        case .week, .month: return "按天"
        case .year: return "按月"
        }
    }
}

struct StorageSnapshot: Codable, Identifiable, Equatable {
    var id: Date { timestamp }
    let dateKey: String
    let timestamp: Date
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64

    var usedFormatted: String { FileSizeFormatter.string(fromByteCount: usedBytes) }
    var freeFormatted: String { FileSizeFormatter.string(fromByteCount: freeBytes) }
}

/// 原始记录最近两天按小时保存，之后按天保存一年；展示时再按所选范围聚合。
enum StorageTimeline {
    private static let defaultsKey = "com.cleanMac.storageTimeline.snapshots"
    nonisolated(unsafe) private static let queue = DispatchQueue(label: "com.cleanMac.storageTimeline")

    static func load() -> [StorageSnapshot] {
        queue.sync {
            guard let data = UserDefaults.standard.data(forKey: defaultsKey),
                  let list = try? JSONDecoder().decode([StorageSnapshot].self, from: data) else { return [] }
            return list.sorted { $0.timestamp < $1.timestamp }
        }
    }

    static func record(storage: StorageInfo) {
        record(timestamp: Date(), totalBytes: storage.totalBytes, usedBytes: storage.usedBytes, freeBytes: storage.freeBytes)
    }

    static func record(timestamp: Date, totalBytes: Int64, usedBytes: Int64, freeBytes: Int64) {
        guard totalBytes > 0 else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let snapshot = StorageSnapshot(
            dateKey: formatter.string(from: timestamp),
            timestamp: timestamp,
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            freeBytes: freeBytes
        )

        queue.sync {
            let existing = (try? JSONDecoder().decode(
                [StorageSnapshot].self,
                from: UserDefaults.standard.data(forKey: defaultsKey) ?? Data()
            )) ?? []
            let calendar = Calendar.current
            let hourlyCutoff = calendar.date(byAdding: .day, value: -2, to: timestamp) ?? timestamp
            let yearlyCutoff = calendar.date(byAdding: .day, value: -370, to: timestamp) ?? timestamp
            var latestByBucket: [Date: StorageSnapshot] = [:]

            for item in existing + [snapshot] where item.timestamp >= yearlyCutoff {
                let component: Calendar.Component = item.timestamp >= hourlyCutoff ? .hour : .day
                guard let bucket = calendar.dateInterval(of: component, for: item.timestamp)?.start else { continue }
                if let previous = latestByBucket[bucket], previous.timestamp >= item.timestamp { continue }
                latestByBucket[bucket] = item
            }

            let retained = latestByBucket.values.sorted { $0.timestamp < $1.timestamp }
            if let data = try? JSONEncoder().encode(retained) {
                UserDefaults.standard.set(data, forKey: defaultsKey)
            }
        }
        AppLog.info("storage snapshot", metadata: ["used": "\(usedBytes)", "free": "\(freeBytes)"])
    }

    static func snapshots(_ snapshots: [StorageSnapshot], for period: StoragePeriod, now: Date = Date()) -> [StorageSnapshot] {
        let calendar = Calendar.current
        var latestByBucket: [Date: StorageSnapshot] = [:]
        for snapshot in samples(snapshots, for: period, now: now) {
            guard let bucket = calendar.dateInterval(of: period.bucketComponent, for: snapshot.timestamp)?.start else { continue }
            if let previous = latestByBucket[bucket], previous.timestamp >= snapshot.timestamp { continue }
            latestByBucket[bucket] = snapshot
        }
        return latestByBucket.values.sorted { $0.timestamp < $1.timestamp }
    }

    static func samples(_ snapshots: [StorageSnapshot], for period: StoragePeriod, now: Date = Date()) -> [StorageSnapshot] {
        guard let interval = Calendar.current.dateInterval(of: period.calendarComponent, for: now) else { return [] }
        return snapshots.filter { interval.contains($0.timestamp) }.sorted { $0.timestamp < $1.timestamp }
    }

    static func label(for snapshot: StorageSnapshot, period: StoragePeriod) -> String {
        let formatter = DateFormatter()
        switch period {
        case .today: formatter.dateFormat = "HH:mm"
        case .week, .month: formatter.dateFormat = "M月d日"
        case .year: formatter.dateFormat = "M月"
        }
        return formatter.string(from: snapshot.timestamp)
    }

    static func delta(_ snapshots: [StorageSnapshot]) -> (bytes: Int64, text: String)? {
        guard let first = snapshots.first, let last = snapshots.last, first.id != last.id else { return nil }
        let change = last.usedBytes - first.usedBytes
        let sign = change >= 0 ? "+" : "−"
        return (change, "\(sign)\(FileSizeFormatter.string(fromByteCount: abs(change)))")
    }
}
