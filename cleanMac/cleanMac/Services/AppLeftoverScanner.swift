import Foundation
import Security

nonisolated struct AppLeftoverItem: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let name: String
    let size: Int64
    let isDirectory: Bool
    var ownershipReason = ""
    var impact = ""
    var isShared = false
    var isSelectable = true
    var defaultSelected = false
    var relatedBundleIdentifiers: Set<String> = []
    var relatedApplicationPaths: Set<String> = []
    var libraryRoot = ""
    var fileNumber: UInt64 = 0
    var sizeIsKnown = true

    var sizeFormatted: String { sizeIsKnown ? FileSizeFormatter.string(fromByteCount: size) : "未统计" }
    var categoryLabel: String {
        if path.contains("/Group Containers/") { return "共享容器" }
        if path.contains("/LaunchAgents/") || path.contains("/LaunchDaemons/") { return "启动项 · 只读" }
        if path.contains("/Caches/") { return "缓存" }
        if path.contains("/Preferences/") { return "偏好设置" }
        if path.contains("/Containers/") { return "沙盒容器" }
        if path.contains("/Application Support/") { return "应用数据" }
        if path.contains("/Saved Application State/") { return "状态存档" }
        if path.contains("/HTTPStorages/") { return "网络存储" }
        if path.contains("/WebKit/") { return "WebKit" }
        if path.contains("/Logs/") { return "日志" }
        return "其他"
    }
}

nonisolated struct AppLeftoverEstimate: Sendable {
    let appPath: String
    let appName: String
    let bundleIdentifier: String?
    let appSize: Int64
    let leftovers: [AppLeftoverItem]
    var issues: [String] = []
    var appFileName: String { URL(fileURLWithPath: appPath).lastPathComponent }
    var displayName: String { ApplicationNameResolver.displayName(atPath: appPath) }
    var leftoverSize: Int64 { AppLeftoverSelection.coveredOnce(leftovers).reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { appSize + leftoverSize }
    var leftoverSizeFormatted: String { FileSizeFormatter.string(fromByteCount: leftoverSize) }
    var totalSizeFormatted: String { FileSizeFormatter.string(fromByteCount: totalSize) }
    var appSizeFormatted: String { FileSizeFormatter.string(fromByteCount: appSize) }
}

nonisolated enum AppLeftoverSelection {
    static func merged(_ estimates: [AppLeftoverEstimate]) -> [AppLeftoverItem] {
        Dictionary(grouping: estimates.flatMap(\.leftovers), by: \.path).values.compactMap { copies in
            guard var item = copies.first else { return nil }
            item.isShared = copies.count > 1 || copies.contains(where: \.isShared)
            item.defaultSelected = !item.isShared && copies.allSatisfy(\.defaultSelected)
            item.isSelectable = copies.allSatisfy(\.isSelectable)
            item.relatedBundleIdentifiers = copies.reduce(into: []) { $0.formUnion($1.relatedBundleIdentifiers) }
            item.relatedApplicationPaths = copies.reduce(into: []) { $0.formUnion($1.relatedApplicationPaths) }
            item.ownershipReason = Array(Set(copies.map(\.ownershipReason))).sorted().joined(separator: "\n")
            return item
        }.sorted { $0.size > $1.size || ($0.size == $1.size && $0.path < $1.path) }
    }
    static func coveredOnce(_ items: [AppLeftoverItem]) -> [AppLeftoverItem] {
        var included = Set<String>(), directories = Set<String>()
        return items.sorted { $0.path.count < $1.path.count }.filter { item in
            guard !included.contains(item.path), !directories.contains(where: { item.path.hasPrefix($0 + "/") }) else { return false }
            included.insert(item.path)
            if item.isDirectory { directories.insert(item.path) }
            return true
        }
    }
}

nonisolated enum AppLeftoverScanner {
    static func estimate(for appPath: String, applications: [ApplicationCacheScanner.InstalledApplication]? = nil) async -> AppLeftoverEstimate {
        await ScanTask.run {
            inspect(appPath: appPath, applications: applications ?? ApplicationCacheScanner.installedApplications())
        }
    }

    static func groupIdentifiers(at appPath: String) -> Set<String> {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: appPath) as CFURL, [], &code) == errSecSuccess,
              let code else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return [] }
        // 读取声明用于关联，不把读取声明表述为签名或信任验证。
        return Set(groups.filter(validIdentifier))
    }

    static func inspect(
        appPath: String, applications: [ApplicationCacheScanner.InstalledApplication],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library"),
        declaredGroups: Set<String>? = nil, groupClaims: [String: Set<String>]? = nil
    ) -> AppLeftoverEstimate {
        let collector = ScanDiagnosticsCollector()
        return ScanContext.$diagnostics.withValue(collector) {
            let app = URL(fileURLWithPath: appPath).standardizedFileURL
            let appName = app.deletingPathExtension().lastPathComponent
            let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
            let identifier = (info?["CFBundleIdentifier"] as? String).flatMap { validIdentifier($0) ? $0 : nil }
            let library = home.appendingPathComponent("Library").standardizedFileURL
            var candidates: [String: AppLeftoverItem] = [:]
            let appSize = FileHelper.directorySize(appPath)

            func add(_ sourceURL: URL, reason: String, shared: Bool = false, selectable: Bool = true,
                     recommended: Bool = false, impact: String = "可能包含软件设置或用户数据，按需选择。", related: Set<String> = [], relatedPaths: Set<String> = []) {
                if Task.isCancelled { return }
                let url = URL(fileURLWithPath: sourceURL.path).standardizedFileURL
                let path = url.path
                guard candidates[path] == nil, url.resolvingSymlinksInPath().path == path,
                      let attrs = try? ScanFileAccess().attributesOfItem(atPath: path),
                      let type = attrs[.type] as? FileAttributeType, type == .typeDirectory || type == .typeRegular else { return }
                let directory = type == .typeDirectory
                // 仅供核对的共享目录不递归计量，避免为厂商整树增加扫描成本。
                let sizeIsKnown = !directory || selectable
                let size = directory ? (sizeIsKnown ? FileHelper.directorySize(path) : 0) : (attrs[.size] as? Int64 ?? 0)
                candidates[path] = AppLeftoverItem(id: path, path: path, name: url.lastPathComponent, size: size, isDirectory: directory,
                    ownershipReason: reason, impact: impact, isShared: shared, isSelectable: selectable,
                    defaultSelected: recommended && !shared && selectable, relatedBundleIdentifiers: related,
                    relatedApplicationPaths: relatedPaths,
                    libraryRoot: library.path, fileNumber: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                    sizeIsKnown: sizeIsKnown)
            }
            func user(_ relative: String, reason: String, recommended: Bool = false) {
                let impact: String
                if relative.hasPrefix("Caches/") { impact = "缓存可能在下次使用时重建，清理前请先退出所属软件。" }
                else if relative.hasPrefix("Logs/") { impact = "移走后将无法直接查看旧诊断日志，可从清理记录中恢复。" }
                else if relative.hasPrefix("Saved Application State/") { impact = "移走后可能无法恢复上次的窗口与会话状态。" }
                else { impact = "可能包含软件设置、登录状态或用户数据，默认保留，按需选择。" }
                add(library.appendingPathComponent(relative), reason: reason, recommended: recommended, impact: impact,
                    related: identifier.map { [$0] } ?? [])
            }
            if let identifier {
                for folder in ["Application Support", "Caches", "Logs", "Preferences", "HTTPStorages", "WebKit"] {
                    user("\(folder)/\(identifier)", reason: "目录名与软件标识 \(identifier) 完整匹配。", recommended: ["Caches", "Logs"].contains(folder))
                }
                user("Preferences/\(identifier).plist", reason: "偏好文件与软件标识完整匹配。")
                user("Saved Application State/\(identifier).savedState", reason: "状态存档与软件标识完整匹配。", recommended: true)
                if let byHost = try? ScanFileAccess().contentsOfDirectory(atPath: library.appendingPathComponent("Preferences/ByHost").path) {
                    for name in byHost where name.hasPrefix(identifier + ".") && name.hasSuffix(".plist") {
                        let host = String(name.dropFirst(identifier.count + 1).dropLast(6))
                        if UUID(uuidString: host) != nil { user("Preferences/ByHost/\(name)", reason: "按主机保存的偏好：软件标识及主机 UUID 完整匹配。") }
                    }
                }
                let containers = library.appendingPathComponent("Containers")
                if let children = try? ScanFileAccess().contentsOfDirectory(at: containers, includingPropertiesForKeys: nil) {
                    for child in children {
                        if Task.isCancelled { break }
                        guard let values = try? ScanContext.values(child, keys: [.isDirectoryKey, .isSymbolicLinkKey]),
                              values.isDirectory == true, values.isSymbolicLink != true else { continue }
                        let metadata = NSDictionary(contentsOf: child.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))?["MCMMetadataIdentifier"] as? String
                        if metadata == identifier || (metadata == nil && child.lastPathComponent == identifier) {
                            add(child, reason: metadata == identifier ? "容器元数据声明的软件标识与本应用一致。" : "容器目录名与软件标识完整匹配。", related: [identifier])
                        }
                    }
                }
            }
            // 文件名和应用声明的名称可补充数据目录线索，不能据此默认删除。
            let aliases = Set([appName, info?["CFBundleName"] as? String, info?["CFBundleDisplayName"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty && !$0.contains("/") && $0 != "." && $0 != ".." }.map { $0.lowercased() })
            for folder in ["Application Support", "Caches", "Logs"] {
                let base = library.appendingPathComponent(folder)
                guard let children = try? ScanFileAccess().contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }
                for child in children where aliases.contains(child.lastPathComponent.lowercased()) {
                    let nameOwners = applications.filter { $0.aliases.contains(child.lastPathComponent.lowercased()) }.map { $0.application.id }
                    add(child, reason: "仅软件文件名或声明名称匹配，尚不能确认独占归属。", shared: true,
                        selectable: false, impact: "名称匹配仅供核对；确认数据归属后在 Finder 中处理。", related: Set(nameOwners))
                }
            }
            if let identifier {
                let groups = declaredGroups ?? groupIdentifiers(at: appPath)
                var claims = groupClaims ?? [:]
                if groupClaims == nil, !groups.isEmpty {
                    for other in applications {
                        if Task.isCancelled { break }
                        guard let path = other.application.path else { continue }
                        claims[other.application.id] = groupIdentifiers(at: path)
                    }
                }
                let base = library.appendingPathComponent("Group Containers")
                if !groups.isEmpty, let children = try? ScanFileAccess().contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
                    for child in children {
                        if Task.isCancelled { break }
                        guard let values = try? ScanContext.values(child, keys: [.isDirectoryKey, .isSymbolicLinkKey]),
                              values.isDirectory == true, values.isSymbolicLink != true else { continue }
                        let metadata = NSDictionary(contentsOf: child.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))?["MCMMetadataIdentifier"] as? String
                        let group = metadata ?? child.lastPathComponent
                        guard groups.contains(group) else { continue }
                        var consumers = Set(claims.filter { $0.value.contains(group) }.keys)
                        consumers.insert(identifier)
                        add(child, reason: "本应用的 application-groups 声明包含 \(group)。已识别使用者：\(consumers.sorted().joined(separator: "、"))。",
                            shared: true, impact: "此共享容器可能包含同组软件的数据。默认不选；选择会影响所有使用者。", related: consumers,
                            relatedPaths: Set(applications.filter { consumers.contains($0.application.id) }.compactMap { $0.application.path }))
                    }
                }
                // 同厂商目录只作为共享线索，既不推断独占，也不提供整树清理。
                let parts = identifier.split(separator: ".")
                if parts.count >= 3 {
                    let vendor = String(parts[1])
                    let support = library.appendingPathComponent("Application Support")
                    if let children = try? ScanFileAccess().contentsOfDirectory(at: support, includingPropertiesForKeys: nil) {
                        for child in children where child.lastPathComponent.lowercased() == vendor.lowercased() {
                            add(child, reason: "目录名与软件标识中的厂商名称一致，仅为可能共享的线索。", shared: true,
                                selectable: false, impact: "可能服务于同厂商的多个软件；不提供整目录回收。")
                        }
                    }
                }
                for base in [library.appendingPathComponent("LaunchAgents"), systemLibrary.appendingPathComponent("LaunchAgents"), systemLibrary.appendingPathComponent("LaunchDaemons")] {
                    guard let files = try? ScanFileAccess().contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }
                    for sourceFile in files where sourceFile.pathExtension == "plist" {
                        if Task.isCancelled { break }
                        // 去除枚举 URL 携带的缓存路径信息后，再进行符号链接校验。
                        let file = URL(fileURLWithPath: sourceFile.path).standardizedFileURL
                        guard file.resolvingSymlinksInPath().path == file.path,
                              let attrs = try? ScanFileAccess().attributesOfItem(atPath: file.path),
                              attrs[.type] as? FileAttributeType == .typeRegular,
                              let plist = NSDictionary(contentsOf: file) as? [String: Any] else { continue }
                        let executable = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                        let executablePath = executable.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
                        let insideApp = executable?.hasPrefix("/") == true && executablePath?.hasPrefix(app.path + "/") == true
                        let label = plist["Label"] as? String ?? ""
                        guard insideApp || label == identifier || label.hasPrefix(identifier + ".") else { continue }
                        add(file, reason: insideApp ? "启动项声明的执行路径位于该应用包内：\(executablePath ?? "")。" : "启动项 Label 与软件标识匹配，但执行路径未确认：\(executable ?? "未声明")。",
                            shared: !insideApp, selectable: false, impact: "仅展示关联信息；移动 plist 不等于停止已加载服务，请在系统登录项中管理。", related: [identifier])
                    }
                }
            }
            let report = collector.snapshot(finished: true, cancelled: Task.isCancelled)
            var issues = report.issues.prefix(20).map { "\($0.path)：\($0.message)" }
            if identifier == nil { issues.append("应用缺少有效的软件标识；仅名称匹配的项目只供核对，不提供自动回收。") }
            if report.status == .cancelled { issues.append("关联扫描已取消，当前清单不完整。") }
            if report.issues.count > 20 { issues.append("另有 \(report.issues.count - 20) 处读取问题。") }
            return AppLeftoverEstimate(appPath: appPath, appName: appName, bundleIdentifier: identifier,
                                       appSize: appSize, leftovers: candidates.values.sorted { $0.size > $1.size }, issues: issues)
        }
    }

    static func validIdentifier(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }
    static func isProtected(_ appPath: String) -> Bool { SafetyWhitelist.isProtectedApp(path: appPath) }

    static func canRemove(_ item: AppLeftoverItem) -> Bool {
        let url = URL(fileURLWithPath: item.path).standardizedFileURL
        guard item.isSelectable, !item.libraryRoot.isEmpty, url.path == item.path,
              url.path.hasPrefix(item.libraryRoot + "/"), url.resolvingSymlinksInPath().path == url.path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: item.path),
              (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == item.fileNumber else { return false }
        return !item.path.contains("/LaunchAgents/") && !item.path.contains("/LaunchDaemons/")
    }

    static func removeLeftovers(_ items: [AppLeftoverItem]) -> (removed: Int, failed: Int, details: [String]) {
        var removed = 0, failed = 0
        var details: [String] = []
        for item in AppLeftoverSelection.coveredOnce(items) {
            guard canRemove(item), DeleteDryRun.validate(path: item.path, context: "app-leftover").allowed else {
                let reason = "路径受保护、已变化或仅供核对，请重新扫描。"
                failed += 1
                details.append("\(item.path)：\(reason)")
                CleaningHistoryStore.shared.record(path: item.path, size: item.size, category: "应用残留", state: .failed, message: reason)
                continue
            }
            do {
                try CleaningHistoryStore.shared.moveToTrash(path: item.path, size: item.size, category: "应用残留")
                removed += 1
            } catch {
                failed += 1
                details.append("\(item.path)：\(error.localizedDescription)")
            }
        }
        return (removed, failed, details)
    }
}
