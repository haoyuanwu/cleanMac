import Foundation

/// 扫描已安装应用数据及全部沙盒容器中的缓存，不扫描或修改 .app 包内资源。
enum ApplicationCacheScanner {
    struct InstalledApplication: Sendable {
        let application: CacheApplication
        let aliases: Set<String>
    }

    struct DataRoot: Sendable {
        let url: URL
        let owner: CacheApplication
        let isCacheRoot: Bool
        var isSandboxContainer = false
        var kind: CacheDataRootKind = .applicationSupport
    }

    nonisolated static func scan(catalog: CacheRuleCatalog = CacheRuleStore.shared.activeCatalog, forceFull: Bool = false) async -> [FileItem] {
        await ScanTask.run {
            let roots = dataRoots(applications: installedApplications())
            let browserIDs = Set(BrowserCacheApplication.allCases.map(\.bundleIdentifier))
            return cacheItems(in: roots.filter { $0.isSandboxContainer || !browserIDs.contains($0.owner.id) },
                              ignoreStore: .shared, catalog: catalog, index: .shared, monitor: .shared, forceFull: forceFull)
        }
    }

    nonisolated static func installedApplications(searchPaths: [String]? = nil) -> [InstalledApplication] {
        let fm = ScanFileAccess()
        let paths = searchPaths ?? ["/Applications", FileManager.default.homeDirectoryForCurrentUser.path + "/Applications",
                                    "/System/Applications", "/System/Library/CoreServices/Applications"]
        var applications: [String: InstalledApplication] = [:]
        for path in paths {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { return Array(applications.values) }
                let values = try? ScanContext.values(url, keys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    // URL 枚举器不会遍历符号链接；在非目录项上调用 skipDescendants
                    // 可能连带跳过紧随其后的目录（沙盒中有大量用户目录链接）。
                    continue
                }
                guard url.pathExtension.lowercased() == "app", values?.isDirectory == true else { continue }
                enumerator.skipDescendants()
                guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                      let identifier = info["CFBundleIdentifier"] as? String, !identifier.isEmpty,
                      applications[identifier] == nil else { continue }
                let name = ApplicationNameResolver.displayName(atPath: url.path)
                let aliases = [identifier, name, url.deletingPathExtension().lastPathComponent,
                               info["CFBundleName"] as? String, info["CFBundleDisplayName"] as? String]
                    .compactMap { $0 }.map { $0.lowercased() }.filter { !$0.isEmpty }
                applications[identifier] = InstalledApplication(
                    application: CacheApplication(id: identifier, name: name, path: url.path),
                    aliases: Set(aliases)
                )
            }
        }
        return applications.values.sorted { $0.application.id < $1.application.id }
    }

    /// 名称必须唯一且完整匹配；bundle id 可匹配应用自己的 helper / 沙盒组前缀。
    nonisolated static func owner(of name: String, applications: [InstalledApplication]) -> CacheApplication? {
        let key = name.lowercased()
        let exact = applications.filter { $0.application.id.lowercased() == key }
        if exact.count == 1 { return exact[0].application }
        let matches = applications.filter {
            let identifier = $0.application.id.lowercased()
            return $0.aliases.contains(key) || key.hasPrefix(identifier + ".")
                || key.hasSuffix("." + identifier)
        }
        return matches.count == 1 ? matches[0].application : nil
    }

    nonisolated static func dataRoots(
        applications: [InstalledApplication], home: URL = FileManager.default.homeDirectoryForCurrentUser,
        sharedLibrary: URL = URL(fileURLWithPath: "/Library")
    ) -> [DataRoot] {
        let libraries = [home.appendingPathComponent("Library"), sharedLibrary]
        var roots: [DataRoot] = []
        for library in libraries {
            for directory in ["Caches", "Application Support", "Containers", "Group Containers"] {
                let base = library.appendingPathComponent(directory)
                discoverRoots(at: base, depth: 0, isCacheRoot: directory == "Caches",
                              isSandboxContainer: directory == "Containers" || directory == "Group Containers",
                              kind: directory == "Caches" ? .caches : directory == "Containers" ? .container : directory == "Group Containers" ? .groupContainer : .applicationSupport,
                              applications: applications, into: &roots)
            }
        }
        return roots
    }

    nonisolated private static func discoverRoots(
        at base: URL, depth: Int, isCacheRoot: Bool, isSandboxContainer: Bool,
        kind: CacheDataRootKind, applications: [InstalledApplication], into roots: inout [DataRoot]
    ) {
        guard !Task.isCancelled,
              base.resolvingSymlinksInPath().standardizedFileURL.path == base.standardizedFileURL.path,
              let children = try? ScanFileAccess().contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
              ) else { return }
        for url in children.sorted(by: { $0.path < $1.path }) {
            let values = try? ScanContext.values(url, keys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true,
                  values?.isPackage != true || isSandboxContainer else { continue }
            let metadataIdentifier: String? = isSandboxContainer
                ? (NSDictionary(contentsOf: url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))?["MCMMetadataIdentifier"] as? String)
                : nil
            let application = metadataIdentifier.flatMap { owner(of: $0, applications: applications) }
                ?? owner(of: url.lastPathComponent, applications: applications)
                ?? owner(of: FileManager.default.displayName(atPath: url.path), applications: applications)
                ?? (isSandboxContainer && depth == 0 ? containerApplication(at: url, identifier: metadataIdentifier) : nil)
            if let application {
                roots.append(DataRoot(url: url, owner: application, isCacheRoot: isCacheRoot,
                                      isSandboxContainer: isSandboxContainer, kind: kind))
            } else if depth < 1 {
                // 兼容 Vendor/App 的数据目录布局，不在未归属目录中无限递归。
                discoverRoots(at: url, depth: depth + 1, isCacheRoot: isCacheRoot,
                              isSandboxContainer: isSandboxContainer, kind: kind,
                              applications: applications, into: &roots)
            }
        }
    }

    nonisolated private static func containerApplication(at url: URL, identifier: String?) -> CacheApplication {
        let displayName = FileManager.default.displayName(atPath: url.path)
        let name = displayName == url.lastPathComponent ? (identifier ?? displayName) : displayName
        return CacheApplication(id: identifier ?? url.lastPathComponent, name: name, path: nil)
    }

    nonisolated static func isCacheName(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("cache") || name.contains("缓存")
    }

    nonisolated static func isCacheFileName(_ name: String) -> Bool {
        let fileExtension = (name as NSString).pathExtension.lowercased()
        // 名称含 cache 的配置和代码文件不是缓存内容（如 cache-config.json）。
        return isCacheName(name) && (fileExtension.isEmpty
            || ["cache", "db", "db-wal", "db-shm", "dat", "bin"].contains(fileExtension))
    }

    nonisolated static func cacheItems(
        in roots: [DataRoot], ignoreStore: CacheScanIgnoreStore? = nil, now: Date = Date(),
        catalog: CacheRuleCatalog = CacheRuleStore.shared.activeCatalog,
        index: CacheScanIndex? = nil, monitor: CacheEventMonitor? = nil, forceFull: Bool = false
    ) -> [FileItem] {
        var items: [FileItem] = []
        var includedPaths = Set<String>()
        ignoreStore?.prepare(for: catalog.fingerprint)
        let revision = ignoreStore?.revision ?? 0
        var emptyRoots: [CacheScanIgnoreStore.Record] = []
        var rescannedPaths = Set<String>()
        var reused = 0, refreshed = 0
        let rulesHash = catalog.fingerprint
        // 先处理父路径；命中缓存目录后不再收集其子缓存，避免重复计数和删除。
        for root in roots.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            if Task.isCancelled { break }
            let path = root.url.standardizedFileURL.path
            guard !CacheRuleMatcher.isApplicationResourceRoot(root.url, kind: root.kind),
                  root.url.resolvingSymlinksInPath().path == path,
                  !includedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { continue }
            let ruleMatches = CacheRuleMatcher.matches(in: root, catalog: catalog)
            let token = monitor?.token(for: path)
            if !forceFull, let index, let token,
               let cached = index.reusable(root: root, rules: rulesHash, token: token, now: now) {
                for item in cached where !includedPaths.contains(where: { item.path == $0 || item.path.hasPrefix($0 + "/") }) {
                    items.append(item); includedPaths.insert(item.path)
                }
                ScanContext.diagnostics?.skip(path)
                reused += 1
                continue
            }
            refreshed += 1
            let knownCaches = Set(ruleMatches.keys)
            let stampBefore = token?.available == true ? CacheScanIndex.treeStamp(root, cachePaths: knownCaches) : nil
            let startCount = items.count
            let issueCount = ScanContext.diagnostics?.errorRevision ?? 0
            var rootComplete = false
            defer {
                if rootComplete, !Task.isCancelled, let index, let monitor, let token, let stampBefore,
                   (ScanContext.diagnostics?.errorRevision ?? 0) == issueCount {
                    index.remember(root: root, items: Array(items.dropFirst(startCount)), rules: rulesHash,
                                   before: token, after: monitor.token(for: path), beforeStamp: stampBefore, cachePaths: knownCaches)
                }
            }
            if root.isCacheRoot {
                appendItem(at: root.url, owner: root.owner, into: &items, includedPaths: &includedPaths)
                rootComplete = (try? ScanFileAccess().contentsOfDirectory(atPath: path)) != nil
                continue
            }
            if index == nil, !forceFull, ignoreStore?.shouldSkip(path, at: now) == true {
                ScanContext.diagnostics?.skip(path)
                continue
            }
            let before = CacheScanIgnoreStore.record(for: path, applicationName: root.owner.name, at: now)
            var completed = true
            var foundCache = false
            guard let enumerator = ScanFileAccess().enumerator(
                at: root.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in completed = false; return true }
            ) else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { completed = false; break }
                let values: URLResourceValues
                do { values = try ScanContext.values(url, keys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]) }
                catch { completed = false; continue }
                if values.isSymbolicLink == true { continue }
                // 沙盒 Documents 是软件私有数据；只查找其中明确命名的缓存，
                // 不把 Documents、聊天附件或其他普通数据目录作为清理项。
                let isPrivateDocuments = root.isSandboxContainer && (
                    url.path == root.url.appendingPathComponent("Data/Documents").path
                    || url.path == root.url.appendingPathComponent("Documents").path
                )
                let isUserContent = ["Documents", "Downloads", "Desktop", "Pictures", "Movies", "Music"]
                    .contains(url.lastPathComponent) && !isPrivateDocuments
                if values.isPackage == true || isUserContent {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                let ruleMatch = ruleMatches[url.standardizedFileURL.path]
                if ruleMatch != nil || (values.isDirectory == true ? isCacheName(url.lastPathComponent) : isCacheFileName(url.lastPathComponent)) {
                    let previousCount = items.count
                    appendItem(at: url, owner: root.owner, into: &items, includedPaths: &includedPaths, rule: ruleMatch)
                    // 确认完全空的缓存文件夹也可暂时跳过；读取失败不能视为空。
                    let isConfirmedEmpty = values.isDirectory == true
                        ? (try? ScanFileAccess().contentsOfDirectory(atPath: url.path).isEmpty) == true
                        : ((try? ScanFileAccess().attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value == 0
                    if items.count > previousCount || !isConfirmedEmpty { foundCache = true }
                    if values.isDirectory == true { enumerator.skipDescendants() }
                }
            }
            if completed && !Task.isCancelled {
                rootComplete = true
                rescannedPaths.insert(path)
                if !foundCache, let before,
                   let after = CacheScanIgnoreStore.record(for: path, applicationName: root.owner.name, at: now),
                   before.modificationDate == after.modificationDate, before.fileNumber == after.fileNumber {
                    emptyRoots.append(after)
                }
            }
        }
        if !Task.isCancelled {
            ignoreStore?.apply(emptyRoots: emptyRoots, rescannedPaths: rescannedPaths, expectedRevision: revision)
        }
        let complete = !Task.isCancelled && (ScanContext.diagnostics?.snapshot(finished: true).status ?? .complete) == .complete
        if monitor == nil || CacheRuleStore.shared.activeCatalog.fingerprint == rulesHash {
            index?.finish(items: items, complete: complete, reused: reused, rescanned: refreshed,
                          liveRoots: Set(roots.map { $0.url.path }), rules: rulesHash)
        }
        return items.sorted { $0.size > $1.size }
    }

    nonisolated private static func appendItem(
        at url: URL, owner: CacheApplication, into items: inout [FileItem], includedPaths: inout Set<String>, rule: CacheRuleMatch? = nil
    ) {
        let path = url.standardizedFileURL.path
        guard !includedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }),
              let attributes = try? ScanFileAccess().attributesOfItem(atPath: path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeDirectory || type == .typeRegular else { return }
        let isDirectory = type == .typeDirectory
        let size = isDirectory ? FileHelper.directorySize(path) : (attributes[.size] as? Int64 ?? 0)
        guard size > 0 else { return }
        var item = FileItem(path: path, name: url.lastPathComponent, size: size,
                            modificationDate: attributes[.modificationDate] as? Date, isDirectory: isDirectory)
        item.cacheApplication = owner
        item.cacheRuleMatch = rule
        if let rule { item.riskLevel = rule.risk }
        items.append(item)
        includedPaths.insert(path)
    }
}
