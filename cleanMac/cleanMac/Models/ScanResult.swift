import Foundation

/// 单个类别的扫描结果
struct ScanResult: Identifiable {
    let id = UUID()
    let category: ScanCategory
    var items: [FileItem]
    var isScanning: Bool = false
    var isCleaned: Bool = false
    var error: String?
    
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
