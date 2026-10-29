import SwiftUI

/// 主内容视图
struct ContentView: View {
    @ObservedObject private var viewModel = MainViewModel.shared
    @StateObject private var xcodeAnalysisViewModel = XcodeAnalysisViewModel()
    @StateObject private var duplicateScanSession = DuplicateScanSession()
    @StateObject private var startupInspection = LocalInspectionSession()
    @StateObject private var privacyInspection = LocalInspectionSession()
    @StateObject private var extensionInspection = LocalInspectionSession()
    @StateObject private var insightsSession = SpaceInsightsSession()
    @StateObject private var diskMapSession = DiskMapSession()
    @StateObject private var deviceInformationViewModel = DeviceInformationViewModel()
    @ObservedObject private var appActions = AppActionCoordinator.shared
    @State private var selectedTab: SidebarView.SidebarTab = .dashboard
    @State private var selectedGroup: WorkspaceGroup = .overview
    @State private var pageTravelDirection: CGFloat = 1
    @State private var showingPage = true
    @State private var returnToOverview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var workspaceAnimation
    @State private var isDeepSearching = false
    @State private var deepSearchStage = ""
    @State private var deepSearchStep = 0
    @State private var hasCompletedDeepSearch = false
    @State private var deepSearchTask: Task<Void, Never>?

    private var activeDestination: WorkspaceDestination {
        if selectedTab == .category, let category = viewModel.selectedCategory { return .category(category) }
        return .page(selectedTab)
    }

    private var navigationMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.44, dampingFraction: 0.88)
    }

    private var visiblePageID: String {
        showingPage ? "detail-" + activeDestination.id : "cards-" + selectedGroup.id
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 20 * pageTravelDirection)),
            removal: .opacity.combined(with: .offset(x: -10 * pageTravelDirection))
        )
    }

    private func setPageTravel(toward group: WorkspaceGroup) {
        let groups = WorkspaceGroup.allCases
        pageTravelDirection = (groups.firstIndex(of: group) ?? 0) >= (groups.firstIndex(of: selectedGroup) ?? 0) ? 1 : -1
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(viewModel: viewModel, xcodeIsScanning: xcodeAnalysisViewModel.isScanning,
                        diskMapIsLoading: diskMapSession.isLoading, selectedGroup: selectedGroup) { group in
                setPageTravel(toward: group)
                withAnimation(navigationMotion) {
                    if group == .overview { openDestination(.page(.dashboard)) }
                    else if group == .device { openDestination(.page(.deviceInfo)) }
                    else { showingPage = false; selectedGroup = group; returnToOverview = false }
                }
            }
            ZStack {
                Group {
                    if !showingPage {
                        WorkspaceCardsView(group: selectedGroup, viewModel: viewModel,
                                           namespace: workspaceAnimation, onOpen: openDestination)
                            .id("cards-" + selectedGroup.id)
                            .transition(pageTransition)
                    } else {
                        VStack(spacing: 0) {
                            if selectedTab != .dashboard {
                                HStack(spacing: 12) {
                                    if selectedTab != .dashboard && selectedTab != .deviceInfo {
                                        Button {
                                            if returnToOverview || selectedGroup == .overview { openDestination(.page(.dashboard)) }
                                            else {
                                                pageTravelDirection = -1
                                                withAnimation(navigationMotion) { showingPage = false }
                                            }
                                        } label: {
                                            Label(returnToOverview ? "一键清理" : selectedGroup.rawValue, systemImage: "chevron.left")
                                                .font(.system(size: 12, weight: .medium))
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(Theme.surfaceRaised, in: Capsule())
                                        }
                                        .buttonStyle(WorkspacePressStyle())
                                        .keyboardShortcut("[", modifiers: .command)
                                        .help("返回功能卡片")
                                        .accessibilityLabel(returnToOverview ? "返回一键清理结果" : "返回\(selectedGroup.rawValue)")
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 22).padding(.vertical, 8)
                            }
                            pageContent
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .matchedGeometryEffect(id: activeDestination.id, in: workspaceAnimation,
                                               properties: reduceMotion ? [] : .frame, isSource: true)
                        .id("detail-" + activeDestination.id)
                        .transition(pageTransition)
                        .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.24), value: visiblePageID)
                modalLayer.zIndex(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(WorkspaceBackdrop().ignoresSafeArea())
        .navigationTitle("cleanMac")
        .overlay(alignment: .top) {
            if showingPage, selectedTab == .category, let category = viewModel.selectedCategory,
               let result = viewModel.scanResults[category], !result.items.isEmpty,
               let diagnostics = result.diagnostics {
                ScanDiagnosticsBar(category: category, diagnostics: diagnostics)
                    .id(category).padding(.horizontal, 18).padding(.top, 8)
            }
        }
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
            if let items = xcodeAnalysisViewModel.pendingDeletion {
                TrashConfirmationOverlay(
                    xcodeArtifacts: items,
                    onConfirm: { xcodeAnalysisViewModel.confirmTrash() },
                    onCancel: { xcodeAnalysisViewModel.cancelTrash() }
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
            } else if viewModel.isUninstalling {
                SmartCleanCleaningOverlay(title: "正在卸载应用", subtitle: "正在将已确认的应用和关联数据移到废纸篓，请稍候")
                    .transition(.opacity).zIndex(120)
            } else if xcodeAnalysisViewModel.isDeleting {
                SmartCleanCleaningOverlay(
                    title: "正在清理 Xcode 数据",
                    subtitle: "正在将已确认的项目移到废纸篓，请稍候"
                )
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
        .onChange(of: viewModel.selectedLeftoverPaths) { _ in
            if viewModel.showingUninstallDialog { viewModel.refreshUninstallRunningApplications() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 从权限设置或其他应用返回后，不沿用可能跨越权限变化的扫描索引。
            CacheEventMonitor.shared.invalidateAll()
            if viewModel.showingUninstallDialog { viewModel.refreshUninstallRunningApplications() }
            viewModel.resumeUninstallAfterPermissionSettings()
        }
        .onChange(of: viewModel.selectedCategory) { newValue in
            if newValue != nil {
                if selectedTab == .dashboard { returnToOverview = true }
                selectedTab = .category
                selectedGroup = returnToOverview ? .overview : activeDestination.group
                showingPage = true
            }
        }
        .onChange(of: selectedTab) { _ in
            selectedGroup = selectedTab == .category && returnToOverview ? .overview : activeDestination.group
            showingPage = true
        }
        .sheet(isPresented: $viewModel.showingUninstallDialog, onDismiss: { viewModel.cancelUninstall() }) {
            UninstallLeftoverDialog(
                estimates: viewModel.uninstallEstimates,
                appCount: viewModel.pendingDeleteFiles.count,
                isLoading: viewModel.isEstimatingUninstall,
                runningApplications: viewModel.uninstallRunningApplications,
                isQuitting: viewModel.isQuittingUninstallApplications,
                statusMessage: viewModel.uninstallStatusMessage,
                selectedLeftoverPaths: $viewModel.selectedLeftoverPaths,
                onQuit: { viewModel.quitUninstallRunningApplications() },
                onRefresh: { viewModel.refreshUninstallRunningApplications() },
                onConfirm: { viewModel.confirmUninstall() },
                onCancel: { viewModel.cancelUninstall() }
            ).frame(width: 760, height: 580)
        }
        .animation(Theme.spring, value: viewModel.showingUninstallDialog)
        .animation(Theme.spring, value: viewModel.showingDeleteConfirmation)
        .animation(Theme.spring, value: viewModel.showingAlert)
    }

    @ViewBuilder
    private var pageContent: some View {
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
                openInsights: { openDestination(.page(.insights)) }
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
            DiskMapView(session: diskMapSession, storageInfo: viewModel.storageInfo)
        case .duplicates:
            DuplicateFilesView(session: duplicateScanSession)
        case .timeline:
            StorageTimelineView()
        case .whitelist:
            WhitelistView()
        case .settings:
            SettingsView()
        case .startup:
            LocalInspectionView(kind: .startup, session: startupInspection)
        case .privacy:
            LocalInspectionView(kind: .privacy, session: privacyInspection)
        case .extensions:
            LocalInspectionView(kind: .extensions, session: extensionInspection)
        case .insights:
            SpaceInsightsView(viewModel: viewModel, duplicateSession: duplicateScanSession, session: insightsSession)
        }
    }

    private func openDestination(_ destination: WorkspaceDestination) {
        setPageTravel(toward: destination.group)
        withAnimation(navigationMotion) {
            returnToOverview = false
            selectedGroup = destination.group
            switch destination {
            case let .category(category):
                viewModel.selectedCategory = category
                selectedTab = .category
            case let .page(page):
                viewModel.selectedCategory = nil
                selectedTab = page
            }
            showingPage = true
        }
    }

    private func handlePendingOverviewScan() {
        guard appActions.consumeOverviewScanRequest() else { return }
        openDestination(.page(.dashboard))
        Task { await viewModel.scanAll() }
    }

    private func handlePendingDeepScan() {
        guard appActions.consumeDeepScanRequest() else { return }
        openDestination(.page(.dashboard))
        startDeepSearch()
    }

    private func handlePendingDeviceInfo() {
        guard appActions.consumeDeviceInfoRequest() else { return }
        openDestination(.page(.deviceInfo))
        if deviceInformationViewModel.snapshot != nil {
            deviceInformationViewModel.refresh()
        }
    }

    private func handlePendingTrashReview() {
        guard appActions.consumeTrashReviewRequest() else { return }
        openDestination(.category(.trash))
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
