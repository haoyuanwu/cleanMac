import Foundation
import CryptoKit

nonisolated enum CacheDataRootKind: String, Codable, Sendable { case applicationSupport, caches, container, groupContainer }

nonisolated struct CacheRule: Codable, Identifiable, Sendable {
    enum Risk: String, Codable, Sendable {
        case caution, sensitive
        nonisolated var level: FileRiskLevel { self == .caution ? .caution : .sensitive }
    }
    let id: String
    let title: String
    let bundleIdentifiers: [String]
    let rootKinds: [CacheDataRootKind]
    let relativePaths: [String]
    let reason: String
    let impact: String
    let risk: Risk
    let sources: [String]
}

nonisolated struct CacheRuleMatch: Codable, Sendable {
    let ruleID: String
    let version: String
    let title: String
    let reason: String
    let impact: String
    let risk: FileRiskLevel
    let dataRootPath: String
    let relativePath: String
    let rootKind: CacheDataRootKind
}

nonisolated struct CacheRuleCatalog: Codable, Sendable {
    let schemaVersion: Int
    let version: String
    let title: String
    let rules: [CacheRule]

    nonisolated static let baseline = CacheRuleCatalog(schemaVersion: 1, version: "2026.10.28.0", title: "基础名称识别", rules: [])
    nonisolated var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data(version.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func decode(_ data: Data) throws -> CacheRuleCatalog {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1, !catalog.version.isEmpty, !catalog.title.isEmpty else {
            throw validationError("不支持的规则格式或缺少版本信息。")
        }
        var ids = Set<String>()
        for rule in catalog.rules {
            guard !rule.id.isEmpty, ids.insert(rule.id).inserted, !rule.title.isEmpty,
                  !rule.reason.isEmpty, !rule.impact.isEmpty, !rule.bundleIdentifiers.isEmpty,
                  rule.bundleIdentifiers.allSatisfy({ !$0.isEmpty && !$0.contains("*") && $0.contains(".") }),
                  !rule.rootKinds.isEmpty, !rule.relativePaths.isEmpty, !rule.sources.isEmpty,
                  rule.sources.allSatisfy({ URL(string: $0)?.scheme == "https" && URL(string: $0)?.host != nil }),
                  rule.relativePaths.allSatisfy({ isValidRelativePath($0, kinds: rule.rootKinds) }) else {
                throw validationError("规则 \(rule.id) 缺少说明、归属或包含不允许的路径。")
            }
        }
        return catalog
    }

    nonisolated static func isValidRelativePath(_ path: String, kinds: [CacheDataRootKind]) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let protected = Set(["documents", "downloads", "desktop", "pictures", "movies", "music",
                             "local storage", "session storage", "indexeddb", "cookies", "login data", "preferences", "backups"])
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.contains("*"), !path.contains("?"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".."
                  && !$0.lowercased().hasSuffix(".app") && !protected.contains($0.lowercased()) }) else { return false }
        // 单独的 Storage 可能包含离线内容；仅允许标准缓存根内的精确目标。
        if parts.contains(where: { $0.lowercased() == "storage" }), kinds.contains(where: { $0 != .caches }) { return false }
        return true
    }

    nonisolated private static func validationError(_ message: String) -> NSError {
        NSError(domain: "cleanMac.cacheRules", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// 精确路径，不支持通配符；逐级拒绝符号链接、软件包和越界目录。
enum CacheRuleMatcher {
    /// 沙盒容器的 bundle ID 可能以 .app 结尾，不能仅凭后缀把它当成应用包。
    nonisolated static func isApplicationResourceRoot(_ url: URL, kind: CacheDataRootKind) -> Bool {
        let components = url.pathComponents
        let parent = url.deletingLastPathComponent().lastPathComponent
        let containerRoot = (kind == .container && parent == "Containers")
            || (kind == .groupContainer && parent == "Group Containers")
        for (index, component) in components.enumerated() where component.lowercased().hasSuffix(".app") {
            if containerRoot, index == components.count - 1,
               !FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents").path) { continue }
            return true
        }
        return false
    }

    nonisolated static func isWithinRecordedRoot(_ item: FileItem) -> Bool {
        guard let match = item.cacheRuleMatch else { return true }
        let root = URL(fileURLWithPath: match.dataRootPath).standardizedFileURL
        return validatedURL(root: root, relative: match.relativePath, kind: match.rootKind)?.path
            == URL(fileURLWithPath: item.path).standardizedFileURL.path
    }

    nonisolated private static func validatedURL(root: URL, relative: String, kind: CacheDataRootKind) -> URL? {
        guard CacheRuleCatalog.isValidRelativePath(relative, kinds: [kind]),
              root.resolvingSymlinksInPath().path == root.path,
              !isApplicationResourceRoot(root, kind: kind) else { return nil }
        var candidate = root
        for component in relative.split(separator: "/") {
            candidate.appendPathComponent(String(component))
            guard let values = try? ScanContext.values(candidate, keys: [.isSymbolicLinkKey, .isPackageKey, .isDirectoryKey]),
                  values.isSymbolicLink != true, values.isPackage != true, values.isDirectory == true,
                  candidate.resolvingSymlinksInPath().path == candidate.path else { return nil }
        }
        return candidate.path.hasPrefix(root.path + "/") ? candidate : nil
    }

    nonisolated static func matches(in root: ApplicationCacheScanner.DataRoot, catalog: CacheRuleCatalog) -> [String: CacheRuleMatch] {
        let rootURL = root.url.standardizedFileURL
        guard rootURL.resolvingSymlinksInPath().path == rootURL.path,
              !isApplicationResourceRoot(rootURL, kind: root.kind) else { return [:] }
        var matches: [String: CacheRuleMatch] = [:]
        for rule in catalog.rules where rule.bundleIdentifiers.contains(root.owner.id) && rule.rootKinds.contains(root.kind) {
            for relative in rule.relativePaths {
                if Task.isCancelled { return matches }
                guard CacheRuleCatalog.isValidRelativePath(relative, kinds: rule.rootKinds) else { continue }
                guard let candidate = validatedURL(root: rootURL, relative: relative, kind: root.kind) else { continue }
                let match = CacheRuleMatch(ruleID: rule.id, version: catalog.version, title: rule.title,
                                           reason: rule.reason, impact: rule.impact, risk: rule.risk.level,
                                           dataRootPath: rootURL.path, relativePath: relative, rootKind: root.kind)
                if let existing = matches[candidate.path], existing.risk >= match.risk { continue }
                matches[candidate.path] = match
            }
        }
        return matches
    }
}
