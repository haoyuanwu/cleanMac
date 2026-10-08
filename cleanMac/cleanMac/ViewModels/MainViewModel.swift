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
    
    // MARK: - Private
    private let scanService = ScanService()
    private let cleanService = CleanService()
    private let systemInfoService = SystemInfoService()
    private var applicationsWaitingForPermission: [FileItem] = []
    private var isWaitingForAppManagementSettings = false
    
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
    
    /// 全盘扫描
    func scanAll() async {
        scanState = .scanning
        overallProgress = 0
        
        let categories = ScanCategory.allCases
        let total = Double(categories.count)
        
        for (index, category) in categories.enumerated() {
            await scanCategory(category)
            overallProgress = Double(index + 1) / total
        }
        
        scanState = .completed
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
        
        scanResults[category] = ScanResult(category: category, items: items, error: scanError)
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
        pendingDeleteFiles = [file]
        pendingDeleteCategory = category
        showingDeleteConfirmation = true
    }
    
    /// 请求批量删除文件（显示确认对话框）
    func requestDeleteFiles(_ files: [FileItem], from category: ScanCategory) {
        pendingDeleteFiles = files
        pendingDeleteCategory = category
        showingDeleteConfirmation = true
    }
    
    /// 确认删除待删除的文件
    func confirmDelete() {
        guard let category = pendingDeleteCategory else { return }
        let files = pendingDeleteFiles

        pendingDeleteFiles = []
        pendingDeleteCategory = nil

        if category == .applications {
            Task { await uninstallApplications(files) }
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
                    await MainActor.run {
                        scanResults[category]?.items.removeAll { $0.path == file.path }
                    }
                } catch {
                    failed += 1
                }
            }
            if failed > 0 {
                await MainActor.run {
                    alertTitle = "部分删除失败"
                    alertMessage = category == .trash
                        ? "\(failed) 个项目未能永久删除"
                        : "\(failed) 个项目未能移到废纸篓"
                    showingAlert = true
                }
            }
        }
        
    }

    /// 使用 Finder 式回收操作卸载应用，系统可在需要时请求管理员授权。
    private func uninstallApplications(_ files: [FileItem], afterPermissionRequest: Bool = false) async {
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

        let failedCount = files.count - movedPaths.count
        if failedCount == 0 {
            alertTitle = "卸载完成"
            alertMessage = "已将 \(files.count) 个应用移到废纸篓。"
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
    
    /// 取消删除
    func cancelDelete() {
        pendingDeleteFiles = []
        pendingDeleteCategory = nil
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
