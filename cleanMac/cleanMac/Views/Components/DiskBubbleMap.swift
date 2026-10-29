import SwiftUI

enum DiskMapColors {
    static func color(for node: DiskMapNode) -> Color {
        let palette: [Color] = [.indigo, .blue, .purple, .teal, .orange, .pink]
        let index = node.id.utf8.reduce(0) { ($0 * 31 + Int($1)) % palette.count }
        return palette[index]
    }
}

struct DiskMapItemIcon: View {
    let node: DiskMapNode
    var size: CGFloat = 32

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .resizable().scaledToFit().foregroundStyle(node.isDirectory ? Color.blue : .secondary)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: node.path) {
            guard node.path.hasPrefix("/") else { return }
            icon = NSWorkspace.shared.icon(forFile: node.path)
        }
    }
}

struct DiskBubbleMap: View {
    let nodes: [DiskMapNode]
    let focusedID: String?
    let selectedIDs: Set<String>
    @Binding var hoveredID: String?
    let onSelect: (DiskMapNode) -> Void
    let onDrill: (DiskMapNode) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var bubbleHoverID: String?

    private var visibleNodes: [DiskMapNode] {
        Array(nodes.filter { $0.size > 0 }.sorted {
            $0.size == $1.size ? $0.id < $1.id : $0.size > $1.size
        }.prefix(18))
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let bubbles = DiskBubbleLayout.arrange(weights: visibleNodes.map { ($0.id, $0.size) }, in: geometry.size)
                let byID = Dictionary(visibleNodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                ZStack(alignment: .topLeading) {
                    ForEach(bubbles) { bubble in
                        if let node = byID[bubble.id] {
                            bubbleView(node, diameter: bubble.radius * 2)
                                .position(bubble.center)
                        }
                    }
                    if let id = hoveredID, let node = byID[id], let bubble = bubbles.first(where: { $0.id == id }) {
                        DiskMapHoverInfo(node: node)
                            .frame(width: min(260, max(180, geometry.size.width - 24)))
                            .position(x: min(max(135, bubble.center.x), max(135, geometry.size.width - 135)),
                                      y: min(max(72, bubble.center.y + bubble.radius * 0.45), max(72, geometry.size.height - 72)))
                            .allowsHitTesting(false)
                            .zIndex(10)
                    }
                    if visibleNodes.isEmpty {
                        Text("项目大小为 0，可在左侧目录清单中查看")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
            Text(nodes.filter { $0.size > 0 }.count > 18
                 ? "展示最大的 18 项 · 全部项目见左侧清单"
                 : "完整数值与小项目可在左侧清单查看")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    private func bubbleView(_ node: DiskMapNode, diameter: CGFloat) -> some View {
        let tint = DiskMapColors.color(for: node)
        let active = focusedID == node.id || hoveredID == node.id
        return Button { onSelect(node) } label: {
            Circle()
                .fill(RadialGradient(colors: [
                    tint.opacity(colorScheme == .dark ? 0.18 : 0.06),
                    tint.opacity(colorScheme == .dark ? 0.38 : 0.22)
                ], center: .init(x: 0.38, y: 0.3), startRadius: 0, endRadius: diameter * 0.65))
                .overlay(Circle().strokeBorder(active ? Color.accentColor : tint.opacity(0.55), lineWidth: active ? 2.5 : 1))
                .overlay {
                    if diameter >= 46 {
                        VStack(spacing: diameter > 120 ? 8 : 3) {
                            DiskMapItemIcon(node: node, size: min(58, max(20, diameter * 0.25)))
                            if diameter >= 90 {
                                Text(node.name)
                                    .font(.system(size: diameter > 180 ? 16 : 12, weight: .semibold))
                                    .lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
                                    .frame(maxWidth: diameter * 0.72)
                                Text(node.sizeFormatted)
                                    .font(.system(size: diameter > 180 ? 14 : 11, weight: .medium, design: .rounded))
                                    .monospacedDigit().lineLimit(1)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if selectedIDs.contains(node.id), diameter >= 46 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor, Theme.surfaceRaised)
                            .font(.system(size: 18))
                            .padding(diameter * 0.1)
                    }
                }
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .shadow(color: tint.opacity(active ? 0.2 : 0.05), radius: active ? 14 : 5, y: 4)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDrill(node) })
        .onHover { hovering in
            if hovering { hoveredID = node.id; bubbleHoverID = node.id }
            else if bubbleHoverID == node.id {
                bubbleHoverID = nil
                if hoveredID == node.id { hoveredID = nil }
            }
        }
        .animation(reduceMotion ? nil : Theme.ease, value: active)
        .accessibilityLabel("\(node.name)，\(node.sizeFormatted)")
        .accessibilityValue(DiskMapSelectionPolicy.protectionReason(for: node.path) ?? "可选择的项目")
        .accessibilityHint(node.isDirectory ? "选择查看；也可在左侧使用进入目录按钮" : "选择查看文件信息")
        .accessibilityAddTraits(focusedID == node.id ? .isSelected : [])
        .help("\(node.name) · \(node.sizeFormatted)\n\(node.path)")
        .contextMenu {
            Button(node.isDirectory ? "进入目录" : "查看详情") { onDrill(node) }
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
            }
        }
    }
}

/// 与悬停目标绑定，异步读取元数据，避免移动鼠标时遍历目录。
private struct DiskMapHoverInfo: View {
    let node: DiskMapNode
    @State private var modified: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Label(DiskMapSelectionPolicy.protectionReason(for: node.path) ?? (node.isDirectory ? "文件夹 · 可选择" : "文件 · 可选择"),
                  systemImage: DiskMapSelectionPolicy.protectionReason(for: node.path) == nil ? "info.circle" : "lock.fill")
                .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
            Text("大小：\(node.sizeFormatted)").font(.system(size: 12)).monospacedDigit()
            if let modified {
                Text("修改于 \(modified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
            }
            Text(node.path).font(.system(size: 10)).foregroundStyle(Theme.navigationSecondary)
                .lineLimit(2).truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
        .task(id: node.path) {
            modified = nil
            let path = node.path
            modified = await Task.detached(priority: .utility) {
                (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            }.value
        }
    }
}
