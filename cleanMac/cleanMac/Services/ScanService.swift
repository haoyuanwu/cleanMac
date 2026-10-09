import Foundation
import AppKit

struct TrashScanOutcome: Sendable {
    let items: [FileItem]
    let error: String?
}

/// 文件扫描服务
final class ScanService: @unchecked Sendable {
    nonisolated(unsafe) private let fileManager = FileManager.default
    nonisolated(unsafe) private let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    
    // MARK: - 系统缓存扫描
    func scanSystemCache() async -> [FileItem] {
        await Task.detached { [weak self] in
            guard let self else { return [] }
            var items: [FileItem] = []
            let paths = [
                "\(self.homeDir)/Library/Caches",
                "/Library/Caches",
                "/System/Library/Caches"
            ]
            
            for path in paths {
                items.append(contentsOf: self.scanCacheEntries(in: path, minSize: 1024 * 100))
            }
            return items.sorted { $0.size > $1.size }
        }.value
    }
    
    // MARK: - 日志文件扫描
    func scanLogFiles() async -> [FileItem] {
        await Task.detached { [weak self] in
            guard let self else { return [] }
            var items: [FileItem] = []

            // 常规日志目录只展示其下的文件夹，不把整个日志根目录列为清理项。
            let logRoots = [
                "\(self.homeDir)/Library/Logs",
                "/Library/Logs",
                "/var/log"
            ]

            for path in logRoots {
                items.append(contentsOf: self.scanImmediateLogFolders(in: path))
            }

            // 开发工具目录中只选名称明确为 Logs 的子目录。
            let developerRoots = [
                "\(self.homeDir)/Library/Developer/Xcode/DerivedData",
                "\(self.homeDir)/Library/Developer/Xcode/Archives",
                "\(self.homeDir)/Library/Developer/CoreSimulator"
            ]

            for path in developerRoots {
                items.append(contentsOf: self.scanNamedLogFolders(in: path))
            }

            if let androidLogs = self.logFolderItem(at: "\(self.homeDir)/.android/logs") {
                items.append(androidLogs)
            }

            var seenPaths = Set<String>()
            return items.filter { seenPaths.insert($0.path).inserted }
                .sorted { $0.size > $1.size }
        }.value
    }
    
    // MARK: - 浏览器缓存扫描
    func scanBrowserCache() async -> [FileItem] {
        await Task.detached { [weak self] in
            guard let self else { return [] }
            var items: [FileItem] = []
            
            let safariPaths = [
                "\(self.homeDir)/Library/Caches/com.apple.Safari",
                "\(self.homeDir)/Library/Safari/LocalStorage",
                "\(self.homeDir)/Library/Caches/com.apple.WebKit.WebContent",
                "\(self.homeDir)/Library/Containers/com.apple.Safari/Data/Library/Caches"
            ]
            
            let chromePaths = [
                "\(self.homeDir)/Library/Caches/Google/Chrome",
                "\(self.homeDir)/Library/Caches/com.google.Chrome",
                "\(self.homeDir)/Library/Application Support/Google/Chrome"
            ]
            
            let firefoxPaths = [
                "\(self.homeDir)/Library/Caches/Mozilla/Firefox",
                "\(self.homeDir)/Library/Caches/org.mozilla.firefox",
                "\(self.homeDir)/Library/Application Support/Firefox"
            ]
            
            let edgePaths = [
                "\(self.homeDir)/Library/Caches/com.microsoft.edgemac",
                "\(self.homeDir)/Library/Caches/Microsoft Edge",
                "\(self.homeDir)/Library/Application Support/Microsoft Edge"
            ]
            
            let allPaths = safariPaths + chromePaths + firefoxPaths + edgePaths
            for path in allPaths {
                items.append(contentsOf: self.scanBrowserCacheDirectories(in: path))
            }
            return items.sorted { $0.size > $1.size }
        }.value
    }
    
    // MARK: - 废纸篓扫描
    func scanTrash() async -> TrashScanOutcome {
        await Task.detached { [weak self] in
            guard let self else { return TrashScanOutcome(items: [], error: nil) }
            var items: [FileItem] = []
            var readErrors: [String] = []
            
            let userTrashPath = "\(self.homeDir)/.Trash"
            do {
                items.append(contentsOf: try self.scanTrashDirectory(userTrashPath))
            } catch where !self.isMissingTrashDirectory(error) {
                readErrors.append(error.localizedDescription)
            } catch { }
            
            if let volumes = try? self.fileManager.contentsOfDirectory(atPath: "/Volumes") {
                for volume in volumes {
                    let userTrashesPath = "/Volumes/\(volume)/.Trashes/\(getuid())"
                    do {
                        items.append(contentsOf: try self.scanTrashDirectory(userTrashesPath))
                    } catch where !self.isMissingTrashDirectory(error) {
                        readErrors.append(error.localizedDescription)
                    } catch { }
                }
            }
            
            let error = readErrors.isEmpty ? nil :
                "无法读取部分废纸篓位置：\(readErrors[0])。请在「设置 → 权限」中前往完全磁盘访问授权，重启应用后重新扫描。"
            return TrashScanOutcome(items: items.sorted { $0.size > $1.size }, error: error)
        }.value
    }
    
    // MARK: - 应用残留扫描
    func scanAppLeftover() async -> [FileItem] {
        await Task.detached { [weak self] in
            guard let self else { return [] }
            var items: [FileItem] = []
            
            let installedApps = self.getInstalledApplications()
            guard !installedApps.bundleIDs.isEmpty else { return [] }
            
            let appSupportPath = "\(self.homeDir)/Library/Application Support"
            items.append(contentsOf: self.scanLeftovers(in: appSupportPath, installedApps: installedApps))
            
            let containersPath = "\(self.homeDir)/Library/Containers"
            items.append(contentsOf: self.scanLeftovers(in: containersPath, installedApps: installedApps))
            
            let savedStatePath = "\(self.homeDir)/Library/Saved Application State"
            items.append(contentsOf: self.scanLeftovers(in: savedStatePath, installedApps: installedApps))
            
            return items.sorted { $0.size > $1.size }
        }.value
    }
    
    // MARK: - 下载文件夹扫描
    func scanDownloads() async -> [FileItem] {
        await Task.detached { [weak self] in
            guard let self else { return [] }
            let downloadsPath = "\(self.homeDir)/Downloads"
            return self.scanDirectory(downloadsPath, minSize: 1024 * 1024)
        }.value
    }
    
    // MARK: - 大文件扫描
    func scanLargeFiles(minSizeMB: Int = 100) async -> [FileItem] {
        await Task.detached { [weak self] in
            guard let self else { return [] }
            let minSize = Int64(minSizeMB) * 1024 * 1024
            var items: [FileItem] = []
            
            let searchPaths = [
                "\(self.homeDir)/Documents",
                "\(self.homeDir)/Desktop",
                "\(self.homeDir)/Downloads",
                "\(self.homeDir)/Movies",
                "\(self.homeDir)/Music",
                "\(self.homeDir)/Pictures"
            ]
            
            for path in searchPaths {
                items.append(contentsOf: self.scanDirectory(path, minSize: minSize))
            }
            
            return Array(items.sorted { $0.size > $1.size }.prefix(100))
        }.value
    }
    
    // MARK: - 应用程序扫描
    func scanApplications() async -> [FileItem] {
        await Task.detached { [weak self] in
            guard let self else { return [] }
            var items: [FileItem] = []
            
            let appPaths = [
                "/Applications",
                "\(self.homeDir)/Applications"
            ]
            
            for appPath in appPaths {
                guard self.fileManager.fileExists(atPath: appPath) else { continue }
                
                if let contents = try? self.fileManager.contentsOfDirectory(atPath: appPath) {
                    for item in contents where item.hasSuffix(".app") {
                        let fullPath = (appPath as NSString).appendingPathComponent(item)
                        
                        // 计算应用大小
                        let size = FileHelper.directorySize(fullPath)
                        
                        // 获取修改日期
                        let attrs = try? self.fileManager.attributesOfItem(atPath: fullPath)
                        let modDate = attrs?[.modificationDate] as? Date
                        
                        let appName = (item as NSString).deletingPathExtension
                        
                        // 获取应用图标
                        let appIcon = self.getAppIcon(for: fullPath)
                        
                        items.append(FileItem(
                            path: fullPath,
                            name: appName,
                            size: size,
                            modificationDate: modDate,
                            isDirectory: true,
                            appIcon: appIcon
                        ))
                    }
                }
            }
            
            return items.sorted { $0.size > $1.size }
        }.value
    }
    
    /// 获取应用图标
    nonisolated private func getAppIcon(for appPath: String) -> NSImage? {
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }
    
    // MARK: - 安装包扫描
    func scanInstallers() async -> [FileItem] {
        await Task.detached { [weak self] in
            guard let self else { return [] }
            var items: [FileItem] = []

            // 扫描常见安装包位置
            let searchPaths = [
                "\(self.homeDir)/Downloads",
                "\(self.homeDir)/Desktop",
                "\(self.homeDir)/Documents",
                "\(self.homeDir)/Movies",
                "/Library/InstallerSandboxes",
                "\(self.homeDir)/Library/Caches"
            ]

            // 安装包/可安装分发包扩展名（含移动端与 Windows 包）
            let installerExtensions = [
                // macOS / Linux
                "pkg", "dmg", "mpkg", "iso",
                "deb", "rpm", "appimage",
                // Windows
                "exe", "msi", "msix", "appx",
                // Android / 跨端
                "apk", "aab", "ipa", "xapk", "apks",
                // 压缩安装包
                "zip", "7z", "tar", "gz", "tgz"
            ]

            for path in searchPaths {
                guard self.fileManager.fileExists(atPath: path) else { continue }
                items.append(contentsOf: self.scanDirectory(path, extensions: installerExtensions))
            }

            var seen = Set<String>()
            return items
                .filter { seen.insert($0.path).inserted }
                .sorted { $0.size > $1.size }
        }.value
    }
    
    // MARK: - 私有方法

    /// 缓存根目录按一级项目展示；文件夹计入其内容，避免与内部文件重复统计。
    nonisolated private func scanCacheEntries(in path: String, minSize: Int64) -> [FileItem] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        return names.compactMap { name in
            let fullPath = (path as NSString).appendingPathComponent(name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
                  let type = attributes[.type] as? FileAttributeType,
                  type == .typeDirectory || type == .typeRegular else { return nil }

            let isDirectory = type == .typeDirectory
            let size = isDirectory
                ? FileHelper.directorySize(fullPath)
                : (attributes[.size] as? Int64) ?? 0
            guard size >= minSize else { return nil }

            return FileItem(
                path: fullPath,
                name: name,
                size: size,
                modificationDate: attributes[.modificationDate] as? Date,
                isDirectory: isDirectory
            )
        }
    }

    /// 日志根目录下的一级文件夹。
    nonisolated private func scanImmediateLogFolders(in path: String) -> [FileItem] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        return names.compactMap { name in
            logFolderItem(at: (path as NSString).appendingPathComponent(name))
        }
    }

    /// 开发工具目录中明确命名为日志的文件夹。
    nonisolated private func scanNamedLogFolders(in path: String) -> [FileItem] {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var items: [FileItem] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true else { continue }
            let name = url.lastPathComponent.lowercased()
            if name == "log" || name == "logs" || name.hasSuffix(".logs") {
                if let item = logFolderItem(at: url.path) {
                    items.append(item)
                }
                enumerator.skipDescendants()
            }
        }
        return items
    }

    nonisolated private func logFolderItem(at path: String) -> FileItem? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              (attributes[.type] as? FileAttributeType) == .typeDirectory else { return nil }
        let size = FileHelper.directorySize(path)
        guard size > 0 else { return nil }
        return FileItem(
            path: path,
            name: (path as NSString).lastPathComponent,
            size: size,
            modificationDate: attributes[.modificationDate] as? Date,
            isDirectory: true
        )
    }

    /// 仅返回浏览器路径中名称含 cache 的文件夹，不展开其内部文件或子缓存目录。
    nonisolated private func scanBrowserCacheDirectories(in path: String) -> [FileItem] {
        let rootURL = URL(fileURLWithPath: path)
        guard let rootAttributes = try? fileManager.attributesOfItem(atPath: path),
              (rootAttributes[.type] as? FileAttributeType) == .typeDirectory else { return [] }

        func cacheItem(at url: URL) -> FileItem {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return FileItem(
                path: url.path,
                name: url.lastPathComponent,
                size: FileHelper.directorySize(url.path),
                modificationDate: attributes?[.modificationDate] as? Date,
                isDirectory: true
            )
        }

        if rootURL.lastPathComponent.localizedCaseInsensitiveContains("cache") {
            return [cacheItem(at: rootURL)]
        }

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var items: [FileItem] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true else { continue }
            if url.lastPathComponent.localizedCaseInsensitiveContains("cache") {
                items.append(cacheItem(at: url))
                enumerator.skipDescendants()
            }
        }
        return items
    }
    
    /// 扫描目录
    nonisolated private func scanDirectory(_ path: String, minSize: Int64 = 0, extensions: [String]? = nil) -> [FileItem] {
        guard fileManager.fileExists(atPath: path) else { return [] }
        
        var items: [FileItem] = []
        guard let enumerator = fileManager.enumerator(atPath: path) else { return [] }
        
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            
            guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                  let fileType = attrs[.type] as? FileAttributeType else { continue }
            
            let isDir = fileType == .typeDirectory
            let size = (attrs[.size] as? Int64) ?? 0
            let modDate = attrs[.modificationDate] as? Date
            
            if let extensions = extensions {
                let ext = (fullPath as NSString).pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }
            }
            
            guard size >= minSize else { continue }
            
            let item = FileItem(
                path: fullPath,
                name: (fullPath as NSString).lastPathComponent,
                size: size,
                modificationDate: modDate,
                isDirectory: isDir
            )
            items.append(item)
        }
        
        return items
    }
    
    /// 扫描废纸篓目录
    nonisolated private func scanTrashDirectory(_ path: String) throws -> [FileItem] {
        var items: [FileItem] = []
        var firstItemError: Error?
        
        let contents = try fileManager.contentsOfDirectory(atPath: path)
        
        for item in contents {
            let fullPath = (path as NSString).appendingPathComponent(item)
            
            do {
                let attrs = try fileManager.attributesOfItem(atPath: fullPath)
                let size = (attrs[.size] as? Int64) ?? 0
                let modDate = attrs[.modificationDate] as? Date
                let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
                
                let totalSize = isDir ? FileHelper.directorySize(fullPath) : size
                
                items.append(FileItem(
                    path: fullPath,
                    name: item,
                    size: totalSize,
                    modificationDate: modDate,
                    isDirectory: isDir
                ))
            } catch {
                firstItemError = firstItemError ?? error
            }
        }

        if items.isEmpty, let firstItemError {
            throw firstItemError
        }
        
        return items
    }

    nonisolated private func isMissingTrashDirectory(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
    }
    
    private struct InstalledApplications {
        var bundleIDs = Set<String>()
        var names = Set<String>()
    }

    /// 查找常见安装位置中的应用，包含系统应用和子目录中的应用。
    nonisolated private func getInstalledApplications() -> InstalledApplications {
        var installed = InstalledApplications()
        let appPaths = [
            "/Applications",
            "\(homeDir)/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications"
        ]

        for appPath in appPaths {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: appPath),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                installed.bundleIDs.insert(id.lowercased())
                installed.names.insert(url.deletingPathExtension().lastPathComponent.lowercased())
                if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                    installed.names.insert(displayName.lowercased())
                }
                if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                    installed.names.insert(bundleName.lowercased())
                }
            }
        }
        return installed
    }

    /// 扫描可识别应用标识、且对应应用未安装的残留文件夹。
    nonisolated private func scanLeftovers(in directory: String, installedApps: InstalledApplications) -> [FileItem] {
        guard fileManager.fileExists(atPath: directory) else { return [] }
        
        var items: [FileItem] = []
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        
        for item in contents {
            let fullPath = (directory as NSString).appendingPathComponent(item)
            guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                  (attrs[.type] as? FileAttributeType) == .typeDirectory,
                  let bundleID = leftoverBundleID(for: item, in: directory),
                  !bundleID.hasPrefix("com.apple.") else { continue }

            let isInstalled = installedApps.bundleIDs.contains { installedID in
                bundleID == installedID || bundleID.hasPrefix(installedID + ".")
            } || installedApps.names.contains(item.lowercased())
            guard !isInstalled else { continue }

            items.append(FileItem(
                path: fullPath,
                name: item,
                size: FileHelper.directorySize(fullPath),
                modificationDate: attrs[.modificationDate] as? Date,
                isDirectory: true
            ))
        }
        
        return items
    }

    nonisolated private func leftoverBundleID(for name: String, in directory: String) -> String? {
        let isSavedState = (directory as NSString).lastPathComponent == "Saved Application State"
        if isSavedState && !name.lowercased().hasSuffix(".savedstate") { return nil }
        let candidate = isSavedState ? String(name.dropLast(".savedState".count)) : name
        let parts = candidate.lowercased().split(separator: ".")
        guard parts.count >= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else {
            return nil
        }
        return candidate.lowercased()
    }
}
