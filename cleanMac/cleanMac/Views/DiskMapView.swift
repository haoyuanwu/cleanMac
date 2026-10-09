import SwiftUI
import Combine

/// 随主窗口存活的临时会话；刷新时清空，退出应用后自然释放。
@MainActor
final class DiskMapSession: ObservableObject {
    @Published var root: DiskMapNode?
    @Published var stack: [DiskMapNode] = []
    @Published var isLoading = false

    private var directoryChildren: [String: [DiskMapNode]] = [:]

    func cachedChildren(of path: String) -> [DiskMapNode]? {
        directoryChildren[path]
    }

    func children(of path: String) async -> [DiskMapNode] {
        if let cached = directoryChildren[path] { return cached }
        let children = await DiskMapBuilder.children(of: path)
        directoryChildren[path] = children
        return children
    }

    func clear() {
        root = nil
        stack.removeAll()
        directoryChildren.removeAll()
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

                if session.isLoading {
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

                        if current.children.isEmpty {
                            Text("此节点下无可展示子项")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

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

                    Text("点按色块或小文件卡片查看内容 · 横向滚动查看其余项目 · 用上方路径返回")
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
            MetricTile(title: "体量", value: node.sizeFormatted, subtitle: "\(node.children.count) 个子项", gradient: Theme.warmGradient, compact: true)
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
        session.isLoading = true
        defer { session.isLoading = false }
        if viewModel.hasScanned {
            session.root = await DiskMapBuilder.fromScanResults(viewModel.scanResults)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let children = await session.children(of: home)
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

        guard node.isDirectory, !session.isLoading else { return }
        if let children = session.cachedChildren(of: node.path) {
            showExpanded(node, children: children)
            return
        }

        session.isLoading = true
        Task {
            let children = await session.children(of: node.path)
            showExpanded(node, children: children)
            session.isLoading = false
        }
    }

    private func showExpanded(_ node: DiskMapNode, children: [DiskMapNode]) {
        let expanded = DiskMapNode(
            id: node.id,
            name: node.name,
            path: node.path,
            size: node.size,
            isDirectory: true,
            children: children
        )
        drillForward = true
        withAnimation(Theme.spring) {
            session.stack.append(expanded)
        }
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

            VStack(spacing: 0) {
                if !arrangement.cells.isEmpty {
                    ZStack(alignment: .topLeading) {
                        ForEach(arrangement.cells) { cell in
                            if let child = node.children.first(where: { $0.id == cell.node.id }) {
                                largeBlock(child, cell: cell)
                                    .position(x: cell.rect.midX, y: cell.rect.midY)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: arrangement.mapHeight)
                }

                if !arrangement.compact.isEmpty {
                    compactStrip(arrangement.compact, rows: arrangement.rows)
                        .frame(width: geo.size.width, height: arrangement.stripHeight)
                }
            }
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

    private func arrange(in size: CGSize) -> (cells: [TreemapCell], compact: [DiskMapNode], mapHeight: CGFloat, stripHeight: CGFloat, rows: Int) {
        let nodes = node.children.map {
            TreemapNode(id: $0.id, name: $0.name, size: $0.size, color: color(for: $0, index: 0))
        }
        // 先按保留一行小项目的可用面积试排。放不下名称和大小的块统一进入横向区域。
        let probeHeight = max(1, size.height - 154)
        let probe = TreemapLayout.squarify(
            nodes: nodes,
            in: CGRect(x: 0, y: 0, width: size.width, height: probeHeight)
        )
        let readableIDs = Set(probe.filter { $0.rect.width >= 124 && $0.rect.height >= 74 }.map(\.id))
        let large = nodes.filter { readableIDs.contains($0.id) }
        let compact = node.children.filter { !readableIDs.contains($0.id) }
        let rows = large.isEmpty ? 3 : 1
        let stripHeight: CGFloat = compact.isEmpty ? 0 : (large.isEmpty ? size.height : 154)
        let mapHeight = max(0, size.height - stripHeight)
        let cells = TreemapLayout.squarify(
            nodes: large,
            in: CGRect(x: 0, y: 0, width: size.width, height: mapHeight)
        )
        return (cells, compact, mapHeight, stripHeight, rows)
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

    private func compactStrip(_ children: [DiskMapNode], rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("较小项目 · \(children.count) 项")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 10))
                Text("横向滚动查看")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: true) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(104), spacing: 8), count: rows), spacing: 8) {
                    ForEach(children) { child in
                        compactBlock(child)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(10)
    }

    private func compactBlock(_ child: DiskMapNode) -> some View {
        let tint = color(for: child, index: 0)
        let isSelected = selectedID == child.id
        return Button {
            select(child)
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(
                    colors: [tint.opacity(0.92), tint.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.35),
                                lineWidth: isSelected ? 2.5 : 1)
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                            .font(.system(size: 13))
                        Text(child.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(child.sizeFormatted)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundColor(.white)
                    .padding(10)
                }
                .frame(width: 172, height: 104)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.name, forType: .string)
        } label: {
            Label("复制名称", systemImage: "character.textbox")
        }
    }
}
