import Foundation

/// 应用缓存扫描的负结果缓存，与用户清理白名单独立。
final class CacheScanIgnoreStore: @unchecked Sendable {
    struct Record: Codable, Identifiable, Sendable {
        let path: String
        let applicationName: String
        let scannedAt: Date
        let modificationDate: Date
        let fileNumber: UInt64
        nonisolated var id: String { path }
    }

    nonisolated static let shared = CacheScanIgnoreStore()
    nonisolated static let didChange = Notification.Name("cleanMac.cacheScanIgnoreDidChange")
    nonisolated static let lifetime: TimeInterval = 24 * 60 * 60
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private let defaults: UserDefaults
    nonisolated private let key: String
    nonisolated(unsafe) private var records: [String: Record]
    nonisolated(unsafe) private var currentRevision = 0

    nonisolated init(defaults: UserDefaults = .standard, key: String = "com.cleanMac.cacheScan.automaticIgnores.v1") {
        self.defaults = defaults
        self.key = key
        let loaded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        records = Dictionary(loaded.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// 规则版本、内容或回退发生变化时，旧的负结果不能继续跳过扫描。
    nonisolated func prepare(for rulesFingerprint: String) {
        lock.lock()
        guard defaults.string(forKey: key + ".rulesFingerprint") != rulesFingerprint else { lock.unlock(); return }
        records.removeAll()
        currentRevision += 1
        defaults.set(rulesFingerprint, forKey: key + ".rulesFingerprint")
        persistLocked()
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    nonisolated var revision: Int {
        lock.lock(); defer { lock.unlock() }
        return currentRevision
    }

    nonisolated var allRecords: [Record] {
        lock.lock(); defer { lock.unlock() }
        return records.values.sorted { $0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending
            || ($0.applicationName == $1.applicationName && $0.path < $1.path) }
    }

    nonisolated static func record(for path: String, applicationName: String, at date: Date) -> Record? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Record(path: path, applicationName: applicationName, scannedAt: date,
                      modificationDate: modified, fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)
    }

    nonisolated func shouldSkip(_ path: String, at date: Date = Date()) -> Bool {
        lock.lock()
        let record = records[path]
        lock.unlock()
        guard let record, date >= record.scannedAt, date.timeIntervalSince(record.scannedAt) < Self.lifetime,
              let current = Self.record(for: path, applicationName: record.applicationName, at: date) else { return false }
        return current.modificationDate == record.modificationDate && current.fileNumber == record.fileNumber
    }

    /// 一次扫描只持久化一次；设置中恢复路径后，不再接收旧扫描的忽略结果。
    nonisolated func apply(emptyRoots: [Record], rescannedPaths: Set<String>, expectedRevision: Int) {
        guard !emptyRoots.isEmpty || !rescannedPaths.isEmpty else { return }
        lock.lock()
        guard currentRevision == expectedRevision else { lock.unlock(); return }
        for path in rescannedPaths { records.removeValue(forKey: path) }
        for record in emptyRoots { records[record.path] = record }
        persistLocked()
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    nonisolated func remove(_ path: String) {
        lock.lock()
        records.removeValue(forKey: path)
        currentRevision += 1
        persistLocked()
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    nonisolated func removeAll() {
        lock.lock()
        records.removeAll()
        currentRevision += 1
        persistLocked()
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    nonisolated private func persistLocked() {
        if let data = try? JSONEncoder().encode(Array(records.values)) { defaults.set(data, forKey: key) }
    }
}
