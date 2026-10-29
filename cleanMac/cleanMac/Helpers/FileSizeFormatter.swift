import Foundation

enum FileSizeFormatter: Sendable {
    private nonisolated(unsafe) static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.countStyle = .file
        return f
    }()
    
    nonisolated static func string(fromByteCount count: Int64) -> String {
        if count == 0 { return "0 B" }
        if count > 0 && count < 1024 { return "\(count) B" }
        return formatter.string(fromByteCount: count)
    }
}
