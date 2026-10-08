import SwiftUI

/// 主内容视图
struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var selectedTab: SidebarView.SidebarTab = .dashboard
    
    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, selectedTab: $selectedTab)
        } detail: {
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(viewModel: viewModel)
                case .category:
                    if let category = viewModel.selectedCategory {
                        CategoryDetailView(category: category, viewModel: viewModel) {
                            selectedTab = .settings
                        }
                            .id(category)
                    } else {
                        categoryPlaceholder
                    }
                case .xcode:
                    XcodeAnalysisView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .navigationTitle("cleanMac")
        .alert(viewModel.alertTitle, isPresented: $viewModel.showingAlert) {
            Button("好的") { }
        } message: {
            Text(viewModel.alertMessage)
        }
        .alert(deleteActionTitle,
               isPresented: $viewModel.showingDeleteConfirmation) {
            Button("取消", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button(deleteActionTitle, role: .destructive) {
                viewModel.confirmDelete()
            }
        } message: {
            let count = viewModel.pendingDeleteFiles.count
            let totalSize = viewModel.pendingDeleteFiles.reduce(0) { $0 + $1.size }
            let sizeFormatted = FileSizeFormatter.string(fromByteCount: totalSize)
            let isTrash = viewModel.pendingDeleteCategory == .trash
            let isApplication = viewModel.pendingDeleteCategory == .applications
            
            if count <= 3 {
                // 少量文件时显示文件名
                let fileNames = viewModel.pendingDeleteFiles.map(\.name).joined(separator: "\n")
                Text(isTrash
                     ? "确定永久删除以下 \(count) 个项目（共 \(sizeFormatted)）吗？此操作无法撤销。\n\n\(fileNames)"
                     : isApplication
                     ? "确定卸载以下 \(count) 个应用（共 \(sizeFormatted)）吗？应用将移到废纸篓；相关数据可在应用残留中单独清理。\n\n\(fileNames)"
                     : "确定将以下 \(count) 个项目移到废纸篓（共 \(sizeFormatted)）吗？\n\n\(fileNames)")
            } else {
                // 大量文件时显示数量和大小
                Text(isTrash
                     ? "确定永久删除 \(count) 个项目（共 \(sizeFormatted)）吗？此操作无法撤销。"
                     : isApplication
                     ? "确定卸载 \(count) 个应用（共 \(sizeFormatted)）吗？应用将移到废纸篓；相关数据可在应用残留中单独清理。"
                     : "确定将 \(count) 个项目移到废纸篓（共 \(sizeFormatted)）吗？")
            }
        }
        .task {
            await viewModel.loadSystemInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("scanAll"))) { _ in
            Task { await viewModel.scanAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.resumeUninstallAfterPermissionSettings()
        }
        .onChange(of: viewModel.selectedCategory) { newValue in
            // 当从概览页面点击扫描结果时，自动切换到类别页面
            if newValue != nil {
                selectedTab = .category
            }
        }
    }

    private var deleteActionTitle: String {
        switch viewModel.pendingDeleteCategory {
        case .applications: "卸载"
        case .trash: "永久删除"
        default: "移到废纸篓"
        }
    }
    
    private var categoryPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("选择一个清理类别")
                .font(.headline)
            Text("从左侧边栏选择要扫描或清理的类别")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
