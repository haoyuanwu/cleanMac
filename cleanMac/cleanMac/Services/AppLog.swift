import Foundation
import AppKit

/// 应用日志：权限失败、删除失败、dry-run 等
enum AppLog {
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    nonisolated(unsafe) private static let queue = DispatchQueue(label: "com.cleanMac.applog", qos: .utility)
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    nonisolated static var logFileURL: URL {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/cleanMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("cleanMac.log")
    }

    nonisolated static func debug(_ message: String, metadata: [String: String] = [:]) {
        write(.debug, message, metadata: metadata)
    }

    nonisolated static func info(_ message: String, metadata: [String: String] = [:]) {
        write(.info, message, metadata: metadata)
    }

    nonisolated static func warn(_ message: String, metadata: [String: String] = [:]) {
        write(.warn, message, metadata: metadata)
    }

    nonisolated static func error(_ message: String, metadata: [String: String] = [:]) {
        write(.error, message, metadata: metadata)
    }

    nonisolated static func write(_ level: Level, _ message: String, metadata: [String: String] = [:]) {
        let timestamp = formatter.string(from: Date())
        let meta = metadata.isEmpty ? "" : " " + metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        let line = "[\(timestamp)] [\(level.rawValue)] \(message)\(meta)\n"
        let url = logFileURL
        queue.async {
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: url.path) {
                    if let handle = try? FileHandle(forWritingTo: url) {
                        defer { try? handle.close() }
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                    }
                } else {
                    try? data.write(to: url)
                }
            }
            #if DEBUG
            fputs(line, stderr)
            #endif
        }
    }

    /// 打开日志文件
    static func revealLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }
}
