import Foundation

/// 元数据统计，不读取文件内容，不触发云端文件下载。
nonisolated struct FileStorageMeasurement: Codable, Sendable {
    let logicalBytes: Int64
    let allocatedBytes: Int64?
    let cloudPlaceholderCount: Int

    nonisolated static func file(_ url: URL) -> FileStorageMeasurement? {
        guard let values = try? ScanContext.values(url, keys: [
            .fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]) else { return nil }
        let placeholder = values.isUbiquitousItem == true
            && values.ubiquitousItemDownloadingStatus != .current
            && values.ubiquitousItemDownloadingStatus != .downloaded
        return Self(logicalBytes: Int64(values.fileSize ?? 0),
                    allocatedBytes: (values.totalFileAllocatedSize ?? values.fileAllocatedSize).map(Int64.init),
                    cloudPlaceholderCount: placeholder ? 1 : 0)
    }
}
