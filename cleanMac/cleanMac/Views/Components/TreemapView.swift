import SwiftUI

/// 磁盘 Treemap：按体量嵌套矩形
struct TreemapNode: Identifiable {
    let id: String
    let name: String
    let size: Int64
    let color: Color
    var children: [TreemapNode] = []

    var sizeFormatted: String { FileSizeFormatter.string(fromByteCount: size) }
}

struct TreemapView: View {
    let root: TreemapNode
    var onSelect: ((TreemapNode) -> Void)? = nil

    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { geo in
            let cells = squarify(
                nodes: root.children.isEmpty ? [root] : root.children,
                in: CGRect(origin: .zero, size: geo.size)
            )

            ZStack(alignment: .topLeading) {
                ForEach(cells) { cell in
                    cellView(cell)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
        .cardShadow()
    }

    private func cellView(_ cell: TreemapCell) -> some View {
        let isHovered = hoveredID == cell.node.id
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        cell.node.color.opacity(isHovered ? 0.95 : 0.82),
                        cell.node.color.opacity(isHovered ? 0.70 : 0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if cell.rect.width > 64 && cell.rect.height > 36 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cell.node.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        if cell.rect.height > 52 {
                            Text(cell.node.sizeFormatted)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.92))
                                .monospacedDigit()
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: cell.rect.width, height: cell.rect.height)
            .position(x: cell.rect.midX, y: cell.rect.midY)
            .scaleEffect(isHovered ? 0.985 : 1)
            .animation(Theme.spring, value: hoveredID)
            .onHover { hovering in
                withAnimation(Theme.ease) { hoveredID = hovering ? cell.node.id : nil }
            }
            .onTapGesture { onSelect?(cell.node) }
            .help("\(cell.node.name) · \(cell.node.sizeFormatted)")
    }
}

struct TreemapCell: Identifiable {
    let node: TreemapNode
    let rect: CGRect
    var id: String { node.id }
}

/// 按文件大小分割面积，递归选择接近一半的分组，避免大量细长色块。
enum TreemapLayout {
    static func squarify(nodes: [TreemapNode], in bounds: CGRect) -> [TreemapCell] {
        let sorted = nodes.filter { $0.size > 0 }.sorted {
            $0.size == $1.size ? $0.id < $1.id : $0.size > $1.size
        }
        var result: [TreemapCell] = []
        partition(ArraySlice(sorted), in: bounds, into: &result)
        return result
    }

    private static func partition(_ nodes: ArraySlice<TreemapNode>, in rect: CGRect, into result: inout [TreemapCell]) {
        guard let first = nodes.first, rect.width > 0, rect.height > 0 else { return }
        if nodes.count == 1 {
            let insetX = min(2, rect.width / 4)
            let insetY = min(2, rect.height / 4)
            result.append(TreemapCell(node: first, rect: rect.insetBy(dx: insetX, dy: insetY)))
            return
        }

        let total = nodes.reduce(0.0) { $0 + Double($1.size) }
        var leading = 0.0
        var splitIndex = nodes.startIndex + 1
        for index in nodes.startIndex..<(nodes.endIndex - 1) {
            let next = leading + Double(nodes[index].size)
            if abs(total / 2 - next) <= abs(total / 2 - leading) || index == nodes.startIndex {
                leading = next
                splitIndex = index + 1
            } else {
                break
            }
        }

        let fraction = CGFloat(leading / total)
        let firstRect: CGRect
        let secondRect: CGRect
        if rect.width >= rect.height {
            let width = rect.width * fraction
            firstRect = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
            secondRect = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            let height = rect.height * fraction
            firstRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
            secondRect = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
        partition(nodes[nodes.startIndex..<splitIndex], in: firstRect, into: &result)
        partition(nodes[splitIndex..<nodes.endIndex], in: secondRect, into: &result)
    }
}

private extension TreemapView {
    func squarify(nodes: [TreemapNode], in bounds: CGRect) -> [TreemapCell] {
        TreemapLayout.squarify(nodes: nodes, in: bounds)
    }
}
