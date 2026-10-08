import SwiftUI

/// 多级磁盘 Treemap 页面：点击块下钻，面包屑返回
struct DiskMapView: View {
    @ObservedObject var viewModel: MainViewModel

    @State private var root: DiskMapNode?
    @State private var stack: [DiskMapNode] = []
    @State private var selectedFile: DiskMapNode?
    @State private var isLoading = false
    @State private var appeared = false
    /// 下钻方向：true 向下，false 返回
    @State private var drillForward = true

    private var current: DiskMapNode? {
        stack.last ?? root
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                breadcrumb

                if isLoading {
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

                    if !current.children.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                            ForEach(current.children.filter { $0.size > 0 }.sorted { $0.size > $1.size }) { child in
                                Button {
                                    drill(into: child)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                                            .foregroundColor(.accentColor)
                                        Text(child.name)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer(minLength: 4)
                                        Text(child.sizeFormatted)
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()
                                    }
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(child.path)
                                .contextMenu {
                                    DiskMapNodeContextMenu(node: child, onSelect: drill)
                                }
                            }
                        }
                    }

                    Text("点按目录色块下钻，点按文件色块查看详情 · 用上方路径返回")
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
            guard !appeared else { return }
            appeared = true
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
                    stack.removeAll()
                    await rebuild()
                }
            }
            .disabled(isLoading)
        }
    }

    // MARK: - 面包屑
    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    drillForward = false
                    withAnimation(Theme.spring) {
                        stack.removeAll()
                    }
                } label: {
                    Text("根")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(stack.isEmpty ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.05)))
                        )
                        .foregroundColor(stack.isEmpty ? .white : .primary)
                }
                .buttonStyle(.plain)

                ForEach(Array(stack.enumerated()), id: \.element.id) { index, node in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Button {
                        drillForward = false
                        withAnimation(Theme.spring) {
                            stack = Array(stack.prefix(index + 1))
                        }
                    } label: {
                        Text(node.name)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(index == stack.count - 1
                                          ? AnyShapeStyle(Theme.accentGradient)
                                          : AnyShapeStyle(Color.primary.opacity(0.05)))
                            )
                            .foregroundColor(index == stack.count - 1 ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(index == stack.count - 1 ? 1.02 : 1)
                    .animation(Theme.springSnappy, value: stack.count)
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
        isLoading = true
        if viewModel.hasScanned {
            root = await DiskMapBuilder.fromScanResults(viewModel.scanResults)
        } else if let home = Optional(FileManager.default.homeDirectoryForCurrentUser.path) {
            let children = await DiskMapBuilder.children(of: home, limit: 18)
            root = DiskMapNode(
                id: "home",
                name: "用户目录",
                path: home,
                size: children.reduce(0) { $0 + $1.size },
                isDirectory: true,
                children: children
            )
        }
        isLoading = false
    }

    private func drill(into node: DiskMapNode) {
        if !node.isDirectory && node.children.isEmpty {
            selectedFile = node
            return
        }

        Task {
            // 已有子项（扫描结果构建）直接下钻，避免误当路径去扫
            if !node.children.isEmpty {
                drillForward = true
                withAnimation(Theme.spring) {
                    stack.append(node)
                }
                return
            }

            guard node.isDirectory else { return }
            isLoading = true
            let children = await DiskMapBuilder.children(of: node.path, limit: 24)
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
                stack.append(expanded)
            }
            isLoading = false
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
            let cells = TreemapLayout.squarify(
                nodes: node.children.map {
                    TreemapNode(id: $0.id, name: $0.name, size: $0.size, color: color(for: $0, index: 0), children: [])
                },
                in: CGRect(origin: .zero, size: geo.size)
            )

            ZStack(alignment: .topLeading) {
                ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                    let child = node.children.first { $0.id == cell.node.id }
                    let tint = color(for: child ?? sampleNode(cell.node), index: index)
                    let isSelected = selectedID == cell.node.id

                    Button {
                        guard let child else { return }
                        withAnimation(Theme.spring) {
                            selectedID = child.id
                        }
                        onDrill(child)
                    } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.92), tint.opacity(0.62)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.35),
                                    lineWidth: isSelected ? 2.5 : 1
                                )
                        )
                        .overlay(alignment: .topLeading) {
                            if cell.rect.width > 44 && cell.rect.height > 22 {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cell.node.name)
                                        .font(.system(size: cell.rect.width > 72 ? 13 : 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(cell.rect.height > 40 ? 2 : 1)
                                        .truncationMode(.middle)
                                        .minimumScaleFactor(0.6)
                                    if cell.rect.width > 80 && cell.rect.height > 56 {
                                        Text(cell.node.sizeFormatted)
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(.white.opacity(0.95))
                                            .monospacedDigit()
                                    }
                                    if cell.rect.width > 100 && cell.rect.height > 80 {
                                        Text(hint(for: child))
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                }
                                .padding(cell.rect.width > 72 ? 10 : 4)
                            }
                        }
                        .frame(width: cell.rect.width, height: cell.rect.height)
                        .scaleEffect(isSelected ? 0.97 : (0.86 + 0.14 * reveal))
                        .opacity(Double(reveal))
                        .shadow(
                            color: isSelected ? tint.opacity(0.45) : .clear,
                            radius: 12,
                            y: 4
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: cell.rect.midX, y: cell.rect.midY)
                    .animation(Theme.spring, value: selectedID)
                    .help("\(cell.node.name) · \(cell.node.sizeFormatted)")
                    .contextMenu {
                        if let child {
                            DiskMapNodeContextMenu(node: child, onSelect: onDrill)
                        }
                    }
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

    private func hint(for child: DiskMapNode?) -> String {
        guard let child else { return "" }
        if !child.children.isEmpty { return "点按下钻 · \(child.children.count) 项" }
        if child.isDirectory { return "点按下钻子目录" }
        return "点按查看文件详情"
    }

    private func sampleNode(_ node: TreemapNode) -> DiskMapNode {
        DiskMapNode(id: node.id, name: node.name, path: node.id, size: node.size, isDirectory: true)
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
