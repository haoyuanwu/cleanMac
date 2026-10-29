import Foundation
import CryptoKit
import Darwin

nonisolated struct CacheGrowth: Codable, Sendable {
    let application: String
    let bytes: Int64
    let paths: [String]
}
nonisolated struct CacheScanComparison: Codable, Sendable {
    let date: Date
    let previousDate: Date?
    let added: Int
    let removed: Int
    let increasedBytes: Int64
    let decreasedBytes: Int64
    let reusedRoots: Int
    let rescannedRoots: Int
    let growth: [CacheGrowth]
    let complete: Bool
    var description: String {
        guard complete else { return "本次结果不完整，不更新对比基线。" }
        guard previousDate != nil else { return "首次完整结果已建立对比基线。" }
        return "较上次新增 \(added) 项、减少 \(removed) 项；逻辑大小增加 \(FileSizeFormatter.string(fromByteCount: increasedBytes))、减少 \(FileSizeFormatter.string(fromByteCount: decreasedBytes))。"
    }
}

final class CacheScanIndex: @unchecked Sendable {
    nonisolated static let shared = CacheScanIndex()
    nonisolated private let lock = NSLock()
    nonisolated private let fileURL: URL
    nonisolated(unsafe) private var state: State
    nonisolated(unsafe) private var failure: String?

    nonisolated struct CachedItem: Codable, Sendable {
        let path: String
        let name: String
        let size: Int64
        let modified: Date?
        let directory: Bool
        let storage: FileStorageMeasurement?
        let owner: CacheApplication?
        let rule: CacheRuleMatch?
        let number: UInt64
        let permissions: UInt64
        init(_ item: FileItem) {
            path = item.path; name = item.name; size = item.size; modified = item.modificationDate
            directory = item.isDirectory; storage = item.storage; owner = item.cacheApplication; rule = item.cacheRuleMatch
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            number = (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            permissions = (attrs?[.posixPermissions] as? NSNumber)?.uint64Value ?? 0
        }
        func restored() -> FileItem? {
            let url = URL(fileURLWithPath: path)
            guard let attrs = InspectionFS.attributes(url), (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == number,
                  (attrs[.posixPermissions] as? NSNumber)?.uint64Value == permissions,
                  attrs[.modificationDate] as? Date == modified else { return nil }
            if directory, (try? ScanFileAccess().contentsOfDirectory(atPath: path)) == nil { return nil }
            var item = FileItem(path: path, name: name, size: size, modificationDate: modified, isDirectory: directory, storage: storage)
            item.cacheApplication = owner
            item.cacheRuleMatch = rule
            item.riskLevel = rule?.risk ?? .safe
            return item
        }
    }
    nonisolated struct Root: Codable, Sendable {
        let number: UInt64
        let device: UInt64
        let permissions: UInt64
        let modified: Date?
        let owner: CacheApplication
        let rules: String
        let token: CacheEventToken
        let date: Date
        let items: [CachedItem]
        let stamp: String
    }
    nonisolated struct Baseline: Codable, Sendable { let size: Int64; let application: String }
    nonisolated struct State: Codable, Sendable {
        var schema = 1
        var roots: [String: Root] = [:]
        var baseline: [String: Baseline] = [:]
        var baselineDate: Date?
        var comparison: CacheScanComparison?
        var rules: String?
    }
    nonisolated init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/cleanMac/cache-scan-index.json")
        if let data = try? Data(contentsOf: self.fileURL), let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.schema == 1 { state = decoded }
        else { state = State() }
    }
    /// 目录元数据指纹，不读取文件内容；补足 FSEvents 尚未交付的时间窗口。
    nonisolated static func treeStamp(_ root: ApplicationCacheScanner.DataRoot, cachePaths: Set<String> = []) -> String? {
        guard let enumerator = ScanFileAccess().enumerator(at: root.url, includingPropertiesForKeys: nil) else { return nil }
        let errorRevision = ScanContext.diagnostics?.errorRevision ?? 0
        var digest = [UInt8](repeating: 0, count: 32)
        var count = 0
        func include(_ url: URL) -> mode_t? {
            ScanContext.diagnostics?.visit(url.path)
            var info = stat()
            guard url.path.withCString({ lstat($0, &info) }) == 0 else {
                ScanContext.diagnostics?.failure(url.path, error: NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
                return nil
            }
            let row = "\(url.path)|\(info.st_ino)|\(info.st_dev)|\(info.st_mode)|\(info.st_uid)|\(info.st_gid)|\(info.st_size)|\(info.st_blocks)|\(info.st_mtimespec.tv_sec)|\(info.st_mtimespec.tv_nsec)|\(info.st_ctimespec.tv_sec)|\(info.st_ctimespec.tv_nsec)"
            let hash = Array(SHA256.hash(data: Data(row.utf8)))
            // 每个路径唯一；按行异或并计数，使目录枚举顺序不影响指纹。
            for index in digest.indices { digest[index] ^= hash[index] }
            count += 1
            return info.st_mode & S_IFMT
        }
        guard include(root.url) != nil else { return nil }
        for case let url as URL in enumerator {
            if Task.isCancelled { return nil }
            guard let type = include(url) else { return nil }
            if type != S_IFDIR { continue }
            let isPrivateDocuments = root.isSandboxContainer && (url.path == root.url.appendingPathComponent("Data/Documents").path || url.path == root.url.appendingPathComponent("Documents").path)
            let relativeComponents = String(url.path.dropFirst(root.url.path.count)).split(separator: "/")
            let insideCache = root.isCacheRoot || relativeComponents.contains(where: { ApplicationCacheScanner.isCacheName(String($0)) })
                || cachePaths.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") })
            let userData = ["Documents", "Downloads", "Desktop", "Pictures", "Movies", "Music"].contains(url.lastPathComponent) && !isPrivateDocuments
            if !insideCache && (userData || (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true) { enumerator.skipDescendants() }
        }
        guard (ScanContext.diagnostics?.errorRevision ?? 0) == errorRevision else { return nil }
        return digest.map { String(format: "%02x", $0) }.joined() + "-\(count)"
    }

    nonisolated var lastComparison: CacheScanComparison? { lock.lock(); defer { lock.unlock() }; return state.comparison }
    nonisolated var persistenceError: String? { lock.lock(); defer { lock.unlock() }; return failure }
    nonisolated func reusable(root: ApplicationCacheScanner.DataRoot, rules: String, token: CacheEventToken, now: Date = Date()) -> [FileItem]? {
        lock.lock(); let record = state.roots[root.url.path]; lock.unlock()
        guard token.available, let record, record.token == token, record.rules == rules, record.owner == root.owner,
              now >= record.date, now.timeIntervalSince(record.date) < 600,
              let attrs = InspectionFS.attributes(root.url),
              (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == record.number,
              (attrs[.systemNumber] as? NSNumber)?.uint64Value == record.device,
              (attrs[.posixPermissions] as? NSNumber)?.uint64Value == record.permissions,
              attrs[.modificationDate] as? Date == record.modified,
              (try? ScanFileAccess().contentsOfDirectory(atPath: root.url.path)) != nil,
              Self.treeStamp(root, cachePaths: Set(record.items.filter(\.directory).map(\.path))) == record.stamp else { return nil }
        var items: [FileItem] = []
        for cached in record.items {
            guard cached.path == root.url.path || cached.path.hasPrefix(root.url.path + "/"), let item = cached.restored() else { return nil }
            items.append(item)
        }
        return items
    }
    nonisolated func remember(root: ApplicationCacheScanner.DataRoot, items: [FileItem], rules: String, before: CacheEventToken, after: CacheEventToken, beforeStamp: String? = nil, cachePaths: Set<String> = []) {
        guard before == after, before.available, let attrs = InspectionFS.attributes(root.url) else { return }
        let paths = cachePaths.union(items.filter(\.isDirectory).map(\.path))
        guard let stamp = Self.treeStamp(root, cachePaths: paths), beforeStamp == nil || beforeStamp == stamp else { return }
        let record = Root(number: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            device: (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
            permissions: (attrs[.posixPermissions] as? NSNumber)?.uint64Value ?? 0, modified: attrs[.modificationDate] as? Date,
            owner: root.owner, rules: rules, token: after, date: Date(), items: items.map(CachedItem.init), stamp: stamp)
        lock.lock(); state.roots[root.url.path] = record; lock.unlock()
    }
    nonisolated func finish(items: [FileItem], complete: Bool, reused: Int, rescanned: Int, liveRoots: Set<String>, rules: String) {
        lock.lock(); defer { lock.unlock() }
        if state.rules != rules { state.baseline = [:]; state.baselineDate = nil }
        var next: [String: Baseline] = [:]
        for item in items { next[item.path] = Baseline(size: item.size, application: item.cacheApplication?.name ?? "其他应用") }
        var increase: Int64 = 0, decrease: Int64 = 0
        var growth: [String: (bytes: Int64, paths: [String])] = [:]
        for (path, entry) in next {
            let delta = entry.size - (state.baseline[path]?.size ?? 0)
            if delta > 0 { increase += delta; growth[entry.application, default: (0, [])].bytes += delta; growth[entry.application, default: (0, [])].paths.append(path) }
            else { decrease -= delta }
        }
        for (path, entry) in state.baseline where next[path] == nil { decrease += entry.size }
        state.comparison = CacheScanComparison(date: Date(), previousDate: state.baselineDate,
            added: Set(next.keys).subtracting(state.baseline.keys).count, removed: Set(state.baseline.keys).subtracting(next.keys).count,
            increasedBytes: increase, decreasedBytes: decrease, reusedRoots: reused, rescannedRoots: rescanned,
            growth: growth.map { CacheGrowth(application: $0.key, bytes: $0.value.bytes, paths: $0.value.paths.sorted()) }.sorted { $0.bytes > $1.bytes }, complete: complete)
        if complete {
            state.rules = rules; state.baseline = next; state.baselineDate = Date()
            state.roots = state.roots.filter { liveRoots.contains($0.key) && $0.value.rules == rules }
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            failure = nil
        } catch { failure = "扫描索引保存失败：\(error.localizedDescription)" }
    }
}
