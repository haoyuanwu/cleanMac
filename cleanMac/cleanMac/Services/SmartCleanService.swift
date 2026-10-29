import Foundation

/// 智能一键清理：从扫描结果生成低风险推荐集
struct SmartCleanPlan: Identifiable {
    let id = UUID()
    let items: [FileItem]
    let totalSize: Int64
    let categorySummary: [(category: ScanCategory, size: Int64, count: Int)]

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
            summary.append((category, size, recommended.count))
        }

        let total = picked.reduce(Int64(0)) { $0 + $1.size }
        return SmartCleanPlan(items: picked, totalSize: total, categorySummary: summary)
    }
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
