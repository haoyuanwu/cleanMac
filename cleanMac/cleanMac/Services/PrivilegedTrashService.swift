import Foundation

struct PrivilegedTrashOutcome: Sendable {
    let succeeded: Bool
    let message: String?
}

/// 普通回收遇到权限不足时，将扫描器支持的缓存和日志项目批量移入废纸篓。
enum PrivilegedTrashService {
    nonisolated static func isSupportedItem(_ path: String) -> Bool {
        let source = URL(fileURLWithPath: path).standardizedFileURL
        let resolved = source.resolvingSymlinksInPath()
        let candidates = [source.path, resolved.path]

        for candidate in candidates {
            // 日志：/var/log 与 /Library/Logs 下任意层级
            if candidate.hasPrefix("/var/log/")
                || candidate.hasPrefix("/private/var/log/")
                || candidate.hasPrefix("/Library/Logs/") {
                return true
            }
            // 系统/本地缓存目录下
            if candidate.hasPrefix("/Library/Caches/")
                || candidate.hasPrefix("/System/Library/Caches/") {
                return true
            }
        }
        return false
    }

    /// 一次 AppleScript 管理员授权处理整批项目，并按目标是否实际出现逐项反馈。
    nonisolated static func moveToTrash(paths: [String]) -> [String: PrivilegedTrashOutcome] {
        let fileManager = FileManager.default
        let trash = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        var outcomes: [String: PrivilegedTrashOutcome] = [:]
        guard let trashAttributes = try? fileManager.attributesOfItem(atPath: trash.path),
              (trashAttributes[.type] as? FileAttributeType) == .typeDirectory else {
            for path in paths {
                outcomes[path] = .init(succeeded: false, message: "无法访问当前用户的废纸篓。")
            }
            return outcomes
        }

        var moves: [(source: String, destination: String)] = []
        for path in Set(paths) {
            let source = URL(fileURLWithPath: path).standardizedFileURL
            guard isSupportedItem(source.path),
                  DeleteDryRun.validate(path: source.path, context: "privileged-trash").allowed,
                  let attributes = try? fileManager.attributesOfItem(atPath: source.path),
                  let type = attributes[.type] as? FileAttributeType,
                  type == .typeDirectory || type == .typeRegular else {
                outcomes[path] = .init(succeeded: false, message: "缓存或日志路径无效，或不在支持的目录中。")
                continue
            }
            let destination = trash.appendingPathComponent("\(source.lastPathComponent)-\(UUID().uuidString)")
            moves.append((source.path, destination.path))
        }
        guard !moves.isEmpty else { return outcomes }

        // 路径由 AppleScript 的 quoted form 转义；所有移动和归属修正共用一次管理员授权。
        // 归属修正确保移入用户废纸篓后，后续清空废纸篓不再需要管理员密码。
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
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                processError = String(detail.prefix(300))
            } else if process.terminationStatus != 0 {
                processError = "管理员授权未完成。"
            }
        } catch {
            processError = error.localizedDescription
        }

        for move in moves {
            let succeeded = fileManager.fileExists(atPath: move.destination)
                && !fileManager.fileExists(atPath: move.source)
            outcomes[move.source] = .init(
                succeeded: succeeded,
                message: succeeded ? nil : (processError ?? "管理员授权后仍未能移动项目，请检查系统保护或文件权限。")
            )
        }
        return outcomes
    }
}
