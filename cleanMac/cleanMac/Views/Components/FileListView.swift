import SwiftUI

/// 文件列表视图
struct FileListView: View {
    let files: [FileItem]
    let allFiles: [FileItem]
    let onDelete: (FileItem) -> Void
    let onDeleteBatch: (([FileItem]) -> Void)?
    let deleteTitle: String
    let onReveal: (FileItem) -> Void
    let onOpen: (FileItem) -> Void
    
    @Binding var selectedFiles: Set<FileItem.ID>
    @State private var hoveredFileID: FileItem.ID?
    @State private var selectionAnchorID: FileItem.ID?
    
    init(
        files: [FileItem],
        allFiles: [FileItem],
        selectedFiles: Binding<Set<FileItem.ID>> = .constant([]),
        onDelete: @escaping (FileItem) -> Void,
        onDeleteBatch: (([FileItem]) -> Void)? = nil,
        deleteTitle: String = "移到废纸篓",
        onReveal: @escaping (FileItem) -> Void,
        onOpen: @escaping (FileItem) -> Void
    ) {
        self.files = files
        self.allFiles = allFiles
        self._selectedFiles = selectedFiles
        self.onDelete = onDelete
        self.onDeleteBatch = onDeleteBatch
        self.deleteTitle = deleteTitle
        self.onReveal = onReveal
        self.onOpen = onOpen
    }
    
    /// 当前选中的文件对象
    private var selectedFileItems: [FileItem] {
        allFiles.filter { selectedFiles.contains($0.id) }
    }
    
    /// 右键菜单关联的文件
    private func contextMenuTargets(for file: FileItem) -> [FileItem] {
        if selectedFiles.contains(file.id) {
            return selectedFileItems
        }
        return [file]
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(files) { file in
                    FileCardRow(
                        file: file,
                        isSelected: selectedFiles.contains(file.id),
                        isHovered: hoveredFileID == file.id,
                        onToggleSelection: {
                            toggleSelection(for: file)
                        },
                        onSelect: {
                            if NSEvent.modifierFlags.contains(.shift) {
                                // Shift+点击：选择范围
                                selectRange(to: file)
                            } else {
                                // 整行点击与复选框一致：切换当前项，保留其他选择。
                                toggleSelection(for: file)
                            }
                        },
                        onOpen: { onOpen(file) },
                        onReveal: { onReveal(file) },
                        deleteTitle: deleteTitle,
                        onDelete: { onDelete(file) }
                    )
                    .contextMenu {
                        contextMenuContent(for: file)
                    }
                    .onHover { isHovered in
                        hoveredFileID = isHovered ? file.id : nil
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(Color(.windowBackgroundColor))
    }

    private func toggleSelection(for file: FileItem) {
        if selectedFiles.contains(file.id) {
            selectedFiles.remove(file.id)
        } else {
            selectedFiles.insert(file.id)
        }
        selectionAnchorID = file.id
    }
    
    /// 选择范围
    private func selectRange(to targetFile: FileItem) {
        guard let anchorID = selectionAnchorID ?? files.first(where: { selectedFiles.contains($0.id) })?.id,
              let firstIndex = files.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = files.firstIndex(where: { $0.id == targetFile.id }) else {
            selectedFiles.insert(targetFile.id)
            selectionAnchorID = targetFile.id
            return
        }
        
        let range = min(firstIndex, targetIndex)...max(firstIndex, targetIndex)
        let idsInRange = files[range].map(\.id)
        selectedFiles.formUnion(idsInRange)
    }
    
    // MARK: - 右键菜单内容
    
    @ViewBuilder
    private func contextMenuContent(for file: FileItem) -> some View {
        let targets = contextMenuTargets(for: file)
        let count = targets.count
        
        // 打开（单选）
        if count == 1 {
            Button { onOpen(file) } label: {
                Label("打开", systemImage: "macwindow")
            }
            Divider()
        }
        
        // 在 Finder 中显示
        Button {
            for f in targets { onReveal(f) }
        } label: {
            Label(count > 1 ? "在 Finder 中全部显示" : "在 Finder 中显示", systemImage: "folder")
        }
        
        // 复制路径
        Button {
            copyToPasteboard(targets.map(\.path))
        } label: {
            Label(count > 1 ? "复制全部路径" : "复制路径", systemImage: "doc.on.doc")
        }
        
        // 复制文件名
        Button {
            copyToPasteboard(targets.map(\.name))
        } label: {
            Label(count > 1 ? "复制全部文件名" : "复制文件名", systemImage: "character.textbox")
        }
        
        // 显示简介（单选）
        if count == 1 {
            Divider()
            Button { revealInfoPanel(for: file) } label: {
                Label("显示简介", systemImage: "info.circle")
            }
        }
        
        // 删除
        Divider()
        Button(role: .destructive) {
            if count > 1, let batch = onDeleteBatch {
                batch(targets)
            } else {
                onDelete(file)
            }
        } label: {
            Label(count > 1 ? "\(deleteTitle) (\(count) 项)" : deleteTitle, systemImage: "trash")
        }
    }
    
    /// 复制文本到剪贴板
    private func copyToPasteboard(_ texts: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texts.joined(separator: "\n"), forType: .string)
    }
    
    /// 打开 Finder 文件简介面板
    private func revealInfoPanel(for file: FileItem) {
        let script = """
        tell application "Finder"
            reveal POSIX file "\(file.path)"
            activate
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }
}

// MARK: - 文件卡片行
struct FileCardRow: View {
    let file: FileItem
    let isSelected: Bool
    let isHovered: Bool
    let onToggleSelection: () -> Void
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let deleteTitle: String
    let onDelete: () -> Void

    private var showsActions: Bool { isHovered || isSelected }
    
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSelected ? "取消选择" : "选择文件")
            .accessibilityLabel(isSelected ? "取消选择 \(file.name)" : "选择 \(file.name)")

            HStack(spacing: 14) {
                // 文件图标
                if let appIcon = file.appIcon {
                    // 应用程序图标
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // 系统图标
                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text.fill")
                        .font(.system(size: 20))
                        .foregroundColor(file.isDirectory ? .blue : .secondary)
                        .frame(width: 36, height: 36)
                        .background(file.isDirectory ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            
                // 文件信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.path)
                
                    Text(file.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "时间未知")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.75))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onOpen)
            .onTapGesture(count: 1, perform: onSelect)

            HStack(spacing: 0) {
                Text(file.sizeFormatted)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 78, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: onOpen)
                    .onTapGesture(count: 1, perform: onSelect)

                HStack(spacing: 4) {
                    IconOnlyButton(systemImage: "folder", help: "在 Finder 中显示", action: onReveal)
                    IconOnlyButton(systemImage: "trash", help: deleteTitle, role: .destructive, action: onDelete)
                }
                .padding(.leading, showsActions ? 8 : 0)
                .frame(width: showsActions ? 68 : 0, alignment: .trailing)
                .opacity(showsActions ? 1 : 0)
                .clipped()
                .allowsHitTesting(showsActions)
            }
            .animation(.easeInOut(duration: 0.18), value: showsActions)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.055))
                .frame(height: 1)
                .padding(.leading, 84)
        }
    }
    
    private var rowBackground: some ShapeStyle {
        if isSelected {
            return Color.accentColor.opacity(0.09)
        }
        if isHovered {
            return Color.primary.opacity(0.035)
        }
        return Color.clear
    }
}

private struct IconOnlyButton: View {
    let systemImage: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(ActionIconButtonStyle(isHovered: isHovered, isDestructive: role == .destructive))
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ActionIconButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isDestructive ? .red : (isHovered ? .primary : .secondary))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDestructive && (isHovered || configuration.isPressed)
                          ? Color.red.opacity(configuration.isPressed ? 0.22 : 0.12)
                          : Color.primary.opacity(configuration.isPressed ? 0.18 : (isHovered ? 0.11 : 0.045)))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
