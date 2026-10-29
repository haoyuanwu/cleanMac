import Foundation

/// 同一路径固定归属一个类别；目录及其子路径在一份清单中只计一次。
enum ScanPathOwnership {
    nonisolated static func unique(_ groups: [(ScanCategory, [FileItem])]) -> [(ScanCategory, FileItem)] {
        let priority = [ScanCategory.browserCache, .applicationCache, .systemCache] + ScanCategory.allCases
        let order = Dictionary(priority.enumerated().reversed().map { ($0.element, $0.offset) }, uniquingKeysWith: { _, new in new })
        let candidates = groups.flatMap { category, items in
            items.map { (category, $0, URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path) }
        }.sorted {
            let left = $0.2.split(separator: "/").count, right = $1.2.split(separator: "/").count
            if left != right { return left < right }
            if $0.2 != $1.2 { return $0.2 < $1.2 }
            return order[$0.0, default: 100] < order[$1.0, default: 100]
        }
        var seen = Set<String>(), directories = Set<String>()
        var result: [(ScanCategory, FileItem)] = []
        for (category, item, path) in candidates {
            guard !seen.contains(path) else { continue }
            var parent = (path as NSString).deletingLastPathComponent
            var covered = false
            while !parent.isEmpty {
                if directories.contains(parent) { covered = true; break }
                if parent == "/" { break }
                parent = (parent as NSString).deletingLastPathComponent
            }
            guard !covered else { continue }
            seen.insert(path)
            if item.isDirectory { directories.insert(path) }
            result.append((category, item))
        }
        return result
    }

    static func reconcile(_ results: inout [ScanCategory: ScanResult]) {
        let categories = ScanCategory.overviewScanCategories
        let groups = categories.compactMap { category -> (ScanCategory, [FileItem])? in
            guard let result = results[category], !result.isScanning, !result.isCleaned else { return nil }
            return (category, result.items + result.overlappingItems)
        }
        let retained = Dictionary(grouping: unique(groups), by: { $0.0 })
        for (category, items) in groups {
            let visible = retained[category, default: []].map { $0.1 }
            let paths = Set(visible.map(\.path))
            results[category]?.items = visible
            results[category]?.overlappingItems = items.filter { !paths.contains($0.path) }
        }
    }
}
