import Foundation

/// 重复文件检测：按大小预分组，再哈希比对
enum DuplicateFileScanner {
    struct DuplicateGroup: Identifiable, Sendable {
        let id: String
        let size: Int64
        let hash: String
        let files: [FileItem]

        var sizeFormatted: String { FileSizeFormatter.string(fromByteCount: size) }
        var wastedSize: Int64 {
            guard files.count > 1 else { return 0 }
            return size * Int64(files.count - 1)
        }
        var wastedSizeFormatted: String { FileSizeFormatter.string(fromByteCount: wastedSize) }
    }

    /// 在给定根目录下扫描重复文件
    static func findDuplicates(
        roots: [String],
        minSize: Int64 = 1_000_000,
        limitPerRoot: Int = 4000
    ) async -> [DuplicateGroup] {
        let worker = Task.detached(priority: .userInitiated) { () -> [DuplicateGroup] in
            let fm = FileManager.default
            var candidatesBySize: [Int64: [(path: String, name: String, date: Date?)]] = [:]

            for root in roots {
                if Task.isCancelled { return [] }
                let rootURL = URL(fileURLWithPath: root)
                guard let enumerator = fm.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                var scanned = 0
                // 在非 async 上下文中迭代 DirectoryEnumerator
                while scanned < limitPerRoot && !Task.isCancelled {
                    guard let url = enumerator.nextObject() as? URL else { break }
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                    guard values?.isRegularFile == true else { continue }
                    let size = Int64(values?.fileSize ?? 0)
                    guard size >= minSize else { continue }
                    scanned += 1
                    candidatesBySize[size, default: []].append(
                        (url.path, url.lastPathComponent, values?.contentModificationDate)
                    )
                }
            }

            var groups: [DuplicateGroup] = []
            for (size, list) in candidatesBySize where list.count > 1 {
                if Task.isCancelled { return [] }
                var byHash: [String: [String]] = [:]
                var nameByPath: [String: String] = [:]
                var dateByPath: [String: Date?] = [:]

                for item in list {
                    if Task.isCancelled { return [] }
                    nameByPath[item.path] = item.name
                    dateByPath[item.path] = item.date
                    if let hash = fileHash(at: item.path) {
                        byHash[hash, default: []].append(item.path)
                    }
                }

                for (hash, paths) in byHash where paths.count > 1 {
                    let files = paths.map { path in
                        FileItem(
                            path: path,
                            name: nameByPath[path] ?? (path as NSString).lastPathComponent,
                            size: size,
                            modificationDate: dateByPath[path] ?? nil,
                            isDirectory: false
                        )
                    }
                    .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }

                    groups.append(
                        DuplicateGroup(
                            id: hash,
                            size: size,
                            hash: hash,
                            files: files
                        )
                    )
                }
            }

            return groups.sorted { ($0.size * Int64(max(0, $0.files.count - 1))) > ($1.size * Int64(max(0, $1.files.count - 1))) }
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// 文件内容哈希（先读头 1MB + 尾 1MB，足够区分重复副本）
    nonisolated static func fileHash(at path: String) -> String? {
        let handle = FileHandle(forReadingAtPath: path)
        defer { try? handle?.close() }
        guard let handle else { return nil }

        var data = Data()
        if let head = try? handle.read(upToCount: 1 << 20) {
            data.append(head)
        }
        if let size = try? handle.seekToEnd(), size > 2 << 20 {
            try? handle.seek(toOffset: size - (1 << 20))
            if let tail = try? handle.read(upToCount: 1 << 20) {
                data.append(tail)
            }
        }

        var hash: UInt64 = 5381
        for b in data {
            hash = 127 &* hash &+ UInt64(b)
        }
        return String(format: "%llx_%d", hash, data.count)
    }

    /// 删除重复（保留 keep，删除其余）
    nonisolated static func removeDuplicates(keep: FileItem, remove: [FileItem]) -> (removed: Int, failed: Int) {
        var removed = 0
        var failed = 0
        for file in remove where file.path != keep.path {
            let decision = DeleteDryRun.validate(path: file.path, context: "dedupe")
            guard decision.allowed else {
                failed += 1
                continue
            }
            do {
                try FileManager.default.removeItem(atPath: file.path)
                removed += 1
                AppLog.info("dedupe removed", metadata: ["path": file.path])
            } catch {
                failed += 1
                AppLog.error("dedupe failed", metadata: ["path": file.path, "error": error.localizedDescription])
            }
        }
        return (removed, failed)
    }
}
