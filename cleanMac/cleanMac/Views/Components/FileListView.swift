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
        let maxSize = files.map(\.size).max() ?? 0

        return ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(files) { file in
                    FileCardRow(
                        file: file,
                        isSelected: selectedFiles.contains(file.id),
                        isHovered: hoveredFileID == file.id,
                        sizeRatio: maxSize > 0 ? Double(file.size) / Double(maxSize) : 0,
                        onToggleSelection: {
                            withAnimation(Theme.springSnappy) {
                                toggleSelection(for: file)
                            }
                        },
                        onSelect: {
                            withAnimation(Theme.springSnappy) {
                                if NSEvent.modifierFlags.contains(.shift) {
                                    selectRange(to: file)
                                } else {
                                    toggleSelection(for: file)
                                }
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
                        withAnimation(Theme.ease) {
                            hoveredFileID = isHovered ? file.id : nil
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Theme.canvas)
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

        if count > 1 {
            Button {
                for t in targets {
                    UserWhitelist.add(t.path)
                }
            } label: {
                Label("批量加入白名单", systemImage: "shield.lefthalf.filled")
            }
        }
        
        // 显示简介（单选）
        if count == 1 {
            Divider()
            Button { revealInfoPanel(for: file) } label: {
                Label("显示简介", systemImage: "info.circle")
            }
        }

        // 白名单
        Divider()
        if UserWhitelist.isWhitelisted(file.path) {
            Button {
                UserWhitelist.remove(file.path)
            } label: {
                Label("移出白名单", systemImage: "shield.slash")
            }
            .help("移出白名单后允许清理")
        } else {
            Button {
                UserWhitelist.add(file.path)
            } label: {
                Label(count > 1 ? "将所选加入白名单" : "加入白名单", systemImage: "shield")
            }
            .help("加入白名单后永不清理")
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
    /// 相对当前列表最大文件的体量 0...1
    var sizeRatio: Double = 1
    let onToggleSelection: () -> Void
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void
    let deleteTitle: String
    let onDelete: () -> Void

    private var showsActions: Bool { isHovered || isSelected }

    /// 定宽格式，避免日期/时间参差
    private var dateText: String {
        guard let date = file.modificationDate else { return "时间未知" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 14) {
            // 左侧选中指示条
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                .frame(width: 3, height: 28)
                .animation(Theme.spring, value: isSelected)

            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.85))
                    .frame(width: 28, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSelected ? "取消选择" : "选择文件")
            .accessibilityLabel(isSelected ? "取消选择 \(file.name)" : "选择 \(file.name)")

            HStack(spacing: 14) {
                if let appIcon = file.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text.fill")
                        .font(.system(size: 22))
                        .foregroundColor(file.isDirectory ? .blue : .secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(file.isDirectory ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.12))
                        )
                }

                // 左侧信息：名称 + 日期 / 体量条（条左对齐）
                VStack(alignment: .leading, spacing: 8) {
                    Text(file.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.path)

                    ProportionBar(
                        progress: sizeRatio,
                        gradient: sizeGradient,
                        height: 4
                    )
                    .frame(maxWidth: 160, alignment: .leading)
                    .help("相对本列表最大文件的体量")

                    Text(dateText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onOpen)
            .onTapGesture(count: 1, perform: onSelect)

            // 右侧：定宽列，保证整列对齐
            HStack(spacing: 8) {
                Text(file.sizeFormatted)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 92, alignment: .trailing)

                HStack(spacing: 6) {
                    IconOnlyButton(systemImage: "folder", help: "在 Finder 中显示", action: onReveal)
                    IconOnlyButton(systemImage: "trash", help: deleteTitle, role: .destructive, action: onDelete)
                }
                .padding(.leading, showsActions ? 4 : 0)
                .frame(width: showsActions ? 88 : 0, alignment: .trailing)
                .opacity(showsActions ? 1 : 0)
                .clipped()
                .allowsHitTesting(showsActions)
            }
            .animation(Theme.spring, value: showsActions)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.04), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.008 : 1)
        .animation(Theme.spring, value: isHovered)
        .animation(Theme.spring, value: isSelected)
        .animation(Theme.easeSlow, value: sizeRatio)
    }

    private var sizeGradient: LinearGradient {
        // 大文件更偏暖色强调
        if sizeRatio >= 0.66 {
            return Theme.warmGradient
        }
        if sizeRatio >= 0.33 {
            return Theme.accentGradient
        }
        return LinearGradient(
            colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.35)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.11)
        }
        if isHovered {
            return Theme.surfaceRaised
        }
        return Color.primary.opacity(0.025)
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
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDestructive && (isHovered || configuration.isPressed)
                          ? Color.red.opacity(configuration.isPressed ? 0.22 : 0.12)
                          : Color.primary.opacity(configuration.isPressed ? 0.16 : (isHovered ? 0.10 : 0.05)))
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.springSnappy, value: isHovered)
            .animation(Theme.springSnappy, value: configuration.isPressed)
    }
}
