import Foundation

/// 单条残留记录
struct AppLeftoverItem: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let name: String
    let size: Int64
    let isDirectory: Bool

    var sizeFormatted: String { FileSizeFormatter.string(fromByteCount: size) }

    var categoryLabel: String {
        let p = path
        if p.contains("/Library/Caches") { return "缓存" }
        if p.contains("/Library/Preferences") { return "偏好设置" }
        if p.contains("/Library/Containers") { return "沙盒容器" }
        if p.contains("/Library/Application Support") { return "应用数据" }
        if p.contains("/Library/Saved Application State") { return "状态存档" }
        if p.contains("/Library/HTTPStorages") { return "网络存储" }
        if p.contains("/Library/WebKit") { return "WebKit" }
        if p.contains("/Library/Logs") { return "日志" }
        return "其他"
    }
}

/// 卸载增强：估算 .app 相关残留数据
struct AppLeftoverEstimate: Sendable {
    let appPath: String
    let appName: String
    let bundleIdentifier: String?
    let appSize: Int64
    let leftovers: [AppLeftoverItem]

    var appFileName: String { URL(fileURLWithPath: appPath).lastPathComponent }
    var displayName: String { ApplicationNameResolver.displayName(atPath: appPath) }

    var leftoverSize: Int64 {
        leftovers.reduce(0) { $0 + $1.size }
    }

    var totalSize: Int64 { appSize + leftoverSize }
    var leftoverSizeFormatted: String { FileSizeFormatter.string(fromByteCount: leftoverSize) }
    var totalSizeFormatted: String { FileSizeFormatter.string(fromByteCount: totalSize) }
    var appSizeFormatted: String { FileSizeFormatter.string(fromByteCount: appSize) }
}

enum AppLeftoverScanner {
    /// 根据 bundle id / 应用名匹配常见残留目录并估算大小
    static func estimate(for appPath: String) async -> AppLeftoverEstimate {
        let url = URL(fileURLWithPath: appPath)
        let appName = url.deletingPathExtension().lastPathComponent
        var bundleId: String?
        if let dict = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] {
            bundleId = dict["CFBundleIdentifier"] as? String
        }

        let appSize = await Task.detached {
            FileHelper.directorySize(appPath)
        }.value

        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [(path: String, name: String)] = []

        func add(_ relative: String, label: String? = nil) {
            let full = home.appendingPathComponent(relative).standardizedFileURL.path
            let library = home.appendingPathComponent("Library", isDirectory: true).standardizedFileURL.path
            guard full.hasPrefix(library + "/") else { return }
            candidates.append((full, label ?? (relative as NSString).lastPathComponent))
        }

        if let bundleId,
           bundleId.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil {
            add("Library/Application Support/\(bundleId)")
            add("Library/Containers/\(bundleId)")
            add("Library/Caches/\(bundleId)")
            add("Library/Preferences/\(bundleId).plist")
            add("Library/Preferences/\(bundleId)")
            add("Library/Saved Application State/\(bundleId).savedState")
            add("Library/HTTPStorages/\(bundleId)")
            add("Library/WebKit/\(bundleId)")
        }

        add("Library/Application Support/\(appName)")
        add("Library/Caches/\(appName)")
        add("Library/Logs/\(appName)")

        var leftovers: [AppLeftoverItem] = []
        for candidate in candidates {
            let path = candidate.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let directory = isDir.boolValue
            let pathCopy = path

            let size: Int64 = await Task.detached(priority: .utility) { () -> Int64 in
                if directory {
                    return FileHelper.directorySize(pathCopy)
                }
                let attrs = try? FileManager.default.attributesOfItem(atPath: pathCopy)
                return (attrs?[.size] as? Int64) ?? 0
            }.value

            guard size > 0 else { continue }

            leftovers.append(
                AppLeftoverItem(
                    id: path,
                    path: path,
                    name: candidate.name,
                    size: size,
                    isDirectory: isDir.boolValue
                )
            )
        }

        return AppLeftoverEstimate(
            appPath: appPath,
            appName: appName,
            bundleIdentifier: bundleId,
            appSize: appSize,
            leftovers: leftovers.sorted { $0.size > $1.size }
        )
    }

    static func isProtected(_ appPath: String) -> Bool {
        SafetyWhitelist.isProtectedApp(path: appPath)
    }

    /// 清理所选残留路径
    nonisolated static func removeLeftovers(_ paths: [String]) -> (removed: Int, failed: Int) {
        let fm = FileManager.default
        var removed = 0
        var failed = 0
        for path in paths {
            let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library").standardizedFileURL.path
            let resolvedParent = URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path
            guard path.hasPrefix(library + "/"),
                  resolvedParent.hasPrefix(library + "/"),
                  DeleteDryRun.validate(path: path, context: "app-leftover").allowed else {
                failed += 1
                continue
            }
            do {
                try fm.removeItem(atPath: path)
                removed += 1
            } catch {
                failed += 1
            }
        }
        return (removed, failed)
    }
}
