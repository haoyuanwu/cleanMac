import SwiftUI

/// 主内容视图
struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var xcodeAnalysisViewModel = XcodeAnalysisViewModel()
    @StateObject private var diskMapSession = DiskMapSession()
    @State private var selectedTab: SidebarView.SidebarTab = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: viewModel,
                xcodeIsScanning: xcodeAnalysisViewModel.isScanning,
                diskMapIsLoading: diskMapSession.isLoading,
                selectedTab: $selectedTab
            )
                .scrollContentBackground(.hidden)
                .background(Theme.sidebarGradient.ignoresSafeArea())
        } detail: {
            ZStack(alignment: .top) {
                Theme.canvas.ignoresSafeArea()
                Theme.canvasWash.ignoresSafeArea()

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
                        XcodeAnalysisView(viewModel: xcodeAnalysisViewModel)
                    case .diskMap:
                        DiskMapView(viewModel: viewModel, session: diskMapSession)
                    case .whitelist:
                        WhitelistView()
                    case .settings:
                        SettingsView()
                    }
                }

                // 居中模态：卸载残留 / 删除确认 / 提示
                modalLayer

                // 删除成功：Vortex 撒花 × 2
                CelebrationBanner(token: viewModel.celebrationToken)
                    .zIndex(30)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("cleanMac")
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
            if newValue != nil {
                selectedTab = .category
            }
        }
        .animation(Theme.spring, value: viewModel.showingUninstallDialog)
        .animation(Theme.spring, value: viewModel.showingDeleteConfirmation)
        .animation(Theme.spring, value: viewModel.showingAlert)
    }

    // MARK: - 模态层
    @ViewBuilder
    private var modalLayer: some View {
        ModalHostView(
            isPresented: viewModel.showingSmartCleanDialog,
            onDismiss: { viewModel.cancelSmartClean() }
        ) {
            SmartCleanConfirmDialog(
                plan: viewModel.smartCleanDraft ?? SmartCleanPlan(items: [], totalSize: 0, categorySummary: []),
                selectedPaths: $viewModel.smartCleanSelectedPaths,
                onConfirm: { viewModel.confirmSmartClean() },
                onCancel: { viewModel.cancelSmartClean() }
            )
        }
        .zIndex(19)

        ModalHostView(
            isPresented: viewModel.showingUninstallDialog,
            onDismiss: { viewModel.cancelUninstall() }
        ) {
            UninstallLeftoverDialog(
                estimates: viewModel.uninstallEstimates,
                selectedLeftoverPaths: $viewModel.selectedLeftoverPaths,
                onConfirm: { viewModel.confirmUninstall() },
                onCancel: { viewModel.cancelUninstall() }
            )
        }
        .zIndex(20)

        ModalHostView(
            isPresented: viewModel.showingDeleteConfirmation,
            onDismiss: { viewModel.cancelDelete() }
        ) {
            ModalDialogView(
                title: viewModel.deleteRequest?.actionTitle ?? "确认操作",
                message: viewModel.deleteRequest?.message ?? "",
                confirmTitle: viewModel.deleteRequest?.actionTitle ?? "确定",
                isDestructive: true,
                onConfirm: { viewModel.confirmDelete() },
                onCancel: { viewModel.cancelDelete() }
            )
        }
        .zIndex(10)

        ModalHostView(
            isPresented: viewModel.showingAlert,
            onDismiss: { viewModel.showingAlert = false }
        ) {
            ModalDialogView(
                title: viewModel.alertTitle,
                message: viewModel.alertMessage,
                confirmTitle: "好的",
                showsCancel: false,
                onConfirm: { viewModel.showingAlert = false }
            )
        }
        .zIndex(11)
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
