import Foundation

/// 文件操作工具
enum FileHelper: Sendable {
    nonisolated private static let fileManager = ScanFileAccess()
    
    /// 计算目录大小（跳过符号链接，避免重复计算）
    nonisolated static func directorySize(_ path: String) -> Int64 {
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }
        var logical: Int64 = 0, allocated: Int64 = 0, placeholders = 0
        var complete = true
        while let file = enumerator.nextObject() as? URL {
            if Task.isCancelled { complete = false; break }
            guard let attrs = try? fileManager.attributesOfItem(atPath: file.path) else { complete = false; continue }
            guard attrs[.type] as? FileAttributeType == .typeRegular else { continue }
            logical += (attrs[.size] as? Int64) ?? 0
            if let measurement = FileStorageMeasurement.file(file) {
                placeholders += measurement.cloudPlaceholderCount
                if let bytes = measurement.allocatedBytes { allocated += bytes } else { complete = false }
            } else { complete = false }
        }
        // 枚举失败时，分配大小不能当作完整值。
        if ScanContext.diagnostics?.snapshot().issues.contains(where: { $0.path == path || $0.path.hasPrefix(path + "/") }) == true {
            complete = false
        }
        ScanContext.diagnostics?.remember(.init(logicalBytes: logical, allocatedBytes: complete ? allocated : nil,
                                                cloudPlaceholderCount: placeholders), for: path)
        return logical
    }

    nonisolated static func directorySizeRecursive(_ path: String) -> Int64 {
        directorySize(path)
    }

    /// 检查路径是否存在
    nonisolated static func pathExists(_ path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }
    
    /// 获取文件属性
    nonisolated static func attributes(of path: String) -> [FileAttributeKey: Any]? {
        try? fileManager.attributesOfItem(atPath: path)
    }
}
