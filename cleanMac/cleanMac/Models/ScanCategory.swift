import Foundation
import SwiftUI

/// 清理类别定义
enum ScanCategory: String, CaseIterable, Identifiable, Sendable {
    case systemCache = "系统缓存"
    case applicationCache = "应用缓存"
    case logFiles = "日志文件"
    case browserCache = "浏览器缓存"
    case trash = "废纸篓"
    case appLeftover = "应用残留"
    case downloads = "下载文件夹"
    case largeFiles = "大文件"
    case applications = "应用程序"
    case installers = "安装包"

    /// 概览只汇总垃圾清理类；文件整理与应用管理在各自页面按需扫描。
    static let overviewScanCategories: [ScanCategory] = [
        .systemCache, .applicationCache, .browserCache, .logFiles, .appLeftover, .trash
    ]
    
    var id: String { rawValue }

    var itemUnit: String {
        if self == .systemCache || self == .applicationCache { return "项目" }
        return self == .browserCache || self == .appLeftover || self == .logFiles ? "文件夹" : "文件"
    }
    
    /// 与侧边栏、概览和类别详情共用的 Iconfont 资源。
    var iconAsset: String {
        switch self {
        case .systemCache: return "SidebarSystemCache"
        case .applicationCache: return "SidebarApplications"
        case .logFiles: return "SidebarLogs"
        case .browserCache: return "SidebarBrowserCache"
        case .trash: return "SidebarTrash"
        case .appLeftover: return "SidebarAppLeftover"
        case .downloads: return "SidebarDownloads"
        case .largeFiles: return "SidebarLargeFiles"
        case .applications: return "SidebarApplications"
        case .installers: return "SidebarInstallers"
        }
    }
    
    var color: Color {
        switch self {
        case .systemCache: return .blue
        case .applicationCache: return .teal
        case .logFiles: return .orange
        case .browserCache: return .purple
        case .trash: return .red
        case .appLeftover: return .pink
        case .downloads: return .green
        case .largeFiles: return .cyan
        case .applications: return .indigo
        case .installers: return .brown
        }
    }
    
    var description: String {
        switch self {
        case .systemCache: return "清理系统及未归属已安装应用的缓存"
        case .applicationCache: return "按软件查找应用数据与全部沙盒容器中的缓存文件夹和文件"
        case .logFiles: return "清理系统和应用日志文件夹"
        case .browserCache: return "查找 Safari、Chrome、Firefox 等浏览器的缓存文件夹"
        case .trash: return "清空废纸篓中所有文件"
        case .appLeftover: return "查找已卸载应用留下的数据文件夹"
        case .downloads: return "清理下载文件夹中的文件"
        case .largeFiles: return "扫描磁盘上占用大量空间的文件"
        case .applications: return "管理已安装的应用程序"
        case .installers: return "清理 .pkg、.dmg、.apk、.exe 等安装包文件"
        }
    }
    
    /// 该类别是否需要管理员权限
    var requiresPrivileges: Bool {
        switch self {
        case .systemCache: return true
        case .applicationCache: return false
        case .logFiles: return true
        case .trash: return false
        case .browserCache: return false
        case .appLeftover: return false
        case .downloads: return false
        case .largeFiles: return false
        case .applications: return false
        case .installers: return false
        }
    }
}
