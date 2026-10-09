import SwiftUI

/// 主内容视图
struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @StateObject private var xcodeAnalysisViewModel = XcodeAnalysisViewModel()
    @StateObject private var duplicateScanSession = DuplicateScanSession()
    @StateObject private var diskMapSession = DiskMapSession()
    @StateObject private var deviceInformationViewModel = DeviceInformationViewModel()
    @ObservedObject private var appActions = AppActionCoordinator.shared
    @State private var selectedTab: SidebarView.SidebarTab = .dashboard
    @State private var isDeepSearching = false
    @State private var deepSearchStage = ""
    @State private var deepSearchTask: Task<Void, Never>?

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
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 260)
        } detail: {
            ZStack(alignment: .top) {
                Theme.canvas.ignoresSafeArea()
                Theme.canvasWash.ignoresSafeArea()

                Group {
                    switch selectedTab {
                    case .dashboard:
                        DashboardView(
                            viewModel: viewModel,
                            duplicateSession: duplicateScanSession,
                            xcodeViewModel: xcodeAnalysisViewModel,
                            isDeepSearching: isDeepSearching,
                            deepSearchStage: deepSearchStage,
                            onDeepSearch: startDeepSearch,
                            onCancelDeepSearch: cancelDeepSearch,
                            openDuplicates: { selectedTab = .duplicates },
                            openXcode: { selectedTab = .xcode }
                        )
                    case .deviceInfo:
                        DeviceInformationView(viewModel: deviceInformationViewModel)
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
                        DiskMapView(session: diskMapSession)
                    case .duplicates:
                        DuplicateFilesView(session: duplicateScanSession)
                    case .timeline:
                        StorageTimelineView()
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
        .overlay {
            ZStack {
            if viewModel.showingSmartCleanDialog {
                GeometryReader { geometry in
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Color.black.opacity(0.23))
                            .ignoresSafeArea()
                            .onTapGesture { viewModel.cancelSmartClean() }

                        SmartCleanConfirmDialog(
                            plan: viewModel.smartCleanDraft ?? SmartCleanPlan(items: [], totalSize: 0, categorySummary: []),
                            selectedPaths: $viewModel.smartCleanSelectedPaths,
                            onAddToWhitelist: { viewModel.addSmartCleanItemToWhitelist($0) },
                            onConfirm: { viewModel.confirmSmartClean() },
                            onCancel: { viewModel.cancelSmartClean() }
                        )
                        .frame(
                            width: min(720, geometry.size.width - 36),
                            height: min(700, geometry.size.height - 36)
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
                .zIndex(100)
            }
            if viewModel.isSmartCleaning {
                SmartCleanCleaningOverlay()
                    .transition(.opacity)
                    .zIndex(120)
            }
            }
        }
        .task {
            await viewModel.loadStartupSnapshot()
            handlePendingOverviewScan()
            handlePendingTrashReview()
        }
        .onChange(of: appActions.overviewScanRequest) { _ in
            handlePendingOverviewScan()
        }
        .onChange(of: appActions.trashReviewRequest) { _ in
            handlePendingTrashReview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("scanAll"))) { _ in
            Task { await viewModel.scanAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("trashDidChange"))) { _ in
            guard viewModel.scanResults[.trash] != nil else { return }
            Task { await viewModel.scanCategory(.trash) }
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

    private func handlePendingOverviewScan() {
        guard appActions.consumeOverviewScanRequest() else { return }
        selectedTab = .dashboard
        Task { await viewModel.scanAll() }
    }

    private func handlePendingTrashReview() {
        guard appActions.consumeTrashReviewRequest() else { return }
        viewModel.selectedCategory = .trash
        selectedTab = .category
        Task { await viewModel.scanCategory(.trash) }
    }

    private func startDeepSearch() {
        guard !isDeepSearching, !viewModel.isScanning, !viewModel.isCleaning,
              !duplicateScanSession.isLoading, !xcodeAnalysisViewModel.isScanning else { return }
        isDeepSearching = true
        deepSearchStage = "正在扫描清理、文件整理与应用项目…"
        deepSearchTask = Task {
            await viewModel.scanAll(scope: .deep)
            guard !Task.isCancelled else { return }

            deepSearchStage = "正在查找重复文件…"
            await duplicateScanSession.scan()
            guard !Task.isCancelled else { return }

            deepSearchStage = "正在分析 Xcode 数据…"
            await xcodeAnalysisViewModel.scanAndWait()
            guard !Task.isCancelled else { return }

            isDeepSearching = false
            deepSearchStage = ""
            deepSearchTask = nil
        }
    }

    private func cancelDeepSearch() {
        deepSearchTask?.cancel()
        deepSearchTask = nil
        viewModel.cancelScanAll()
        duplicateScanSession.cancel()
        xcodeAnalysisViewModel.cancel()
        isDeepSearching = false
        deepSearchStage = ""
    }

    // MARK: - 模态层
    @ViewBuilder
    private var modalLayer: some View {
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
