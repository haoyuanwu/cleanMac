import Foundation

/// 文件操作工具
enum FileHelper: Sendable {
    nonisolated(unsafe) private static let fileManager = FileManager.default
    
    /// 计算目录大小（跳过符号链接，避免重复计算）
    nonisolated static func directorySize(_ path: String) -> Int64 {
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }
        var totalSize: Int64 = 0
        
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            
            // 获取文件属性（不跟随符号链接）
            guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath) else { continue }
            
            // 跳过符号链接
            let fileType = attrs[.type] as? FileAttributeType
            if fileType == .typeSymbolicLink {
                continue
            }
            
            // 只计算文件大小，不计算目录元数据大小
            if fileType == .typeRegular {
                totalSize += (attrs[.size] as? Int64) ?? 0
            }
        }
        
        return totalSize
    }
    
    /// 计算目录大小（包含子目录，但跳过符号链接）
    nonisolated static func directorySizeRecursive(_ path: String) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var totalSize: Int64 = 0
        
        for case let fileURL as URL in enumerator {
            // 跳过符号链接
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            
            if resourceValues?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            
            if resourceValues?.isRegularFile == true {
                totalSize += Int64(resourceValues?.fileSize ?? 0)
            }
        }
        
        return totalSize
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
