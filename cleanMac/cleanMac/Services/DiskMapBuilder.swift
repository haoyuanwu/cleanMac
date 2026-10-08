import Foundation

/// 磁盘地图节点构建
struct DiskMapNode: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let isDirectory: Bool
    var children: [DiskMapNode] = []

    var sizeFormatted: String { FileSizeFormatter.string(fromByteCount: size) }
}

enum DiskMapBuilder {
    /// 列出目录下的一级子项（按大小降序，可上限）
    static func children(of path: String, limit: Int = 24) async -> [DiskMapNode] {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var nodes: [DiskMapNode] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = values?.isDirectory ?? false
            let size: Int64 = await Task.detached(priority: .utility) { () -> Int64 in
                let p = entry.path
                if isDir {
                    return FileHelper.directorySize(p)
                }
                let attrs = try? FileManager.default.attributesOfItem(atPath: p)
                return (attrs?[.size] as? Int64) ?? 0
            }.value

            guard size > 0 else { continue }
            nodes.append(
                DiskMapNode(
                    id: entry.path,
                    name: entry.lastPathComponent,
                    path: entry.path,
                    size: size,
                    isDirectory: isDir
                )
            )
        }
        return nodes
            .sorted { $0.size > $1.size }
            .prefix(limit)
            .map { $0 }
    }

    /// 从扫描结果构建首页级地图（类别 → 顶层大项）
    static func fromScanResults(_ scanResults: [ScanCategory: ScanResult]) async -> DiskMapNode {
        var categoryNodes: [DiskMapNode] = []

        for category in ScanCategory.allCases {
            guard let result = scanResults[category], !result.items.isEmpty, !result.isCleaned else { continue }
            let items = result.items.sorted { $0.size > $1.size }.prefix(16)
            let children = items.map { item -> DiskMapNode in
                DiskMapNode(
                    id: item.path,
                    name: item.name,
                    path: item.path,
                    size: item.size,
                    isDirectory: item.isDirectory
                )
            }
            let total = children.reduce(Int64(0)) { $0 + $1.size }
            categoryNodes.append(
                DiskMapNode(
                    id: "cat-\(category.id)",
                    name: category.rawValue,
                    // 虚拟路径：下钻时优先用已构建 children
                    path: "cleanMac://category/\(category.id)",
                    size: total,
                    isDirectory: true,
                    children: Array(children)
                )
            )
        }

        let total = categoryNodes.reduce(Int64(0)) { $0 + $1.size }
        return DiskMapNode(
            id: "root",
            name: "可清理内容",
            path: "cleanMac://root",
            size: total,
            isDirectory: true,
            children: categoryNodes.sorted { $0.size > $1.size }
        )
    }
}
