import SwiftUI
import Combine

/// 在概览深度搜索与重复文件页面之间共享本次扫描结果。
@MainActor
final class DuplicateScanSession: ObservableObject {
    @Published var groups: [DuplicateFileScanner.DuplicateGroup] = []
    @Published var isLoading = false
    @Published var hasScanned = false
    private var scanTask: Task<[DuplicateFileScanner.DuplicateGroup], Never>?
    private var generation = 0

    var totalWasted: Int64 { groups.reduce(0) { $0 + $1.wastedSize } }

    func scan() async {
        guard !isLoading else {
            await scanTask?.value
            return
        }
        isLoading = true
        generation += 1
        let requestGeneration = generation
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = ["\(home)/Downloads", "\(home)/Documents", "\(home)/Desktop", "\(home)/Movies"]
        let task = Task { await DuplicateFileScanner.findDuplicates(roots: roots) }
        scanTask = task
        let result = await task.value
        guard generation == requestGeneration else { return }
        scanTask = nil
        if !task.isCancelled {
            groups = result
            hasScanned = true
        }
        isLoading = false
    }

    func cancel() {
        generation += 1
        scanTask?.cancel()
        scanTask = nil
        isLoading = false
    }
}

/// 重复文件清理页
struct DuplicateFilesView: View {
    @ObservedObject var session: DuplicateScanSession
    @State private var selectedRemovePaths = Set<String>()
    @State private var keepPaths: [String: String] = [:]
    @State private var expandedGroupIDs = Set<String>()
    @State private var appearProgress: CGFloat = 0
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""

    private var totalWasted: Int64 {
        session.totalWasted
    }

    private var groups: [DuplicateFileScanner.DuplicateGroup] { session.groups }
    private var isLoading: Bool { session.isLoading }
    private var hasScanned: Bool { session.hasScanned }

    var body: some View {
        VStack(spacing: 0) {
            // 固定 Header（不随列表滚动）
            headerBar
            if hasScanned && !isLoading {
                metricsBar
            }
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

            // 内容区
            if !hasScanned && !isLoading {
                GeometryReader { viewport in
                    ScrollView {
                        preScanState
                            .frame(minHeight: viewport.size.height)
                    }
                }
            } else if isLoading {
                GeometryReader { viewport in
                    ScrollView {
                        scanningState
                            .frame(minHeight: viewport.size.height)
                    }
                }
            } else if groups.isEmpty {
                GeometryReader { viewport in
                    ScrollView {
                        emptyState
                            .frame(minHeight: viewport.size.height)
                    }
                }
            } else {
                // 可折叠 + 可滚动列表
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                }
            }
        }
        .navigationTitle("")
        .background(Theme.canvas.ignoresSafeArea())
        .onAppear {
            withAnimation(Theme.easeSlow) { appearProgress = 1 }
        }
        .alert("部分删除失败", isPresented: $showingDeleteError) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage)
        }
    }

    // MARK: - 固定 Header
    private var headerBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.55, blue: 0.25), Color(red: 1, green: 0.35, blue: 0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("重复文件")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("点箭头展开副本 · 点圆点选保留")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if hasScanned && !isLoading {
                DetailTextButton(title: "全部展开", systemImage: "chevron.down") {
                    withAnimation(Theme.spring) {
                        expandedGroupIDs = Set(groups.map(\.id))
                    }
                }
                DetailTextButton(title: "全部收起", systemImage: "chevron.up") {
                    withAnimation(Theme.spring) {
                        expandedGroupIDs.removeAll()
                    }
                }
                DetailTextButton(title: "重新扫描", systemImage: "arrow.clockwise") {
                    Task { await scan() }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Theme.canvas)
    }

    private var metricsBar: some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "重复组",
                value: "\(groups.count)",
                subtitle: "展开可查看副本",
                gradient: Theme.accentGradient,
                compact: true
            )
            MetricTile(
                title: "可释放",
                value: FileSizeFormatter.string(fromByteCount: totalWasted),
                subtitle: "保留一份后的冗余",
                gradient: Theme.warmGradient,
                compact: true
            )
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background(Theme.canvas)
    }

    // MARK: - 折叠分组
    private func groupSection(_ group: DuplicateFileScanner.DuplicateGroup) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.id)

        return VStack(alignment: .leading, spacing: 0) {
            // 折叠头
            Button {
                withAnimation(Theme.spring) {
                    if isExpanded {
                        expandedGroupIDs.remove(group.id)
                    } else {
                        expandedGroupIDs.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.orange)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.files.first?.name ?? "副本")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text("\(group.files.count) 份 · 每份 \(group.sizeFormatted)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("冗余 \(group.wastedSizeFormatted)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 展开的副本列表（组内滚动）
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(group.files) { file in
                            fileRow(file, group: group)
                        }

                        Button {
                            Task { await deleteExtra(in: group) }
                        } label: {
                            Text("删除冗余 \(group.files.count - 1) 份 · \(group.wastedSizeFormatted)")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundColor(.white)
                                .background(Capsule().fill(Color.red.opacity(0.88)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .padding(10)
                }
                .frame(maxHeight: 260)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
        .cardShadow()
    }

    private func fileRow(_ file: FileItem, group: DuplicateFileScanner.DuplicateGroup) -> some View {
        let keepPath = keepPaths[group.id] ?? group.files.first?.path ?? ""
        let isKeep = file.path == keepPath

        return HStack(spacing: 10) {
            Button {
                withAnimation(Theme.spring) {
                    keepPaths[group.id] = file.path
                    for f in group.files where f.path != file.path {
                        selectedRemovePaths.insert(f.path)
                    }
                }
            } label: {
                Image(systemName: isKeep ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(isKeep ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(isKeep ? "保留此份" : "设为保留")

            VStack(alignment: .leading, spacing: 2) {
                Text(file.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "时间未知")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            Spacer()
            Text(isKeep ? "保留" : "可删")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isKeep ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill((isKeep ? Color.green : Color.red).opacity(0.12)))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isKeep ? Color.green.opacity(0.06) : Color.primary.opacity(0.03))
        )
    }

    /// 未扫描：与分类页同构的居中主视觉
    private var preScanState: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 132, height: 132)
                    .blur(radius: 18)

                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 100, height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.55, blue: 0.25), Color(red: 1, green: 0.35, blue: 0.42)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .elevatedShadow()
            }
            .scaleEffect(0.88 + 0.12 * appearProgress)
            .opacity(appearProgress)

            VStack(spacing: 10) {
                Text("尚未扫描重复文件")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("将对比下载、文稿、桌面、影片中的大文件（≥1MB），找出内容相同的副本。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .lineSpacing(3)
            }
            .opacity(min(1, max(0, (appearProgress - 0.15) / 0.55)))
            .offset(y: (1 - appearProgress) * 10)

            Button {
                Task { await scan() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                    Text("开始扫描")
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 13)
            }
            .buttonStyle(GradientButtonStyleCompact())
            .opacity(min(1, max(0, (appearProgress - 0.35) / 0.5)))
            .offset(y: (1 - appearProgress) * 12)
            .scaleEffect(0.96 + 0.04 * appearProgress)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var scanningState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.15)
            Text("正在扫描重复文件…")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            Text("下载 / 文稿 / 桌面 / 影片 · 单文件 ≥ 1MB")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("未发现明显重复文件")
                .font(.headline)
            Text("扫描范围：下载、文稿、桌面、影片（单文件 ≥ 1MB）")
                .font(.caption)
                .foregroundColor(.secondary)

        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func scan() async {
        expandedGroupIDs = []
        await session.scan()
        selectedRemovePaths = []
        keepPaths = [:]
        for g in groups {
            keepPaths[g.id] = g.files.first?.path
        }
    }

    private func deleteExtra(in group: DuplicateFileScanner.DuplicateGroup) async {
        let keepPath = keepPaths[group.id] ?? group.files.first?.path ?? ""
        guard let keep = group.files.first(where: { $0.path == keepPath }) ?? group.files.first else { return }
        let remove = group.files.filter { $0.path != keep.path }
        let outcome = DuplicateFileScanner.removeDuplicates(keep: keep, remove: remove)
        AppLog.info("dedupe group cleaned", metadata: [
            "removed": "\(outcome.removed)",
            "failed": "\(outcome.failed)"
        ])
        await scan()
        if outcome.failed > 0 {
            deleteErrorMessage = "\(outcome.failed) 个副本未能删除：\n" + outcome.details.prefix(3).joined(separator: "\n")
            showingDeleteError = true
        }
    }
}
