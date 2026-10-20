import SwiftUI

/// 主内容视图
struct ContentView: View {
    @ObservedObject private var viewModel = MainViewModel.shared
    @StateObject private var xcodeAnalysisViewModel = XcodeAnalysisViewModel()
    @StateObject private var duplicateScanSession = DuplicateScanSession()
    @StateObject private var diskMapSession = DiskMapSession()
    @StateObject private var deviceInformationViewModel = DeviceInformationViewModel()
    @ObservedObject private var appActions = AppActionCoordinator.shared
    @State private var selectedTab: SidebarView.SidebarTab = .dashboard
    @State private var isDeepSearching = false
    @State private var deepSearchStage = ""
    @State private var deepSearchStep = 0
    @State private var hasCompletedDeepSearch = false
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
                            deepSearchStep: deepSearchStep,
                            hasCompletedDeepSearch: hasCompletedDeepSearch,
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

                // 居中模态：卸载残留 / 提示
                modalLayer

            }
        }
        .navigationTitle("cleanMac")
        .overlay {
            ZStack {
            // 覆盖整个主窗口，包含侧边栏；只响应新完成的清理。
            CelebrationBanner(token: viewModel.celebrationToken)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(30)

            if viewModel.showingDeleteConfirmation, let request = viewModel.deleteRequest {
                TrashConfirmationOverlay(
                    request: request,
                    onConfirm: { viewModel.confirmDelete() },
                    onCancel: { viewModel.cancelDelete() }
                )
                .transition(.opacity)
                .zIndex(110)
            }
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
            if viewModel.showingDonationPrompt {
                DonationOverlay {
                    viewModel.showingDonationPrompt = false
                }
                .transition(.opacity)
                .zIndex(130)
            }
            }
        }
        .task {
            await viewModel.loadStartupSnapshot()
            handlePendingOverviewScan()
            handlePendingDeepScan()
            handlePendingDeviceInfo()
            handlePendingTrashReview()
        }
        .onChange(of: appActions.overviewScanRequest) { _ in
            handlePendingOverviewScan()
        }
        .onChange(of: appActions.deepScanRequest) { _ in
            handlePendingDeepScan()
        }
        .onChange(of: appActions.deviceInfoRequest) { _ in
            handlePendingDeviceInfo()
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

    private func handlePendingDeepScan() {
        guard appActions.consumeDeepScanRequest() else { return }
        selectedTab = .dashboard
        startDeepSearch()
    }

    private func handlePendingDeviceInfo() {
        guard appActions.consumeDeviceInfoRequest() else { return }
        selectedTab = .deviceInfo
        if deviceInformationViewModel.snapshot != nil {
            deviceInformationViewModel.refresh()
        }
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
        deepSearchStep = 0
        deepSearchStage = "正在扫描清理、文件整理与应用项目…"
        deepSearchTask = Task {
            await viewModel.scanAll(scope: .deep, showDonationAfterCompletion: false)
            guard !Task.isCancelled else { return }

            deepSearchStep = 1
            deepSearchStage = "正在查找重复文件…"
            await duplicateScanSession.scan()
            guard !Task.isCancelled else { return }

            deepSearchStep = 2
            deepSearchStage = "正在分析 Xcode 数据…"
            await xcodeAnalysisViewModel.scanAndWait()
            guard !Task.isCancelled else { return }

            hasCompletedDeepSearch = true
            viewModel.presentFirstScanDonationPromptIfNeeded()
            isDeepSearching = false
            deepSearchStep = 0
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
        deepSearchStep = 0
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
