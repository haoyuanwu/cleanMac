import Foundation

/// 用户自定义白名单（永不清理 / 卸载）
enum UserWhitelist {
    nonisolated(unsafe) private static let defaultsKey = "com.cleanMac.userWhitelist.paths"

    nonisolated(unsafe) private static let queue = DispatchQueue(label: "com.cleanMac.userWhitelist")

    nonisolated static var paths: Set<String> {
        queue.sync {
            let list = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
            return Set(list.map { SafetyWhitelist.normalizeForCompare($0) })
        }
    }

    nonisolated static func contains(_ path: String) -> Bool {
        let normalized = SafetyWhitelist.normalizeForCompare(path)
        return queue.sync {
            let list = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
            return list.map { SafetyWhitelist.normalizeForCompare($0) }.contains(normalized)
        }
    }

    nonisolated static func add(_ path: String) {
        let normalized = SafetyWhitelist.normalizeForCompare(path)
        queue.sync {
            var list = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
            list.insert(normalized)
            UserDefaults.standard.set(Array(list).sorted(), forKey: defaultsKey)
        }
        AppLog.info("whitelist add", metadata: ["path": normalized])
    }

    nonisolated static func remove(_ path: String) {
        let normalized = SafetyWhitelist.normalizeForCompare(path)
        queue.sync {
            var list = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
            list.remove(normalized)
            UserDefaults.standard.set(Array(list).sorted(), forKey: defaultsKey)
        }
        AppLog.info("whitelist remove", metadata: ["path": normalized])
    }

    /// 命中用户白名单（前缀匹配：加文件夹可保护其下文件）
    nonisolated static func isWhitelisted(_ path: String) -> Bool {
        let normalized = SafetyWhitelist.normalizeForCompare(path)
        let list = paths
        if list.contains(normalized) { return true }
        for entry in list {
            if normalized.hasPrefix(entry + "/") { return true }
        }
        return false
    }

    /// 过滤掉白名单项
    nonisolated static func filterOut(_ items: [FileItem]) -> [FileItem] {
        items.filter { !isWhitelisted($0.path) }
    }

    /// 全部路径（已规范化、排序）
    nonisolated static func allEntries() -> [String] {
        Array(paths).sorted()
    }

    /// 计算单条路径占用（文件或目录）
    nonisolated static func size(of path: String) -> Int64 {
        let normalized = SafetyWhitelist.normalizeForCompare(path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue {
            return FileHelper.directorySize(normalized)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: normalized)
        return (attrs?[.size] as? Int64) ?? 0
    }

    /// 同步计算一组路径大小（后台可调）
    static func sizeMap(for paths: [String]) async -> [String: Int64] {
        var result: [String: Int64] = [:]
        await withTaskGroup(of: (String, Int64).self) { group in
            for path in paths {
                let normalized = SafetyWhitelist.normalizeForCompare(path)
                group.addTask {
                    (normalized, UserWhitelist.size(of: normalized))
                }
            }
            for await (path, size) in group {
                result[path] = size
            }
        }
        return result
    }
}
