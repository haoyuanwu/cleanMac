import Foundation

/// 只读取元数据；不会启动模型、虚拟机或执行包管理器清理命令。
nonisolated enum DevelopmentStorageScanner {
    struct Location: Sendable {
        let owner: String
        let path: String
        let detail: String
        let cleanable: Bool
    }

    static func locations(_ kind: DevelopmentStorageKind, home: URL, environment: [String: String]) -> [Location] {
        func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }
        func configured(_ key: String, _ fallback: String) -> String {
            guard let value = environment[key], value.hasPrefix("/") else { return path(fallback) }
            return value
        }
        func location(_ owner: String, _ relative: String, _ detail: String, _ cleanable: Bool = false) -> Location {
            Location(owner: owner, path: path(relative), detail: detail, cleanable: cleanable)
        }
        let cache = "可再生缓存；退出相关构建任务后清理，下次使用可能重新下载。"
        switch kind {
        case .packages:
            return [
                location("Homebrew", "Library/Caches/Homebrew", cache, true),
                location("npm", ".npm/_cacache", cache, true),
                location("npm", ".npm/_logs", "npm 日志", true),
                location("pnpm", "Library/pnpm/store", cache, true),
                location("pnpm", ".local/share/pnpm/store", cache, true),
                location("pnpm", ".pnpm-store", cache, true),
                location("Yarn", "Library/Caches/Yarn", cache, true),
                location("Yarn", ".cache/yarn", cache, true),
                location("Yarn", ".yarn/berry/cache", cache, true),
                location("pnpm", "Library/Caches/pnpm", cache, true),
                location("pip", "Library/Caches/pip", cache, true),
                location("pip", ".cache/pip", cache, true),
                location("Cargo", ".cargo/registry", cache, true),
                location("Cargo", ".cargo/git", cache, true),
                location("Gradle", ".gradle/caches", cache, true),
                location("CocoaPods", "Library/Caches/CocoaPods", cache, true),
                location("Maven", ".m2/repository", cache, true),
                location("uv", ".cache/uv", cache, true),
                location("SwiftPM", "Library/Caches/org.swift.swiftpm", cache, true)
            ]
        case .ai:
            let installed = "已安装组件，可能仍在使用；仅盘点，请在所属工具中卸载。"
            let models = "模型数据，可能包含自定义模型；占用不等于可回收空间，请在模型管理器中删除。"
            let hfHome = configured("HF_HOME", ".cache/huggingface")
            let transient = "临时文件、缓存或日志；退出所属软件和开发任务后清理，下次使用可能重新生成或下载。"
            return [
                location("Ollama", ".ollama", models),
                Location(owner: "Ollama", path: configured("OLLAMA_MODELS", ".ollama/models"), detail: models, cleanable: false),
                Location(owner: "Hugging Face", path: environment["HF_HUB_CACHE"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? hfHome + "/hub", detail: models, cleanable: false),
                Location(owner: "Hugging Face", path: hfHome + "/xet", detail: transient, cleanable: true),
                Location(owner: "Hugging Face", path: hfHome + "/tmp", detail: transient, cleanable: true),
                Location(owner: "Hugging Face", path: hfHome + "/logs", detail: transient, cleanable: true),
                location("nvm", ".nvm", installed),
                location("rustup", ".rustup", installed),
                location("pyenv", ".pyenv", installed),
                location("Claude Code", ".claude", "含会话、设置与插件；仅盘点，保留凭据与工作记录。"),
                location("Claude Code", ".local/share/claude", installed),
                location("Codex", ".codex", "含会话、设置及工具资源；仅盘点。"),
                location("Cursor", ".cursor", installed),
                location("Cursor", "Library/Application Support/Cursor", "含编辑器状态与工作区数据；仅盘点。"),
                location("VS Code", ".vscode", installed),
                location("VS Code", "Library/Application Support/Code", installed),
                location("Ollama", "Library/Logs/Ollama", transient, true),
                location("Cursor", "Library/Caches/com.todesktop.230313mzl4w4u92", transient, true),
                location("VS Code", "Library/Caches/com.microsoft.VSCode", transient, true)
            ]
        case .containers:
            let disk = "虚拟磁盘或虚拟机数据，可能包含唯一数据；仅盘点，在所属软件中管理。"
            return [
                location("Docker", "Library/Containers/com.docker.docker/Data/vms", disk),
                location("Parallels", "Parallels", disk),
                location("Parallels", "Documents/Parallels", disk),
                location("UTM", "Library/Containers/com.utmapp.UTM/Data/Documents", disk),
                location("VMware", "Virtual Machines.localized", disk),
                location("VMware", "Documents/Virtual Machines.localized", disk),
                location("OrbStack", "Library/Group Containers/HUAQ24HBR6.dev.orbstack/data", disk),
                location("Lima", ".lima", disk),
                location("Colima", ".colima", disk)
            ]
        case .projects: return []
        }
    }

    static func scan(_ kind: DevelopmentStorageKind, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     environment: [String: String] = ProcessInfo.processInfo.environment,
                     includeDocker: Bool = true, diagnostics: ScanDiagnosticsCollector? = nil) -> DevelopmentStorageReport {
        let collector = diagnostics ?? ScanDiagnosticsCollector()
        return ScanContext.$diagnostics.withValue(collector) {
            var entries: [DevelopmentStorageEntry] = []
            if kind == .projects {
                for root in projectRoots(home) where !Task.isCancelled {
                    discoverProjects(root, entries: &entries)
                }
            } else {
                for location in locations(kind, home: home, environment: environment) where !Task.isCancelled {
                    if var entry = measure(location) {
                        if kind == .ai, !location.cleanable, aiDiscoveryRoots(home: home).contains(location.path) {
                            entry.children = discoverTransient(in: URL(fileURLWithPath: location.path), owner: location.owner)
                        }
                        entries.append(entry)
                    }
                }
            }
            // 自定义环境路径或嵌套项目根只能统计一次。
            var retained: [DevelopmentStorageEntry] = []
            for entry in entries.sorted(by: { $0.id.count < $1.id.count }) {
                guard !retained.contains(where: { entry.id == $0.id || entry.id.hasPrefix($0.id + "/") }) else { continue }
                retained.append(entry)
            }
            let docker = kind == .containers && includeDocker && !Task.isCancelled ? dockerUsage() : nil
            return DevelopmentStorageReport(entries: retained.sorted { $0.file.size > $1.file.size },
                diagnostics: collector.snapshot(finished: true, cancelled: Task.isCancelled), docker: docker)
        }
    }

    /// 只在已知的软件数据根目录与固定包装层中寻找缓存，不进入模型、会话、源码、插件或版本目录。
    static func aiDiscoveryRoots(home: URL) -> Set<String> {
        Set([".ollama", ".nvm", ".rustup", ".pyenv", ".claude", ".local/share/claude", ".codex", ".cursor", ".vscode",
             "Library/Application Support/Cursor", "Library/Application Support/Code"].map { home.appendingPathComponent($0).path })
    }
    static func isTransientName(_ name: String, owner: String) -> Bool {
        let names: Set<String> = ["tmp", ".tmp", "temp", ".temp", "cache", "caches", ".cache", "log", "logs", ".logs", "code cache", "gpucache", "cacheddata", "shadercache", "dawncache", "dawnwebgpucache", "dawngraphitecache"]
        return names.contains(name.lowercased()) || (owner == "Claude Code" && name == "debug")
            || (owner == "rustup" && name == "downloads")
    }
    static func transientLocations(in root: URL, owner: String) -> [Location] {
        guard !Task.isCancelled, safePath(root), !UserWhitelist.isWhitelisted(root.path),
              let children = try? ScanFileAccess().contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var found: [Location] = []
        for child in children {
            if Task.isCancelled { break }
            guard safePath(child), !UserWhitelist.isWhitelisted(child.path),
                  let values = try? ScanContext.values(child, keys: [.isDirectoryKey]), values.isDirectory == true else { continue }
            if isTransientName(child.lastPathComponent, owner: owner) {
                found.append(Location(owner: owner, path: child.path,
                    detail: "临时文件、缓存或日志；退出所属软件和开发任务后清理，下次使用可能重新生成或下载。", cleanable: true))
            } else if ["data", "user", "service worker", "network"].contains(child.lastPathComponent.lowercased()) {
                found += transientLocations(in: child, owner: owner)
            }
        }
        return found
    }
    private static func discoverTransient(in root: URL, owner: String) -> [DevelopmentStorageEntry] {
        transientLocations(in: root, owner: owner).compactMap(measure).sorted { $0.file.size > $1.file.size }
    }
    /// 与发现规则共享名称及包装层，执行前重新核对，不能仅凭路径里含有 cache 就允许删除。
    static func isAITransientPath(_ url: URL, home: URL) -> Bool {
        guard url.path.hasPrefix(home.path + "/") else { return false }
        let locations = locations(.ai, home: home, environment: ProcessInfo.processInfo.environment)
        if locations.contains(where: { $0.cleanable && $0.path == url.path }) { return true }
        for root in locations where aiDiscoveryRoots(home: home).contains(root.path) && url.path.hasPrefix(root.path + "/") {
            let relative = String(url.path.dropFirst(root.path.count + 1)).split(separator: "/").map(String.init)
            guard let name = relative.last, isTransientName(name, owner: root.owner) else { continue }
            if relative.dropLast().allSatisfy({ ["data", "user", "service worker", "network"].contains($0.lowercased()) }) { return true }
        }
        return false
    }

    static func projectRoots(_ home: URL) -> [URL] {
        ["Desktop", "Documents", "Projects", "Developer", "Code", "repos"].map { home.appendingPathComponent($0) }
    }
    static func artifactOwner(_ name: String, siblings: Set<String>) -> String? {
        let node = siblings.contains("package.json")
        switch name {
        case "node_modules", ".next", ".nuxt": return node ? "Node.js" : nil
        case "Pods": return siblings.contains("Podfile") ? "CocoaPods" : nil
        case ".build": return siblings.contains("Package.swift") ? "SwiftPM" : nil
        case "target": return siblings.contains("Cargo.toml") ? "Cargo" : nil
        case "build", "dist":
            return node || !siblings.isDisjoint(with: ["build.gradle", "build.gradle.kts", "settings.gradle", "CMakeLists.txt", "pubspec.yaml", "pyproject.toml", "setup.py", "Package.swift"]) ? "工程构建" : nil
        default: return nil
        }
    }
    private static func discoverProjects(_ root: URL, entries: inout [DevelopmentStorageEntry]) {
        guard !Task.isCancelled, safePath(root), !UserWhitelist.isWhitelisted(root.path),
              let children = try? ScanFileAccess().contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        let siblings = Set(children.map(\.lastPathComponent))
        for child in children {
            if Task.isCancelled { break }
            guard safePath(child), !UserWhitelist.isWhitelisted(child.path),
                  let values = try? ScanContext.values(child, keys: [.isDirectoryKey, .isPackageKey]), values.isDirectory == true else { continue }
            if let owner = artifactOwner(child.lastPathComponent, siblings: siblings) {
                if let entry = measure(Location(owner: owner, path: child.path,
                    detail: "可再生工程目录；确认未存放手写文件，停止开发任务后清理。项目：\(root.lastPathComponent)", cleanable: true)) { entries.append(entry) }
            } else if !child.lastPathComponent.hasPrefix("."), values.isPackage != true,
                      !["node_modules", "Pods", "build", "dist", "target", "vendor"].contains(child.lastPathComponent) {
                discoverProjects(child, entries: &entries)
            }
        }
    }
    /// 不穿过符号链接父目录，也不跟随根目录链接。
    static func safePath(_ url: URL) -> Bool {
        url.standardizedFileURL.path == url.standardizedFileURL.resolvingSymlinksInPath().path
    }
    private static func measure(_ location: Location) -> DevelopmentStorageEntry? {
        let url = URL(fileURLWithPath: location.path).standardizedFileURL
        guard safePath(url), !UserWhitelist.isWhitelisted(url.path),
              let attrs = try? ScanFileAccess().attributesOfItem(atPath: url.path),
              let type = attrs[.type] as? FileAttributeType, type == .typeDirectory || type == .typeRegular else { return nil }
        let directory = type == .typeDirectory
        let revision = ScanContext.diagnostics?.errorRevision
        let size = directory ? FileHelper.directorySize(url.path) : (attrs[.size] as? Int64 ?? 0)
        var file = FileItem(path: url.path, name: url.lastPathComponent, size: size,
                            modificationDate: attrs[.modificationDate] as? Date, isDirectory: directory)
        file.riskLevel = .sensitive
        return DevelopmentStorageEntry(file: file, owner: location.owner, detail: location.detail,
            cleanable: location.cleanable && !UserWhitelist.paths.contains(where: { $0.hasPrefix(url.path + "/") }) && revision == ScanContext.diagnostics?.errorRevision && !Task.isCancelled)
    }
    static func isCleanablePath(_ path: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard safePath(url), !UserWhitelist.isWhitelisted(path),
              !UserWhitelist.paths.contains(where: { $0.hasPrefix(url.path + "/") }) else { return false }
        if locations(.packages, home: home, environment: [:]).contains(where: { $0.path == url.path }) { return true }
        if isAITransientPath(url, home: home) {
            guard let attrs = try? ScanFileAccess().attributesOfItem(atPath: url.path) else { return false }
            return attrs[.type] as? FileAttributeType == .typeDirectory
        }
        guard projectRoots(home).contains(where: { url.path.hasPrefix($0.path + "/") }),
              let names = try? ScanFileAccess().contentsOfDirectory(atPath: url.deletingLastPathComponent().path) else { return false }
        return artifactOwner(url.lastPathComponent, siblings: Set(names)) != nil
    }

    static func dockerUsage(timeout: TimeInterval = 8) -> String {
        let candidates = ["/opt/homebrew/bin/docker", "/usr/local/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return "未找到 Docker CLI；虚拟磁盘占用仍会单独列出。"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cleanmac-docker-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forWritingTo: url) else { return "无法建立 Docker 查询缓冲区。" }
        defer { try? handle.close(); try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["system", "df", "--format", "{{.Type}}\t总量 {{.Size}}\t可回收 {{.Reclaimable}}"]
        // 只查询本机默认 socket，避免继承远端 Docker context。
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sockets = [home + "/.docker/run/docker.sock", home + "/.orbstack/run/docker.sock", "/var/run/docker.sock"]
        guard let socket = sockets.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return "未找到本机 Docker socket；请启动容器引擎后重新扫描。" }
        process.arguments = ["--host", "unix://" + socket] + (process.arguments ?? [])
        process.environment = ["PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", "HOME": home]
        process.standardOutput = handle; process.standardError = handle
        do { try process.run() } catch { return "Docker 查询失败：\(error.localizedDescription)" }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && !Task.isCancelled && Date() < deadline { Thread.sleep(forTimeInterval: 0.03) }
        if process.isRunning {
            process.terminate()
            let stop = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < stop { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return "Docker 查询超时或已取消；可回收空间未知。"
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let reader = try? FileHandle(forReadingFrom: url) else { return "Docker 引擎不可用或无读取权限；可回收空间未知。" }
        defer { try? reader.close() }
        let data = (try? reader.read(upToCount: 65536)) ?? Data()
        return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 } ?? "Docker 未返回占用数据。"
    }
}
