import Foundation

nonisolated struct SpaceInsight: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let logicalBytes: Int64
    let evidence: [String]
    let paths: [String]
}

nonisolated enum LocalSpaceInsights {
    static func build(results: [ScanCategory: ScanResult], comparison: CacheScanComparison?,
                      duplicates: [DuplicateFileScanner.DuplicateGroup], now: Date = Date(),
                      accessDates: [String: Date]? = nil) -> [SpaceInsight] {
        var suggestions: [SpaceInsight] = []
        func eligible(_ item: FileItem) -> Bool {
            SafetyWhitelist.canDelete(path: item.path) && !SafetyWhitelist.isProtectedApp(path: item.path)
                && item.riskLevel != .blocked && (item.storage?.cloudPlaceholderCount ?? 0) == 0
        }
        if let comparison, comparison.complete, let previous = comparison.previousDate,
           let cacheResult = results[.applicationCache], !cacheResult.isScanning, !cacheResult.isCleaned,
           cacheResult.diagnostics?.status != .cancelled {
            for growth in comparison.growth.prefix(3) where growth.bytes > 0 && growth.paths.allSatisfy({ SafetyWhitelist.canDelete(path: $0) }) {
                suggestions.append(SpaceInsight(id: "growth:" + growth.application, title: "\(growth.application) 的缓存增长",
                    detail: "两次完整扫描之间逻辑大小增加，先查看增长路径及所属软件。", logicalBytes: growth.bytes,
                    evidence: ["上次基线：\(previous.formatted())", "本次扫描：\(comparison.date.formatted())", "\(growth.paths.count) 个增长路径；规则变化会重建基线。", "增长量不等于实际可释放量。"], paths: growth.paths))
            }
        }
        for group in duplicates.sorted(by: { $0.wastedSize > $1.wastedSize }).prefix(3) where group.files.count > 1 {
            let files = group.files.filter(eligible)
            guard files.count > 1 else { continue }
            suggestions.append(SpaceInsight(id: "duplicate:" + group.id, title: "\(files.count) 份疑似重复内容",
                detail: "可先查看副本，确认内容一致后再选择保留项。", logicalBytes: Int64(files.count - 1) * group.size,
                evidence: ["候选按相同大小及分段哈希匹配，未保证整文件逐字节相同。", "哈希线索：\(group.hash)", "保留一份后的冗余逻辑大小，不代表 APFS 精确释放量。"], paths: files.map(\.path)))
        }
        if let result = results[.largeFiles], !result.isScanning, !result.isCleaned, result.diagnostics?.status != .cancelled {
            for file in result.items.sorted(by: { $0.size > $1.size }).prefix(30) where !file.isDirectory && file.size >= 100 * 1024 * 1024 && eligible(file) {
                let access = accessDates?[file.path] ?? (accessDates == nil ? (try? URL(fileURLWithPath: file.path).resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate : nil)
                let date = access ?? file.modificationDate
                guard let date, date <= now, now.timeIntervalSince(date) >= 180 * 86400 else { continue }
                suggestions.append(SpaceInsight(id: "old:" + file.path,
                    title: access == nil ? "修改时间较早的大文件" : "较久未记录访问的大文件",
                    detail: file.name + "；保留、归档或删除请按实际用途决定。", logicalBytes: file.size,
                    evidence: ["\(access == nil ? "修改" : "访问")时间：\(date.formatted())", "超过 180 天；文件系统时间可能未更新，不能证明实际未使用。", "依据已扫描的大文件快照生成，不自动操作文件。"], paths: [file.path]))
                if suggestions.filter({ $0.id.hasPrefix("old:") }).count >= 5 { break }
            }
        }
        if let result = results[.applicationCache], !result.isScanning, !result.isCleaned, result.diagnostics?.status != .cancelled {
            let grouped = Dictionary(grouping: result.items.filter(eligible), by: { $0.cacheApplication?.name ?? "其他应用" })
            if let largest = grouped.max(by: { $0.value.reduce(0) { $0 + $1.size } < $1.value.reduce(0) { $0 + $1.size } }), !largest.value.isEmpty {
                let scope = result.error != nil || result.diagnostics?.status == .partial
                    ? "扫描存在无法读取的路径，此排序仅针对已发现的项目，不代表全盘排行。" : "范围为本次已完成的应用缓存扫描。"
                suggestions.append(SpaceInsight(id: "largest-cache", title: "\(largest.key) 的缓存占用较多",
                    detail: "先在应用缓存页面核对风险与识别依据，再决定处理范围。", logicalBytes: largest.value.reduce(0) { $0 + $1.size },
                    evidence: ["当前扫描中该软件关联的缓存逻辑大小最多。", scope, "\(largest.value.count) 个缓存项目；系统必需路径及白名单不会作为操作建议。", "缓存可能重建，云端占位和共享块影响可释放量。"], paths: largest.value.map(\.path)))
            }
        }
        return suggestions
    }
}
