import Foundation

/// 删除前二次校验（dry-run）
enum DeleteDryRun {
    struct Decision: Equatable {
        let path: String
        let allowed: Bool
        let reason: String
    }

    /// 校验是否允许删除；写入日志
    nonisolated static func validate(path: String, context: String = "delete") -> Decision {
        let normalized = SafetyWhitelist.normalizeForCompare(path)

        if normalized.isEmpty {
            return Decision(path: path, allowed: false, reason: "空路径")
        }
        if normalized == "/" {
            return Decision(path: path, allowed: false, reason: "根目录")
        }
        if SafetyWhitelist.isBlocked(path: normalized) {
            return Decision(path: path, allowed: false, reason: "命中安全白名单")
        }
        if UserWhitelist.isWhitelisted(normalized) {
            return Decision(path: path, allowed: false, reason: "用户白名单保护")
        }
        if SafetyWhitelist.isProtectedApp(path: normalized) {
            return Decision(path: path, allowed: false, reason: "受保护系统应用")
        }
        // 仅允许删除用户可写或明确清理范围内的路径
        if !isLikelyDeletable(normalized) {
            return Decision(path: path, allowed: false, reason: "路径不在可清理范围")
        }

        AppLog.debug("dry-run allow", metadata: ["path": normalized, "context": context])
        return Decision(path: path, allowed: true, reason: "ok")
    }

    nonisolated static func validate(items: [FileItem], context: String = "batch") -> (allowed: [FileItem], blocked: [(FileItem, String)]) {
        var allowed: [FileItem] = []
        var blocked: [(FileItem, String)] = []
        for item in items {
            let decision = validate(path: item.path, context: context)
            if decision.allowed {
                allowed.append(item)
            } else {
                blocked.append((item, decision.reason))
                AppLog.warn("dry-run block", metadata: [
                    "path": item.path,
                    "reason": decision.reason
                ])
            }
        }
        return (allowed, blocked)
    }

    /// 是否落在常见可清理位置
    private nonisolated static func isLikelyDeletable(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let allowedPrefixes = [
            home + "/Library",
            home + "/Downloads",
            home + "/Desktop",
            home + "/Documents",
            home + "/Movies",
            home + "/Music",
            home + "/Pictures",
            home + "/.Trash",
            "/Library/Caches",
            "/Library/Logs",
            "/var/folders",
            "/Applications",
        ]
        for prefix in allowedPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") {
                return true
            }
        }
        // 系统缓存单文件可清
        if path.hasPrefix("/System/Library/Caches/") {
            return true
        }
        return false
    }
}
