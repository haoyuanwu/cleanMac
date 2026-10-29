import Foundation
import AppKit

nonisolated struct RunningUninstallApplication: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let bundleIdentifier: String?
    let bundlePath: String?
    let executablePath: String?
    var id: Int32 { pid }
}

nonisolated enum ApplicationUninstallPreflight {
    static func matches(_ process: RunningUninstallApplication, appPaths: Set<String>, bundleIdentifiers: Set<String>) -> Bool {
        if let identifier = process.bundleIdentifier, bundleIdentifiers.contains(identifier) { return true }
        return [process.bundlePath, process.executablePath].compactMap { $0 }.contains { path in
            appPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    static func canUninstall(_ path: String, roots: [String]? = nil, currentAppPath: String = Bundle.main.bundleURL.path) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let roots = roots ?? ["/Applications", FileManager.default.homeDirectoryForCurrentUser.path + "/Applications"]
        guard url.pathExtension.lowercased() == "app", url.path != URL(fileURLWithPath: currentAppPath).standardizedFileURL.path,
              roots.contains(where: { url.path.hasPrefix($0 + "/") }),
              !SafetyWhitelist.isProtectedApp(path: path), !SafetyWhitelist.isBlocked(path: path), !UserWhitelist.isWhitelisted(path),
              url.resolvingSymlinksInPath().path == url.path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              attrs[.type] as? FileAttributeType == .typeDirectory else { return false }
        // 不卸载另一个应用包中的嵌套 helper。
        return !url.deletingLastPathComponent().pathComponents.contains { $0.lowercased().hasSuffix(".app") }
    }
}

@MainActor enum ApplicationRuntimeControl {
    static func running(appPaths: Set<String>, bundleIdentifiers: Set<String>) -> [RunningUninstallApplication] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard !application.isTerminated, application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
            let info = RunningUninstallApplication(pid: application.processIdentifier, name: application.localizedName ?? "后台应用",
                bundleIdentifier: application.bundleIdentifier, bundlePath: application.bundleURL?.standardizedFileURL.path,
                executablePath: application.executableURL?.standardizedFileURL.path)
            return ApplicationUninstallPreflight.matches(info, appPaths: appPaths, bundleIdentifiers: bundleIdentifiers) ? info : nil
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 仅请求正常退出，不强制终止；保存对话框或拒绝退出均保留给用户处理。
    static func requestQuit(_ processes: [RunningUninstallApplication]) async -> [String] {
        var failures: [String] = []
        for info in processes {
            guard let app = NSRunningApplication(processIdentifier: info.pid), !app.isTerminated else { continue }
            guard app.bundleIdentifier == info.bundleIdentifier,
                  app.bundleURL?.standardizedFileURL.path == info.bundlePath else {
                failures.append("\(info.name)：进程身份已变化，请重新检查。"); continue
            }
            if !app.terminate() { failures.append("\(info.name)：系统未接受退出请求。") }
        }
        for _ in 0..<30 {
            if Task.isCancelled { return failures }
            let alive = processes.contains { NSRunningApplication(processIdentifier: $0.pid)?.isTerminated == false }
            if !alive { return failures }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return failures
    }
}
