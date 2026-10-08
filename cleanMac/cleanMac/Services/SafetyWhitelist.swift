import Foundation

/// 文件风险分级：决定默认是否可一键清理、是否阻止删除
enum FileRiskLevel: Int, Comparable, Sendable, Hashable {
    /// 低风险：缓存、日志等可安全清理
    case safe = 0
    /// 中风险：下载、安装包等用户文件，需确认
    case caution = 1
    /// 高风险：可能影响系统/正在使用，默认不勾选
    case sensitive = 2
    /// 禁止：系统关键路径，永不提供删除
    case blocked = 3

    nonisolated static func < (lhs: FileRiskLevel, rhs: FileRiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .safe: return "可安全清理"
        case .caution: return "请确认"
        case .sensitive: return "谨慎"
        case .blocked: return "已保护"
        }
    }
}

/// 安全白名单：路径保护与风险分级
enum SafetyWhitelist {
    /// 绝对禁止删除的前缀
    nonisolated(unsafe) static let blockedPrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/private/etc",
        "/Library/Apple",
        "/Library/Security",
        "/Applications/Utilities/Terminal.app",
        "/Applications/Utilities/Activity Monitor.app",
        "/Applications/System Settings.app",
        "/Applications/Safari.app",
        "/System/Applications",
        "/Volumes/Macintosh HD",
    ]

    /// 禁止删除的精确路径（常见系统缓存虽可清但不整树删）
    nonisolated(unsafe) static let blockedExactPaths: Set<String> = [
        "/Library/Caches",
        "/System/Library/Caches",
        "/var/log",
        "/Library/Logs",
    ]

    /// 系统应用 bundle id / 名称（卸载保护）
    nonisolated(unsafe) static let protectedAppNames: Set<String> = [
        "Safari.app",
        "Mail.app",
        "Messages.app",
        "Maps.app",
        "Photos.app",
        "Notes.app",
        "Reminders.app",
        "Calendar.app",
        "Contacts.app",
        "FaceTime.app",
        "Podcasts.app",
        "TV.app",
        "Music.app",
        "News.app",
        "Stocks.app",
        "Wallet.app",
        "Calculator.app",
        "Preview.app",
        "System Settings.app",
        "Terminal.app",
        "Activity Monitor.app",
        "Disk Utility.app",
        "Script Editor.app",
        "Archive Utility.app",
        "Keychain Access.app",
        "Boot Camp Assistant.app",
        "Migration Assistant.app",
        "VoiceOver Utility.app",
    ]

    /// 是否为受保护系统应用
    nonisolated static func isProtectedApp(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if protectedAppNames.contains(name) { return true }
        // /System/Applications 与系统附带工具
        if path.hasPrefix("/System/Applications") { return true }
        if path.hasPrefix("/Applications/Utilities") {
            return ["Terminal.app", "Activity Monitor.app", "Disk Utility.app", "Script Editor.app"].contains(name)
        }
        return false
    }

    /// 路径是否绝对禁止删除
    nonisolated static func isBlocked(path: String) -> Bool {
        let normalized = normalize(path)
        for prefix in blockedPrefixes {
            if normalized == normalize(prefix) || normalized.hasPrefix(normalize(prefix) + "/") {
                // 允许删除 /System/Library/Caches 下的单个缓存项，但不允许删根目录
                if normalized.hasPrefix("/System/Library/Caches") {
                    return normalized == "/System/Library/Caches"
                }
                return true
            }
        }
        if blockedExactPaths.contains(normalized) { return true }
        return false
    }

    /// 风险分级
    nonisolated static func riskLevel(for path: String, category: ScanCategory) -> FileRiskLevel {
        let normalized = normalize(path)

        if isBlocked(path: normalized) || isProtectedApp(path: normalized) {
            return .blocked
        }

        switch category {
        case .systemCache, .logFiles, .browserCache, .appLeftover, .trash:
            // 系统级目录下的缓存降为 sensitive，用户目录缓存为 safe
            if normalized.hasPrefix("/Library") || normalized.hasPrefix("/var") {
                return .sensitive
            }
            return .safe

        case .downloads, .installers, .largeFiles:
            return .caution

        case .applications:
            return isProtectedApp(path: normalized) ? .blocked : .caution
        }
    }

    /// 是否允许进入一键清理推荐集
    nonisolated static func isRecommendedForAutoClean(_ risk: FileRiskLevel) -> Bool {
        risk == .safe
    }

    /// 是否允许删除
    nonisolated static func canDelete(path: String) -> Bool {
        !isBlocked(path: path) && !UserWhitelist.isWhitelisted(path)
    }

    /// 过滤可删除项
    nonisolated static func filterDeletable(_ items: [FileItem]) -> [FileItem] {
        items.filter { canDelete(path: $0.path) }
    }

    /// 为 FileItem 附加风险（在创建时调用）
    nonisolated static func annotated(_ item: FileItem, category: ScanCategory) -> FileItem {
        var copy = item
        copy.riskLevel = riskLevel(for: item.path, category: category)
        return copy
    }

    /// 路径规范化（对外供 dry-run 使用）
    nonisolated static func normalizeForCompare(_ path: String) -> String {
        normalize(path)
    }

    private nonisolated static func normalize(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") {
            p.removeLast()
        }
        return (p as NSString).standardizingPath
    }
}
