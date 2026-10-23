import SwiftUI
import AppKit

struct XcodeAnalysisView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: XcodeAnalysisViewModel

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pageHeader

                    if viewModel.isScanning {
                        scanningState
                            .frame(minHeight: max(320, viewport.size.height - 128))
                    } else if let result = viewModel.result {
                        summarySection(result)
                        kindSections(result)
                    } else {
                        idleState
                            .frame(minHeight: max(320, viewport.size.height - 128))
                    }
                }
                .frame(maxWidth: 920)
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("")
        .background(Theme.reviewCanvas(.indigo))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !viewModel.selectedPaths.isEmpty, !viewModel.isScanning {
                selectionBar
            }
        }
        .alert("删除失败", isPresented: Binding(
            get: { viewModel.deletionError != nil },
            set: { if !$0 { viewModel.deletionError = nil } }
        )) {
            Button("好的", role: .cancel) { viewModel.deletionError = nil }
        } message: {
            Text(viewModel.deletionError ?? "")
        }
    }

    // MARK: - 页头
    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("SidebarXcode")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.45, blue: 0.98),
                                    Color(red: 0.55, green: 0.35, blue: 0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .elevatedShadow()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Xcode 空间分析")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("构建缓存、归档、模拟器与扩展的占用情况")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            if viewModel.result != nil {
                DetailTextButton(title: "重新分析", systemImage: "sparkle.magnifyingglass") {
                    viewModel.scan()
                }
                .disabled(viewModel.isScanning || viewModel.isDeleting)
            }
        }
    }

    // MARK: - 汇总
    private func summarySection(_ result: XcodeAnalysisResult) -> some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "已分析空间",
                value: FileSizeFormatter.string(fromByteCount: result.totalSize),
                subtitle: "Xcode 相关占用",
                gradient: Theme.accentGradient,
                compact: true
            )
            MetricTile(
                title: "文件与文件夹",
                value: "\(result.artifacts.count)",
                subtitle: "扫描到的条目",
                gradient: Theme.successGradient,
                compact: true
            )
            MetricTile(
                title: "插件与扩展",
                value: "\(result.pluginCount)",
                subtitle: "编辑器扩展",
                gradient: Theme.warmGradient,
                compact: true
            )
        }
    }

    // MARK: - 分组列表
    private func kindSections(_ result: XcodeAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("分类明细")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accentGradient)
                    .textCase(.uppercase)
                    .kerning(0.5)
                Spacer()
                selectionButton()
            }

            ForEach(XcodeArtifactKind.allCases) { kind in
                group(kind, result: result)
            }
        }
    }

    private func selectionButton(in kind: XcodeArtifactKind? = nil) -> some View {
        let items = viewModel.selectableArtifacts(in: kind)
        let selectedCount = items.filter { viewModel.selectedPaths.contains($0.path) }.count
        let allSelected = !items.isEmpty && selectedCount == items.count
        return Button {
            viewModel.toggleSelectAll(in: kind)
        } label: {
            Capsule()
                .fill(allSelected ? Color.accentColor : Color.secondary.opacity(selectedCount > 0 ? 0.7 : 0.35))
                .frame(width: 4, height: kind == nil ? 20 : 32)
                .frame(width: 20, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("已选 \(selectedCount) 项，共 \(items.count) 项可选择")
        .disabled(items.isEmpty || viewModel.isScanning || viewModel.isDeleting)
        .accessibilityLabel("\(allSelected ? "取消全选" : "全选")\(kind?.rawValue ?? "所有分类")中的可删除项目")
        .help("\(allSelected ? "取消全选" : "全选")\(kind?.rawValue ?? "所有分类")中的可删除项目")
    }

    private var selectionBar: some View {
        SelectionSummaryCapsule(
            count: viewModel.selectedPaths.count,
            totalSize: viewModel.selectedSize,
            actionTitle: "移到废纸篓",
            isBusy: viewModel.isDeleting,
            onClear: { viewModel.clearSelection() },
            onDelete: {
                viewModel.requestTrash(viewModel.selectedArtifacts)
            }
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 空闲 / 扫描中
    private var idleState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.14))
                    .frame(width: 120, height: 120)
                    .blur(radius: 16)

                Image("SidebarXcode")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .frame(width: 88, height: 88)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.indigo.opacity(0.9), Color.purple.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .elevatedShadow()
                    .accessibilityHidden(true)
            }

            VStack(spacing: 8) {
                Text("尚未分析 Xcode 数据")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("扫描构建产物、缓存、归档、模拟器和编辑器扩展的占用。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button {
                viewModel.scan()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                    Text("开始分析")
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(GradientButtonStyleCompact())
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var scanningState: some View {
        ScanningPlaceholderView(
            title: "正在分析 Xcode 数据…",
            subtitle: "可切换其他页面，分析会在后台继续"
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var selectionGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [Color(red: 0.45, green: 0.65, blue: 1), Color(red: 0.65, green: 0.50, blue: 1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return Theme.accentGradient
    }

    // MARK: - 分组卡片
    private func group(_ kind: XcodeArtifactKind, result: XcodeAnalysisResult) -> some View {
        let items = result.artifacts(for: kind)
        let isExpanded = viewModel.expandedKinds.contains(kind)
        let selectableItems = viewModel.selectableArtifacts(in: kind)
        let selectedCount = selectableItems.filter { viewModel.selectedPaths.contains($0.path) }.count
        let selectionProgress = selectableItems.isEmpty ? 0 : Double(selectedCount) / Double(selectableItems.count)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toggleExpanded(kind)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.categoryGradient(.accentColor))
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            Text(kind.note)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(selectedCount > 0 ? "已选 \(selectedCount)/\(selectableItems.count) 项" : "\(items.count) 项")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .monospacedDigit()

                        Text(FileSizeFormatter.string(fromByteCount: result.size(for: kind)))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.warmGradient)
                            .monospacedDigit()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.rawValue)，\(items.count) 项，\(isExpanded ? "收起" : "展开")")
            }
            .padding(.leading, 16)

            if isExpanded {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)

                if items.isEmpty {
                    Text("未发现相关文件")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            artifactRow(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [Theme.surfaceRaised, Theme.surfaceRaised.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    selectionGradient
                        .opacity(colorScheme == .dark ? 0.20 : 0.13)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: geometry.size.width * selectionProgress)
                        }
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectionProgress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            selectionButton(in: kind)
                .padding(.top, 12)
        }
        .cardShadow()
        .accessibilityValue("已选择 \(selectedCount) 项，共 \(selectableItems.count) 项可选择")
    }

    private func artifactRow(_ item: XcodeArtifact) -> some View {
        let isSelected = viewModel.selectedPaths.contains(item.path)
        return HStack(spacing: 10) {
            Button {
                viewModel.toggleSelection(item)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.kind == .plugins ? "puzzlepiece.extension" : "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(item.detail ?? item.path)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(item.path)
                    }
                    Spacer(minLength: 8)
                    Text(item.sizeFormatted)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canDelete(item) || viewModel.isScanning || viewModel.isDeleting)
            .accessibilityLabel("\(isSelected ? "取消选择" : "选择") \(item.name)，\(item.sizeFormatted)")
            .accessibilityValue(isSelected ? "已选择" : "未选择")
            .help(viewModel.canDelete(item) ? "点击选择或取消选择" : "此项目不在可删除范围内")

            Button {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
            .accessibilityLabel("在 Finder 中显示 \(item.name)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.025))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isSelected)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                viewModel.requestTrash(viewModel.selectedPaths.contains(item.path) ? viewModel.selectedArtifacts : [item])
            } label: {
                Label(viewModel.selectedPaths.contains(item.path) && viewModel.selectedPaths.count > 1
                      ? "将所选 \(viewModel.selectedPaths.count) 项移到废纸篓" : "移到废纸篓", systemImage: "trash")
            }
            .disabled(!viewModel.canDelete(item) || viewModel.isScanning || viewModel.isDeleting)
        }
    }
}
