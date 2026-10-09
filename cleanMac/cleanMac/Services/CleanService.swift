import Foundation

struct EmptyTrashOutcome: Sendable {
    let cleanedBytes: Int64
    let failedCount: Int
}

/// 文件清理服务
class CleanService {
    private let fileManager = FileManager.default
    
    /// 清理指定文件列表（删除前 dry-run 二次校验）
    func clean(items: [FileItem], category: ScanCategory) async throws -> Int64 {
        var totalCleaned: Int64 = 0
        let validated = DeleteDryRun.validate(items: items, context: "clean-\(category.rawValue)")

        for item in validated.allowed {
            do {
                if category.requiresPrivileges && (item.path.hasPrefix("/Library") || item.path.hasPrefix("/System")) {
                    try cleanWithPrivileges(path: item.path)
                } else {
                    try fileManager.removeItem(atPath: item.path)
                }
                totalCleaned += item.size
                AppLog.info("cleaned", metadata: ["path": item.path, "size": "\(item.size)"])
            } catch {
                AppLog.error("clean failed", metadata: ["path": item.path, "error": error.localizedDescription])
            }
        }

        for (item, reason) in validated.blocked {
            AppLog.warn("clean skipped", metadata: ["path": item.path, "reason": reason])
        }

        return totalCleaned
    }
    
    /// 清理单个文件
    func cleanSingle(item: FileItem, requiresPrivileges: Bool = false) throws {
        let decision = DeleteDryRun.validate(path: item.path, context: "cleanSingle")
        guard decision.allowed else {
            AppLog.warn("cleanSingle blocked", metadata: ["path": item.path, "reason": decision.reason])
            return
        }
        if requiresPrivileges {
            try cleanWithPrivileges(path: item.path)
        } else {
            try fileManager.removeItem(atPath: item.path)
        }
    }
    
    /// 清空废纸篓
    func emptyTrash(items: [FileItem]) async -> EmptyTrashOutcome {
        await Task.detached(priority: .utility) {
            var cleanedBytes: Int64 = 0
            var failedCount = 0
            for item in items {
                guard isDirectTrashEntry(item.path), !UserWhitelist.isWhitelisted(item.path) else {
                    failedCount += 1
                    AppLog.warn("trash delete blocked", metadata: ["path": item.path])
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: URL(fileURLWithPath: item.path))
                    cleanedBytes += item.size
                } catch {
                    failedCount += 1
                    AppLog.warn("trash delete failed", metadata: ["path": item.path, "error": error.localizedDescription])
                }
            }
            return EmptyTrashOutcome(cleanedBytes: cleanedBytes, failedCount: failedCount)
        }.value
    }
    
    /// 使用管理员权限清理
    private func cleanWithPrivileges(path: String) throws {
        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        try ShellExecutor.execute("rm -rf \"\(escapedPath)\"", asRoot: true)
    }
}

/// 只允许删除扫描所得废纸篓根目录下的直接子项，绝不删除废纸篓根目录本身。
nonisolated private func isDirectTrashEntry(_ path: String) -> Bool {
    let parent = (SafetyWhitelist.normalizeForCompare(path) as NSString).deletingLastPathComponent
    let homeTrashPath = FileManager.default.homeDirectoryForCurrentUser.path + "/.Trash"
    let homeTrash = (homeTrashPath as NSString).standardizingPath
    if parent == homeTrash { return true }

    let components = parent.split(separator: "/")
    return components.count == 4
        && components[0] == "Volumes"
        && components[2] == ".Trashes"
        && components[3] == String(getuid())
}
