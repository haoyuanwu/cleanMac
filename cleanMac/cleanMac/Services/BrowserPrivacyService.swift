import Foundation

nonisolated struct BrowserProfile: Sendable {
    let browser: BrowserCacheApplication
    let name: String
    let url: URL
}

nonisolated enum BrowserPrivacyService {
    static func profiles(home: URL) -> [BrowserProfile] {
        var result: [BrowserProfile] = []
        for (browser, relative) in [(BrowserCacheApplication.chrome, "Google/Chrome"), (.edge, "Microsoft Edge")] {
            let base = home.appendingPathComponent("Library/Application Support/" + relative)
            for url in InspectionFS.children(base) where url.lastPathComponent == "Default" || url.lastPathComponent.hasPrefix("Profile ") || ["Guest Profile", "System Profile"].contains(url.lastPathComponent) {
                guard let attrs = InspectionFS.attributes(url), attrs[.type] as? FileAttributeType == .typeDirectory else { continue }
                result.append(BrowserProfile(browser: browser, name: url.lastPathComponent, url: url))
            }
        }
        for url in InspectionFS.children(home.appendingPathComponent("Library/Application Support/Firefox/Profiles")) {
            guard let attrs = InspectionFS.attributes(url), attrs[.type] as? FileAttributeType == .typeDirectory else { continue }
            result.append(BrowserProfile(browser: .firefox, name: url.lastPathComponent, url: url))
        }
        return result
    }
    static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     runningBundleIdentifiers: Set<String> = []) -> InspectionReport {
        let collector = ScanDiagnosticsCollector()
        return ScanContext.$diagnostics.withValue(collector) {
            var items: [InspectionItem] = []
            func add(_ url: URL, browser: BrowserCacheApplication, profile: String, kind: String, impact: String, shared: Bool = false) {
                guard let attrs = InspectionFS.attributes(url), attrs[.type] as? FileAttributeType == .typeRegular else { return }
                var bytes = attrs[.size] as? Int64 ?? 0
                var notes = [impact, "仅显示文件元数据，不读取网站、账号、历史条目或 Cookie 内容。"]
                for suffix in ["-wal", "-shm"] {
                    if let metadata = InspectionFS.attributes(URL(fileURLWithPath: url.path + suffix)) { bytes += metadata[.size] as? Int64 ?? 0 }
                }
                if shared { notes.append("历史和下载记录共用数据库；大小包含该数据库及已有 WAL/SHM，不能按两份相加。") }
                if runningBundleIdentifiers.contains(browser.bundleIdentifier) { notes.append("检查开始时浏览器正在运行；本次未修改或打开数据库查询。") }
                items.append(InspectionItem(id: browser.rawValue + ":" + kind + ":" + url.path,
                    name: kind + " · " + profile, owner: browser.name, kind: kind, path: url.path,
                    source: browser.name + " 本地配置文件", size: bytes, notes: notes))
            }
            for profile in profiles(home: home) {
                if Task.isCancelled { return InspectionFS.finish(items, collector: collector) }
                if profile.browser == .firefox {
                    for kind in ["浏览历史", "下载记录"] {
                        add(profile.url.appendingPathComponent("places.sqlite"), browser: .firefox, profile: profile.name, kind: kind,
                            impact: "清除可能丢失浏览/下载记录；places.sqlite 还可能包含书签，不应整库当作缓存删除。", shared: true)
                    }
                    add(profile.url.appendingPathComponent("cookies.sqlite"), browser: .firefox, profile: profile.name, kind: "Cookie",
                        impact: "清除 Cookie 可能退出网站登录并丢失站点偏好。")
                } else {
                    for kind in ["浏览历史", "下载记录"] {
                        add(profile.url.appendingPathComponent("History"), browser: profile.browser, profile: profile.name, kind: kind,
                            impact: "清除可能丢失浏览历史及下载清单；下载清单不是已下载文件本体。", shared: true)
                    }
                    for path in ["Network/Cookies", "Cookies"] {
                        add(profile.url.appendingPathComponent(path), browser: profile.browser, profile: profile.name, kind: "Cookie",
                            impact: "清除 Cookie 可能退出网站登录并丢失站点偏好。")
                    }
                }
            }
            add(home.appendingPathComponent("Library/Safari/History.db"), browser: .safari, profile: "当前用户", kind: "浏览历史",
                impact: "清除历史会丢失访问记录，并可能影响通过 iCloud 同步的历史。")
            add(home.appendingPathComponent("Library/Safari/Downloads.plist"), browser: .safari, profile: "当前用户", kind: "下载记录",
                impact: "这是下载清单；不等于下载文件本体。")
            for path in ["Library/Cookies/Cookies.binarycookies", "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"] {
                add(home.appendingPathComponent(path), browser: .safari, profile: "当前用户", kind: "Cookie", impact: "清除可能退出网站登录。")
            }
            return InspectionFS.finish(items, collector: collector)
        }
    }
}
