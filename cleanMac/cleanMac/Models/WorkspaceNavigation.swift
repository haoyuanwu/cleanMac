import SwiftUI

enum WorkspaceGroup: String, CaseIterable, Identifiable {
    case overview = "一键清理"
    case cleanup = "垃圾清理"
    case files = "文件整理"
    case applications = "应用与开发"
    case storage = "磁盘分析"
    case preferences = "偏好与保护"
    case device = "设备信息"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "sparkle.magnifyingglass"
        case .device: return "desktopcomputer"
        case .cleanup: return "sparkles"
        case .files: return "folder"
        case .applications: return "app.badge"
        case .storage: return "chart.pie"
        case .preferences: return "slider.horizontal.3"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return "扫描、查看结果、确认清理，一步接着一步。"
        case .device: return "查看这台 Mac 的硬件、系统与设备状态。"
        case .cleanup: return "找出可释放的空间，让每一次清理都有依据。"
        case .files: return "从下载、大文件和重复内容中，整理出更多空间。"
        case .applications: return "管理应用与开发数据，让工作环境轻装上阵。"
        case .storage: return "看清空间分布，也看见每一天的变化。"
        case .preferences: return "按你的方式设置扫描、提醒与文件保护。"
        }
    }
    var destinations: [WorkspaceDestination] {
        switch self {
        case .overview: return [.page(.dashboard), .page(.insights)]
        case .device: return [.page(.deviceInfo)]
        case .cleanup: return ScanCategory.overviewScanCategories.map(WorkspaceDestination.category)
        case .files: return [.category(.downloads), .category(.largeFiles), .category(.installers), .page(.duplicates)]
        case .applications: return [.category(.applications), .page(.xcode), .page(.startup), .page(.extensions)]
        case .storage: return [.page(.diskMap), .page(.timeline)]
        case .preferences: return [.page(.whitelist), .page(.settings), .page(.privacy)]
        }
    }
}

enum WorkspaceDestination: Hashable, Identifiable {
    case category(ScanCategory)
    case page(SidebarView.SidebarTab)

    var id: String {
        switch self {
        case let .category(category): return "category-" + category.id
        case let .page(page): return "page-" + page.id
        }
    }
    var title: String {
        switch self {
        case let .category(category): return category.rawValue
        case let .page(page): return page.rawValue
        }
    }
    var group: WorkspaceGroup {
        WorkspaceGroup.allCases.first { $0.destinations.contains(self) } ?? .overview
    }
    var subtitle: String {
        switch self {
        case let .category(category): return category.description
        case .page(.dashboard): return "磁盘概况、清理扫描与空间建议"
        case .page(.deviceInfo): return "查看硬件、系统与设备状态"
        case .page(.duplicates): return "找出内容相同的文件，保留需要的那一份"
        case .page(.xcode): return "管理构建产物、模拟器与开发缓存"
        case .page(.diskMap): return "用目录清单和空间地图逐层探索磁盘"
        case .page(.timeline): return "追踪磁盘占用，了解空间增长趋势"
        case .page(.whitelist): return "保护重要路径，让清理避开它们"
        case .page(.settings): return "扫描计划、自动忽略、提醒与应用设置"
        case .page(.startup): return "只读查看登录项、后台服务和签名信息"
        case .page(.privacy): return "查看历史、下载记录及 Cookie 文件，了解影响"
        case .page(.extensions): return "盘点浏览器、编辑器和共享音频插件"
        case .page(.insights): return "依据本机扫描数据生成可解释的空间建议"
        default: return "查看详细内容"
        }
    }
    var symbol: String {
        switch self {
        case .page(.dashboard): return "house"
        case .page(.deviceInfo): return "desktopcomputer"
        case .page(.duplicates): return "doc.on.doc"
        case .page(.xcode): return "hammer"
        case .page(.diskMap): return "chart.pie"
        case .page(.timeline): return "chart.line.uptrend.xyaxis"
        case .page(.whitelist): return "shield.lefthalf.filled"
        case .page(.settings): return "gearshape"
        case .page(.startup): return "power"
        case .page(.privacy): return "hand.raised"
        case .page(.extensions): return "puzzlepiece.extension"
        case .page(.insights): return "lightbulb"
        default: return "square.grid.2x2"
        }
    }
    var color: Color {
        switch self {
        case let .category(category): return category.color
        case .page(.deviceInfo), .page(.timeline): return .blue
        case .page(.duplicates): return .orange
        case .page(.whitelist): return .green
        default: return .indigo
        }
    }
}
