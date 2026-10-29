import Foundation

/// 磁盘浏览与清理选择分离；未知系统数据默认只允许浏览。
enum DiskMapSelectionPolicy {
    nonisolated static func protectionReason(for path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String? {
        guard path.hasPrefix("/") else { return "虚拟目录，仅供浏览" }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let normalized = url.path
        let resolved = url.resolvingSymlinksInPath().path
        for candidate in Set([normalized, resolved]) {
            let systemRoots = ["/System", "/usr", "/bin", "/sbin", "/etc", "/var", "/opt", "/private", "/dev", "/cores", "/Volumes"]
            if systemRoots.contains(where: { candidate == $0 || candidate.hasPrefix($0 + "/") }) {
                return "系统关键目录，仅供浏览"
            }
            if candidate == "/" || candidate == "/Users" || candidate == "/Applications" || candidate == "/Library" {
                return "系统基础目录，不可整体选择"
            }
            let userRoots = [home, home + "/Library", home + "/Applications", home + "/Desktop", home + "/Documents",
                             home + "/Downloads", home + "/Pictures", home + "/Movies", home + "/Music"]
            if userRoots.contains(candidate) { return "用户基础目录，不可整体选择" }
            if candidate.hasPrefix("/Library/") || candidate.hasPrefix(home + "/Library/") {
                let cacheRoots = ["/Library/Caches", "/Library/Logs", home + "/Library/Caches", home + "/Library/Logs"]
                if !cacheRoots.contains(where: { candidate.hasPrefix($0 + "/") }) {
                    return "应用或系统资源库数据，仅供浏览"
                }
                if cacheRoots.contains(candidate) { return "资源库基础目录，不可整体选择" }
            }
            let components = URL(fileURLWithPath: candidate).pathComponents
            if let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }), index < components.count - 1 {
                return "应用程序内部资源，不可单独选择"
            }
            if SafetyWhitelist.isBlocked(path: candidate) || SafetyWhitelist.isProtectedApp(path: candidate) {
                return "受保护的系统项目"
            }
            if UserWhitelist.isWhitelisted(candidate) { return "已加入白名单保护" }
        }
        return nil
    }
}
