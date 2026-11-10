import SwiftUI

/// 玻璃背景上的小字号文字保持足够对比度，不依赖系统 disabled 状态降低可读性。
private enum DevelopmentStoragePalette {
    static let secondary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.84, green: 0.87, blue: 0.93, alpha: 1)
            : NSColor(srgbRed: 0.24, green: 0.27, blue: 0.33, alpha: 1)
    })
}

struct DevelopmentStorageView: View {
    let kind: DevelopmentStorageKind
    @ObservedObject var session: DevelopmentStorageSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var owner = "全部工具"
    private var selected: Set<String> {
        get { session.selections[kind] ?? [] }
        nonmutating set { session.selections[kind] = newValue }
    }
    @State private var expanded = Set<String>()
    private var expandedTools: Set<String> {
        get { session.expandedTools[kind] ?? [] }
        nonmutating set { session.expandedTools[kind] = newValue }
    }
    @State private var sortBySize = true
    private var report: DevelopmentStorageReport? { session.reports[kind] }
    private var allEntries: [DevelopmentStorageEntry] { report?.entries ?? [] }
    private var entries: [DevelopmentStorageEntry] {
        allEntries.filter { owner == "全部工具" || $0.owner == owner }
            .compactMap { kind == .ai ? $0.matching(query) : (query.isEmpty || ($0.owner + " " + $0.file.path).localizedCaseInsensitiveContains(query) ? $0 : nil) }
            .sorted {
                if sortBySize, $0.file.size != $1.file.size { return $0.file.size > $1.file.size }
                return ($0.owner + $0.id).localizedStandardCompare($1.owner + $1.id) == .orderedAscending
            }
    }
    private var visibleEntries: [DevelopmentStorageEntry] {
        kind == .ai ? entries.filter { expandedTools.contains($0.owner) }.flatMap(\.descendants) : entries
    }
    private var eligible: [DevelopmentStorageEntry] { DevelopmentStorageSelection.eligible(visibleEntries) }
    private var bulkEntries: [DevelopmentStorageEntry] { kind == .ai ? entries.flatMap(\.descendants) : entries }
    private var bulkEligible: [DevelopmentStorageEntry] { DevelopmentStorageSelection.eligible(bulkEntries) }
    private var targets: [DevelopmentStorageEntry] { DevelopmentStorageSelection.targets(selected, visible: visibleEntries) }
    private var canClean: Bool { kind == .packages || kind == .projects || kind == .ai }
    private var aiOwners: [String] {
        let groups = Dictionary(grouping: entries, by: \.owner)
        return groups.keys.sorted {
            if sortBySize {
                let left = groups[$0, default: []].reduce(0) { $0 + $1.file.size }
                let right = groups[$1, default: []].reduce(0) { $0 + $1.file.size }
                if left != right { return left > right }
            }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
    private var tint: Color {
        switch kind { case .packages: .indigo; case .ai: .purple; case .containers: .blue; case .projects: .orange }
    }
    private var showingResults: Bool { report != nil && !session.loading.contains(kind) }
    private var motion: Animation { reduceMotion ? .linear(duration: 0.01) : Theme.ease }

    var body: some View {
        GeometryReader { viewport in
            VStack(alignment: .leading, spacing: showingResults ? 7 : 12) {
                header
                if session.loading.contains(kind) {
                    scanning.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else if let report {
                    results(report)
                        .transition(.opacity)
                } else {
                    idle.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 920)
            .padding(.horizontal, 28).padding(.top, showingResults ? 4 : 10).padding(.bottom, showingResults ? 4 : 12)
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
            .animation(motion, value: session.loading.contains(kind))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if report != nil, !session.loading.contains(kind) { footer }
        }
        .onChange(of: query) { _ in
            if kind == .ai, !query.isEmpty { expandedTools.formUnion(entries.map(\.owner)) }
            reconcile()
        }
        .onChange(of: owner) { _ in reconcile() }
        .onChange(of: allEntries.flatMap(\.descendants).map(\.id)) { _ in reconcile() }
        .onChange(of: expandedTools) { _ in reconcile() }
        .onChange(of: kind) { _ in
            expanded.removeAll(); query = ""; owner = "全部工具"
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol).font(.system(size: showingResults ? 17 : 19, weight: .semibold))
                .moduleIconPlate(tint: tint, size: 38, radius: 11)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.rawValue).font(.system(size: showingResults ? 18 : 20, weight: .bold, design: .rounded))
                if showingResults {
                    Text("\(Set(allEntries.map(\.owner)).count) 个工具 · " + (canClean
                        ? "\(DevelopmentStorageSelection.eligible(allEntries.flatMap(\.descendants)).count) 个可选目录"
                        : "\(allEntries.count) 个只读目录"))
                        .font(.system(size: 11)).foregroundStyle(DevelopmentStoragePalette.secondary)
                } else {
                    Text(headerSubtitle).font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.help(headerSubtitle)
            Spacer(minLength: 8)
            if showingResults {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("逻辑占用").font(.system(size: 11)).foregroundStyle(DevelopmentStoragePalette.secondary)
                    Text(FileSizeFormatter.string(fromByteCount: allEntries.reduce(0) { $0 + $1.file.size }))
                        .font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit()
                }.fixedSize().help("已发现目录的逻辑大小，包含其缓存子目录，不等于可回收空间。")
                DetailTextButton(title: "重新扫描", systemImage: "arrow.clockwise", action: scan).disabled(session.busy(for: kind))
            }
        }
    }
    private var headerSubtitle: String {
        switch kind {
        case .packages: "查看开发依赖的下载缓存与构建缓存"
        case .ai: "按软件展开缓存、日志与临时目录，手动选择清理"
        case .containers: "区分引擎可回收空间与虚拟磁盘占用"
        case .projects: "单列项目依赖与构建物，保留普通文档"
        }
    }
    private var idle: some View {
        VStack(spacing: 22) {
            Image(systemName: kind.symbol).font(.system(size: 42, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 100, height: 100)
                .background(Theme.categoryGradient(tint), in: RoundedRectangle(cornerRadius: 28))
                .elevatedShadow().accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("尚未扫描" + kind.rawValue).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(kind.subtitle).font(.system(size: 13)).foregroundStyle(DevelopmentStoragePalette.secondary)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 440)
            }
            Button(action: scan) {
                Label("开始扫描", systemImage: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 24).padding(.vertical, 12)
            }.buttonStyle(GradientButtonStyleCompact()).disabled(session.busy(for: kind))
            Text(canClean ? "扫描后手动选择目录 · 不会自动清理" : "仅盘点占用 · 在所属工具中管理")
                .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
            if session.busy(for: kind) { Text("当前模块正在处理任务，请稍候。").font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary) }
        }.padding(.vertical, 24)
    }
    private var scanning: some View {
        VStack(spacing: 16) {
            ScanningPlaceholderView(title: session.cancelling.contains(kind) ? "正在取消扫描…" : "正在扫描" + kind.rawValue + "…",
                subtitle: "仅统计文件元数据，可切换页面，扫描会在后台继续。",
                diagnostics: session.progress[kind])
            Button(session.cancelling.contains(kind) ? "正在取消…" : "取消扫描", action: { session.cancelScan(kind) })
                .buttonStyle(ReadableControlButtonStyle(tint: .orange))
                .disabled(session.cancelling.contains(kind)).controlSize(.regular)
        }
    }
    @ViewBuilder private func results(_ report: DevelopmentStorageReport) -> some View {
        let selectableIDs = Set(eligible.map(\.id))
        filters
        HStack {
            Text(kind == .ai ? "\(aiOwners.count) 个软件 · 可展开缓存目录" : "\(entries.count) / \(allEntries.count) 个目录").font(.system(size: 12, weight: .medium))
                .foregroundStyle(DevelopmentStoragePalette.secondary)
            Spacer()
            if canClean {
                Button {
                    if targets.isEmpty { selectAll() } else { invertSelection() }
                } label: {
                    Label(targets.isEmpty ? "全选" : "反选",
                          systemImage: targets.isEmpty ? "checkmark.square" : "arrow.triangle.2.circlepath")
                }.keyboardShortcut("a", modifiers: .command)
                    .help(targets.isEmpty ? "全选当前筛选结果中的可清理目录，AI 软件组会自动展开（⌘A）" : "反选当前筛选结果中的可清理目录（⌘A）")
                    .buttonStyle(ReadableControlButtonStyle()).controlSize(.small)
                    .font(.system(size: 12, weight: .medium)).disabled(bulkEligible.isEmpty || session.busy(for: kind))
            } else { Label("仅查看", systemImage: "eye").font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary) }
        }
        ScrollView {
            LazyVStack(spacing: 8) {
                if let message = session.messages[kind] {
                    Label(message, systemImage: (session.failures[kind] ?? []).isEmpty ? "info.circle" : "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary).textSelection(.enabled)
                }
                if let summary = report.diagnostics.summary {
                    Label(summary, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
                }
                if !report.diagnostics.issues.isEmpty || !(session.failures[kind] ?? []).isEmpty {
                    DisclosureGroup("查看读取与处理提示") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(report.diagnostics.issues) { Text($0.path + "：" + $0.message).textSelection(.enabled) }
                                ForEach(session.failures[kind] ?? [], id: \.self) { Text($0).textSelection(.enabled) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }.font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
                }

                if let docker = report.docker { dockerCard(docker) }
                if entries.isEmpty { emptyResults }
                if kind == .ai {
                    ForEach(aiOwners, id: \.self) { tool in aiGroup(tool, selectableIDs: selectableIDs) }
                } else {
                    ForEach(entries) { entry in storageRow(entry, selectableIDs: selectableIDs) }
                }
            }.padding(.bottom, 8)
        }
    }
    private func storageRow(_ entry: DevelopmentStorageEntry, selectableIDs: Set<String>) -> some View {
        DevelopmentStorageRow(entry: entry, kind: kind, isSelected: selected.contains(entry.id),
            selectable: selectableIDs.contains(entry.id), busy: session.busy(for: kind),
            isExpanded: expanded.contains(entry.id), toggle: { toggle(entry.id) }, expand: {
                withAnimation(motion) {
                    if !expanded.insert(entry.id).inserted { expanded.remove(entry.id) }
                }
            })
            .contextMenu {
                Button("在 Finder 中显示", systemImage: "folder") { reveal([entry]) }
                Button("复制路径", systemImage: "doc.on.doc") { copyPaths([entry]) }
                Button(expanded.contains(entry.id) ? "收起详情" : "展开详情", systemImage: "info.circle") {
                    withAnimation(motion) {
                        if !expanded.insert(entry.id).inserted { expanded.remove(entry.id) }
                    }
                }
                if selectableIDs.contains(entry.id) {
                    Divider()
                    Button(selected.contains(entry.id) ? "取消选择此目录" : "选择此目录", systemImage: "checkmark.circle") {
                        toggle(entry.id)
                    }.disabled(session.busy(for: kind))
                    Button("移到废纸篓…", systemImage: "trash", role: .destructive) {
                        reviewEntries([entry])
                    }.disabled(session.busy(for: kind))
                    if selected.contains(entry.id), targets.count > 1 {
                        Button("检查所选 \(targets.count) 项…", systemImage: "checklist") {
                            reviewEntries(targets)
                        }.disabled(session.busy(for: kind))
                    }
                }
            }
    }
    private func aiGroup(_ tool: String, selectableIDs: Set<String>) -> some View {
        let roots = entries.filter { $0.owner == tool }
        let caches = DevelopmentStorageSelection.eligible(roots.flatMap(\.descendants))
        let open = expandedTools.contains(tool)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(motion) {
                        if !expandedTools.insert(tool).inserted { expandedTools.remove(tool) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").frame(width: 14)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tool).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                            Text("可选缓存 \(caches.count) 项 · \(FileSizeFormatter.string(fromByteCount: caches.reduce(0) { $0 + $1.file.size }))")
                                .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
                        }
                        Spacer()
                        Text(FileSizeFormatter.string(fromByteCount: roots.reduce(0) { $0 + $1.file.size }))
                            .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel((open ? "收起" : "展开") + tool + "的缓存与数据")
                if open, !caches.isEmpty {
                    Button(caches.allSatisfy({ selected.contains($0.id) }) ? "取消缓存选择" : "选择缓存") {
                        withAnimation(motion) {
                            if caches.allSatisfy({ selected.contains($0.id) }) { selected.subtract(caches.map(\.id)) }
                            else { selected.formUnion(caches.map(\.id)) }
                        }
                    }.buttonStyle(ReadableControlButtonStyle()).font(.system(size: 12)).disabled(session.busy(for: kind))
                }
            }.padding(14).gradientGlass(cornerRadius: 12)
            .contextMenu {
                Button(open ? "收起软件目录" : "展开软件目录", systemImage: open ? "chevron.up" : "chevron.down") {
                    withAnimation(motion) {
                        if !expandedTools.insert(tool).inserted { expandedTools.remove(tool) }
                    }
                }
                Button("在 Finder 中显示数据目录", systemImage: "folder") { reveal(roots) }
                Button("复制数据目录路径", systemImage: "doc.on.doc") { copyPaths(roots) }
                if !caches.isEmpty {
                    Divider()
                    Button("选择此软件的缓存（\(caches.count) 项）", systemImage: "checkmark.circle") {
                        withAnimation(motion) {
                            expandedTools.insert(tool)
                            selected.formUnion(caches.map(\.id))
                        }
                    }.disabled(session.busy(for: kind))
                    if caches.contains(where: { selected.contains($0.id) }) {
                        Button("取消此软件的缓存选择", systemImage: "circle") {
                            withAnimation(motion) { selected.subtract(caches.map(\.id)) }
                        }.disabled(session.busy(for: kind))
                    }
                }
            }
            if open {
                ForEach(roots) { root in
                    storageRow(root, selectableIDs: selectableIDs)
                    if !root.children.isEmpty {
                        Text("缓存、日志与临时目录 · 已含在上方软件占用中")
                            .font(.system(size: 11)).foregroundStyle(DevelopmentStoragePalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 20)
                        ForEach(root.children) { child in
                            storageRow(child, selectableIDs: selectableIDs).padding(.leading, 16)
                        }
                    }
                }
                if caches.isEmpty {
                    Text("未发现可选择的缓存目录；模型、会话和软件数据仅查看。")
                        .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary).padding(.horizontal, 14)
                }
            }
        }.padding(.bottom, 6)
    }
    private var filters: some View {
        HStack(spacing: 10) {
            ExpandableSearchField(placeholder: "搜索工具、目录或路径", text: $query)
            Spacer(minLength: 8)
            ChoiceDropdown(title: "所属工具", selection: $owner,
                           options: (["全部工具"] + Array(Set(allEntries.map(\.owner))).filter { $0 != "全部工具" }.sorted())
                            .map { ChoiceItem(value: $0, title: $0) }, symbol: "line.3.horizontal.decrease")
            ChoiceDropdown(title: "目录排序", selection: $sortBySize, options: [
                ChoiceItem(value: true, title: "按大小", symbol: "arrow.down.to.line.compact"),
                ChoiceItem(value: false, title: "按名称", symbol: "textformat")])

        }.font(.system(size: 12)).disabled(session.cleaning == kind)
    }
    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 28)).foregroundStyle(DevelopmentStoragePalette.secondary)
            Text(allEntries.isEmpty ? "当前范围内未发现目录" : "没有匹配的目录").font(.system(size: 15, weight: .semibold))
            Text(allEntries.isEmpty ? "扫描常用默认位置；自定义存储位置可能未覆盖。" : "试试其他关键词，或清除筛选条件。")
                .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
            if !allEntries.isEmpty { Button("清除筛选") { query = ""; owner = "全部工具" }.buttonStyle(ReadableControlButtonStyle()) }
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    private func dockerCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Docker 引擎报告", systemImage: "shippingbox").font(.system(size: 14, weight: .semibold))
            Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Text("可回收量为引擎估算，与下方虚拟磁盘占用分开统计。请在容器管理器中核对后清理。")
                .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).gradientGlass(cornerRadius: 14)
        .contextMenu {
            Button("复制 Docker 报告", systemImage: "doc.on.doc") { copyText(text) }
            Button("重新扫描", systemImage: "arrow.clockwise", action: scan).disabled(session.busy(for: kind))
        }
    }
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                listSummary
                Spacer(minLength: 8)
                selectionSummary
            }
            VStack(spacing: 6) {
                selectionSummary
                listSummary
            }
        }
        .frame(maxWidth: 920).padding(.horizontal, 28).padding(.vertical, targets.isEmpty ? 8 : 6)
        .frame(maxWidth: .infinity).background(Theme.surfaceSunk.opacity(0.5))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .animation(motion, value: targets.count)
    }
    private var listSummary: some View {
        HStack(spacing: 6) {
            Text(canClean ? "可选 \(bulkEligible.count) 个目录" : "当前 \(entries.count) 个目录")
            Text("·")
            Text(FileSizeFormatter.string(fromByteCount: (canClean ? bulkEligible : entries).reduce(0) { $0 + $1.file.size }))
                .fontWeight(.semibold).monospacedDigit()
        }.font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
            .fixedSize().accessibilityElement(children: .combine)
            .help(canClean ? "当前筛选结果中可清理目录的逻辑大小，不含只读数据；AI 软件总目录与缓存不重复计数。" : "当前结果的逻辑大小，不代表可回收空间。")
    }
    @ViewBuilder private var selectionSummary: some View {
        if session.cleaning == kind {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在移到废纸篓…").font(.system(size: 12))
            }
        } else if canClean, !targets.isEmpty {
            SelectionSummaryCapsule(count: targets.count,
                totalSize: targets.reduce(0) { $0 + $1.file.size },
                actionTitle: "检查所选项目", isBusy: session.busy(for: kind),
                onClear: { withAnimation(motion) { selected.removeAll() } },
                onDelete: { reviewEntries(targets) })
                .transition(.opacity)
        } else if !canClean {
            Label("仅查看", systemImage: "eye").font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
        }
    }
    private func selectAll() {
        guard !session.busy(for: kind) else { return }
        withAnimation(motion) {
            if kind == .ai { expandedTools.formUnion(bulkEligible.map(\.owner)) }
            selected = DevelopmentStorageSelection.selectAll(bulkEntries)
        }
    }
    private func invertSelection() {
        guard !session.busy(for: kind) else { return }
        withAnimation(motion) {
            if kind == .ai { expandedTools.formUnion(bulkEligible.map(\.owner)) }
            selected = DevelopmentStorageSelection.invert(selected, in: bulkEntries)
        }
    }
    /// 右键操作的单项目范围固定为点击的目录，不隐式合并页面中其他选择。
    private func reviewEntries(_ candidates: [DevelopmentStorageEntry]) {
        guard !session.busy(for: kind) else { return }
        let allowed = DevelopmentStorageSelection.eligible(candidates)
        guard !allowed.isEmpty else { return }
        session.requestReview(DevelopmentStorageReview(kind: kind, entries: allowed))
    }
    private func reveal(_ entries: [DevelopmentStorageEntry]) {
        NSWorkspace.shared.activateFileViewerSelecting(entries.map { $0.file.pathURL })
    }
    private func copyPaths(_ entries: [DevelopmentStorageEntry]) { copyText(entries.map(\.id).joined(separator: "\n")) }
    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    private func scan() {
        selected.removeAll(); expanded.removeAll()
        session.scan(kind)
    }
    private func reconcile() { selected = DevelopmentStorageSelection.reconcile(selected, visible: visibleEntries) }
    private func toggle(_ id: String) {
        guard !session.busy(for: kind) else { return }
        withAnimation(motion) { if !selected.insert(id).inserted { selected.remove(id) } }
    }
}

private struct DevelopmentStorageRow: View {
    let entry: DevelopmentStorageEntry
    let kind: DevelopmentStorageKind
    let isSelected: Bool
    let selectable: Bool
    let busy: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    let expand: () -> Void
    @State private var hovered = false
    private var title: String {
        if kind == .projects { return entry.file.pathURL.deletingLastPathComponent().lastPathComponent + " / " + entry.file.name }
        if kind == .ai { return entry.file.name }
        return entry.owner
    }
    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: selectable ? (isSelected ? "checkmark.circle.fill" : "circle") : "eye")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isSelected ? Theme.actionInk : Theme.actionInk.opacity(0.7))
                .frame(width: 28, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    if !selectable { Text("仅查看").font(.system(size: 10, weight: .medium)).foregroundStyle(DevelopmentStoragePalette.secondary) }
                }
                Text(entry.file.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path + "/", with: "~/"))
                    .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.file.sizeFormatted).font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary).monospacedDigit()
                Text(entry.file.storage?.allocatedBytes.map { "磁盘占用 " + FileSizeFormatter.string(fromByteCount: $0) } ?? "磁盘占用未知")
                    .font(.system(size: 11)).foregroundStyle(DevelopmentStoragePalette.secondary).monospacedDigit()
            }
        }.contentShape(Rectangle())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if selectable {
                    Button(action: toggle) { rowContent }
                        .buttonStyle(.plain).disabled(busy)
                        .accessibilityLabel("\(title)，\(entry.file.sizeFormatted)，\(isSelected ? "已选择" : "未选择")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else {
                    rowContent.accessibilityElement(children: .combine)
                }
                Button(action: expand) { Image(systemName: isExpanded ? "chevron.up" : "chevron.down").frame(width: 24, height: 32) }
                    .buttonStyle(ReadableControlButtonStyle(iconOnly: true))
                    .accessibilityLabel((isExpanded ? "收起" : "展开") + title + "的详情")
            }.padding(12)
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Text(entry.file.path).textSelection(.enabled)
                    Text(entry.detail)
                    HStack {
                        Label(entry.owner, systemImage: "folder")
                        Spacer()
                        Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(entry.file.path, inFileViewerRootedAtPath: "") }
                            .buttonStyle(ReadableControlButtonStyle(tint: .blue))
                    }
                }.font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 14).transition(.opacity)
            }
        }
        .background(Theme.inlineSurface.opacity(hovered ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Theme.actionInk.opacity(0.65) : Theme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
        }
        .onHover { hovered = $0 }
    }
}
