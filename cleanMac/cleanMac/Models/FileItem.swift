import Foundation
import AppKit

/// 单个可清理文件
struct FileItem: Identifiable, Hashable, @unchecked Sendable {
    let id = UUID()
    let path: String
    let name: String
    let size: Int64
    let modificationDate: Date?
    let isDirectory: Bool
    nonisolated(unsafe) let appIcon: NSImage?
    
    nonisolated init(path: String, name: String, size: Int64, modificationDate: Date?, isDirectory: Bool, appIcon: NSImage? = nil) {
        self.path = path
        self.name = name
        self.size = size
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
        self.appIcon = appIcon
    }
    
    var sizeFormatted: String {
        FileSizeFormatter.string(fromByteCount: size)
    }
    
    var pathURL: URL {
        URL(fileURLWithPath: path)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
    
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.path == rhs.path
    }
}
