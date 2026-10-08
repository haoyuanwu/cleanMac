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
    /// 风险分级（安全白名单）
    var riskLevel: FileRiskLevel = .safe

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

    /// 是否默认可进入智能清理
    var isAutoCleanRecommended: Bool {
        SafetyWhitelist.isRecommendedForAutoClean(riskLevel)
    }

    /// 是否允许删除
    var isDeletable: Bool {
        SafetyWhitelist.canDelete(path: path)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.path == rhs.path
    }
}
