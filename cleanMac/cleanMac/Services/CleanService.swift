import Foundation

struct EmptyTrashOutcome: Sendable {
    let cleanedBytes: Int64
    let failedCount: Int
    let failureDetails: [String]
}

struct CleanOutcome: Sendable {
    let cleanedBytes: Int64
    let removedPaths: Set<String>
    let failures: [String: String]
}

/// 文件清理服务
class CleanService {
    private let fileManager = FileManager.default
    
    /// 同一批次的受保护缓存和日志只触发一次管理员授权。
    func clean(items: [FileItem], category: ScanCategory) async -> CleanOutcome {
        await cleanBatch([(category, items)])
    }

    func cleanBatch(_ groups: [(ScanCategory, [FileItem])]) async -> CleanOutcome {
        let owned = ScanPathOwnership.unique(groups)
        let items = owned.map { $0.1 }
        let categories = Dictionary(uniqueKeysWithValues: owned.map { ($0.1.path, $0.0) })
        return await Task.detached(priority: .userInitiated) {
            CleanService.performClean(items, categories: categories)
        }.value
    }

    private nonisolated static func performClean(_ items: [FileItem], categories: [String: ScanCategory]) -> CleanOutcome {
        let fileManager = FileManager.default
        let validated = DeleteDryRun.validate(items: items, context: "clean-batch")
        var removedPaths = Set<String>()
        var failures = Dictionary(uniqueKeysWithValues: validated.blocked.map { ($0.0.path, $0.1) })
        var privilegedPaths: [String] = []
        var alreadyMissing = Set<String>()

        for item in validated.allowed {
            do {
                if categories[item.path] == .trash {
                    guard isDirectTrashEntry(item.path) else { throw CocoaError(.fileWriteNoPermission) }
                    try fileManager.removeItem(atPath: item.path)
                    CleaningHistoryStore.shared.record(path: item.path, size: item.size, category: ScanCategory.trash.rawValue, state: .permanentlyDeleted)
                } else {
                    try CleaningHistoryStore.shared.moveToTrash(path: item.path, size: item.size,
                        category: categories[item.path]?.rawValue ?? "清理")
                }
                removedPaths.insert(item.path)
            } catch {
                if isRemovalMissingError(error) {
                    alreadyMissing.insert(item.path)
                    CleaningHistoryStore.shared.record(path: item.path, size: item.size, category: categories[item.path]?.rawValue ?? "清理", state: .alreadyMissing)
                    removedPaths.insert(item.path)
                } else if isRemovalPermissionError(error), PrivilegedRemovalService.isSupported(item.path) {
                    privilegedPaths.append(item.path)
                } else {
                    failures[item.path] = error.localizedDescription
                }
            }
        }
        if !privilegedPaths.isEmpty {
            let permanent = privilegedPaths.filter { categories[$0] == .trash }
            let recoverable = privilegedPaths.filter { categories[$0] != .trash }
            let elevated = PrivilegedTrashService.moveToTrash(paths: recoverable)
            for path in recoverable {
                let outcome = elevated[path]
                if outcome?.succeeded == true { removedPaths.insert(path) }
                else { failures[path] = outcome?.message ?? "无法移到废纸篓。" }
                CleaningHistoryStore.shared.record(path: path, size: items.first { $0.path == path }?.size ?? 0,
                    category: categories[path]?.rawValue ?? "清理", state: outcome?.succeeded == true ? .movedToTrash : .failed,
                    trashPath: outcome?.trashPath, message: outcome?.message)
            }
            let deleted = PrivilegedRemovalService.remove(paths: permanent)
            removedPaths.formUnion(deleted.removedPaths)
            failures.merge(deleted.failures) { _, new in new }
            for path in permanent {
                CleaningHistoryStore.shared.record(path: path, size: items.first { $0.path == path }?.size ?? 0,
                    category: ScanCategory.trash.rawValue, state: deleted.removedPaths.contains(path) ? .permanentlyDeleted : .failed,
                    message: deleted.failures[path])
            }
        }
        for item in items {
            if let reason = failures[item.path] {
                CleaningHistoryStore.shared.record(path: item.path, size: item.size, category: categories[item.path]?.rawValue ?? "清理", state: .failed, message: reason)
                AppLog.error("clean failed", metadata: ["path": item.path, "error": reason])
            } else if removedPaths.contains(item.path) {
                AppLog.info("cleaned", metadata: ["path": item.path, "size": "\(item.size)"])
            }
        }
        return CleanOutcome(
            cleanedBytes: items.filter { removedPaths.contains($0.path) && !alreadyMissing.contains($0.path) }.reduce(0) { $0 + $1.size },
            removedPaths: removedPaths,
            failures: failures
        )
    }
    
    /// 清理单个文件
    func cleanSingle(item: FileItem) throws {
        let decision = DeleteDryRun.validate(path: item.path, context: "cleanSingle")
        guard decision.allowed else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: decision.reason])
        }
        try CleaningHistoryStore.shared.moveToTrash(path: item.path, size: item.size, category: "单项清理")
    }
    
    /// 清空废纸篓
    func emptyTrash(items: [FileItem]) async -> EmptyTrashOutcome {
        await Task.detached(priority: .utility) {
            var cleanedBytes: Int64 = 0
            var failures: [String: String] = [:]
            var privilegedPaths: [String] = []
            var alreadyMissing = Set<String>()
            for item in items {
                guard isDirectTrashEntry(item.path), !UserWhitelist.isWhitelisted(item.path) else {
                    failures[item.path] = "路径不在可清理的废纸篓范围，或已加入白名单。"
                    AppLog.warn("trash delete blocked", metadata: ["path": item.path])
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: URL(fileURLWithPath: item.path))
                    cleanedBytes += item.size
                } catch {
                    if isRemovalMissingError(error) {
                        alreadyMissing.insert(item.path)
                    } else if isRemovalPermissionError(error) {
                        privilegedPaths.append(item.path)
                    } else {
                        failures[item.path] = error.localizedDescription
                    }
                }
            }
            if !privilegedPaths.isEmpty {
                let elevated = PrivilegedRemovalService.remove(paths: privilegedPaths)
                cleanedBytes += items.filter { elevated.removedPaths.contains($0.path) }
                    .reduce(0) { $0 + $1.size }
                failures.merge(elevated.failures) { _, new in new }
            }
            for item in items {
                CleaningHistoryStore.shared.record(path: item.path, size: item.size, category: ScanCategory.trash.rawValue,
                    state: failures[item.path] != nil ? .failed : alreadyMissing.contains(item.path) ? .alreadyMissing : .permanentlyDeleted,
                    message: failures[item.path])
            }
            for (path, reason) in failures {
                AppLog.warn("trash delete failed", metadata: ["path": path, "error": reason])
            }
            return EmptyTrashOutcome(
                cleanedBytes: cleanedBytes,
                failedCount: failures.count,
                failureDetails: failures.sorted { $0.key < $1.key }
                    .map { "\($0.key)：\($0.value)" }
            )
        }.value
    }
    
}

nonisolated func isRemovalMissingError(_ error: Error) -> Bool {
    let ns = error as NSError
    return (ns.domain == NSCocoaErrorDomain && [4, 260].contains(ns.code))
        || (ns.domain == NSPOSIXErrorDomain && ns.code == 2)
}

nonisolated func isRemovalPermissionError(_ error: Error) -> Bool {
    let ns = error as NSError
    if (ns.domain == NSCocoaErrorDomain && [257, 513].contains(ns.code))
        || (ns.domain == NSPOSIXErrorDomain && [1, 13].contains(ns.code))
    { return true }
    if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
        return isRemovalPermissionError(underlying)
    }
    let message = ns.localizedDescription.lowercased()
    return ["permission", "not permitted", "access denied", "权限", "不允许访问"]
        .contains { message.contains($0) }
}

enum PrivilegedRemovalService {
    struct Outcome: Sendable {
        let removedPaths: Set<String>
        let failures: [String: String]
    }

    /// 仅允许扫描器展示的系统缓存、日志和当前用户废纸篓的直接子项。
    nonisolated static func isSupported(_ path: String) -> Bool {
        isDirectTrashEntry(path) || PrivilegedTrashService.isSupportedItem(path)
    }

    nonisolated static func remove(paths: [String]) -> Outcome {
        let fm = FileManager.default
        var failures: [String: String] = [:]
        let accepted = Set(paths).filter { path in
            let allowed = isSupported(path) && DeleteDryRun.validate(path: path, context: "privileged-clean").allowed
            if !allowed { failures[path] = "路径不在可提权清理范围。" }
            return allowed
        }
        guard !accepted.isEmpty else { return Outcome(removedPaths: [], failures: failures) }

        let script = """
        on run argv
            set commandText to "set -f; "
            repeat with sourcePath in argv
                set commandText to commandText & "/bin/rm -rf " & quoted form of sourcePath & " 2>&1; "
            end repeat
            set commandText to commandText & "/usr/bin/true"
            do shell script commandText with administrator privileges
        end run
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + accepted.sorted()
        process.standardOutput = output
        process.standardError = output
        var detail: String?
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                detail = String(message.prefix(300))
            } else if process.terminationStatus != 0 {
                detail = "管理员授权未完成。"
            }
        } catch {
            detail = error.localizedDescription
        }

        var removed = Set<String>()
        for path in accepted {
            if fm.fileExists(atPath: path) {
                failures[path] = detail ?? "管理员授权后仍未能删除。"
            } else {
                removed.insert(path)
            }
        }
        return Outcome(removedPaths: removed, failures: failures)
    }
}

/// 只允许删除扫描所得废纸篓根目录下的直接子项，绝不删除废纸篓根目录本身。
nonisolated func isDirectTrashEntry(_ path: String) -> Bool {
    let source = URL(fileURLWithPath: path).standardizedFileURL
    let parent = source.deletingLastPathComponent().path
    let resolvedParent = source.deletingLastPathComponent().resolvingSymlinksInPath().path
    let homeTrashPath = FileManager.default.homeDirectoryForCurrentUser.path + "/.Trash"
    let homeTrash = (homeTrashPath as NSString).standardizingPath
    if parent == homeTrash { return resolvedParent == homeTrash }

    let components = parent.split(separator: "/")
    return resolvedParent == parent
        && components.count == 4
        && components[0] == "Volumes"
        && components[2] == ".Trashes"
        && components[3] == String(getuid())
}
