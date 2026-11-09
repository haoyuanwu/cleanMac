import Foundation

nonisolated enum DevelopmentStorageKind: String, CaseIterable, Sendable {
    case packages = "包管理器"
    case ai = "AI / 工具链"
    case containers = "容器与虚拟机"
    case projects = "工程产物"

    var symbol: String {
        switch self {
        case .packages: "shippingbox"
        case .ai: "cpu"
        case .containers: "externaldrive"
        case .projects: "hammer"
        }
    }
    var subtitle: String {
        switch self {
        case .packages: "Homebrew、npm、pnpm、yarn、pip、Cargo、Gradle 与 CocoaPods 的下载及构建缓存。"
        case .ai: "按软件查看模型、工具链与编程工具，展开临时文件、缓存和日志并手动清理。"
        case .containers: "查看 Docker 引擎报告的可回收空间，以及本机虚拟机磁盘的实际占用。"
        case .projects: "在 Desktop、Documents、Projects、Developer、Code、repos 中查找可再生依赖与构建目录。"
        }
    }
}

nonisolated struct DevelopmentStorageEntry: Identifiable, Sendable {
    var id: String { file.path }
    let file: FileItem
    let owner: String
    let detail: String
    let cleanable: Bool
    var children: [DevelopmentStorageEntry] = []

    var descendants: [DevelopmentStorageEntry] { [self] + children.flatMap(\.descendants) }

    func matching(_ query: String) -> DevelopmentStorageEntry? {
        if query.isEmpty || (owner + " " + file.path).localizedCaseInsensitiveContains(query) { return self }
        let matches = children.compactMap { $0.matching(query) }
        guard !matches.isEmpty else { return nil }
        return DevelopmentStorageEntry(file: file, owner: owner, detail: detail, cleanable: cleanable, children: matches)
    }

    /// 保留软件根目录的单次统计，同时更新已清理子目录对应的占用。
    func removing(_ paths: Set<String>) -> DevelopmentStorageEntry? {
        guard !paths.contains(where: { id == $0 || id.hasPrefix($0 + "/") }) else { return nil }
        let remaining = children.compactMap { $0.removing(paths) }
        let removedBytes = children.reduce(0) { $0 + $1.file.size } - remaining.reduce(0) { $0 + $1.file.size }
        guard remaining.flatMap(\.descendants).map(\.id) != children.flatMap(\.descendants).map(\.id) else { return self }
        let newSize = max(0, file.size - removedBytes)
        let oldAllocated = children.compactMap { $0.file.storage?.allocatedBytes }
        let newAllocated = remaining.compactMap { $0.file.storage?.allocatedBytes }
        let allocated: Int64? = if let previous = file.storage?.allocatedBytes,
            oldAllocated.count == children.count, newAllocated.count == remaining.count {
            max(0, previous - oldAllocated.reduce(0, +) + newAllocated.reduce(0, +))
        } else { nil }
        var updated = FileItem(path: id, name: file.name, size: newSize, modificationDate: file.modificationDate,
            isDirectory: file.isDirectory, storage: .init(logicalBytes: newSize, allocatedBytes: allocated,
                cloudPlaceholderCount: file.storage?.cloudPlaceholderCount ?? 0))
        updated.riskLevel = file.riskLevel
        return DevelopmentStorageEntry(file: updated, owner: owner, detail: detail, cleanable: cleanable, children: remaining)
    }
}

nonisolated struct DevelopmentStorageReport: Sendable {
    let entries: [DevelopmentStorageEntry]
    let diagnostics: ScanDiagnostics
    let docker: String?
}

/// 选择范围与当前显示清单一致；筛选收窄后不保留隐藏的已选目录。
nonisolated enum DevelopmentStorageSelection {
    static func eligible(_ entries: [DevelopmentStorageEntry]) -> [DevelopmentStorageEntry] {
        let protected = UserWhitelist.paths
        return entries.filter { entry in
            entry.cleanable && SafetyWhitelist.canDelete(path: entry.id)
                && !protected.contains(where: { entry.id == $0 || entry.id.hasPrefix($0 + "/") || $0.hasPrefix(entry.id + "/") })
        }
    }
    static func selectAll(_ entries: [DevelopmentStorageEntry]) -> Set<String> {
        Set(eligible(entries).map(\.id))
    }
    static func invert(_ selection: Set<String>, in entries: [DevelopmentStorageEntry]) -> Set<String> {
        selectAll(entries).subtracting(selection)
    }
    static func reconcile(_ selection: Set<String>, visible: [DevelopmentStorageEntry]) -> Set<String> {
        selection.intersection(eligible(visible).map(\.id))
    }
    static func targets(_ selection: Set<String>, visible: [DevelopmentStorageEntry]) -> [DevelopmentStorageEntry] {
        eligible(visible).filter { selection.contains($0.id) }
    }
}

nonisolated struct DevelopmentStorageReview: Identifiable, Sendable {
    let id = UUID()
    let kind: DevelopmentStorageKind
    let entries: [DevelopmentStorageEntry]
    var totalSize: Int64 { entries.reduce(0) { $0 + $1.file.size } }
}
