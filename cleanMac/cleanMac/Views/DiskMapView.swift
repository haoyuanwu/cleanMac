import SwiftUI
import Combine

/// 随主窗口存活的临时会话；刷新时清空，退出应用后自然释放。
@MainActor
final class DiskMapSession: ObservableObject {
    @Published var root: DiskMapNode?
    @Published var stack: [DiskMapNode] = []
    @Published var isLoading = false
    @Published var volumeInfo: StorageInfo?
    @Published private(set) var loadingPaths: Set<String> = []

    private var directoryChildren: [String: [DiskMapNode]] = [:]
    private(set) var generation = 0

    func cachedChildren(of path: String) -> [DiskMapNode]? {
        directoryChildren[path]
    }

    func children(of path: String) async -> [DiskMapNode] {
        if let cached = directoryChildren[path] { return cached }
        let requestGeneration = generation
        let children = await DiskMapBuilder.children(of: path)
        if requestGeneration == generation {
            directoryChildren[path] = children
        }
        return children
    }

    func beginLoading(_ path: String) -> Int {
        loadingPaths.insert(path)
        isLoading = true
        return generation
    }

    func finishLoading(_ path: String, generation requestGeneration: Int) {
        guard requestGeneration == generation else { return }
        loadingPaths.remove(path)
        isLoading = !loadingPaths.isEmpty
    }

    func clear() {
        generation += 1
        root = nil
        volumeInfo = nil
        stack.removeAll()
        directoryChildren.removeAll()
        loadingPaths.removeAll()
        isLoading = false
    }
}

/// 目录清单与空间地图联动：单击选择、双击下钻、路径导航返回。
struct DiskMapView: View {
    @ObservedObject var session: DiskMapSession
    var storageInfo: StorageInfo?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedNode: DiskMapNode?
    @State private var hoveredNodeID: String?
    @State private var scrollTargetID: String?
    @State private var selectedIDs = Set<String>()
    @State private var forwardNodes: [DiskMapNode] = []
    @State private var sortByName = false
    @State private var mapStyle = MapStyle.bubbles

    private enum MapStyle: String, CaseIterable {
        case bubbles = "气泡"
        case rectangles = "矩形"
    }

    private var current: DiskMapNode? { session.stack.last ?? session.root }
    private var children: [DiskMapNode] {
        guard let current else { return [] }
        return current.children.sorted {
            if !sortByName, $0.size != $1.size { return $0.size > $1.size }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private var selectedNodes: [DiskMapNode] { children.filter { selectedIDs.contains($0.id) && DiskMapSelectionPolicy.protectionReason(for: $0.path) == nil } }
    private var isCurrentLoading: Bool { current.map { session.loadingPaths.contains($0.path) } ?? false }

    var body: some View {
        VStack(spacing: 16) {
            header
            if let current {
                pathBar
                GeometryReader { geometry in
                    HStack(spacing: 16) {
                        directoryPanel(current)
                            .frame(width: min(320, max(248, geometry.size.width * 0.34)))
                        mapPanel(current)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                bottomBar
            } else if session.isLoading {
                ScanningPlaceholderView(title: "正在分析磁盘空间…", subtitle: "可切换其他页面，分析会在后台继续")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(minWidth: 640, minHeight: 560)

        .navigationTitle("")
        .onChange(of: current?.path) { _ in
            focusedNode = nil
            hoveredNodeID = nil
            selectedIDs.removeAll()
            scrollTargetID = nil
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accentGradient)
                .frame(width: 44, height: 44)
                .background(Theme.accentGradientSoft, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("磁盘地图").font(.system(size: 21, weight: .bold, design: .rounded))
                Text("从目录到空间，一眼找到大文件")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button("用户目录") { Task { await rebuild(at: FileManager.default.homeDirectoryForCurrentUser.path) } }
                Button("应用程序") { Task { await rebuild(at: "/Applications") } }
                Divider()
                Button("选择文件夹…", action: chooseFolder)
            } label: {
                Label("分析位置", systemImage: "folder.badge.gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(session.isLoading)
            if session.root != nil {
                DetailTextButton(title: "重新分析", systemImage: "arrow.clockwise") {
                    Task { await rebuild(at: session.root?.path) }
                }
                .disabled(session.isLoading)
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                navigationButton("chevron.left", label: "返回上级", disabled: session.stack.isEmpty) {
                    guard let node = session.stack.popLast() else { return }
                    forwardNodes.append(node)
                }
                navigationButton("chevron.right", label: "前进", disabled: forwardNodes.isEmpty) {
                    guard let node = forwardNodes.popLast() else { return }
                    session.stack.append(expanded(node, children: session.cachedChildren(of: node.path) ?? node.children))
                }
            }
            Divider().frame(height: 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let root = session.root {
                        pathButton(root, index: nil)
                    }
                    ForEach(Array(session.stack.enumerated()), id: \.offset) { index, node in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        pathButton(node, index: index)
                    }
                }
            }
            if let current {
                navigationButton("folder", label: "在 Finder 中显示当前目录", disabled: false) { reveal([current]) }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .gradientGlass(cornerRadius: 12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
    }

    private func navigationButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private func pathButton(_ node: DiskMapNode, index: Int?) -> some View {
        Button {
            let retainedCount = index.map { $0 + 1 } ?? 0
            guard retainedCount < session.stack.count else { return }
            forwardNodes = Array(session.stack.dropFirst(retainedCount).reversed())
            session.stack = Array(session.stack.prefix(retainedCount))
        } label: {
            Label(node.name, systemImage: index == nil ? "house.fill" : "folder.fill")
                .font(.system(size: 12, weight: current?.id == node.id ? .semibold : .regular))
                .foregroundStyle(current?.id == node.id ? Color.primary : .secondary)
                .lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain)
        .help(node.path)
    }

    private func directoryPanel(_ node: DiskMapNode) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                DiskMapItemIcon(node: node, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text("\(node.sizeFormatted) · \(node.children.count) 个项目")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            HStack {
                Menu {
                    Button("选择全部") { selectedIDs = Set(children.filter { DiskMapSelectionPolicy.protectionReason(for: $0.path) == nil }.map(\.id)) }
                    Button("仅选择文件夹") { selectedIDs = Set(children.filter { $0.isDirectory && DiskMapSelectionPolicy.protectionReason(for: $0.path) == nil }.map(\.id)) }
                    Button("取消选择") { selectedIDs.removeAll() }
                } label: { Text("选择").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Menu {
                    Button("按大小") { sortByName = false }
                    Button("按名称") { sortByName = true }
                } label: {
                    Label(sortByName ? "名称" : "大小", systemImage: "arrow.down")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(children) { child in directoryRow(child, parent: node).id(child.id) }
                    }
                    .padding(8)
                }
                .onChange(of: scrollTargetID) { id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : Theme.ease) { proxy.scrollTo(id, anchor: .center) }
                }
                .overlay {
                    if isCurrentLoading { ProgressView().padding(16).background(.regularMaterial, in: Capsule()) }
                }
            }
        }
        .gradientGlass(cornerRadius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func directoryRow(_ node: DiskMapNode, parent: DiskMapNode) -> some View {
        let isFocused = focusedNode?.id == node.id || hoveredNodeID == node.id
        let protection = DiskMapSelectionPolicy.protectionReason(for: node.path)
        return HStack(spacing: 8) {
            Toggle("选择 \(node.name)", isOn: Binding(
                get: { selectedIDs.contains(node.id) },
                set: { if $0 && protection == nil { selectedIDs.insert(node.id) } else { selectedIDs.remove(node.id) } }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            .disabled(protection != nil)
            .help(protection ?? "选择 \(node.name)")
            if protection != nil {
                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    .help(protection!).accessibilityLabel(protection!)
            }

            Button { select(node) } label: {
                HStack(spacing: 8) {
                    DiskMapItemIcon(node: node, size: 26)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(node.name).font(.system(size: 12, weight: .medium))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Text(node.sizeFormatted)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit().lineLimit(1)
                            Spacer(minLength: 0)
                            ProportionBar(progress: Double(node.size) / Double(max(1, parent.size)),
                                          gradient: Theme.categoryGradient(DiskMapColors.color(for: node)), height: 3)
                                .frame(width: 32)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { drill(into: node) })
            .accessibilityLabel("\(node.name)，\(node.sizeFormatted)")
            .accessibilityHint(node.isDirectory ? "双击进入目录，也可使用右侧进入按钮" : "选择查看文件信息")
            if node.isDirectory {
                Button { drill(into: node) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 30)
                }
                .buttonStyle(.borderless)
                .help("进入 \(node.name)")
                .accessibilityLabel("进入 \(node.name)")
            }
        }
        .padding(.horizontal, 8)
        .background(isFocused ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(isFocused ? Color.accentColor : .clear, lineWidth: 1))
        .onHover { hovering in
            if hovering { hoveredNodeID = node.id }
            else if hoveredNodeID == node.id { hoveredNodeID = nil }
        }
        .help(protection.map { "\($0)\n\(node.path)" } ?? node.path)
        .contextMenu { DiskMapNodeContextMenu(node: node, onSelect: drill) }
    }

    private func mapPanel(_ node: DiskMapNode) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("空间分布").font(.system(size: 14, weight: .semibold))
                    Text(mapStyle == .bubbles ? "气泡面积代表文件占用" : "色块大小展示占用结构")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Picker("地图样式", selection: $mapStyle) {
                    ForEach(MapStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 108)
            }
            .padding(16)
            ZStack {
                if isCurrentLoading {
                    ScanningPlaceholderView(title: "正在分析目录…", subtitle: "正在读取目录与文件占用", animationHeight: 210)
                } else if node.children.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder").font(.system(size: 32)).foregroundStyle(.secondary)
                        Text("没有可显示的项目").font(.system(size: 13))
                        Text("目录可能为空，或暂时无法访问")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else if mapStyle == .bubbles {
                    DiskBubbleMap(nodes: node.children, focusedID: focusedNode?.id,
                                  selectedIDs: selectedIDs, hoveredID: $hoveredNodeID, onSelect: { select($0, fromMap: true) }, onDrill: drill)
                        .padding(12)
                } else {
                    MultiLevelTreemap(node: node, onDrill: drill,
                                      onSelect: { select($0, fromMap: true) }, focusedID: hoveredNodeID ?? focusedNode?.id,
                                      onHoverNode: { hoveredNodeID = $0 })
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().padding(.horizontal, 16)
            mapInspector(node)
        }
        .gradientGlass(cornerRadius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func mapInspector(_ parent: DiskMapNode) -> some View {
        HStack(spacing: 10) {
            if let focusedNode {
                DiskMapItemIcon(node: focusedNode, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(focusedNode.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(focusedNode.sizeFormatted) · 占当前目录 \(Int(Double(focusedNode.size) / Double(max(1, parent.size)) * 100))%")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if focusedNode.isDirectory {
                    Button { drill(into: focusedNode) } label: {
                        Image(systemName: "arrow.right.circle.fill").font(.system(size: 22))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    .help("进入 \(focusedNode.name)").accessibilityLabel("进入 \(focusedNode.name)")
                } else {
                    navigationButton("folder", label: "在 Finder 中显示所选文件", disabled: false) { reveal([focusedNode]) }
                }
            } else {
                Image(systemName: "cursorarrow.rays").foregroundStyle(Color.accentColor)
                Text("单击查看 · 双击文件夹进入")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16).frame(height: 60)
    }

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                volumeSummary
                Spacer(minLength: 4)
                selectionSummary
                revealButton
            }
            VStack(spacing: 10) {
                volumeSummary
                HStack { selectionSummary; Spacer(); revealButton }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .gradientGlass(cornerRadius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
    }

    private var volumeSummary: some View {
        let storageInfo = session.volumeInfo ?? storageInfo
        return HStack(spacing: 10) {
            Image(systemName: "internaldrive.fill").font(.system(size: 23)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(storageInfo?.volumeName ?? "磁盘空间").font(.system(size: 12, weight: .semibold))
                    if let storageInfo {
                        Text("可用 \(storageInfo.freeFormatted)")
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if let storageInfo {
                    ProportionBar(progress: min(1, max(0, storageInfo.usedPercentage)), gradient: Theme.accentGradient, height: 4)
                }
            }
        }
        .frame(minWidth: 190, idealWidth: 250, maxWidth: 300, alignment: .leading)
        .help(storageInfo.map { "已使用 \($0.usedFormatted) / 共 \($0.totalFormatted)" } ?? "")
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("已选择 \(selectedNodes.count) 项").font(.system(size: 12, weight: .medium))
            Text(FileSizeFormatter.string(fromByteCount: selectedNodes.reduce(0) { $0 + $1.size }))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var revealButton: some View {
        Button { reveal(selectedNodes) } label: {
            Label("在 Finder 中显示", systemImage: "folder")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .buttonStyle(GradientButtonStyleCompact())
        .disabled(selectedNodes.isEmpty)
        .opacity(selectedNodes.isEmpty ? 0.45 : 1)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 54)).foregroundStyle(Theme.accentGradient)
                .frame(width: 112, height: 112)
                .background(Theme.accentGradientSoft, in: RoundedRectangle(cornerRadius: 30))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("看清空间，找到重点").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("目录清单与空间地图并排呈现，逐层查看文件占用。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Button { Task { await rebuild() } } label: {
                Label("分析用户目录", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .buttonStyle(GradientButtonStyleCompact())
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "分析文件夹"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await rebuild(at: url.path) }
        }
    }

    private func rebuild(at path: String? = nil) async {
        guard !session.isLoading else { return }
        let path = path ?? FileManager.default.homeDirectoryForCurrentUser.path
        session.clear()
        forwardNodes.removeAll()
        let requestGeneration = session.beginLoading(path)
        let volumeInfo = await Task.detached(priority: .utility) {
            guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path) else { return nil as StorageInfo? }
            let total = (attributes[.systemSize] as? Int64) ?? 0
            let free = (attributes[.systemFreeSize] as? Int64) ?? 0
            let name = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "磁盘空间"
            return StorageInfo(totalBytes: total, usedBytes: max(0, total - free), freeBytes: free, volumeName: name)
        }.value
        let children = await session.children(of: path)
        guard requestGeneration == session.generation else { return }
        session.volumeInfo = volumeInfo
        session.root = DiskMapNode(id: path, name: path == FileManager.default.homeDirectoryForCurrentUser.path
                                  ? "用户目录" : FileManager.default.displayName(atPath: path),
                                  path: path, size: children.reduce(0) { $0 + $1.size },
                                  isDirectory: true, children: children)
        session.finishLoading(path, generation: requestGeneration)
    }

    private func drill(into node: DiskMapNode) {
        guard node.isDirectory else { select(node); return }
        forwardNodes.removeAll()
        let children = session.cachedChildren(of: node.path) ?? node.children
        session.stack.append(expanded(node, children: children))
        guard session.cachedChildren(of: node.path) == nil, children.isEmpty,
              !session.loadingPaths.contains(node.path) else { return }
        let requestGeneration = session.beginLoading(node.path)
        Task {
            let children = await session.children(of: node.path)
            guard requestGeneration == session.generation else { return }
            if let index = session.stack.lastIndex(where: { $0.path == node.path }) {
                withAnimation(reduceMotion ? nil : Theme.ease) {
                    session.stack[index] = expanded(node, children: children)
                }
            }
            session.finishLoading(node.path, generation: requestGeneration)
        }
    }

    private func expanded(_ node: DiskMapNode, children: [DiskMapNode]) -> DiskMapNode {
        DiskMapNode(id: node.id, name: node.name, path: node.path, size: node.size,
                    isDirectory: node.isDirectory, children: children)
    }

    private func select(_ node: DiskMapNode, fromMap: Bool = false) {
        focusedNode = node
        guard DiskMapSelectionPolicy.protectionReason(for: node.path) == nil else {
            if fromMap { scrollTargetID = node.id }
            return
        }
        if NSEvent.modifierFlags.contains(.command) {
            if selectedIDs.contains(node.id) { selectedIDs.remove(node.id) }
            else { selectedIDs.insert(node.id) }
        } else {
            selectedIDs = [node.id]
        }
        if fromMap { scrollTargetID = node.id }
    }

    private func reveal(_ nodes: [DiskMapNode]) {
        NSWorkspace.shared.activateFileViewerSelecting(nodes.filter { $0.path.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0.path) })
    }
}

// MARK: - 多级色块
struct MultiLevelTreemap: View {
    let node: DiskMapNode
    let onDrill: (DiskMapNode) -> Void
    var onSelect: ((DiskMapNode) -> Void)?
    var focusedID: String?
    var onHoverNode: ((String?) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reveal: CGFloat = 0
    @State private var selectedID: String?

    var body: some View {
        GeometryReader { geo in
            let arrangement = arrange(in: geo.size)
            let childrenByID = Dictionary(node.children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    ForEach(arrangement.cells) { cell in
                        if let child = childrenByID[cell.node.id] {
                            largeBlock(child, cell: cell)
                                .position(x: cell.rect.midX, y: cell.rect.midY)
                        }
                    }
                }
                .frame(width: arrangement.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
        .cardShadow()
        .onAppear {
            reveal = 0
            withAnimation(reduceMotion ? nil : Theme.easeSlow.delay(0.05)) {
                reveal = 1
            }
        }
        .onChange(of: node.id) { _ in
            selectedID = nil
            reveal = 0
            withAnimation(reduceMotion ? nil : Theme.easeSlow.delay(0.04)) {
                reveal = 1
            }
        }
    }

    private func arrange(in size: CGSize) -> (cells: [TreemapCell], width: CGFloat) {
        let viewportWidth = max(1, size.width)
        guard !node.children.isEmpty else { return ([], viewportWidth) }

        let height = max(1, size.height)
        let columns = max(4, Int(viewportWidth / 140))
        let rows = max(3, Int(height / 96))
        let unitWidth = viewportWidth / CGFloat(columns)
        let unitHeight = height / CGFloat(rows)
        let maxColumnSpan = max(1, columns / 2)
        let maxRowSpan = max(1, rows - 1)
        let maximumUnits = maxColumnSpan * maxRowSpan
        let density = sqrt(4.0 / Double(max(4, node.children.count)))
        let largestUnits = max(1, min(maximumUnits, Int((Double(maximumUnits) * density).rounded())))
        let sorted = node.children.sorted {
            $0.size == $1.size ? $0.id < $1.id : $0.size > $1.size
        }
        let largestSize = Double(max(1, sorted.first?.size ?? 0))
        var occupied: Set<Int> = []
        var firstOpenColumn = 0
        var usedColumns = 0
        var cells: [TreemapCell] = []

        // 从大到小放入网格；大块最多占可见宽度一半，高度也保留一行给其他文件。
        for child in sorted {
            let ratio = Double(max(0, child.size)) / largestSize
            let desiredUnits = 1 + Double(largestUnits - 1) * pow(ratio, 0.85)
            let span = bestSpan(
                desiredUnits: desiredUnits,
                maximumUnits: largestUnits,
                maximumColumns: maxColumnSpan,
                maximumRows: maxRowSpan,
                unitSize: CGSize(width: unitWidth, height: unitHeight)
            )

            var column = firstOpenColumn
            var placedRow = 0
            search: while true {
                for row in 0...(rows - span.rows) {
                    let isFree = (column..<(column + span.columns)).allSatisfy { candidateColumn in
                        (row..<(row + span.rows)).allSatisfy { candidateRow in
                            !occupied.contains(candidateColumn * rows + candidateRow)
                        }
                    }
                    if isFree {
                        placedRow = row
                        break search
                    }
                }
                column += 1
            }

            for occupiedColumn in column..<(column + span.columns) {
                for occupiedRow in placedRow..<(placedRow + span.rows) {
                    occupied.insert(occupiedColumn * rows + occupiedRow)
                }
            }
            usedColumns = max(usedColumns, column + span.columns)
            while firstOpenColumn < usedColumns && (0..<rows).allSatisfy({ row in
                occupied.contains(firstOpenColumn * rows + row)
            }) {
                firstOpenColumn += 1
            }

            let rect = CGRect(
                x: CGFloat(column) * unitWidth,
                y: CGFloat(placedRow) * unitHeight,
                width: CGFloat(span.columns) * unitWidth,
                height: CGFloat(span.rows) * unitHeight
            ).insetBy(dx: 2, dy: 2)
            let treemapNode = TreemapNode(
                id: child.id,
                name: child.name,
                size: child.size,
                color: color(for: child, index: 0)
            )
            cells.append(TreemapCell(node: treemapNode, rect: rect))
        }
        return (cells, max(viewportWidth, CGFloat(usedColumns) * unitWidth))
    }

    private func bestSpan(
        desiredUnits: Double,
        maximumUnits: Int,
        maximumColumns: Int,
        maximumRows: Int,
        unitSize: CGSize
    ) -> (columns: Int, rows: Int) {
        var best = (columns: 1, rows: 1)
        var bestScore = Double.infinity
        for columns in 1...maximumColumns {
            for rows in 1...maximumRows where columns * rows <= maximumUnits {
                let areaDifference = abs(Double(columns * rows) - desiredUnits)
                let aspectRatio = Double(CGFloat(columns) * unitSize.width / (CGFloat(rows) * unitSize.height))
                let score = areaDifference + abs(log(aspectRatio)) * 0.15
                if score < bestScore {
                    best = (columns, rows)
                    bestScore = score
                }
            }
        }
        return best
    }

    private func largeBlock(_ child: DiskMapNode, cell: TreemapCell) -> some View {
        let tint = color(for: child, index: 0)
        let isSelected = (focusedID ?? selectedID) == child.id
        return Button {
            select(child)
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(
                    colors: [tint.opacity(0.92), tint.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.35),
                                lineWidth: isSelected ? 2.5 : 1)
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(child.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text(child.sizeFormatted)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        if cell.rect.height > 100 {
                            Text(hint(for: child))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(10)
                }
                .frame(width: cell.rect.width, height: cell.rect.height)
                .scaleEffect(isSelected ? 0.97 : (0.86 + 0.14 * reveal))
                .opacity(Double(reveal))
                .shadow(color: isSelected ? tint.opacity(0.45) : .clear, radius: 12, y: 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { onHoverNode?($0 ? child.id : nil) }
        .animation(reduceMotion ? nil : Theme.spring, value: selectedID)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDrill(child) })
        .accessibilityLabel("\(child.name)，\(child.sizeFormatted)")
        .help("\(child.name) · \(child.sizeFormatted)")
        .contextMenu {
            DiskMapNodeContextMenu(node: child, onSelect: onDrill)
        }
    }

    private func select(_ child: DiskMapNode) {
        withAnimation(reduceMotion ? nil : Theme.spring) {
            selectedID = child.id
        }
        if let onSelect { onSelect(child) }
        else { onDrill(child) }
    }

    private func hint(for child: DiskMapNode?) -> String {
        guard let child else { return "" }
        if child.isDirectory { return "双击进入目录" }
        return "单击查看文件详情"
    }

    private func color(for node: DiskMapNode, index: Int) -> Color {
        DiskMapColors.color(for: node)
    }
}

private struct DiskMapNodeContextMenu: View {
    let node: DiskMapNode
    let onSelect: (DiskMapNode) -> Void

    private var isLocalPath: Bool { node.path.hasPrefix("/") }

    var body: some View {
        Button {
            onSelect(node)
        } label: {
            Label(node.isDirectory ? "进入目录" : "查看详情",
                  systemImage: node.isDirectory ? "folder" : "info.circle")
        }

        if isLocalPath {
            Divider()
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: node.path))
            } label: {
                Label(node.isDirectory ? "打开文件夹" : "打开文件", systemImage: "arrow.up.forward.app")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            } label: {
                Label("复制路径", systemImage: "doc.on.doc")
            }

            Divider()
            if UserWhitelist.contains(node.path) {
                Button {
                    UserWhitelist.remove(node.path)
                } label: {
                    Label("移出白名单", systemImage: "shield.slash")
                }
            } else if UserWhitelist.isWhitelisted(node.path) {
                Button {} label: {
                    Label("已受上级目录白名单保护", systemImage: "shield.lefthalf.filled")
                }
                .disabled(true)
            } else {
                Button {
                    UserWhitelist.add(node.path)
                } label: {
                    Label("加入白名单", systemImage: "shield")
                }
                .help("加入后不会被清理或卸载")
            }
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.name, forType: .string)
        } label: {
            Label("复制名称", systemImage: "character.textbox")
        }
    }
}
