import SwiftUI

struct WorkspaceCardsView: View {
    let group: WorkspaceGroup
    @ObservedObject var viewModel: MainViewModel
    let namespace: Namespace.ID
    let onOpen: (WorkspaceDestination) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("cleanMac / \(group.rawValue)")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.navigationSecondary)
                        Text(group.rawValue).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(group.subtitle).font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: group.symbol)
                        .font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.accentGradient)
                        .frame(width: 64, height: 64)
                        .background(Theme.accentGradientSoft, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityHidden(true)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 210), spacing: 18),
                                         count: group.destinations.count > 4 ? 3 : 2), spacing: 18) {
                    ForEach(group.destinations) { destination in
                        WorkspaceFeatureCard(destination: destination, result: result(for: destination)) {
                            onOpen(destination)
                        }
                        .matchedGeometryEffect(id: destination.id, in: namespace,
                                               properties: reduceMotion ? [] : .frame, isSource: true)
                        .contextMenu {
                            Button("打开 \(destination.title)") { onOpen(destination) }
                            if case let .category(category) = destination {
                                Button("扫描") { Task { await viewModel.scanCategory(category) } }
                                    .disabled(viewModel.scanResults[category]?.isScanning == true)
                            }
                        }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.rays")
                    Text("选择功能卡片查看详情，扫描结果会在各页面间保留。")
                }
                .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
            }
            .padding(32)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }

    }

    private func result(for destination: WorkspaceDestination) -> ScanResult? {
        guard case let .category(category) = destination else { return nil }
        return viewModel.scanResults[category]
    }
}

private struct WorkspaceFeatureCard: View {
    let destination: WorkspaceDestination
    let result: ScanResult?
    let onOpen: () -> Void
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Group {
                        if case let .category(category) = destination {
                            Image(category.iconAsset).renderingMode(.template).resizable().scaledToFit()
                        } else {
                            Image(systemName: destination.symbol).resizable().scaledToFit()
                        }
                    }
                    .foregroundStyle(destination.color)
                    .frame(width: 21, height: 21)
                    .frame(width: 42, height: 42)
                    .background(destination.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isHovered ? Color.accentColor : Theme.navigationSecondary)
                        .frame(width: 28, height: 28)
                        .background(Theme.surfaceSunk, in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(destination.title).font(.system(size: 17, weight: .semibold))
                    Text(destination.subtitle).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                        .lineLimit(2).frame(height: 34, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack(spacing: 8) {
                    if result?.isScanning == true {
                        ProgressView().controlSize(.small)
                        Text("正在扫描…")
                    } else if let result {
                        Text(result.error != nil ? "部分内容需注意" : result.isCleaned ? "已清理" : "\(result.itemCount) 项")
                        Spacer(minLength: 4)
                        Text(result.totalSizeFormatted).fontWeight(.semibold).monospacedDigit()
                    } else {
                        Text(destination.group == .cleanup ? "等待扫描" : "查看详情")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                .frame(height: 18)
            }
            .padding(20)
            .foregroundStyle(.primary)
            .gradientGlass(cornerRadius: 23)
            .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(isFocused ? Color.accentColor : isHovered ? Color.accentColor.opacity(0.65) : Theme.hairline,
                        lineWidth: isFocused ? 2 : 1))
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0.025), radius: isHovered ? 16 : 7, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 23))
        }
        .buttonStyle(WorkspacePressStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovered)
        .accessibilityLabel(destination.title)
        .accessibilityHint("展开\(destination.title)页面")
    }
}

struct WorkspacePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
