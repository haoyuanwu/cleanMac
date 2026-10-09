import SwiftUI
import Combine

/// 随主窗口存活的临时会话；刷新时清空，退出应用后自然释放。
@MainActor
final class DiskMapSession: ObservableObject {
    @Published var root: DiskMapNode?
    @Published var stack: [DiskMapNode] = []
    @Published var isLoading = false
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
        stack.removeAll()
        directoryChildren.removeAll()
        loadingPaths.removeAll()
        isLoading = false
    }
}

/// 多级磁盘 Treemap 页面：点击块下钻，面包屑返回
struct DiskMapView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var session: DiskMapSession

    @State private var selectedFile: DiskMapNode?
    /// 下钻方向：true 向下，false 返回
    @State private var drillForward = true

    private var current: DiskMapNode? {
        session.stack.last ?? session.root
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                breadcrumb

                if session.isLoading && session.root == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在展开目录…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else if let current {
                    statsBar(current)

                    ZStack {
                        if session.loadingPaths.contains(current.path) {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("正在分析目录…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("可以返回上级，分析会在后台继续")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            MultiLevelTreemap(node: current) { node in
                                drill(into: node)
                            }
                            .frame(height: 480)
                            .id(current.id)
                            .transition(
                                drillForward
                                    ? .asymmetric(
                                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                                        removal: .scale(scale: 1.08).combined(with: .opacity)
                                    )
                                    : .asymmetric(
                                        insertion: .scale(scale: 1.08).combined(with: .opacity),
                                        removal: .scale(scale: 0.92).combined(with: .opacity)
                                    )
                            )
                        }

                        if current.children.isEmpty && !session.loadingPaths.contains(current.path) {
                            Text("此节点下无可展示子项")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 480)

                    if let selectedFile {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(selectedFile.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .textSelection(.enabled)
                                Text(selectedFile.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
                            Text(selectedFile.sizeFormatted)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(14)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Text("点按色块查看内容 · 横向滚动整张地图查看右侧项目 · 用上方路径返回")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .background(Theme.canvas.ignoresSafeArea())
        .onChange(of: current?.id) { _ in selectedFile = nil }
        .task {
            guard session.root == nil else { return }
            await rebuild()
        }
    }

    // MARK: - 页头
    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.3, green: 0.5, blue: 1), Color(red: 0.5, green: 0.3, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .elevatedShadow()

            VStack(alignment: .leading, spacing: 4) {
                Text("磁盘地图")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("多级 Treemap · 点按色块下钻查看占用结构")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            DetailTextButton(title: "刷新", systemImage: "arrow.clockwise") {
                Task {
                    session.clear()
                    await rebuild()
                }
            }
            .disabled(session.isLoading)
        }
    }

    // MARK: - 面包屑
    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    drillForward = false
                    withAnimation(Theme.spring) {
                        session.stack.removeAll()
                    }
                } label: {
                    Text("根")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(session.stack.isEmpty ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.05)))
                        )
                        .foregroundColor(session.stack.isEmpty ? .white : .primary)
                }
                .buttonStyle(.plain)

                ForEach(Array(session.stack.enumerated()), id: \.element.id) { index, node in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Button {
                        drillForward = false
                        withAnimation(Theme.spring) {
                            session.stack = Array(session.stack.prefix(index + 1))
                        }
                    } label: {
                        Text(node.name)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(index == session.stack.count - 1
                                          ? AnyShapeStyle(Theme.accentGradient)
                                          : AnyShapeStyle(Color.primary.opacity(0.05)))
                            )
                            .foregroundColor(index == session.stack.count - 1 ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(index == session.stack.count - 1 ? 1.02 : 1)
                    .animation(Theme.springSnappy, value: session.stack.count)
                }
            }
        }
    }

    private func statsBar(_ node: DiskMapNode) -> some View {
        HStack(spacing: 12) {
            MetricTile(title: "当前节点", value: node.name, subtitle: node.path, gradient: Theme.accentGradient, compact: true)
            MetricTile(title: "体量", value: node.sizeFormatted,
                       subtitle: session.loadingPaths.contains(node.path) ? "正在分析…" : "\(node.children.count) 个子项",
                       gradient: Theme.warmGradient, compact: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("请先扫描，或点击刷新")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - 动作
    private func rebuild() async {
        guard !session.isLoading else { return }
        let requestGeneration = session.generation
        session.isLoading = true
        defer {
            if requestGeneration == session.generation {
                session.isLoading = !session.loadingPaths.isEmpty
            }
        }
        if viewModel.hasScanned {
            let root = await DiskMapBuilder.fromScanResults(viewModel.scanResults)
            guard requestGeneration == session.generation else { return }
            session.root = root
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let children = await session.children(of: home)
            guard requestGeneration == session.generation else { return }
            session.root = DiskMapNode(
                id: "home",
                name: "用户目录",
                path: home,
                size: children.reduce(0) { $0 + $1.size },
                isDirectory: true,
                children: children
            )
        }
    }

    private func drill(into node: DiskMapNode) {
        if !node.isDirectory && node.children.isEmpty {
            selectedFile = node
            return
        }

        if !node.children.isEmpty {
            drillForward = true
            withAnimation(Theme.spring) {
                session.stack.append(node)
            }
            return
        }

        guard node.isDirectory else { return }
        if let children = session.cachedChildren(of: node.path) {
            showExpanded(node, children: children)
            return
        }

        if session.loadingPaths.contains(node.path) {
            showExpanded(node, children: [])
            return
        }

        let requestGeneration = session.beginLoading(node.path)
        showExpanded(node, children: [])
        Task {
            let children = await session.children(of: node.path)
            guard requestGeneration == session.generation else { return }
            if let index = session.stack.lastIndex(where: { $0.path == node.path }) {
                withAnimation(Theme.spring) {
                    session.stack[index] = expanded(node, children: children)
                }
            }
            session.finishLoading(node.path, generation: requestGeneration)
        }
    }

    private func showExpanded(_ node: DiskMapNode, children: [DiskMapNode]) {
        let childNode = expanded(node, children: children)
        drillForward = true
        withAnimation(Theme.spring) {
            session.stack.append(childNode)
        }
    }

    private func expanded(_ node: DiskMapNode, children: [DiskMapNode]) -> DiskMapNode {
        DiskMapNode(
            id: node.id,
            name: node.name,
            path: node.path,
            size: node.size,
            isDirectory: true,
            children: children
        )
    }
}

// MARK: - 多级色块
struct MultiLevelTreemap: View {
    let node: DiskMapNode
    let onDrill: (DiskMapNode) -> Void

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
            withAnimation(Theme.easeSlow.delay(0.05)) {
                reveal = 1
            }
        }
        .onChange(of: node.id) { _ in
            selectedID = nil
            reveal = 0
            withAnimation(Theme.easeSlow.delay(0.04)) {
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
        let isSelected = selectedID == child.id
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
        .animation(Theme.spring, value: selectedID)
        .help("\(child.name) · \(child.sizeFormatted)")
        .contextMenu {
            DiskMapNodeContextMenu(node: child, onSelect: onDrill)
        }
    }

    private func select(_ child: DiskMapNode) {
        withAnimation(Theme.spring) {
            selectedID = child.id
        }
        onDrill(child)
    }

    private func hint(for child: DiskMapNode?) -> String {
        guard let child else { return "" }
        if !child.children.isEmpty { return "点按下钻 · \(child.children.count) 项" }
        if child.isDirectory { return "点按下钻子目录" }
        return "点按查看文件详情"
    }

    private func color(for node: DiskMapNode, index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.25, green: 0.55, blue: 1.0),
            Color(red: 0.55, green: 0.38, blue: 0.98),
            Color(red: 1.0, green: 0.42, blue: 0.48),
            Color(red: 0.2, green: 0.75, blue: 0.55),
            Color(red: 1.0, green: 0.62, blue: 0.22),
            Color(red: 0.3, green: 0.72, blue: 0.82),
            Color(red: 0.95, green: 0.4, blue: 0.65),
            Color(red: 0.45, green: 0.55, blue: 0.9),
        ]
        // 稳定着色：按 id 哈希
        let idx = abs(node.id.hashValue) % palette.count
        return palette[idx]
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
