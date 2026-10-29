import Foundation

/// 只加载随应用发布并通过校验的本地规则；基础版本始终可回退。
final class CacheRuleStore: @unchecked Sendable {
    nonisolated static let shared = CacheRuleStore()
    nonisolated static let didChange = Notification.Name("cleanMac.cacheRulesChanged")
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private let defaults: UserDefaults
    nonisolated private let key: String
    nonisolated let catalogs: [CacheRuleCatalog]
    nonisolated let loadErrors: [String]
    nonisolated(unsafe) private var selectedVersion: String

    nonisolated init(defaults: UserDefaults = .standard, key: String = "com.cleanMac.cacheRules.version", catalogData: [Data]? = nil) {
        self.defaults = defaults
        self.key = key
        var versions = [CacheRuleCatalog.baseline]
        var errors: [String] = []
        let sources: [Data]
        if let catalogData { sources = catalogData }
        else {
            if let url = Bundle.main.url(forResource: "cache-rules-2026.10.28.1", withExtension: "json"),
               let data = try? Data(contentsOf: url) { sources = [data] }
            else { sources = []; errors.append("专用缓存规则未能加载，当前可使用基础名称识别。") }
        }
        for data in sources {
            do {
                let catalog = try CacheRuleCatalog.decode(data)
                guard !versions.contains(where: { $0.version == catalog.version }) else {
                    errors.append("重复的规则版本已跳过。"); continue
                }
                versions.append(catalog)
            } catch { errors.append("规则校验失败：\(error.localizedDescription)") }
        }
        catalogs = versions
        let saved = defaults.string(forKey: key)
        if let saved, versions.contains(where: { $0.version == saved }) { selectedVersion = saved }
        else {
            selectedVersion = saved == nil ? versions.last!.version : CacheRuleCatalog.baseline.version
            if saved != nil { errors.append("原规则版本不可用，已回退到基础名称识别。") }
        }
        loadErrors = errors
    }

    nonisolated var activeCatalog: CacheRuleCatalog {
        lock.lock(); defer { lock.unlock() }
        return catalogs.first { $0.version == selectedVersion } ?? .baseline
    }

    nonisolated func activate(_ version: String) {
        lock.lock()
        guard catalogs.contains(where: { $0.version == version }), selectedVersion != version else { lock.unlock(); return }
        selectedVersion = version
        defaults.set(version, forKey: key)
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
