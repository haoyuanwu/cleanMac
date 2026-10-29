import Foundation
import Security
import Darwin

nonisolated enum StartupInspectionService {
    static func presence(_ path: String?) -> String {
        guard let path, path.hasPrefix("/") else { return "执行路径待解析" }
        do { _ = try FileManager.default.attributesOfItem(atPath: path); return "文件存在" }
        catch {
            return isRemovalMissingError(error) ? "文件不存在" : "无法确认文件是否存在：\(error.localizedDescription)"
        }
    }
    static func signature(_ path: String?) -> String {
        guard let path, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return "签名未检查" }
        var code: SecStaticCode?
        let creation = SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code)
        if creation == errSecCSUnsigned { return "未签名（不代表恶意）" }
        guard creation == errSecSuccess, let code else { return "无法读取签名：\(creation)" }
        let status = SecStaticCodeCheckValidity(code, [], nil)
        if status == errSecCSUnsigned { return "未签名（不代表恶意）" }
        return status == errSecSuccess ? "签名完整性校验通过；未验证 Apple 信任或公证" : "完整性校验未通过或不可用：\(status)；不作为恶意判定"
    }
    static func launchItem(_ url: URL, source: String) -> InspectionItem? {
        guard let plist = InspectionFS.plist(url) else { return nil }
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let path = program?.hasPrefix("/") == true ? URL(fileURLWithPath: program!).standardizedFileURL.path : nil
        return InspectionItem(id: "launch:" + url.path, name: plist["Label"] as? String ?? url.lastPathComponent,
            owner: source, kind: source.contains("Daemon") ? "LaunchDaemon" : "LaunchAgent", path: url.path,
            source: source, notes: ["声明的执行路径：\(program ?? "未提供")", presence(path), signature(path),
                "plist 声明不代表服务当前正在运行；路径不存在也不代表恶意。"])
    }
    /// dumpbtm 是只读枚举，不调用 resetbtm，也不请求管理员权限。
    static func loginItems(from text: String) -> [InspectionItem] {
        var records: [[String: String]] = [], current: [String: String] = [:]
        var uid = "未提供"
        func append() {
            if current["Name"] != nil || current["URL"] != nil {
                current["UID"] = uid; records.append(current)
            }
            current = [:]
        }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: "^UID\\s*:?\\s*-?[0-9]+", options: .regularExpression) {
                append()
                uid = String(trimmed[range]).replacingOccurrences(of: "[^0-9-]", with: "", options: .regularExpression)
                continue
            }
            if trimmed.range(of: "^#?[0-9]+:", options: .regularExpression) != nil || trimmed.hasPrefix("UUID:") { append() }
            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if ["Name", "URL", "Executable Path", "Identifier", "Type", "Disposition", "Developer Name"].contains(key) { current[key] = value }
        }
        append()
        var seen = Set<String>()
        return records.compactMap { record in
            let raw = record["Executable Path"] ?? record["URL"] ?? ""
            let path = raw.hasPrefix("file:") ? URL(string: raw)?.path ?? raw : raw
            let id = (record["UID"] ?? "未提供") + "|" + (record["Identifier"] ?? record["Name"] ?? "") + "|" + raw
            guard seen.insert(id).inserted else { return nil }
            return InspectionItem(id: "btm:" + id, name: record["Name"] ?? record["Identifier"] ?? "登录项",
                owner: "登录与后台项目", kind: record["Type"] ?? "Login Item", path: path,
                source: "系统后台任务管理数据库（sfltool dumpbtm）", notes: [
                    "用户范围 UID：\(record["UID"] ?? "未提供")", "开发者声明：\(record["Developer Name"] ?? "未提供")", "系统记录：\(record["Disposition"] ?? "未提供")",
                    presence(path), signature(path), "系统记录可能包含历史或其他用户的项目；此处不修改启用状态，以系统设置为准。"
                ])
        }
    }
    static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     systemLibrary: URL = URL(fileURLWithPath: "/Library"), loginText: String? = nil,
                     includeAppleServices: Bool = false, appleLibrary: URL = URL(fileURLWithPath: "/System/Library")) -> InspectionReport {
        let collector = ScanDiagnosticsCollector()
        return ScanContext.$diagnostics.withValue(collector) {
            var items: [InspectionItem] = []
            var roots = [(home.appendingPathComponent("Library/LaunchAgents"), "用户 LaunchAgents"),
                         (systemLibrary.appendingPathComponent("LaunchAgents"), "系统级 LaunchAgents"),
                         (systemLibrary.appendingPathComponent("LaunchDaemons"), "系统级 LaunchDaemons")]
            if includeAppleServices {
                roots += [(appleLibrary.appendingPathComponent("LaunchAgents"), "macOS 内置 LaunchAgents"),
                          (appleLibrary.appendingPathComponent("LaunchDaemons"), "macOS 内置 LaunchDaemons")]
            }
            for (root, source) in roots {
                for file in InspectionFS.children(root) where file.pathExtension == "plist" {
                    if Task.isCancelled { return InspectionFS.finish(items, collector: collector) }
                    if let item = launchItem(file, source: source) { items.append(item) }
                }
            }
            var issues: [String] = []
            if let loginText { items += loginItems(from: loginText) }
            else if !Task.isCancelled {
                let output = loginDump()
                if let error = output.error { issues.append(error) }
                else {
                    let login = loginItems(from: output.text)
                    items += login
                    if login.isEmpty { issues.append("系统未返回可解析的登录项目；请在系统设置核对登录项，不能据此认定没有登录项。") }
                }
            }
            if !Task.isCancelled {
                let apps = ApplicationCacheScanner.installedApplications().map(\.application)
                let overrides = home.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
                    ? StartupControlService.overrides() : nil
                items = items.map { original in
                    var item = original
                    let plist = item.id.hasPrefix("launch:") ? InspectionFS.plist(URL(fileURLWithPath: item.path)) : nil
                    let program = (plist?["Program"] as? String) ?? (plist?["ProgramArguments"] as? [String])?.first ?? item.path
                    item.application = InspectionSoftwareIdentity.application(path: program, identifier: plist?["Label"] as? String, applications: apps)
                    if let label = plist?["Label"] as? String {
                        item.startupLabel = label
                        if URL(fileURLWithPath: item.path).deletingLastPathComponent().standardizedFileURL == home.appendingPathComponent("Library/LaunchAgents").standardizedFileURL {
                            item.startupEnabled = overrides.map { !($0[label] ?? (plist?["Disabled"] as? Bool ?? false)) }
                        }
                        item.startupCanControl = item.startupEnabled != nil && StartupControlService.canControl(item, home: home)
                    }
                    return item
                }
            }
            return InspectionFS.finish(items, collector: collector, issues: issues)
        }
    }
    static func loginDump(timeout: TimeInterval = 6) -> (text: String, error: String?) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cleanmac-login-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forWritingTo: url) else { return ("", "无法建立本地登录项读取缓冲区。") }
        defer { try? handle.close(); try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sfltool")
        process.arguments = ["dumpbtm"]
        process.standardOutput = handle
        process.standardError = handle
        do { try process.run() } catch { return ("", "无法读取系统登录项：\(error.localizedDescription)") }
        let start = Date()
        while process.isRunning && !Task.isCancelled && Date().timeIntervalSince(start) < timeout { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return ("", "登录项读取超时或已取消；请打开系统设置查看，本次登录项清单不完整。")
        }
        process.waitUntilExit()
        guard let reader = try? FileHandle(forReadingFrom: url) else { return ("", "无法读取登录项结果。") }
        defer { try? reader.close() }
        let data = (try? reader.read(upToCount: 2 * 1024 * 1024)) ?? Data()
        guard process.terminationStatus == 0, data.count < 2 * 1024 * 1024 else { return ("", "系统登录项不可用、权限不足或返回内容超过读取上限。") }
        return (String(data: data, encoding: .utf8) ?? "", nil)
    }
}


nonisolated enum InspectionSoftwareIdentity {
    static func application(path: String, identifier: String?, applications: [CacheApplication]) -> CacheApplication? {
        let exactPath = applications.filter { app in app.path.map { path == $0 || path.hasPrefix($0 + "/") } ?? false }
        if let app = exactPath.max(by: { ($0.path?.count ?? 0) < ($1.path?.count ?? 0) }) { return app }
        guard let identifier else { return nil }
        let matches = applications.filter { identifier == $0.id || identifier.hasPrefix($0.id + ".") }
        return matches.max(by: { $0.id.count < $1.id.count })
    }
}

/// 只改变当前用户第三方 LaunchAgent 的下次加载策略，不停止进程或提权。
nonisolated enum StartupControlService {
    static func parseOverrides(_ text: String) -> [String: Bool] {
        var values: [String: Bool] = [:]
        for line in text.components(separatedBy: .newlines) {
            let pieces = line.components(separatedBy: "=>")
            guard pieces.count == 2 else { continue }
            let label = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let state = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if state == "true" { values[label] = true }
            if state == "false" { values[label] = false }
        }
        return values
    }
    static func canControl(_ item: InspectionItem, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard item.application != nil, let label = item.startupLabel, !label.hasPrefix("com.apple."), !label.lowercased().hasPrefix("com.cleanmac."),
              !label.hasPrefix(Bundle.main.bundleIdentifier ?? "com.cleanMac.cache.cleanMac"),
              label.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$", options: .regularExpression) != nil,
              !UserWhitelist.isWhitelisted(item.path),
              item.application?.path.map({ !UserWhitelist.isWhitelisted($0) && !SafetyWhitelist.isProtectedApp(path: $0) }) ?? true else { return false }
        let url = URL(fileURLWithPath: item.path).standardizedFileURL
        let root = home.appendingPathComponent("Library/LaunchAgents").standardizedFileURL
        guard url.deletingLastPathComponent() == root, url.pathExtension == "plist",
              let attrs = InspectionFS.attributes(url), attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = (attrs[.posixPermissions] as? NSNumber)?.intValue, permissions & 0o022 == 0,
              InspectionFS.plist(url)?["Label"] as? String == label else { return false }
        return true
    }
    static func run(_ arguments: [String], timeout: TimeInterval = 3) -> (status: Int32, output: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cleanmac-launchctl-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let handle = try? FileHandle(forWritingTo: url) else { return (-1, "无法建立诊断缓冲") }
        defer { try? handle.close(); try? FileManager.default.removeItem(at: url) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments; process.standardOutput = handle; process.standardError = handle
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let stop = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < stop { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit(); return (-1, "系统响应超时，请重新检查状态")
        }
        process.waitUntilExit()
        let reader = try? FileHandle(forReadingFrom: url); defer { try? reader?.close() }
        let data = (try? reader?.read(upToCount: 1024 * 1024)) ?? Data()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
    static func overrides() -> [String: Bool]? {
        let result = run(["print-disabled", "gui/\(getuid())"])
        guard result.status == 0, result.output.contains("disabled services") else { return nil }
        return parseOverrides(result.output)
    }
    static func setEnabled(_ enabled: Bool, item: InspectionItem,
                           home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           runCommand: ([String]) -> (status: Int32, output: String) = { run($0) }) -> String? {
        guard canControl(item, home: home), let label = item.startupLabel else { return "路径、归属或保护条件已变化，无法修改，请重新检查。" }
        let result = runCommand([enabled ? "enable" : "disable", "gui/\(getuid())/" + label])
        guard result.status == 0 else { return "系统未能修改启动策略：" + String(result.output.prefix(500)) }
        let verification = runCommand(["print-disabled", "gui/\(getuid())"])
        guard verification.status == 0, verification.output.contains("disabled services"),
              !(parseOverrides(verification.output)[label] ?? (InspectionFS.plist(URL(fileURLWithPath: item.path))?["Disabled"] as? Bool ?? false)) == enabled else { return "启动策略已请求修改，但未能确认结果；请重新检查或到系统设置核对。" }
        AppLog.info("startup launch policy changed", metadata: ["label": label, "enabled": String(enabled)])
        return nil
    }
}
