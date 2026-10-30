import Foundation

/// 智能一键清理：从扫描结果生成低风险推荐集
struct SmartCleanPlan: Identifiable {
    let id = UUID()
    let items: [FileItem]
    let totalSize: Int64
    let categorySummary: [(category: ScanCategory, size: Int64, count: Int)]
    let categoryByPath: [String: ScanCategory]

    var totalSizeFormatted: String {
        FileSizeFormatter.string(fromByteCount: totalSize)
    }

    var isEmpty: Bool { items.isEmpty }

    static func build(from scanResults: [ScanCategory: ScanResult]) -> SmartCleanPlan {
        let owned = ScanPathOwnership.unique(ScanCategory.allCases.compactMap { category in
            guard category != .trash, let result = scanResults[category], !result.isCleaned,
                  result.diagnostics?.status != .cancelled, result.diagnostics?.status != .running else { return nil }
            return (category, result.items)
        })
        var picked: [FileItem] = []
        var summary: [(ScanCategory, Int64, Int)] = []
        var categoryByPath: [String: ScanCategory] = [:]

        for category in ScanCategory.allCases {
            guard let result = scanResults[category],
                  !result.isCleaned,
                  result.diagnostics?.status != .cancelled,
                  result.diagnostics?.status != .running,
                  !result.items.isEmpty else { continue }

            let recommended = owned.filter { $0.0 == category }.map { $0.1 }.filter {
                SafetyWhitelist.isRecommendedForAutoClean($0.riskLevel)
                    && SafetyWhitelist.canDelete(path: $0.path)
                    && ($0.storage?.cloudPlaceholderCount ?? 0) == 0
            }
            guard !recommended.isEmpty else { continue }

            let size = recommended.reduce(Int64(0)) { $0 + $1.size }
            picked.append(contentsOf: recommended)
            for item in recommended { categoryByPath[item.path] = category }
            summary.append((category, size, recommended.count))
        }

        let total = picked.reduce(Int64(0)) { $0 + $1.size }
        return SmartCleanPlan(items: picked, totalSize: total, categorySummary: summary, categoryByPath: categoryByPath)
    }

    /// 保留扫描时的类别归属；同一软件在不同类别下的项目分别检查。
    func reviewGroups(query: String = "", sort: SmartCleanReviewSort = .size) -> [SmartCleanReviewGroup] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = items.filter { item in
            let owner = categoryByPath[item.path]
            return query.isEmpty || [item.name, item.path, item.cacheApplication?.name ?? "", owner?.rawValue ?? ""]
                    .contains { $0.localizedStandardContains(query) }
        }
        let grouped = Dictionary(grouping: visible) { item in
            SmartCleanReviewGroup.Key(category: categoryByPath[item.path] ?? .systemCache,
                                      application: item.cacheApplication)
        }
        return grouped.map { key, files in
            SmartCleanReviewGroup(key: key, items: files.sorted { left, right in
                switch sort {
                case .size:
                    if left.size != right.size { return left.size > right.size }
                case .name:
                    let order = left.name.localizedStandardCompare(right.name)
                    if order != .orderedSame { return order == .orderedAscending }
                case .modified:
                    let l = left.modificationDate ?? .distantPast, r = right.modificationDate ?? .distantPast
                    if l != r { return l > r }
                }
                return left.path < right.path
            })
        }.sorted {
            if $0.key.category != $1.key.category {
                return (ScanCategory.allCases.firstIndex(of: $0.key.category) ?? 0)
                    < (ScanCategory.allCases.firstIndex(of: $1.key.category) ?? 0)
            }
            if $0.totalSize != $1.totalSize { return $0.totalSize > $1.totalSize }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

enum SmartCleanReviewSort: String, CaseIterable, Identifiable {
    case size = "大小优先", name = "名称排序", modified = "最近修改"
    var id: String { rawValue }
}

struct SmartCleanReviewGroup: Identifiable {
    struct Key: Hashable {
        let category: ScanCategory
        let application: CacheApplication?
    }
    let key: Key
    let items: [FileItem]
    var id: Key { key }
    var name: String { key.application?.name ?? key.category.rawValue }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// 时间线分层（大文件）
enum FileAgeBucket: String, CaseIterable, Identifiable, Sendable {
    case last30Days = "30 天内"
    case lastYear = "1 年内"
    case older = "1 年以上"
    case unknown = "时间未知"

    var id: String { rawValue }

    static func bucket(for date: Date?) -> FileAgeBucket {
        guard let date else { return .unknown }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days <= 30 { return .last30Days }
        if days <= 365 { return .lastYear }
        return .older
    }
}

enum FileTimeline {
    static func group(_ items: [FileItem]) -> [(bucket: FileAgeBucket, items: [FileItem], totalSize: Int64)] {
        var map: [FileAgeBucket: [FileItem]] = [:]
        for item in items {
            map[FileAgeBucket.bucket(for: item.modificationDate), default: []].append(item)
        }
        return FileAgeBucket.allCases.compactMap { bucket in
            guard let list = map[bucket], !list.isEmpty else { return nil }
            let sorted = list.sorted { $0.size > $1.size }
            return (bucket, sorted, sorted.reduce(Int64(0)) { $0 + $1.size })
        }
    }
}
