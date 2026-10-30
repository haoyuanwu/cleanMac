import SwiftUI
import AppKit

/// 一键清理的下一级检查页。筛选仅改变可见项，不改变用户的清理选择。
struct SmartCleanReviewView: View {
    let plan: SmartCleanPlan
    @Binding var selectedPaths: Set<String>
    let onAddToWhitelist: (FileItem) -> Void
    let onConfirm: () -> Void
    let onBack: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var sort: SmartCleanReviewSort = .size
    @State private var expandedGroups: Set<SmartCleanReviewGroup.Key> = []
    @State private var expandedCategories: Set<ScanCategory> = []
    @State private var expandedPaths: Set<String> = []
    @State private var copiedPath: String?

    private var groups: [SmartCleanReviewGroup] { plan.reviewGroups(query: query, sort: sort) }
    private var selectedItems: [FileItem] { plan.items.filter { selectedPaths.contains($0.path) } }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }

    var body: some View {
        // 一次计算筛选结果，避免每个列表行重复分组。
        let visibleGroups = groups
        let visiblePaths = Set(visibleGroups.flatMap { $0.items.map(\.path) })
        let visibleCategories = ScanCategory.allCases.filter { category in visibleGroups.contains { $0.key.category == category } }
        let hiddenSelected = selectedPaths.intersection(Set(plan.items.map(\.path))).subtracting(visiblePaths).count
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("检查清理清单").font(.system(size: 24, weight: .bold, design: .rounded))
                    Spacer()
                    Text("推荐 \(plan.items.count) 项").font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }
                Text("按分类展开检查项目，保留你需要的内容。")
                    .font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary)
                filters
                HStack(spacing: 16) {
                    Toggle("全选当前结果", isOn: Binding(
                        get: { !visiblePaths.isEmpty && visiblePaths.isSubset(of: selectedPaths) },
                        set: { if $0 { selectedPaths.formUnion(visiblePaths) } else { selectedPaths.subtract(visiblePaths) } }
                    )).toggleStyle(.checkbox).disabled(visiblePaths.isEmpty)
                    Text("显示 \(visiblePaths.count) 项").foregroundStyle(Theme.navigationSecondary)
                    Spacer()
                    Button(expandedCategories.isSuperset(of: Set(visibleCategories)) && !visibleCategories.isEmpty ? "收起分类" : "展开分类") {
                        withAnimation(motion) {
                            let categories = Set(visibleCategories)
                            if expandedCategories.isSuperset(of: categories) { expandedCategories.subtract(categories) }
                            else { expandedCategories.formUnion(categories) }
                        }
                    }.buttonStyle(.plain).disabled(visibleGroups.isEmpty)
                    Button("恢复推荐勾选") { selectedPaths = Set(plan.items.map(\.path)) }
                        .buttonStyle(.plain).help("重新选择本次扫描的全部推荐项目")
                }.font(.system(size: 12))
            }.padding(.horizontal, 28).padding(.bottom, 16)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if visibleGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleCategories) { category in
                            let categoryGroups = visibleGroups.filter { $0.key.category == category }
                            categoryHeader(category, groups: categoryGroups)
                            if expandedCategories.contains(category) {
                                ForEach(categoryGroups) { group in
                                    if group.key.application == nil {
                                        ForEach(group.items, id: \.path) { item in
                                            itemRow(item).gradientGlass(cornerRadius: 12).padding(.leading, 14)
                                        }
                                    } else {
                                        groupSection(group).padding(.leading, 14)
                                    }
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 28).padding(.vertical, 4).padding(.bottom, 20)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)

            footer(hiddenSelected: hiddenSelected)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand(perform: onBack)
        .onChange(of: plan.id) { _ in
            // 白名单会重建推荐集，清除已经不存在的展开状态。
            expandedPaths.formIntersection(Set(plan.items.map(\.path)))
            expandedGroups.formIntersection(Set(plan.reviewGroups().map(\.id)))
            expandedCategories.formIntersection(Set(plan.categorySummary.map(\.category)))
        }
        .task(id: copiedPath) {
            guard copiedPath != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copiedPath = nil
        }
    }

    private func categoryHeader(_ category: ScanCategory, groups: [SmartCleanReviewGroup]) -> some View {
        let items = groups.flatMap(\.items)
        let paths = Set(items.map(\.path))
        let selected = selectedPaths.intersection(paths).count
        let expanded = expandedCategories.contains(category)
        return HStack(spacing: 10) {
            selectionToggle(name: "选择\(category.rawValue)的当前结果", count: selected, total: items.count) { checked in
                if checked { selectedPaths.formUnion(paths) } else { selectedPaths.subtract(paths) }
            }
            Button {
                withAnimation(motion) {
                    if expanded { expandedCategories.remove(category) } else { expandedCategories.insert(category) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(category.iconAsset).resizable().scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.rawValue).font(.system(size: 15, weight: .semibold))
                        Text("已选 \(selected)/\(items.count) 项 · \(expanded ? "收起列表" : "展开检查")")
                            .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(FileSizeFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.size }))
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 18)
                        .foregroundStyle(Theme.navigationSecondary).accessibilityHidden(true)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(category.rawValue)，\(items.count) 项")
                .accessibilityValue(expanded ? "已展开" : "已收起")
        }.padding(14).gradientGlass(cornerRadius: 16)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Label("一键清理", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 8)
                    .gradientGlass(cornerRadius: 18)
            }.buttonStyle(WorkspacePressStyle()).keyboardShortcut("[", modifiers: .command)
                .help("返回扫描结果，保留本轮勾选")
            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.navigationSecondary).accessibilityHidden(true)
            Text("智能一键清理").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.navigationSecondary)
            Spacer()
        }.padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 18)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.navigationSecondary).accessibilityHidden(true)
                TextField("搜索软件、名称或路径", text: $query).textFieldStyle(.plain)
                    .accessibilityLabel("搜索清理清单")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.navigationSecondary).accessibilityLabel("清空搜索")
                }
            }.padding(10).gradientGlass(cornerRadius: 12)
            Picker("排序", selection: $sort) {
                ForEach(SmartCleanReviewSort.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 126).accessibilityLabel("项目排序")
        }.font(.system(size: 12))
    }

    private func groupSection(_ group: SmartCleanReviewGroup) -> some View {
        let expanded = expandedGroups.contains(group.id)
        let paths = Set(group.items.map(\.path))
        let count = paths.intersection(selectedPaths).count
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                selectionToggle(name: "选择\(group.name)的当前结果", count: count, total: paths.count) { selected in
                    if selected { selectedPaths.formUnion(paths) } else { selectedPaths.subtract(paths) }
                }
                Button {
                    withAnimation(motion) {
                        if expanded { expandedGroups.remove(group.id) } else { expandedGroups.insert(group.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        SmartCleanGroupIcon(application: group.key.application, color: group.key.category.color)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text("已选 \(count)/\(paths.count) 项")
                                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                        }
                        Spacer(minLength: 8)
                        Text(FileSizeFormatter.string(fromByteCount: group.totalSize))
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 18)
                            .foregroundStyle(Theme.navigationSecondary).accessibilityHidden(true)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(group.name)，\(group.items.count) 项")
                    .accessibilityValue(expanded ? "已展开" : "已收起").help(expanded ? "收起列表" : "展开查看项目")
            }.padding(14)
            if expanded {
                ForEach(group.items, id: \.path) { item in
                    itemRow(item).padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
        }.gradientGlass(cornerRadius: 16)
    }

    private func itemRow(_ item: FileItem) -> some View {
        let expanded = expandedPaths.contains(item.path)
        let selected = selectedPaths.contains(item.path)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                selectionToggle(name: "选择\(item.name)", count: selected ? 1 : 0, total: 1) { checked in
                    if checked { selectedPaths.insert(item.path) } else { selectedPaths.remove(item.path) }
                }
                FileItemIcon(file: item, size: 28)
                Button {
                    withAnimation(motion) {
                        if expanded { expandedPaths.remove(item.path) } else { expandedPaths.insert(item.path) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(shortPath(item.path)).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                                .lineLimit(1).truncationMode(.middle).help(item.path)
                        }
                        Spacer(minLength: 8)
                        Text(item.sizeFormatted).font(.system(size: 12, weight: .medium)).monospacedDigit()
                        Image(systemName: expanded ? "chevron.up" : "info.circle")
                            .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary).frame(width: 20)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("查看\(item.name)详情")
                    .accessibilityValue(expanded ? "已展开" : "已收起")
            }.padding(10)
            if expanded {
                itemDetails(item).padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .background(Color.accentColor.opacity(selected ? 0.06 : 0.015), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("在 Finder 中显示") { reveal(item) }
            Button("复制路径") { copy(item.path) }
            Divider()
            Button("加入白名单，以后保留") { onAddToWhitelist(item) }
        }
    }

    private func itemDetails(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(item.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 16) {
                Label(item.isDirectory ? "文件夹" : "文件", systemImage: item.isDirectory ? "folder" : "doc")
                if let date = item.modificationDate {
                    Text("修改于 \(date.formatted(date: .abbreviated, time: .shortened))")
                } else { Text("修改时间未知") }
            }.font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            Text(item.cacheRuleMatch?.reason ?? "扫描识别为低风险推荐项。清理后应用可能需要重新生成缓存或记录新的日志。")
                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let impact = item.cacheRuleMatch?.impact {
                Text(impact).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            }
            Text(item.isDirectory ? "清理时将整个文件夹移到废纸篓。可先在 Finder 中检查其内容。" : "清理时将此文件移到废纸篓。")
                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            HStack(spacing: 16) {
                Button { reveal(item) } label: { Label("在 Finder 中检查", systemImage: "folder") }
                Button { copy(item.path) } label: {
                    Label(copiedPath == item.path ? "已复制" : "复制路径", systemImage: copiedPath == item.path ? "checkmark" : "doc.on.doc")
                }
                Spacer(minLength: 0)
                Button { onAddToWhitelist(item) } label: { Label("加入白名单", systemImage: "shield") }
            }.buttonStyle(.borderless).font(.system(size: 12))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: plan.isEmpty ? "checkmark.shield" : "magnifyingglass").font(.system(size: 30)).foregroundStyle(.indigo)
            Text(plan.isEmpty ? "没有待清理项目" : "没有匹配的项目").font(.system(size: 16, weight: .semibold))
            Text(plan.isEmpty ? "加入白名单的项目已从清单中移除。" : "试试其他软件名称或路径，已有勾选会保留。")
                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            if !plan.isEmpty {
                Button("清除搜索") { query = "" }.buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity, minHeight: 180).gradientGlass(cornerRadius: 16)
    }

    private func footer(hiddenSelected: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已选 \(selectedItems.count) 项 · \(FileSizeFormatter.string(fromByteCount: selectedSize))")
                        .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(hiddenSelected > 0 ? "包含筛选外已勾选的 \(hiddenSelected) 项" : "所选项目的逻辑大小")
                        .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }
                Spacer(minLength: 12)
                Button(action: onConfirm) {
                    Label("清理所选 \(selectedItems.count) 项", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 22).frame(height: 42)
                }.buttonStyle(SmartCleanActionStyle()).disabled(selectedItems.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("确认将全部已勾选项目移到废纸篓（⌘Return）")
            }
            Text("项目将移到废纸篓，可在设置的清理记录中恢复；清空废纸篓后才可能释放空间。")
                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary).fixedSize(horizontal: false, vertical: true)
        }.padding(18).gradientGlass(cornerRadius: 18)
            .padding(.horizontal, 28).padding(.bottom, 20).padding(.top, 8)
    }

    private func selectionToggle(name: String, count: Int, total: Int, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { count == total && total > 0 }, set: set)) {
            Image(systemName: count == total ? "checkmark.square.fill" : count > 0 ? "minus.square.fill" : "square")
                .font(.system(size: 18)).foregroundStyle(count > 0 ? Color.accentColor : Theme.navigationSecondary)
                .frame(width: 26, height: 32)
        }.toggleStyle(.button).buttonStyle(.plain).accessibilityLabel(name)
            .accessibilityValue("已选 \(count) 项，共 \(total) 项")
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
    private func reveal(_ item: FileItem) { NSWorkspace.shared.activateFileViewerSelecting([item.pathURL]) }
    private func copy(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        copiedPath = path
    }
}

private struct SmartCleanGroupIcon: View {
    let application: CacheApplication?
    let color: Color
    @State private var icon: NSImage?
    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().scaledToFit() }
            else { Image(systemName: application == nil ? "archivebox" : "app").font(.system(size: 23)).foregroundStyle(color) }
        }.frame(width: 38, height: 38).accessibilityHidden(true)
            .task(id: application) { icon = application?.icon }
    }
}

private struct SmartCleanActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white)
            .background(Theme.accentGradient, in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.8 : 1)
    }
}
