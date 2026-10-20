import Foundation
import SwiftUI
import Combine

/// 主视图模型
@MainActor
class MainViewModel: ObservableObject {
    static let shared = MainViewModel()
    enum ScanScope {
        case overview
        case deep

        var categories: [ScanCategory] {
            switch self {
            case .overview: return ScanCategory.overviewScanCategories
            case .deep: return ScanCategory.allCases
            }
        }
    }
    // MARK: - Published Properties
    @Published var storageInfo: StorageInfo?
    
    @Published var scanResults: [ScanCategory: ScanResult] = [:]
    @Published var selectedCategory: ScanCategory?
    @Published var scanState: ScanState = .idle
    @Published var overallProgress: Double = 0
    @Published private(set) var lastCompletedScanScope: ScanScope = .overview
    @Published var showingAlert = false
    @Published var showingDonationPrompt = false
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
    /// 清空废纸篓过程占位（阻断交互）
    @Published var isEmptyingTrash = false
    @Published private(set) var isSmartCleaning = false
    /// 删除成功烟花庆祝
    @Published var celebrationToken = 0

    /// 文件已不存在（已被删除/移动）时视为成功路径，直接刷新
    private func isFileGoneError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            // NSFileNoSuchFileError = 4, NSFileReadNoSuchFileError = 260
            if ns.code == 4 || ns.code == 260 { return true }
        }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 2 { return true } // ENOENT
        let message = ns.localizedDescription.lowercased()
        return message.contains("doesn't exist")
            || message.contains("doesn’t exist")
            || message.contains("no such file")
            || message.contains("not found")
    }

    private func isPermissionError(_ error: Error) -> Bool {
        isRemovalPermissionError(error)
    }

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
    private let donationPromptShownKey = "donationPromptShownAfterFirstScan"
    
    // MARK: - 计算属性
    
    var totalCleanableSize: Int64 {
        ScanCategory.overviewScanCategories.reduce(0) { total, category in
            guard let result = scanResults[category], !result.isCleaned else { return total }
            return total + result.totalSize
        }
    }
    
    var totalCleanableSizeFormatted: String {
        FileSizeFormatter.string(fromByteCount: totalCleanableSize)
    }
    
    var totalCleanedSize: Int64 {
        ScanCategory.overviewScanCategories.reduce(0) { total, category in
            guard let result = scanResults[category], result.isCleaned else { return total }
            return total + result.totalSize
        }
    }
    
    var totalCleanedSizeFormatted: String {
        FileSizeFormatter.string(fromByteCount: totalCleanedSize)
    }
    
    var totalFileCount: Int {
        ScanCategory.overviewScanCategories.reduce(0) { total, category in
            guard let result = scanResults[category], !result.isCleaned else { return total }
            return total + result.itemCount
        }
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

    var hasOverviewScan: Bool {
        ScanCategory.overviewScanCategories.contains { scanResults[$0] != nil }
    }

    var overviewScanIsComplete: Bool {
        ScanCategory.overviewScanCategories.allSatisfy {
            guard let result = scanResults[$0] else { return false }
            return !result.isScanning
        }
    }
    
    // MARK: - Init
    
    /// 启动时只读取卷容量与空闲空间，不遍历用户文件或受保护目录。
    func loadStartupSnapshot() async {
        isLoadingSystemInfo = true
        let service = systemInfoService
        let storage = await Task.detached(operation: { service.getStorageInfo() }).value
        self.storageInfo = storage

        if storage.totalBytes > 0 { StorageTimeline.record(storage: storage) }

        isLoadingSystemInfo = false
    }
    
    // MARK: - Actions
    
    /// 概览扫描仅覆盖清理项目；深度清理额外覆盖文件整理和应用程序。
    func scanAll(scope: ScanScope = .overview, showDonationAfterCompletion: Bool = true) async {
        guard !isScanning else { return }

        scanState = .scanning
        overallProgress = 0
        AppLog.info("scanAll start")

        scanAllTask = Task { [weak self] in
            guard let self else { return }
            let categories = scope.categories
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

            if Task.isCancelled {
                self.scanState = .completed
                AppLog.info("scanAll cancelled")
                return
            }

            await MainActor.run {
                self.scanState = .completed
                self.lastCompletedScanScope = scope
                AppLog.info("scanAll finished")
                if showDonationAfterCompletion {
                    self.presentFirstScanDonationPromptIfNeeded()
                }
            }
        }
        await scanAllTask?.value
    }

    /// 仅在用户首次完成完整扫描后提示一次；定时扫描不会调用此方法。
    func presentFirstScanDonationPromptIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: donationPromptShownKey) else { return }
        UserDefaults.standard.set(true, forKey: donationPromptShownKey)
        showingDonationPrompt = true
    }

    /// 取消概览清理扫描
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
        SmartCleanPlan.build(from: scanResults.filter {
            ScanCategory.overviewScanCategories.contains($0.key)
        })
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

    func addSmartCleanItemToWhitelist(_ item: FileItem) {
        guard showingSmartCleanDialog, smartCleanDraft?.items.contains(where: { $0.path == item.path }) == true else { return }
        UserWhitelist.add(item.path)
        let protectedPath = SafetyWhitelist.normalizeForCompare(item.path)
        for category in Array(scanResults.keys) {
            scanResults[category]?.items.removeAll {
                let path = SafetyWhitelist.normalizeForCompare($0.path)
                return path == protectedPath || path.hasPrefix(protectedPath + "/")
            }
        }
        smartCleanDraft = smartCleanPlan
        let availablePaths = Set(smartCleanDraft?.items.map(\.path) ?? [])
        smartCleanSelectedPaths.formIntersection(availablePaths)
    }

    /// 确认后清理勾选项（仅 safe 级）
    func confirmSmartClean() {
        guard let plan = smartCleanDraft else {
            cancelSmartClean()
            return
        }
        let selected = plan.items.filter {
            smartCleanSelectedPaths.contains($0.path) && !UserWhitelist.isWhitelisted($0.path)
        }
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
        let startedAt = Date()
        isSmartCleaning = true
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

        let outcome = await cleanService.cleanBatch(grouped.map { ($0.key, $0.value) })
        totalCleaned = outcome.cleanedBytes
        applyCleanOutcome(outcome)

        // 即使清理项目很少，也让全屏动画至少完整展示一小段时间，避免一闪而过。
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < 1.2 {
            try? await Task.sleep(nanoseconds: UInt64((1.2 - elapsed) * 1_000_000_000))
        }

        scanState = .completed
        isSmartCleaning = false
        if totalCleaned > 0 && outcome.failures.isEmpty {
            celebrationToken += 1
        }
        alertTitle = outcome.failures.isEmpty ? "智能清理完成" : "部分清理失败"
        alertMessage = cleanOutcomeMessage(outcome)
        showingAlert = true
    }
    
    /// 清理指定类别
    func cleanCategory(_ category: ScanCategory) async {
        guard let result = scanResults[category], !result.items.isEmpty else { return }
        if category == .applications {
            requestDeleteFiles(result.items, from: .applications)
            return
        }
        if category == .logFiles {
            requestDeleteFiles(result.items, from: .logFiles)
            return
        }
        
        scanState = .cleaning
        
        let outcome = await cleanService.clean(items: result.items, category: category)
        applyCleanOutcome(outcome)
        alertTitle = outcome.failures.isEmpty ? "清理完成" : "部分清理失败"
        alertMessage = cleanOutcomeMessage(outcome)
        showingAlert = true
        scanState = .completed
    }
    
    /// 清理所有已扫描的类别
    func cleanAll() async {
        scanState = .cleaning
        
        let groups = scanResults.compactMap { category, result -> (ScanCategory, [FileItem])? in
            guard category != .applications, !result.items.isEmpty, !result.isCleaned else { return nil }
            return (category, result.items)
        }
        let outcome = await cleanService.cleanBatch(groups)
        applyCleanOutcome(outcome)
        alertTitle = outcome.failures.isEmpty ? "清理完成" : "部分清理失败"
        alertMessage = cleanOutcomeMessage(outcome)
        showingAlert = true
        
        scanState = .completed
    }

    private func applyCleanOutcome(_ outcome: CleanOutcome) {
        for category in Array(scanResults.keys) {
            scanResults[category]?.items.removeAll { outcome.removedPaths.contains($0.path) }
            if scanResults[category]?.items.isEmpty == true {
                scanResults[category]?.isCleaned = true
            }
        }
    }

    private func cleanOutcomeMessage(_ outcome: CleanOutcome) -> String {
        var message = "已清理 \(outcome.removedPaths.count) 项，释放 \(FileSizeFormatter.string(fromByteCount: outcome.cleanedBytes)) 空间。"
        if !outcome.failures.isEmpty {
            let details = outcome.failures.sorted { $0.key < $1.key }.prefix(3)
                .map { "\($0.key)：\($0.value)" }.joined(separator: "\n")
            message += "\n\(outcome.failures.count) 项未能清理：\n\(details)"
        }
        return message
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

        isEmptyingTrash = true
        AppLog.info("emptyTrash start", metadata: ["count": "\(result.items.count)"])

        let outcome = await cleanService.emptyTrash(items: result.items)
        let rescan = await scanService.scanTrash()
        scanResults[.trash] = ScanResult(
            category: .trash,
            items: rescan.items,
            isCleaned: rescan.items.isEmpty && rescan.error == nil,
            error: rescan.error
        )
        isEmptyingTrash = false

        alertTitle = outcome.failedCount == 0 && rescan.error == nil ? "废纸篓已清空" : "部分清空失败"
        if outcome.failedCount == 0, rescan.error == nil {
            alertMessage = "已清理 \(FileSizeFormatter.string(fromByteCount: outcome.cleanedBytes)) 空间"
        } else if outcome.failedCount == 0 {
            alertMessage = rescan.error ?? "废纸篓重新扫描失败。"
        } else {
            alertMessage = "\(outcome.failedCount) 个项目未能删除。\n"
                + outcome.failureDetails.prefix(3).joined(separator: "\n")
                + (rescan.error.map { "\n\($0)" } ?? "")
        }
        showingAlert = true
        AppLog.info("emptyTrash finished", metadata: [
            "failed": "\(outcome.failedCount)",
            "bytes": "\(outcome.cleanedBytes)"
        ])
        await TrashMonitor.shared.refresh(force: true)
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
                self.selectedLeftoverPaths = Set(estimates.flatMap(\.leftovers).map(\.path))
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
            // dry-run 拦截的视为「已跳过」，不计入删除失败，避免日志全选时误报
            var failed = 0
            var skipped = validated.blocked.count
            var removed = 0
            var failureDetails: [String] = []
            var privilegedFiles: [FileItem] = []
            var privilegedTrashDeletionFiles: [FileItem] = []
            for file in files {
                var didRemove = false
                var failureMessage: String?
                do {
                    if category == .trash {
                        try fileManager.removeItem(at: file.pathURL)
                    } else {
                        try fileManager.trashItem(at: file.pathURL, resultingItemURL: nil)
                    }
                    didRemove = true
                } catch {
                    if isFileGoneError(error) {
                        didRemove = true
                        AppLog.info("delete skip already gone", metadata: ["path": file.path])
                    } else if [.logFiles, .systemCache].contains(category), isPermissionError(error),
                              PrivilegedTrashService.isSupportedItem(file.path) {
                        privilegedFiles.append(file)
                        continue
                    } else if category == .trash, isPermissionError(error),
                              isDirectTrashEntry(file.path) {
                        privilegedTrashDeletionFiles.append(file)
                        continue
                    } else {
                        failureMessage = error.localizedDescription
                    }
                }

                if didRemove {
                    removed += 1
                    AppLog.info("deleted", metadata: ["path": file.path])
                    scanResults[category]?.items.removeAll { $0.path == file.path }
                } else {
                    failed += 1
                    let detail = failureMessage ?? "未知错误"
                    failureDetails.append("\(file.name)：\(detail)")
                    AppLog.error("delete failed", metadata: ["path": file.path, "error": detail])
                }
            }

            if !privilegedFiles.isEmpty {
                let paths = privilegedFiles.map(\.path)
                let outcomes = await Task.detached(priority: .userInitiated) {
                    PrivilegedTrashService.moveToTrash(paths: paths)
                }.value
                for file in privilegedFiles {
                    let outcome = outcomes[file.path]
                    if outcome?.succeeded == true {
                        removed += 1
                        AppLog.info("deleted", metadata: ["path": file.path])
                        scanResults[category]?.items.removeAll { $0.path == file.path }
                    } else {
                        failed += 1
                        let detail = outcome?.message ?? "管理员授权后仍未能移动项目。"
                        failureDetails.append("\(file.name)：\(detail)")
                        AppLog.error("delete failed", metadata: ["path": file.path, "error": detail])
                    }
                }
            }

            if !privilegedTrashDeletionFiles.isEmpty {
                let paths = privilegedTrashDeletionFiles.map(\.path)
                let outcome = await Task.detached(priority: .userInitiated) {
                    PrivilegedRemovalService.remove(paths: paths)
                }.value
                for file in privilegedTrashDeletionFiles {
                    if outcome.removedPaths.contains(file.path) {
                        removed += 1
                        AppLog.info("deleted", metadata: ["path": file.path])
                        scanResults[category]?.items.removeAll { $0.path == file.path }
                    } else {
                        failed += 1
                        let detail = outcome.failures[file.path] ?? "管理员授权后仍未能删除。"
                        failureDetails.append("\(file.path)：\(detail)")
                        AppLog.error("delete failed", metadata: ["path": file.path, "error": detail])
                    }
                }
            }

            // 有失败或跳过时刷新该类别，保证列表与磁盘一致
            if failed > 0 || skipped > 0 {
                await self.scanCategory(category)
            }

            if scanResults[category]?.items.isEmpty == true {
                scanResults[category]?.isCleaned = category != .trash
            }
            if removed > 0 && failed == 0 {
                celebrationToken += 1
            }
            if failed > 0 {
                alertTitle = removed == 0 ? "删除失败" : "部分删除失败"
                let summary = category == .trash
                    ? "有 \(failed) 个项目无法删除。"
                    : "有 \(failed) 个项目无法移到废纸篓。"
                let skipNote = skipped > 0 ? "（另有 \(skipped) 项已跳过）" : ""
                alertMessage = summary + skipNote + "\n" + failureDetails.prefix(3).joined(separator: "\n")
                showingAlert = true
            } else if skipped > 0 && removed == 0 {
                // 全部被跳过（如白名单）：静默刷新即可
                AppLog.info("delete all skipped", metadata: [
                    "category": category.rawValue,
                    "skipped": "\(skipped)"
                ])
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
        let remaining = files.filter { !movedPaths.contains($0.path) }
        if !remaining.isEmpty {
            let paths = remaining.map(\.path)
            let outcomes = await Task.detached(priority: .userInitiated) {
                ApplicationUninstallService.moveToTrashWithAdministratorPrivileges(appPaths: paths)
            }.value
            for file in remaining {
                let outcome = outcomes[file.path]
                if outcome?.succeeded == true {
                    movedPaths.insert(file.path)
                } else {
                    failureDetails.append("\(file.name)：\(outcome?.message ?? recycleError ?? "未知错误")")
                }
            }
        }

        scanResults[.applications]?.items.removeAll { movedPaths.contains($0.path) }

        let failedCount = files.count - movedPaths.count
        // 清理勾选的残留
        var leftoverNote = ""
        var leftoverFailed = 0
        if failedCount == 0 && !leftoverPaths.isEmpty {
            let outcome = await Task.detached {
                AppLeftoverScanner.removeLeftovers(leftoverPaths)
            }.value
            leftoverFailed = outcome.failed
            leftoverNote = outcome.removed > 0
                ? "，并删除了 \(outcome.removed) 处残留"
                : ""
        }

        if failedCount == 0 {
            alertTitle = leftoverFailed == 0 ? "卸载完成" : "部分残留清理失败"
            alertMessage = "已将 \(files.count) 个应用移到废纸篓。\(leftoverNote)"
            if leftoverFailed > 0 {
                alertMessage += "\n\(leftoverFailed) 处残留未能删除，请检查权限后重试。"
            }
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
            alertMessage = "\(failedCount) 个应用未能移到废纸篓。请在「系统设置 → 隐私与安全性 → 应用管理」中检查 cleanMac 的授权，并确认应用已退出。受系统保护的应用可能无法卸载。\n\(detail)"
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
