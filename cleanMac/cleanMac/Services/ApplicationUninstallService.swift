import Foundation

struct AdministratorMoveOutcome: Sendable {
    let succeeded: Bool
    let message: String?
}

/// Finder 无法回收受权限保护的应用时，一次管理员授权处理整批应用。
enum ApplicationUninstallService {
    nonisolated static func moveToTrashWithAdministratorPrivileges(appPaths: [String]) -> [String: AdministratorMoveOutcome] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let allowedParents = [
            URL(fileURLWithPath: "/Applications").standardizedFileURL.path,
            home.appendingPathComponent("Applications", isDirectory: true).path
        ]
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        var outcomes: [String: AdministratorMoveOutcome] = [:]
        guard let trashAttributes = try? fileManager.attributesOfItem(atPath: trash.path),
              (trashAttributes[.type] as? FileAttributeType) == .typeDirectory else {
            for path in appPaths {
                outcomes[path] = .init(succeeded: false, message: "无法访问当前用户的废纸篓。")
            }
            return outcomes
        }

        var moves: [(source: String, destination: String)] = []
        for path in Set(appPaths) {
            let source = URL(fileURLWithPath: path).standardizedFileURL
            let parent = source.deletingLastPathComponent().path
            let resolvedParent = source.deletingLastPathComponent().resolvingSymlinksInPath().path
            guard allowedParents.contains(parent),
                  parent == resolvedParent,
                  source.pathExtension.lowercased() == "app",
                  source.path != Bundle.main.bundleURL.standardizedFileURL.path,
                  SafetyWhitelist.canDelete(path: source.path),
                  !SafetyWhitelist.isProtectedApp(path: source.path),
                  let attributes = try? fileManager.attributesOfItem(atPath: source.path),
                  (attributes[.type] as? FileAttributeType) == .typeDirectory else {
                outcomes[path] = .init(succeeded: false, message: "应用路径无效、受保护或不在支持的应用程序目录中。")
                continue
            }
            let destination = trash.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).app")
            moves.append((source.path, destination.path))
        }
        guard !moves.isEmpty else { return outcomes }

        let owner = "\(getuid()):\(getgid())"
        let script = """
        on run argv
            set commandText to "set -f; "
            repeat with itemIndex from 1 to (count of argv) by 2
                set sourcePath to item itemIndex of argv
                set destinationPath to item (itemIndex + 1) of argv
                set commandText to commandText & "/bin/mv -n " & quoted form of sourcePath & " " & quoted form of destinationPath & " 2>&1 && /usr/sbin/chown -R \(owner) " & quoted form of destinationPath & " 2>&1; "
            end repeat
            set commandText to commandText & "/usr/bin/true"
            do shell script commandText with administrator privileges
        end run
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + moves.flatMap { [$0.source, $0.destination] }
        process.standardOutput = output
        process.standardError = output

        var processError: String?
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                processError = String(detail.prefix(300))
            } else if process.terminationStatus != 0 {
                processError = "管理员授权未完成。"
            }
        } catch {
            processError = error.localizedDescription
        }

        for move in moves {
            let succeeded = !fileManager.fileExists(atPath: move.source)
                && fileManager.fileExists(atPath: move.destination)
            outcomes[move.source] = .init(
                succeeded: succeeded,
                message: succeeded ? nil : (processError ?? "管理员授权后仍未能移动应用。")
            )
        }
        return outcomes
    }
}
