import SwiftUI

/// 类别详情视图
struct CategoryDetailView: View {
    let category: ScanCategory
    @ObservedObject var viewModel: MainViewModel
    let onOpenSettings: () -> Void
    
    @State private var sortBy: SortOption = .size
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @State private var selectedFiles = Set<FileItem.ID>()
    @State private var showingEmptyTrashConfirmation = false
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
        
        let keywords = normalizedSearchText(searchText)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if !keywords.isEmpty {
            filtered = filtered.filter { file in
                let name = normalizedSearchText(file.name)
                let path = normalizedSearchText(file.path)
                return keywords.allSatisfy { keyword in
                    fuzzyContains(keyword, in: name) || fuzzyContains(keyword, in: path)
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

    private var allVisibleFilesSelected: Bool {
        !sortedFiles.isEmpty && sortedFiles.allSatisfy { selectedFiles.contains($0.id) }
    }
    
    private var selectedTotalSize: Int64 {
        selectedFileItems.reduce(0) { $0 + $1.size }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部信息栏
            headerBar

            // 内容区域
            if let result = result {
                if result.isScanning {
                    scanningView
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
        .navigationTitle(category.rawValue)
        .onChange(of: result?.items.map(\.id) ?? []) { availableIDs in
            selectedFiles.formIntersection(availableIDs)
        }
        .alert("清空废纸篓", isPresented: $showingEmptyTrashConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清空废纸篓", role: .destructive) {
                Task { await viewModel.emptyTrash() }
            }
        } message: {
            Text("确定永久删除废纸篓中的 \(result?.itemCount ?? 0) 个项目吗？此操作无法撤销。")
        }
    }
    
    // MARK: - 顶部信息栏
    private var headerBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: category.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(category.color)
                    .frame(width: 36, height: 36)
                    .background(category.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                    Text(category.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let result = result, !result.items.isEmpty {
                HStack(spacing: 18) {
                    MetricPill(title: "总大小", value: result.totalSizeFormatted, color: .orange)
                    MetricPill(title: "\(category.itemUnit)数", value: "\(result.itemCount)")

                    if category == .trash {
                        Button(role: .destructive) {
                            showingEmptyTrashConfirmation = true
                        } label: {
                            Label("清空废纸篓", systemImage: "trash.slash")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(result.error != nil)
                        .help(result.error == nil ? "永久删除废纸篓中的所有项目" : "部分废纸篓无法读取，请先授予权限")
                    }
                    
                    Button {
                        Task { await viewModel.scanCategory(category) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .help("重新扫描")
                    .disabled(viewModel.isScanning)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }
    
    // MARK: - 前置页面（未扫描状态）
    private var preScanView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: category.icon)
                    .font(.system(size: 56))
                    .foregroundColor(category.color)
                    .frame(width: 100, height: 100)
                    .background(category.color.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                
                Text(category.rawValue)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(category.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("将扫描以下位置：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(scanPathsForCategory, id: \.self) { path in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 400)
            
            Button {
                Task { await viewModel.scanCategory(category) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                    Text("开始扫描")
                        .font(.headline)
                }
                .frame(width: 200)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isScanning)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// 各类别对应的扫描路径
    private var scanPathsForCategory: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch category {
        case .systemCache:
            return ["\(home)/Library/Caches", "/Library/Caches", "/System/Library/Caches"]
        case .logFiles:
            return [
                "\(home)/Library/Logs",
                "/Library/Logs",
                "/var/log",
                "Xcode 日志文件夹",
                "CoreSimulator 日志文件夹",
                "~/.android/logs"
            ]
        case .browserCache:
            return ["Safari", "Chrome", "Firefox", "Edge 缓存目录"]
        case .trash:
            return ["\(home)/.Trash"]
        case .appLeftover:
            return ["\(home)/Library/Application Support", "\(home)/Library/Containers", "\(home)/Library/Saved Application State"]
        case .downloads:
            return ["\(home)/Downloads"]
        case .largeFiles:
            return ["\(home)/Documents", "\(home)/Desktop", "\(home)/Downloads", "\(home)/Movies", "\(home)/Music", "\(home)/Pictures"]
        case .applications:
            return ["/Applications", "\(home)/Applications"]
        case .installers:
            return [
                "\(home)/Downloads",
                "\(home)/Desktop",
                "\(home)/Documents",
                "系统缓存目录"
            ]
        }
    }
    
    // MARK: - 文件列表内容
    private var fileListContent: some View {
        VStack(spacing: 0) {
            if let error = result?.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
            }

            // 工具栏
            HStack(spacing: 10) {
                // 点击放大镜展开搜索
                if isSearchExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("模糊搜索文件...", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .onAppear { isSearchFocused = true }
                        Button {
                            searchText = ""
                            isSearchFocused = false
                            withAnimation(.easeOut(duration: 0.15)) {
                                isSearchExpanded = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("关闭搜索")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .frame(width: 230, height: 30)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isSearchExpanded = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .help("搜索文件")
                    .accessibilityLabel("搜索文件")
                }
                
                Text("\(sortedFiles.count) 个\(category.itemUnit)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Button {
                    let visibleIDs = Set(sortedFiles.map(\.id))
                    if allVisibleFilesSelected {
                        selectedFiles.subtract(visibleIDs)
                    } else {
                        selectedFiles.formUnion(visibleIDs)
                    }
                } label: {
                    Label(allVisibleFilesSelected ? "取消全选" : "全选",
                          systemImage: allVisibleFilesSelected ? "checkmark.square.fill" : "checkmark.square")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(sortedFiles.isEmpty)
                .help(searchText.isEmpty ? "选择列表中的所有文件" : "选择当前搜索结果")
                
                Spacer()
                
                // 排序下拉选择
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            sortBy = option
                        } label: {
                            if sortBy == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: sortBy.icon)
                        Text(sortBy.rawValue)
                            .fixedSize(horizontal: true, vertical: false)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            // 文件列表
            ZStack {
                FileListView(
                    files: sortedFiles,
                    allFiles: result?.items ?? [],
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
                        viewModel.openFile(file)
                    }
                )
                
                if sortedFiles.isEmpty {
                    noMatchesView
                }
                
            }

            // 汇总条单独占据底部空间，列表最后一行可完整滚动显示。
            if !selectedFileItems.isEmpty {
                selectionSummaryBar
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.windowBackgroundColor))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - 选择汇总悬浮栏
    private var selectionSummaryBar: some View {
        HStack(spacing: 10) {
            Text("已选 \(selectedFileItems.count) 项")
                .font(.system(size: 12, weight: .semibold))
            
            Text(FileSizeFormatter.string(fromByteCount: selectedTotalSize))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button {
                revealSelectedFiles()
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .help("在 Finder 中显示")
            .accessibilityLabel("在 Finder 中显示所选文件")
            
            Button {
                copySelectedPaths()
            } label: {
                Label("复制路径", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .help("复制所选文件的路径")
            
            Button(role: .destructive) {
                deleteSelectedFiles()
            } label: {
                Label(category == .applications ? "卸载" : (category == .trash ? "永久删除" : "移到废纸篓"), systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .tint(.red)
            .help(category == .applications ? "将所选应用移到废纸篓" : (category == .trash ? "永久删除所选项目" : "将所选文件移到废纸篓"))
            
            Button {
                selectedFiles.removeAll()
            } label: {
                Label("取消选择", systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .help("取消选择")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
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
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("正在扫描...")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("正在分析 \(category.rawValue) 中的文件")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("没有可清理的\(category.itemUnit)")
                .font(.headline)
            Text("此类别下没有找到需要清理的\(category.itemUnit)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                Task { await viewModel.scanCategory(category) }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noMatchesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text("没有匹配结果")
                .font(.system(size: 14, weight: .medium))
            Text("换一个关键词试试")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
