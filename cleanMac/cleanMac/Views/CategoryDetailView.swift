import SwiftUI
import UniformTypeIdentifiers

/// 类别详情视图
struct CategoryDetailView: View {
    let category: ScanCategory
    @ObservedObject var viewModel: MainViewModel
    let onOpenSettings: () -> Void
    
    @State private var sortBy: SortOption = .size
    @State private var searchText = ""
    @State private var ageFilter: FileAgeBucket?
    @State private var isSearchExpanded = false
    @State private var selectedFiles = Set<FileItem.ID>()
    @State private var showingEmptyTrashConfirmation = false
    @State private var showingDiagnostics = false
    @State private var previewImage: FileItem?
    @State private var appearProgress: CGFloat = 0
    @FocusState private var isSearchFocused: Bool
    
    enum SortOption: String, CaseIterable {
        case size = "按大小"
        case date = "按日期"
        case name = "按名称"

        var icon: String {
            switch self {
            case .size: return "arrow.down.to.line.compact"
            case .date: return "calendar"
            case .name: return "textformat"
            }
        }

    }
    
    private var result: ScanResult? {
        viewModel.scanResults[category]
    }
    
    /// 是否已扫描
    private var isScanned: Bool {
        result != nil
    }
    
    /// 排序后的文件
    private var sortedFiles: [FileItem] {
        guard let items = result?.items else { return [] }
        
        var filtered = items

        if let ageFilter {
            filtered = filtered.filter { FileAgeBucket.bucket(for: $0.modificationDate) == ageFilter }
        }

        let keywords = normalizedSearchText(searchText)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if !keywords.isEmpty {
            filtered = filtered.filter { file in
                let name = normalizedSearchText(file.name)
                let path = normalizedSearchText(file.path)
                let application = normalizedSearchText(file.cacheApplication?.name ?? "")
                return keywords.allSatisfy { keyword in
                    fuzzyContains(keyword, in: name) || fuzzyContains(keyword, in: path)
                        || fuzzyContains(keyword, in: application)
                }
            }
        }
        
        switch sortBy {
        case .size:
            filtered.sort { $0.size > $1.size }
        case .date:
            filtered.sort { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .name:
            filtered.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        
        return filtered
    }

    private var sortControls: some View {
        HStack(spacing: 3) {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    withAnimation(Theme.ease) { sortBy = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: sortBy == option ? .semibold : .medium))
                        .foregroundStyle(sortBy == option ? Color.white : Color.secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background {
                            if sortBy == option {
                                RoundedRectangle(cornerRadius: 7).fill(Theme.accentGradient)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sortBy == option ? .isSelected : [])
                .help(option.rawValue)
            }
        }
        .padding(3)
        .background(Theme.inlineSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06)))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("文件排序")
    }

    private func normalizedSearchText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    /// 完整包含优先；否则允许查询字符在原顺序下不连续出现。
    private func fuzzyContains(_ query: String, in text: String) -> Bool {
        if text.contains(query) { return true }
        var position = text.startIndex
        for character in query {
            guard let match = text[position...].firstIndex(of: character) else { return false }
            position = text.index(after: match)
        }
        return true
    }
    
    private var selectedFileItems: [FileItem] {
        (result?.items ?? []).filter { selectedFiles.contains($0.id) }
    }

    private var visibleImages: [FileItem] {
        sortedFiles.filter { file in
            !file.isDirectory && UTType(filenameExtension: file.pathURL.pathExtension)?.conforms(to: .image) == true
        }
    }

    private var allVisibleFilesSelected: Bool {
        !sortedFiles.isEmpty && sortedFiles.allSatisfy { selectedFiles.contains($0.id) }
    }
    
    private var selectedTotalSize: Int64 {
        selectedFileItems.reduce(0) { $0 + $1.size }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if result?.isScanning != true {
                    headerBar
                    if let result, !result.items.isEmpty || !result.overlappingItems.isEmpty {
                        DisclosureGroup("空间统计与扫描说明") {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("磁盘占用 \(result.allocatedSize.map { FileSizeFormatter.string(fromByteCount: $0) } ?? "未完整获取") · 已识别云端占位 \(result.cloudPlaceholderCount) 个")
                                Text("磁盘占用为元数据估算，APFS 共享块、快照和废纸篓会影响实际释放量。")
                                if !result.overlappingItems.isEmpty { Text("另有 \(result.overlappingItems.count) 项已归属其他类别，此处不重复统计。") }
                                if category == .applicationCache {
                                    if let comparison = viewModel.applicationCacheComparison {
                                        Text(comparison.description)
                                        Text("复用 \(comparison.reusedRoots) 个目录 · 重扫 \(comparison.rescannedRoots) 个目录；复用前已校验规则、身份、权限、变化版本与元数据。")
                                    }
                                    if let error = CacheScanIndex.shared.persistenceError { Text(error) }
                                }
                            }.font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary).padding(.top, 6)
                        }.font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                            .padding(.horizontal, 22).padding(.bottom, 12)
                    }

                }

                if let result = result {
                    if result.isScanning {
                        VStack(spacing: 12) {
                            scanningView
                            if result.diagnostics != nil {
                                Button("诊断详情") { showingDiagnostics = true }.buttonStyle(.plain)
                                    .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                            }
                            Button(result.diagnostics?.status == .cancelled ? "正在取消…" : "取消扫描") { viewModel.cancelCategoryScan(category) }
                                .disabled(result.diagnostics?.status == .cancelled)
                                .padding(.bottom, 22)
                        }
                    } else if result.items.isEmpty && result.error != nil {
                        scanErrorView
                    } else if result.items.isEmpty {
                        emptyView
                    } else {
                        fileListContent
                    }
                } else {
                    preScanView
                }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            if let diagnostics = result?.diagnostics { ScanDiagnosticsView(category: category, diagnostics: diagnostics) }
        }
        .navigationTitle("")
        .sheet(item: $previewImage) { file in
            ImagePreviewView(files: visibleImages, initialPath: file.path)
        }
        .onChange(of: result?.items.map(\.id) ?? []) { availableIDs in
            selectedFiles.formIntersection(availableIDs)
        }
        .overlay {
            ModalHostView(
                isPresented: showingEmptyTrashConfirmation,
                onDismiss: { showingEmptyTrashConfirmation = false }
            ) {
                ModalDialogView(
                    title: "清空废纸篓",
                    message: "确定永久删除废纸篓中的 \(result?.itemCount ?? 0) 个项目吗？此操作无法撤销。",
                    confirmTitle: "清空废纸篓",
                    isDestructive: true,
                    iconSystemName: "trash.slash.fill",
                    onConfirm: {
                        showingEmptyTrashConfirmation = false
                        Task { await viewModel.emptyTrash() }
                    },
                    onCancel: {
                        showingEmptyTrashConfirmation = false
                    }
                )
            }
        }
        .overlay {
            // 清空废纸篓占位：阻断页面交互
            if viewModel.isEmptyingTrash {
                ZStack {
                    Color.black.opacity(0.30)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.15)
                        Text("正在清空废纸篓…")
                            .font(.system(size: 16, weight: .semibold))
                        Text("请稍候，完成后才能继续操作")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.surfaceRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .elevatedShadow()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: showingEmptyTrashConfirmation)
        .animation(Theme.spring, value: viewModel.isEmptyingTrash)
    }

    // MARK: - 顶部信息区（左：标题+指标 / 右：操作）
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 12) {
                Image(category.iconAsset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(category.color)
                    .frame(width: 18, height: 18)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(category.color.opacity(0.12))
                    )
                    .accessibilityHidden(true)

                Text(category.rawValue)
                    .font(.system(size: 16, weight: .semibold))
            }

            if let result = result, !result.items.isEmpty {
                MetricPill(title: "逻辑大小", value: result.totalSizeFormatted, color: .orange)
                MetricPill(title: "\(category.itemUnit)数", value: "\(result.itemCount)")
            }

            Spacer(minLength: 12)
            if result?.diagnostics != nil {
                Button { showingDiagnostics = true } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain)
                    .foregroundStyle(result?.diagnostics?.summary == nil ? Color.secondary : Color.orange)
                    .help(result?.diagnostics?.summary == nil ? "查看扫描诊断" : "扫描结果不完整，查看诊断")
                    .accessibilityLabel("查看扫描诊断").accessibilityValue(result?.diagnostics?.summary ?? "扫描完成")
            }


            if let result = result, !result.items.isEmpty {
                HStack(spacing: 10) {
                    if category == .trash {
                        DetailTextButton(
                            title: "清空废纸篓",
                            systemImage: "trash.slash",
                            role: .destructive
                        ) {
                            showingEmptyTrashConfirmation = true
                        }
                        .disabled(result.error != nil)
                        .help(result.error == nil ? "永久删除废纸篓中的所有项目" : "部分废纸篓无法读取，请先授予权限")
                    }

                    rescanControl
                }
            } else if result?.isScanning == true {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("扫描中…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else if result != nil {
                rescanControl
            } else {
                Text(category.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var rescanControl: some View {
        if category == .applicationCache {
            Menu {
                Button("增量扫描") { Task { await viewModel.scanCategory(category) } }
                Button("完整重扫") { Task { await viewModel.scanCategory(category, forceFull: true) } }
            } label: { Label("重新扫描", systemImage: "arrow.clockwise") }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 12))
        } else {
            DetailTextButton(title: "重新扫描", systemImage: "arrow.clockwise") {
                Task { await viewModel.scanCategory(category) }
            }
        }
    }

    // MARK: - 前置页面（未扫描状态）：居中一体主视觉
    private var preScanView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 22) {
                // 图标（与标题、按钮同轴）
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.16))
                        .frame(width: 132, height: 132)
                        .blur(radius: 18)

                    Image(category.iconAsset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [category.color, category.color.opacity(0.72)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .elevatedShadow()
                        .accessibilityHidden(true)
                }
                .scaleEffect(0.88 + 0.12 * appearProgress)
                .opacity(appearProgress)

                VStack(spacing: 10) {
                    Text(category.rawValue)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text(category.description)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                        .lineSpacing(4)
                }
                .opacity(min(1, max(0, (appearProgress - 0.15) / 0.55)))
                .offset(y: (1 - appearProgress) * 10)

                // 主按钮与标题同轴融合
                Button {
                    Task { await viewModel.scanCategory(category) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                        Text("开始扫描")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                }
                .buttonStyle(GradientButtonStyleCompact())
                .disabled(result?.isScanning == true)
                .opacity(min(1, max(0, (appearProgress - 0.35) / 0.5)))
                .offset(y: (1 - appearProgress) * 12)
                .scaleEffect(0.96 + 0.04 * appearProgress)
            }
            .frame(maxWidth: 520)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startEntranceAnimation() }
        .onChange(of: category) { _ in
            appearProgress = 0
            startEntranceAnimation()
        }
    }

    private func startEntranceAnimation() {
        appearProgress = 0
        withAnimation(Theme.easeSlow) {
            appearProgress = 1
        }
    }

    // MARK: - 文件列表内容
    private var fileListContent: some View {
        VStack(spacing: 0) {
            if let error = result?.error, error != result?.diagnostics?.summary {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
            }

            // 大文件时间线
            if category == .largeFiles || category == .downloads {
                timelineBar
            }

            // 应用卸载增强
            if category == .applications {
                leftoverSummaryBar
            }

            // 工具栏
            HStack(spacing: 8) {
                if isSearchExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        TextField("模糊搜索文件…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .focused($isSearchFocused)
                            .onAppear { isSearchFocused = true }
                        Button {
                            searchText = ""
                            isSearchFocused = false
                            withAnimation(Theme.spring) {
                                isSearchExpanded = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("关闭搜索")
                    }
                    .padding(.horizontal, 12)
                    .frame(minWidth: 150, idealWidth: 220, maxWidth: 260)
                    .frame(height: 36)
                    .background(Theme.inlineSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                } else {
                    Button {
                        withAnimation(Theme.spring) {
                            isSearchExpanded = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.inlineSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .help("搜索文件")
                    .accessibilityLabel("搜索文件")
                }

                sortControls

                Text(searchText.isEmpty && ageFilter == nil ? "" : "筛选出 \(sortedFiles.count) 个\(category.itemUnit)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Button {
                    withAnimation(Theme.springSnappy) {
                        let visibleIDs = Set(sortedFiles.map(\.id))
                        if allVisibleFilesSelected {
                            selectedFiles.subtract(visibleIDs)
                        } else {
                            selectedFiles.formUnion(visibleIDs)
                        }
                    }
                } label: {
                    Label(allVisibleFilesSelected ? "取消全选" : "全选",
                          systemImage: allVisibleFilesSelected ? "checkmark.square.fill" : "checkmark.square")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .keyboardShortcut("a", modifiers: .command)
                .disabled(sortedFiles.isEmpty)
                .help("选择列表中的所有文件（⌘A）")

                Spacer()

            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

            // 文件列表（底部为悬浮胶囊预留空间）
            ZStack {
                FileListView(
                    files: sortedFiles,
                    allFiles: result?.items ?? [],
                    groupsByApplication: category == .browserCache || category == .applicationCache,
                    applicationGroupSort: sortBy == .size ? .size : (sortBy == .date ? .date : .name),
                    selectedFiles: $selectedFiles,
                    onDelete: { file in
                        viewModel.requestDeleteFile(file, from: category)
                    },
                    onDeleteBatch: { files in
                        viewModel.requestDeleteFiles(files, from: category)
                    },
                    deleteTitle: category == .applications ? "卸载" : (category == .trash ? "永久删除" : "移到废纸篓"),
                    onReveal: { file in
                        viewModel.revealInFinder(file)
                    },
                    onOpen: { file in
                        if visibleImages.contains(where: { $0.path == file.path }) {
                            previewImage = file
                        } else {
                            viewModel.openFile(file)
                        }
                    }
                )
                // 按胶囊的实际高度预留空间，窄窗口换行后也不会遮住最后一行。
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !selectedFileItems.isEmpty {
                        selectionSummaryBar
                            .padding(.top, 8)
                            .padding(.bottom, 18)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Color.clear.frame(height: 12)
                    }
                }

                if sortedFiles.isEmpty {
                    noMatchesView
                }
            }
        }
        .onDeleteCommand {
            guard !selectedFileItems.isEmpty else { return }
            deleteSelectedFiles()
        }
        .animation(Theme.spring, value: selectedFileItems.count)
    }

    // MARK: - 大文件时间线
    private var timelineBar: some View {
        let groups = FileTimeline.group(sortedFiles)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("时间线")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("按修改时间分层")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }

            HStack(spacing: 8) {
                ForEach(groups, id: \.bucket) { group in
                    Button {
                        withAnimation(Theme.spring) {
                            if ageFilter == group.bucket {
                                ageFilter = nil
                            } else {
                                ageFilter = group.bucket
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.bucket.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ageFilter == group.bucket ? .accentColor : .secondary)
                            Text(FileSizeFormatter.string(fromByteCount: group.totalSize))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("\(group.items.count) 项")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            ProportionBar(
                                progress: sortedFiles.isEmpty ? 0 : Double(group.totalSize) / Double(max(1, sortedFiles.reduce(Int64(0)) { $0 + $1.size })),
                                gradient: Theme.categoryGradient(bucketColor(group.bucket)),
                                height: 4
                            )
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(ageFilter == group.bucket
                                      ? AnyShapeStyle(Theme.accentGradientSoft)
                                      : AnyShapeStyle(Theme.inlineSurface))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func bucketColor(_ bucket: FileAgeBucket) -> Color {
        switch bucket {
        case .last30Days: return .red
        case .lastYear: return .orange
        case .older: return .green
        case .unknown: return .gray
        }
    }

    // MARK: - 应用卸载残留摘要
    private var leftoverSummaryBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.indigo)
            Text("点按「卸载」将展示残留路径与大小，可勾选一并删除")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            if selectedFileItems.count == 1, let app = selectedFileItems.first {
                Button {
                    Task { viewModel.requestUninstall([app]) }
                } label: {
                    Label("查看卸载与残留", systemImage: "shippingbox")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(Theme.surfaceSunk.opacity(0.5))
    }
    // MARK: - 选择汇总胶囊（悬浮，不遮挡列表）
    private var selectionSummaryBar: some View {
        SelectionSummaryCapsule(
            count: selectedFileItems.count,
            totalSize: selectedTotalSize,
            actionTitle: deleteButtonTitle,
            onDelete: {
                withAnimation(Theme.springSnappy) {
                    deleteSelectedFiles()
                }
            }
        )
        .padding(.horizontal, 16)
    }

    private var deleteButtonTitle: String {
        switch category {
        case .applications: return "卸载所选"
        case .trash: return "永久删除"
        default: return "移到废纸篓"
        }
    }

    // MARK: - 批量删除
    private func deleteSelectedFiles() {
        let items = selectedFileItems
        guard !items.isEmpty else { return }
        viewModel.requestDeleteFiles(items, from: category)
    }
    
    private func revealSelectedFiles() {
        viewModel.revealInFinder(selectedFileItems)
    }

    private func copySelectedPaths() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedFileItems.map(\.path).joined(separator: "\n"), forType: .string)
    }
    
    // MARK: - 状态视图
    private var scanErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 42))
                .foregroundColor(.orange)
            Text("无法读取废纸篓")
                .font(.headline)
            Text(result?.error ?? "扫描失败")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                Button("前往权限设置", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                Button("重新扫描") {
                    Task { await viewModel.scanCategory(category) }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        ScanningPlaceholderView(
            title: "正在扫描 \(category.rawValue)",
            subtitle: "正在读取文件信息",
            currentPath: result?.diagnostics?.currentPath ?? ""
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 空结果：已干净
    private var emptyView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.16))
                    .frame(width: 132, height: 132)
                    .blur(radius: 18)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Theme.successGradient)
                    .frame(width: 100, height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.green.opacity(0.22),
                                        Color.teal.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(Color.green.opacity(0.22), lineWidth: 1)
                            )
                    )
                    .elevatedShadow()
            }
            .scaleEffect(0.88 + 0.12 * appearProgress)
            .opacity(appearProgress)

            VStack(spacing: 10) {
                Text("没有可清理的\(category.itemUnit)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("此类别很干净，暂时不需要处理")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .opacity(min(1, max(0, (appearProgress - 0.15) / 0.55)))
            .offset(y: (1 - appearProgress) * 10)

            Button {
                Task { await viewModel.scanCategory(category) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("重新扫描")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
            }
            .buttonStyle(GradientButtonStyleCompact())
            .disabled(result?.isScanning == true)
            .opacity(min(1, max(0, (appearProgress - 0.35) / 0.5)))
            .offset(y: (1 - appearProgress) * 12)
            .scaleEffect(0.96 + 0.04 * appearProgress)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startEntranceAnimation() }
    }

    private var noMatchesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("没有匹配结果")
                .font(.system(size: 16, weight: .semibold))
            Text("换一个关键词试试")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if !searchText.isEmpty {
                Button("清除搜索") {
                    withAnimation(Theme.spring) {
                        searchText = ""
                        isSearchExpanded = false
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 详情页文字按钮
struct DetailTextButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    init(title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isDestructive = role == .destructive
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(
                isDestructive
                    ? AnyShapeStyle(Color.red)
                    : AnyShapeStyle(Color.primary)
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1)
        .onHover { hovering in
            withAnimation(Theme.springSnappy) { isHovered = hovering }
        }
    }

    private var backgroundColor: Color {
        if isDestructive {
            return isHovered ? Color.red.opacity(0.12) : Color.red.opacity(0.06)
        }
        return isHovered ? Theme.inlineSurface : Color.primary.opacity(0.04)
    }

    private var borderColor: Color {
        if isDestructive {
            return Color.red.opacity(0.18)
        }
        return Color.primary.opacity(0.08)
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .gradientGlass(cornerRadius: 10)
    }
}
