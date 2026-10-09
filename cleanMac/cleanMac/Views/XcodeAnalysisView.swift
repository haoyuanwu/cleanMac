import SwiftUI
import AppKit

struct XcodeAnalysisView: View {
    @ObservedObject var viewModel: XcodeAnalysisViewModel
    @State private var pendingDeletion: XcodeArtifact?
    @State private var showingDeleteConfirmation = false

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
        .alert("移到废纸篓", isPresented: $showingDeleteConfirmation, presenting: pendingDeletion) { item in
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("移到废纸篓", role: .destructive) {
                pendingDeletion = nil
                viewModel.moveToTrash(item)
            }
        } message: { item in
            Text("确定将“\(item.name)”（\(item.sizeFormatted)）移到废纸篓吗？")
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
            Text("分类明细")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accentGradient)
                .textCase(.uppercase)
                .kerning(0.5)

            ForEach(XcodeArtifactKind.allCases) { kind in
                group(kind, result: result)
            }
        }
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

    // MARK: - 分组卡片
    private func group(_ kind: XcodeArtifactKind, result: XcodeAnalysisResult) -> some View {
        let items = result.artifacts(for: kind)
        let isExpanded = viewModel.expandedKinds.contains(kind)
        return CardView(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
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

                        Text("\(items.count) 项")
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
        }
    }

    private func artifactRow(_ item: XcodeArtifact) -> some View {
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
                .fill(Color.primary.opacity(0.025))
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = item
                showingDeleteConfirmation = true
            } label: {
                Label("移到废纸篓", systemImage: "trash")
            }
            .disabled(!viewModel.canDelete(item) || viewModel.isScanning || viewModel.isDeleting)
        }
    }
}
