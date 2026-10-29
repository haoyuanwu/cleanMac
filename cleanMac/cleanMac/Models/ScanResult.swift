import Foundation

/// 单个类别的扫描结果
nonisolated struct ScanResult: Identifiable, Sendable {
    let id = UUID()
    let category: ScanCategory
    var items: [FileItem]
    var overlappingItems: [FileItem] = []
    var isScanning: Bool = false
    var isCleaned: Bool = false
    var error: String?
    var diagnostics: ScanDiagnostics?
    
    var allocatedSize: Int64? {
        guard items.allSatisfy({ $0.storage?.allocatedBytes != nil }) else { return nil }
        return items.reduce(0) { $0 + ($1.storage?.allocatedBytes ?? 0) }
    }

    var cloudPlaceholderCount: Int { items.reduce(0) { $0 + ($1.storage?.cloudPlaceholderCount ?? 0) } }

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }
    
    var totalSizeFormatted: String {
        FileSizeFormatter.string(fromByteCount: totalSize)
    }
    
    var itemCount: Int {
        items.count
    }
}

/// 全局扫描状态
enum ScanState {
    case idle
    case scanning
    case completed
    case cleaning
    case error(String)
}
