import AppKit

/// 扫描时记录归属，避免根据 Cache 等通用文件夹名称推测软件。
enum BrowserCacheApplication: String, CaseIterable, Sendable {
    case safari, chrome, firefox, edge

    nonisolated var name: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .firefox: return "Firefox"
        case .edge: return "Microsoft Edge"
        }
    }

    nonisolated var bundleIdentifier: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .firefox: return "org.mozilla.firefox"
        case .edge: return "com.microsoft.edgemac"
        }
    }

    nonisolated var cacheApplication: CacheApplication {
        CacheApplication(id: bundleIdentifier, name: name, path: nil)
    }
}
