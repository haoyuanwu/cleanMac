import Foundation

nonisolated enum ExtensionInventoryService {
    static func chromeManifest(_ url: URL, owner: String, profile: String) -> InspectionItem? {
        guard let manifest = InspectionFS.json(url.appendingPathComponent("manifest.json")) else { return nil }
        let identifier = url.deletingLastPathComponent().lastPathComponent
        let name = manifest["name"] as? String ?? identifier
        let source = manifest["update_url"] as? String ?? "未声明更新来源"
        return InspectionItem(id: "chrome:" + url.path, name: name, owner: owner, kind: "浏览器扩展", path: url.path,
            version: manifest["version"] as? String ?? url.lastPathComponent, source: source,
            size: FileHelper.directorySize(url.path), notes: ["配置：\(profile) · 标识：\(identifier)",
                "来源为清单声明，未验证发布者身份；未知来源不代表恶意。", "仅解析 manifest.json，不执行扩展脚本。"])
    }
    static func editorPackage(_ url: URL, owner: String) -> InspectionItem? {
        guard let package = InspectionFS.json(url.appendingPathComponent("package.json")) else { return nil }
        let publisher = package["publisher"] as? String ?? "未知发布者"
        let metadata = package["__metadata"] as? [String: Any]
        return InspectionItem(id: "editor:" + url.path, name: package["displayName"] as? String ?? package["name"] as? String ?? url.lastPathComponent,
            owner: owner, kind: "编辑器扩展", path: url.path, version: package["version"] as? String ?? "未提供",
            source: metadata?["source"] as? String ?? publisher, size: FileHelper.directorySize(url.path),
            notes: ["发布者声明：\(publisher)", "仅解析 package.json；未执行入口文件、安装脚本或激活扩展。"])
    }
    static func bundle(_ url: URL, owner: String, kind: String) -> InspectionItem? {
        guard let attrs = InspectionFS.attributes(url), attrs[.type] as? FileAttributeType == .typeDirectory else { return nil }
        let info = InspectionFS.plist(url.appendingPathComponent("Contents/Info.plist")) ?? [:]
        return InspectionItem(id: "bundle:" + url.path, name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,
            owner: owner, kind: kind, path: url.path,
            version: info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "未提供",
            source: info["CFBundleIdentifier"] as? String ?? "来源未提供", size: FileHelper.directorySize(url.path),
            notes: ["\(kind) 静态包信息；未加载二进制或调用插件接口。", kind == "Safari 扩展" ? "扩展由该宿主应用打包提供；是否启用请在 Safari 设置中核对。" : "音频插件可能被多个宿主共用；目录或标识不能证明具体宿主正在使用。"])
    }
    static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     sharedLibrary: URL = URL(fileURLWithPath: "/Library"),
                     applications: [ApplicationCacheScanner.InstalledApplication]? = nil) -> InspectionReport {
        let collector = ScanDiagnosticsCollector()
        return ScanContext.$diagnostics.withValue(collector) {
            var items: [InspectionItem] = []
            for profile in BrowserPrivacyService.profiles(home: home) {
                if Task.isCancelled { return InspectionFS.finish(items, collector: collector) }
                if profile.browser == .firefox {
                    if let json = InspectionFS.json(profile.url.appendingPathComponent("extensions.json")), let addons = json["addons"] as? [[String: Any]] {
                        for addon in addons {
                            let path = addon["path"] as? String ?? ""
                            let locale = addon["defaultLocale"] as? [String: Any]
                            var bytes: Int64?
                            if path.hasPrefix(profile.url.path + "/"), let attrs = InspectionFS.attributes(URL(fileURLWithPath: path)) {
                                if attrs[.type] as? FileAttributeType == .typeRegular { bytes = attrs[.size] as? Int64 }
                                else if attrs[.type] as? FileAttributeType == .typeDirectory { bytes = FileHelper.directorySize(path) }
                            }
                            items.append(InspectionItem(id: "firefox:" + profile.url.path + ":" + (addon["id"] as? String ?? path),
                                name: locale?["name"] as? String ?? addon["id"] as? String ?? "Firefox 扩展", owner: "Firefox", kind: "浏览器扩展", path: path,
                                version: addon["version"] as? String ?? "未提供", source: addon["sourceURI"] as? String ?? "配置文件声明", size: bytes,
                                notes: ["配置：\(profile.name)", "仅解析 extensions.json；未解压或执行 XPI，未验证来源身份。",
                                    "启用声明：\((addon["active"] as? Bool).map { $0 ? "启用" : "未启用" } ?? "未知")"]))
                        }
                    }
                } else {
                    for identifier in InspectionFS.children(profile.url.appendingPathComponent("Extensions")) {
                        guard InspectionFS.attributes(identifier)?[.type] as? FileAttributeType == .typeDirectory else { continue }
                        for version in InspectionFS.children(identifier) {
                            if Task.isCancelled { return InspectionFS.finish(items, collector: collector) }
                            if let item = chromeManifest(version, owner: profile.browser.name, profile: profile.name) { items.append(item) }
                        }
                    }
                }
            }
            for (relative, owner) in [(".vscode/extensions", "Visual Studio Code"), (".vscode-insiders/extensions", "Visual Studio Code Insiders"), (".vscode-oss/extensions", "Code OSS")] {
                for url in InspectionFS.children(home.appendingPathComponent(relative)) {
                    if Task.isCancelled { return InspectionFS.finish(items, collector: collector) }
                    if let item = editorPackage(url, owner: owner) { items.append(item) }
                }
            }
            for library in [home.appendingPathComponent("Library"), sharedLibrary] {
                for (folder, kind) in [("Components", "Audio Unit"), ("VST", "VST"), ("VST3", "VST3")] {
                    for url in InspectionFS.children(library.appendingPathComponent("Audio/Plug-Ins/" + folder)) {
                        if Task.isCancelled { return InspectionFS.finish(items, collector: collector) }
                        if let item = bundle(url, owner: "音频宿主共享", kind: kind) { items.append(item) }
                    }
                }
                for url in InspectionFS.children(library.appendingPathComponent("Application Support/Avid/Audio/Plug-Ins")) where url.pathExtension == "aaxplugin" {
                    if let item = bundle(url, owner: "Pro Tools / AAX 宿主", kind: "AAX") { items.append(item) }
                }
            }
            for app in applications ?? ApplicationCacheScanner.installedApplications() {
                if Task.isCancelled { return InspectionFS.finish(items, collector: collector) }
                guard let path = app.application.path else { continue }
                let base = URL(fileURLWithPath: path).appendingPathComponent("Contents/PlugIns")
                // 不存在的可选 PlugIns 目录不作为错误。
                for url in InspectionFS.children(base) where url.pathExtension == "appex" {
                    guard let info = InspectionFS.plist(url.appendingPathComponent("Contents/Info.plist")),
                          let ext = info["NSExtension"] as? [String: Any], let point = ext["NSExtensionPointIdentifier"] as? String,
                          point.lowercased().contains("safari") else { continue }
                    if var item = bundle(url, owner: app.application.name, kind: "Safari 扩展") {
                        item.application = app.application
                        items.append(item)
                    }
                }
            }
            let browsers = ["Chrome": "com.google.Chrome", "Google Chrome": "com.google.Chrome", "Microsoft Edge": "com.microsoft.edgemac", "Edge": "com.microsoft.edgemac", "Firefox": "org.mozilla.firefox", "Visual Studio Code": "com.microsoft.VSCode", "Visual Studio Code Insiders": "com.microsoft.VSCodeInsiders", "Code OSS": "com.visualstudio.code.oss"]
            for index in items.indices {
                if let id = browsers[items[index].owner] { items[index].application = CacheApplication(id: id, name: items[index].owner, path: nil) }
            }
            return InspectionFS.finish(items, collector: collector)
        }
    }
}
