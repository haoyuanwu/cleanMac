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
        // 防止允许目录中的符号链接父目录把实际删除位置指向保护范围之外。
        let source = URL(fileURLWithPath: normalized)
        let resolvedParent = source.deletingLastPathComponent().resolvingSymlinksInPath()
        let resolvedPath = resolvedParent.appendingPathComponent(source.lastPathComponent).path
        if SafetyWhitelist.isBlocked(path: resolvedPath) || !isLikelyDeletable(resolvedPath) {
            return Decision(path: path, allowed: false, reason: "实际路径不在可清理范围")
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
            home + "/Applications",
            home + "/.Trash",
            "/Library/Caches",
            "/Library/Logs",
            "/Applications",
        ]
        for prefix in allowedPrefixes {
            if path.hasPrefix(prefix + "/") {
                return true
            }
        }
        // 外接磁盘废纸篓只允许清理当前用户废纸篓中的直接项目。
        let parent = (path as NSString).deletingLastPathComponent
        let components = parent.split(separator: "/")
        if components.count == 4,
           components[0] == "Volumes",
           components[2] == ".Trashes",
           components[3] == String(getuid()) {
            return true
        }
        // 扫描器会列出这些日志目录。系统日志仅允许 /var/log 的直接子目录，
        // 不允许清理日志根目录或任意更深的系统路径。
        if path == home + "/.android/logs" {
            return true
        }
        if ["/var/log", "/private/var/log"].contains(parent) {
            return true
        }
        // 系统缓存单文件可清
        if path.hasPrefix("/System/Library/Caches/") {
            return true
        }
        return false
    }
}
