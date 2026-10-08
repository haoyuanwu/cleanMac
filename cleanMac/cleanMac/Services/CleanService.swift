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
        var cleanedBytes: Int64 = 0
        var failedCount = 0
        for item in items {
            do {
                try fileManager.removeItem(at: item.pathURL)
                cleanedBytes += item.size
            } catch {
                failedCount += 1
            }
        }
        return EmptyTrashOutcome(cleanedBytes: cleanedBytes, failedCount: failedCount)
    }
    
    /// 使用管理员权限清理
    private func cleanWithPrivileges(path: String) throws {
        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        try ShellExecutor.execute("rm -rf \"\(escapedPath)\"", asRoot: true)
    }
}
