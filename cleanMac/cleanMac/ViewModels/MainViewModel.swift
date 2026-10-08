import Foundation
import SwiftUI
import Combine

/// 主视图模型
@MainActor
class MainViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var systemInfo: SystemInfo?
    @Published var storageInfo: StorageInfo?
    @Published var storageBreakdown: [StorageCategory] = []
    
    @Published var scanResults: [ScanCategory: ScanResult] = [:]
    @Published var selectedCategory: ScanCategory?
    @Published var scanState: ScanState = .idle
    @Published var overallProgress: Double = 0
    @Published var showingAlert = false
    @Published var alertMessage = ""
    @Published var alertTitle = ""
    @Published var isLoadingSystemInfo = true
    @Published var showingDeleteConfirmation = false
    @Published var pendingDeleteFiles: [FileItem] = []
    @Published var pendingDeleteCategory: ScanCategory?
    /// 确认弹窗使用的冻结快照，避免展示过程中状态被清空导致文案错乱
    @Published var deleteRequest: DeleteRequest?
    /// 卸载增强：残留估算与勾选
    @Published var uninstallEstimates: [AppLeftoverEstimate] = []
    @Published var selectedLeftoverPaths: Set<String> = []
    @Published var showingUninstallDialog = false
    /// 智能清理确认
    @Published var smartCleanDraft: SmartCleanPlan?
    @Published var smartCleanSelectedPaths: Set<String> = []
    @Published var showingSmartCleanDialog = false

    struct DeleteRequest: Identifiable, Equatable {
        let id = UUID()
        let files: [FileItem]
        let category: ScanCategory

        var count: Int { files.count }
        var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
        var totalSizeFormatted: String { FileSizeFormatter.string(fromByteCount: totalSize) }

        var actionTitle: String {
            switch category {
            case .applications: return "卸载"
            case .trash: return "永久删除"
            default: return "移到废纸篓"
            }
        }

        var message: String {
            let names = files.map(\.name).joined(separator: "\n")
            let size = totalSizeFormatted
            let count = files.count
            let detail = count <= 3 ? "\n\n\(names)" : ""
            switch category {
            case .trash:
                return "确定永久删除 \(count) 个项目（共 \(size)）吗？此操作无法撤销。\(detail)"
            case .applications:
                return "确定卸载 \(count) 个应用（共 \(size)）吗？应用将移到废纸篓；相关数据可在应用残留中单独清理。\(detail)"
            default:
                return "确定将 \(count) 个项目移到废纸篓（共 \(size)）吗？\(detail)"
            }
        }
    }
    
    // MARK: - Private
    private let scanService = ScanService()
    private let cleanService = CleanService()
    private let systemInfoService = SystemInfoService()
    private var applicationsWaitingForPermission: [FileItem] = []
    private var isWaitingForAppManagementSettings = false
    private var scanAllTask: Task<Void, Never>?
    
    // MARK: - 计算属性
    
    var totalCleanableSize: Int64 {
        scanResults.values.reduce(0) { $0 + $1.totalSize }
    }
    
    var totalCleanableSizeFormatted: String {
        FileSizeFormatter.string(fromByteCount: totalCleanableSize)
    }
    
    var totalCleanedSize: Int64 {
        scanResults.values.filter { $0.isCleaned }.reduce(0) { $0 + $1.totalSize }
    }
    
    var totalCleanedSizeFormatted: String {
        FileSizeFormatter.string(fromByteCount: totalCleanedSize)
    }
    
    var totalFileCount: Int {
        scanResults.values.reduce(0) { $0 + $1.itemCount }
    }
    
    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }
    
    var isCleaning: Bool {
        if case .cleaning = scanState { return true }
        return false
    }
    
    var selectedScanResult: ScanResult? {
        guard let category = selectedCategory else { return nil }
        return scanResults[category]
    }
    
    /// 是否已扫描过任何类别
    var hasScanned: Bool {
        !scanResults.isEmpty
    }
    
    // MARK: - Init
    
    /// 加载系统信息（非自动扫描）
    func loadSystemInfo() async {
        isLoadingSystemInfo = true
        
        let service = systemInfoService
        
        // 依次在后台加载，避免阻塞主线程
        let info = await Task.detached(operation: { service.getSystemInfo() }).value
        self.systemInfo = info
        
        let storage = await Task.detached(operation: { service.getStorageInfo() }).value
        self.storageInfo = storage
        
        let breakdown = await Task.detached { service.getStorageBreakdown(usedBytes: storage.usedBytes) }.value
        self.storageBreakdown = breakdown
        
        isLoadingSystemInfo = false
    }
    
    // MARK: - Actions
    
    /// 全盘扫描（全局扫描未结束前不可再次发起；单类扫描不受此限制）
    func scanAll() async {
        guard !isScanning else { return }

        scanState = .scanning
        overallProgress = 0
        AppLog.info("scanAll start")

        scanAllTask = Task { [weak self] in
            guard let self else { return }
            let categories = ScanCategory.allCases
            let total = Double(categories.count)

            for (index, category) in categories.enumerated() {
                if Task.isCancelled {
                    await MainActor.run {
                        self.scanState = .completed
                        AppLog.info("scanAll cancelled")
                    }
                    return
                }
                await self.scanCategory(category)
                await MainActor.run {
                    self.overallProgress = Double(index + 1) / total
                }
            }

            await MainActor.run {
                self.scanState = .completed
                AppLog.info("scanAll finished")
            }
        }
        await scanAllTask?.value
    }

    /// 取消全局扫描
    func cancelScanAll() {
        scanAllTask?.cancel()
        scanAllTask = nil
        if isScanning {
            scanState = .completed
            AppLog.info("scanAll cancel requested")
        }
    }
    
    /// 扫描单个类别
    func scanCategory(_ category: ScanCategory) async {
        scanResults[category] = ScanResult(category: category, items: [], isScanning: true)
        
        var items: [FileItem] = []
        var scanError: String?
        
        switch category {
        case .systemCache:
            items = await scanService.scanSystemCache()
        case .logFiles:
            items = await scanService.scanLogFiles()
        case .browserCache:
            items = await scanService.scanBrowserCache()
        case .trash:
            let outcome = await scanService.scanTrash()
            items = outcome.items
            scanError = outcome.error
        case .appLeftover:
            items = await scanService.scanAppLeftover()
        case .downloads:
            items = await scanService.scanDownloads()
        case .largeFiles:
            items = await scanService.scanLargeFiles()
        case .applications:
            items = await scanService.scanApplications()
        case .installers:
            items = await scanService.scanInstallers()
        }
        
        scanResults[category] = ScanResult(
            category: category,
            items: items
                .map { SafetyWhitelist.annotated($0, category: category) }
                .filter { SafetyWhitelist.canDelete(path: $0.path) && !UserWhitelist.isWhitelisted($0.path) },
            error: scanError
        )
    }

    /// 智能清理推荐集
    var smartCleanPlan: SmartCleanPlan {
        SmartCleanPlan.build(from: scanResults)
    }

    /// 打开智能清理确认弹窗（先看清单）
    func requestSmartClean() {
        let plan = smartCleanPlan
        guard !plan.isEmpty else {
            alertTitle = "无需清理"
            alertMessage = "没有发现可安全自动清理的项目。"
            showingAlert = true
            return
        }
        smartCleanDraft = plan
        smartCleanSelectedPaths = Set(plan.items.map(\.path))
        showingSmartCleanDialog = true
    }

    func cancelSmartClean() {
        smartCleanDraft = nil
        smartCleanSelectedPaths = []
        showingSmartCleanDialog = false
    }

    /// 确认后清理勾选项（仅 safe 级）
    func confirmSmartClean() {
        guard let plan = smartCleanDraft else {
            cancelSmartClean()
            return
        }
        let selected = plan.items.filter { smartCleanSelectedPaths.contains($0.path) }
        cancelSmartClean()

        guard !selected.isEmpty else {
            alertTitle = "未选择项目"
            alertMessage = "请至少勾选一项再清理。"
            showingAlert = true
            return
        }

        Task {
            await runSmartClean(items: selected, plan: plan)
        }
    }

    /// 执行清理（用户已确认的列表）
    private func runSmartClean(items: [FileItem], plan: SmartCleanPlan) async {
        scanState = .cleaning
        var totalCleaned: Int64 = 0

        // 按扫描结果中的类别归属分组
        var grouped: [ScanCategory: [FileItem]] = [:]
        for item in items {
            var assigned: ScanCategory?
            for (category, result) in scanResults {
                if result.items.contains(where: { $0.path == item.path }) {
                    assigned = category
                    break
                }
            }
            let category = assigned ?? .systemCache
            grouped[category, default: []].append(item)
        }

        for (category, group) in grouped {
            do {
                let cleaned = try await cleanService.clean(items: group, category: category)
                totalCleaned += cleaned
                scanResults[category]?.items.removeAll { item in
                    group.contains { $0.path == item.path }
                }
                if scanResults[category]?.items.isEmpty == true {
                    scanResults[category]?.isCleaned = true
                }
            } catch {
                // 继续其他类别
            }
        }

        scanState = .completed
        alertTitle = "智能清理完成"
        alertMessage = "已清理 \(FileSizeFormatter.string(fromByteCount: totalCleaned)) 空间（\(items.count) 项）。"
        showingAlert = true
    }
    
    /// 清理指定类别
    func cleanCategory(_ category: ScanCategory) async {
        guard let result = scanResults[category], !result.items.isEmpty else { return }
        if category == .applications {
            requestDeleteFiles(result.items, from: .applications)
            return
        }
        
        scanState = .cleaning
        
        do {
            let cleaned = try await cleanService.clean(items: result.items, category: category)
            scanResults[category]?.isCleaned = true
            scanResults[category]?.items = []
            
            alertTitle = "清理完成"
            alertMessage = "已清理 \(FileSizeFormatter.string(fromByteCount: cleaned)) 空间"
            showingAlert = true
            scanState = .completed
        } catch {
            scanState = .error(error.localizedDescription)
            alertTitle = "清理失败"
            alertMessage = error.localizedDescription
            showingAlert = true
        }
    }
    
    /// 清理所有已扫描的类别
    func cleanAll() async {
        scanState = .cleaning
        
        var totalCleaned: Int64 = 0
        
        for (category, result) in scanResults where category != .applications && !result.items.isEmpty && !result.isCleaned {
            do {
                let cleaned = try await cleanService.clean(items: result.items, category: category)
                scanResults[category]?.isCleaned = true
                scanResults[category]?.items = []
                totalCleaned += cleaned
            } catch {
                print("Failed to clean \(category.rawValue): \(error)")
            }
        }
        
        alertTitle = "清理完成"
        alertMessage = "已清理 \(FileSizeFormatter.string(fromByteCount: totalCleaned)) 空间"
        showingAlert = true
        
        scanState = .completed
    }
    
    /// 清空废纸篓
    func emptyTrash() async {
        guard let result = scanResults[.trash], !result.items.isEmpty else { return }
        guard result.error == nil else {
            alertTitle = "无法清空废纸篓"
            alertMessage = "部分位置无法读取，请先在设置中完成授权并重新扫描。"
            showingAlert = true
            return
        }

        let outcome = await cleanService.emptyTrash(items: result.items)
        let rescan = await scanService.scanTrash()
        scanResults[.trash] = ScanResult(
            category: .trash,
            items: rescan.items,
            isCleaned: rescan.items.isEmpty && rescan.error == nil,
            error: rescan.error
        )

        alertTitle = outcome.failedCount == 0 && rescan.error == nil ? "废纸篓已清空" : "部分清空失败"
        alertMessage = outcome.failedCount == 0 && rescan.error == nil
            ? "已清理 \(FileSizeFormatter.string(fromByteCount: outcome.cleanedBytes)) 空间"
            : "\(outcome.failedCount) 个项目未能删除，请检查权限后重新扫描。"
        showingAlert = true
    }
    
    /// 请求删除单个文件（显示确认对话框）
    func requestDeleteFile(_ file: FileItem, from category: ScanCategory) {
        requestDeleteFiles([file], from: category)
    }

    /// 请求批量删除文件（显示确认对话框）
    func requestDeleteFiles(_ files: [FileItem], from category: ScanCategory) {
        guard !files.isEmpty else { return }

        // 应用卸载：直接弹残留估算对话框
        if category == .applications {
            requestUninstall(files)
            return
        }

        pendingDeleteFiles = files
        pendingDeleteCategory = category
        deleteRequest = DeleteRequest(files: files, category: category)
        showingDeleteConfirmation = true
    }

    /// 估算残留并展示卸载对话框
    func requestUninstall(_ files: [FileItem]) {
        pendingDeleteFiles = files
        pendingDeleteCategory = .applications
        Task {
            var estimates: [AppLeftoverEstimate] = []
            for file in files {
                let estimate = await AppLeftoverScanner.estimate(for: file.path)
                estimates.append(estimate)
            }
            await MainActor.run {
                self.uninstallEstimates = estimates
                // 默认不勾选残留
                self.selectedLeftoverPaths = []
                self.showingUninstallDialog = true
            }
        }
    }

    /// 确认卸载（可选清理勾选的残留）
    func confirmUninstall() {
        let files = pendingDeleteFiles
        let leftoverPaths = Array(selectedLeftoverPaths)
        cancelUninstall()

        Task {
            await uninstallApplications(files, leftoverPaths: leftoverPaths)
        }
    }

    func cancelUninstall() {
        pendingDeleteFiles = []
        pendingDeleteCategory = nil
        uninstallEstimates = []
        selectedLeftoverPaths = []
        showingUninstallDialog = false
    }

    /// 确认删除（使用冻结快照，不依赖展示中的 @Published 清空）
    func confirmDelete() {
        guard let request = deleteRequest else {
            cancelDelete()
            return
        }
        let category = request.category
        let validated = DeleteDryRun.validate(items: request.files, context: "confirmDelete-\(category.rawValue)")
        let files = validated.allowed

        if validated.blocked.count > 0 {
            AppLog.warn("confirmDelete blocked some", metadata: [
                "blocked": "\(validated.blocked.count)",
                "category": category.rawValue
            ])
        }

        // 先关弹窗并清空 UI 状态，但任务使用上面的局部副本
        cancelDelete()

        if category == .applications {
            // 兜底：若走了旧确认框，也走卸载
            Task { await uninstallApplications(files, leftoverPaths: []) }
            return
        }

        Task {
            let fileManager = FileManager.default
            var failed = 0
            for file in files {
                do {
                    if category == .trash {
                        try fileManager.removeItem(at: file.pathURL)
                    } else {
                        try fileManager.trashItem(at: file.pathURL, resultingItemURL: nil)
                    }
                    AppLog.info("deleted", metadata: ["path": file.path])
                    await MainActor.run {
                        scanResults[category]?.items.removeAll { $0.path == file.path }
                    }
                } catch {
                    failed += 1
                    AppLog.error("delete failed", metadata: [
                        "path": file.path,
                        "error": error.localizedDescription
                    ])
                }
            }
            if failed > 0 {
                await MainActor.run {
                    alertTitle = "部分删除失败"
                    alertMessage = category == .trash
                        ? "有 \(failed) 个项目无法删除，请检查权限后重试。"
                        : "有 \(failed) 个项目无法移到废纸篓，请检查权限后重试。"
                    showingAlert = true
                }
            }
        }
    }

    func cancelDelete() {
        pendingDeleteFiles = []
        pendingDeleteCategory = nil
        deleteRequest = nil
        showingDeleteConfirmation = false
    }

    /// 使用 Finder 式回收操作卸载应用，系统可在需要时请求管理员授权。
    private func uninstallApplications(
        _ files: [FileItem],
        leftoverPaths: [String] = [],
        afterPermissionRequest: Bool = false
    ) async {
        guard !files.isEmpty else { return }

        let (recycledPaths, recycleError) = await withCheckedContinuation {
            (continuation: CheckedContinuation<(Set<String>, String?), Never>) in
            NSWorkspace.shared.recycle(files.map(\.pathURL)) { newURLs, error in
                continuation.resume(returning: (Set(newURLs.keys.map(\.path)), error?.localizedDescription))
            }
        }

        var movedPaths = recycledPaths
        var failureDetails: [String] = []
        for file in files where !movedPaths.contains(file.path) {
            let path = file.path
            let outcome = await Task.detached(priority: .userInitiated) {
                ApplicationUninstallService.moveToTrashWithAdministratorPrivileges(appPath: path)
            }.value
            if outcome.succeeded {
                movedPaths.insert(path)
            } else {
                failureDetails.append("\(file.name)：\(outcome.message ?? recycleError ?? "未知错误")")
            }
        }

        scanResults[.applications]?.items.removeAll { movedPaths.contains($0.path) }

        // 清理勾选的残留
        var leftoverNote = ""
        if !leftoverPaths.isEmpty {
            let outcome = await Task.detached {
                AppLeftoverScanner.removeLeftovers(leftoverPaths)
            }.value
            leftoverNote = outcome.removed > 0
                ? "，并删除了 \(outcome.removed) 处残留"
                : ""
        }

        let failedCount = files.count - movedPaths.count
        if failedCount == 0 {
            alertTitle = "卸载完成"
            alertMessage = "已将 \(files.count) 个应用移到废纸篓。\(leftoverNote)"
        } else {
            let failedFiles = files.filter { !movedPaths.contains($0.path) }
            if !afterPermissionRequest,
               failureIndicatesMissingPermission(recycleError, details: failureDetails) {
                applicationsWaitingForPermission = failedFiles
                isWaitingForAppManagementSettings = true
                if PrivacySettingsOpener.openAppManagement() {
                    return
                }
                applicationsWaitingForPermission = []
                isWaitingForAppManagementSettings = false
            }

            alertTitle = failedCount == files.count ? "卸载失败" : "部分应用卸载失败"
            let detail = failureDetails.prefix(3).joined(separator: "\n")
            alertMessage = "\(failedCount) 个应用未能移到废纸篓。请在「设置 → 权限 → 应用管理」中检查 cleanMac 的授权，并确认应用已退出。受系统保护的应用可能无法卸载。\n\(detail)"
        }
        showingAlert = true
    }

    /// 用户从权限页面返回后，仅自动重试一次，避免反复打开系统设置。
    func resumeUninstallAfterPermissionSettings() {
        guard isWaitingForAppManagementSettings else { return }
        isWaitingForAppManagementSettings = false
        let files = applicationsWaitingForPermission
        applicationsWaitingForPermission = []
        Task { await uninstallApplications(files, afterPermissionRequest: true) }
    }

    private func failureIndicatesMissingPermission(_ recycleError: String?, details: [String]) -> Bool {
        let message = ([recycleError].compactMap { $0 } + details).joined(separator: " ").lowercased()
        return ["permission", "not permitted", "not authorized", "权限", "不允许", "未获授权"]
            .contains { message.contains($0) }
    }

    /// 在 Finder 中显示文件
    func revealInFinder(_ file: FileItem) {
        NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
    }

    /// 在 Finder 中同时定位所选文件
    func revealInFinder(_ files: [FileItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(files.map(\.pathURL))
    }
    
    /// 打开文件
    func openFile(_ file: FileItem) {
        NSWorkspace.shared.open(file.pathURL)
    }
}
