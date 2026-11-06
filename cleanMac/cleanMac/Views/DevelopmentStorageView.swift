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
    @State private var selected = Set<String>()
    @State private var review: DevelopmentStorageReview?
    @State private var expanded = Set<String>()
    @State private var expandedTools = Set<String>()
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
    private var showingResults: Bool { report != nil && session.loading != kind }
    private var motion: Animation { reduceMotion ? .linear(duration: 0.01) : Theme.ease }

    var body: some View {
        GeometryReader { viewport in
            VStack(alignment: .leading, spacing: showingResults ? 7 : 12) {
                header
                if session.loading == kind {
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
            .animation(motion, value: session.loading == kind)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if report != nil, session.loading != kind { footer }
        }
        .sheet(item: $review) { snapshot in
            DevelopmentStorageReviewSheet(review: snapshot) {
                review = nil
            } confirm: {
                review = nil
                selected.subtract(snapshot.entries.map(\.id))
                session.clean(snapshot)
            }
        }
        .onChange(of: query) { _ in
            if kind == .ai, !query.isEmpty { expandedTools.formUnion(entries.map(\.owner)) }
            reconcile()
        }
        .onChange(of: owner) { _ in reconcile() }
        .onChange(of: allEntries.flatMap(\.descendants).map(\.id)) { _ in reconcile() }
        .onChange(of: expandedTools) { _ in reconcile() }
        .onChange(of: kind) { _ in
            selected.removeAll(); expanded.removeAll(); expandedTools.removeAll(); query = ""; owner = "全部工具"; review = nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol).font(.system(size: showingResults ? 17 : 19, weight: .semibold))
                .foregroundStyle(.white).frame(width: showingResults ? 32 : 38, height: showingResults ? 32 : 38)
                .background(Theme.categoryGradient(tint), in: RoundedRectangle(cornerRadius: 11))
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
                DetailTextButton(title: "重新扫描", systemImage: "arrow.clockwise", action: scan).disabled(session.busy)
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
            }.buttonStyle(GradientButtonStyleCompact()).disabled(session.busy)
            Text(canClean ? "扫描后手动选择目录 · 不会自动清理" : "仅盘点占用 · 在所属工具中管理")
                .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
            if session.busy { Text("其他模块正在处理任务，请稍候。 ").font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary) }
        }.padding(.vertical, 24)
    }
    private var scanning: some View {
        VStack(spacing: 16) {
            ScanningPlaceholderView(title: session.cancelling ? "正在取消扫描…" : "正在扫描" + kind.rawValue + "…",
                subtitle: "仅统计文件元数据，可切换页面，扫描会在后台继续。",
                diagnostics: session.progress)
            Button(session.cancelling ? "正在取消…" : "取消扫描", action: session.cancelScan)
                .disabled(session.cancelling).controlSize(.regular)
        }
    }
    @ViewBuilder private func results(_ report: DevelopmentStorageReport) -> some View {
        let selectableIDs = Set(eligible.map(\.id))
        filters
        HStack {
            Text(kind == .ai ? "\(aiOwners.count) 个软件 · 展开后选择缓存目录" : "\(entries.count) / \(allEntries.count) 个目录").font(.system(size: 12, weight: .medium))
                .foregroundStyle(DevelopmentStoragePalette.secondary)
            Spacer()
            if canClean {
                Button(eligible.isEmpty || !eligible.allSatisfy({ selected.contains($0.id) }) ? "选择当前结果" : "取消当前选择") {
                    withAnimation(motion) {
                        if !eligible.isEmpty, eligible.allSatisfy({ selected.contains($0.id) }) { selected.removeAll() }
                        else { selected = Set(eligible.map(\.id)) }
                    }
                }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).disabled(eligible.isEmpty || session.busy)
                .help("仅选择当前筛选结果中允许清理的目录")
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
            selectable: selectableIDs.contains(entry.id), busy: session.busy,
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
                    }.disabled(session.busy)
                    Button("移到废纸篓…", systemImage: "trash", role: .destructive) {
                        reviewEntries([entry])
                    }.disabled(session.busy)
                    if selected.contains(entry.id), targets.count > 1 {
                        Button("检查所选 \(targets.count) 项…", systemImage: "checklist") {
                            reviewEntries(targets)
                        }.disabled(session.busy)
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
                    }.font(.system(size: 12)).disabled(session.busy)
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
                    }.disabled(session.busy)
                    if caches.contains(where: { selected.contains($0.id) }) {
                        Button("取消此软件的缓存选择", systemImage: "circle") {
                            withAnimation(motion) { selected.subtract(caches.map(\.id)) }
                        }.disabled(session.busy)
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
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(DevelopmentStoragePalette.secondary)
                TextField("搜索工具、目录或路径", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("清除搜索")
                }
            }.padding(.horizontal, 9).padding(.vertical, 6).gradientGlass(cornerRadius: 9)
            Picker("所属工具", selection: $owner) {
                Text("全部工具").tag("全部工具")
                ForEach(Array(Set(allEntries.map(\.owner))).sorted(), id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 124)
            Menu {
                Button("按占用大小") { sortBySize = true }
                Button("按工具名称") { sortBySize = false }
            } label: { Label(sortBySize ? "按大小" : "按名称", systemImage: "arrow.up.arrow.down") }
                .fixedSize()
        }.font(.system(size: 12)).disabled(session.cleaning != nil)
    }
    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 28)).foregroundStyle(DevelopmentStoragePalette.secondary)
            Text(allEntries.isEmpty ? "当前范围内未发现目录" : "没有匹配的目录").font(.system(size: 15, weight: .semibold))
            Text(allEntries.isEmpty ? "扫描常用默认位置；自定义存储位置可能未覆盖。" : "试试其他关键词，或清除筛选条件。")
                .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
            if !allEntries.isEmpty { Button("清除筛选") { query = ""; owner = "全部工具" } }
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
            Button("重新扫描", systemImage: "arrow.clockwise", action: scan).disabled(session.busy)
        }
    }
    private var footer: some View {
        HStack(spacing: 12) {
            if session.cleaning == kind {
                ProgressView().controlSize(.small)
                Text("正在移到废纸篓…").font(.system(size: 13, weight: .semibold))
            } else if canClean {
                Text("已选 \(targets.count) 项 · \(FileSizeFormatter.string(fromByteCount: targets.reduce(0) { $0 + $1.file.size }))")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Image(systemName: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
                    .help(kind == .ai ? "仅清理所选缓存目录；收起软件或筛选会取消隐藏项。" : "仅作用于当前结果；更改筛选会取消隐藏项的选择。")
                    .accessibilityLabel("仅操作当前结果中的已选目录，筛选会取消隐藏项的选择")
                Spacer(minLength: 8)
                if !targets.isEmpty {
                    Button("取消选择") { withAnimation(motion) { selected.removeAll() } }.buttonStyle(.plain).font(.system(size: 12))
                }
                DetailTextButton(title: "检查所选项目", systemImage: "checklist") {
                    review = DevelopmentStorageReview(kind: kind, entries: targets)
                }.disabled(targets.isEmpty || session.busy)
            } else {
                Label("模型、工具链与虚拟机可能包含唯一数据，请在所属工具中管理。", systemImage: "eye")
                    .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
            }
        }.frame(maxWidth: 920, minHeight: 38).padding(.horizontal, 28).padding(.vertical, 3)
            .frame(maxWidth: .infinity).background(Theme.inlineSurface)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            .animation(motion, value: targets.count)
    }
    /// 右键操作的单项目范围固定为点击的目录，不隐式合并页面中其他选择。
    private func reviewEntries(_ candidates: [DevelopmentStorageEntry]) {
        guard !session.busy else { return }
        let allowed = DevelopmentStorageSelection.eligible(candidates)
        guard !allowed.isEmpty else { return }
        review = DevelopmentStorageReview(kind: kind, entries: allowed)
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
        selected.removeAll(); expanded.removeAll(); review = nil
        session.scan(kind)
    }
    private func reconcile() { selected = DevelopmentStorageSelection.reconcile(selected, visible: visibleEntries) }
    private func toggle(_ id: String) {
        guard !session.busy else { return }
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
                .foregroundStyle(isSelected ? Color.primary : DevelopmentStoragePalette.secondary)
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
                    .buttonStyle(.plain).foregroundStyle(DevelopmentStoragePalette.secondary)
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
                    }
                }.font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 14).transition(.opacity)
            }
        }
        .background(Theme.inlineSurface.opacity(hovered ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.primary.opacity(0.6) : Theme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
        }
        .onHover { hovered = $0 }
    }
}

private struct DevelopmentStorageReviewSheet: View {
    let review: DevelopmentStorageReview
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("检查所选项目", systemImage: "checklist").font(.system(size: 20, weight: .bold, design: .rounded))
            Text("\(review.kind.rawValue) · \(review.entries.count) 个目录 · \(FileSizeFormatter.string(fromByteCount: review.totalSize))")
                .font(.system(size: 14, weight: .semibold))
            Text("只处理下列目录及其全部内容。请先停止相关开发任务，并确认目录中没有手写文件。")
                .font(.system(size: 13)).foregroundStyle(DevelopmentStoragePalette.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(review.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.owner + " · " + entry.file.name).fontWeight(.semibold)
                                Spacer()
                                Text(entry.file.sizeFormatted).monospacedDigit()
                            }
                            Text(entry.file.path).foregroundStyle(DevelopmentStoragePalette.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }.font(.system(size: 12))
                        Divider()
                    }
                }
            }.frame(maxHeight: 260)
            Text("依赖和缓存可能需要重新下载或构建。项目会移到废纸篓，清空后才释放空间；未选目录不会处理。")
                .font(.system(size: 12)).foregroundStyle(DevelopmentStoragePalette.secondary)
            HStack {
                Button("返回检查", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("移到废纸篓（\(review.entries.count) 项）", role: .destructive, action: confirm)
                    .buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 600).background(Theme.surfaceRaised)
    }
}
