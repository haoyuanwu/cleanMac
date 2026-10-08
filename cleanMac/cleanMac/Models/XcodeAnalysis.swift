import Foundation

enum XcodeArtifactKind: String, CaseIterable, Identifiable, Sendable {
    case derivedData = "构建产物"
    case xcodeCaches = "Xcode 缓存"
    case archives = "归档文件"
    case deviceSupport = "设备支持文件"
    case simulatorDevices = "模拟器设备数据"
    case simulatorCaches = "模拟器缓存与临时文件"
    case deviceLogs = "设备日志"
    case plugins = "插件与编辑器扩展"

    var id: Self { self }

    var icon: String {
        switch self {
        case .derivedData: "hammer.fill"
        case .xcodeCaches: "externaldrive.fill"
        case .archives: "archivebox.fill"
        case .deviceSupport: "iphone"
        case .simulatorDevices: "ipad.and.iphone"
        case .simulatorCaches: "memorychip"
        case .deviceLogs: "doc.text.fill"
        case .plugins: "puzzlepiece.extension.fill"
        }
    }

    var note: String {
        switch self {
        case .derivedData: "项目编译、索引和依赖构建数据"
        case .xcodeCaches: "Xcode 与 Swift Package Manager 的缓存"
        case .archives: "已归档的应用版本，可能需要保留用于发布"
        case .deviceSupport: "连接设备时下载的调试支持文件"
        case .simulatorDevices: "模拟器中的应用和用户数据"
        case .simulatorCaches: "模拟器生成的缓存和临时文件"
        case .deviceLogs: "连接设备产生的日志"
        case .plugins: "独立插件及第三方应用中的 Xcode 编辑器扩展"
        }
    }
}

struct XcodeArtifact: Identifiable, Sendable {
    let path: String
    let name: String
    let detail: String?
    let size: Int64
    let kind: XcodeArtifactKind

    var id: String { path }
    var sizeFormatted: String { FileSizeFormatter.string(fromByteCount: size) }
}

struct XcodeAnalysisResult: Sendable {
    let artifacts: [XcodeArtifact]
    let scannedAt: Date

    var totalSize: Int64 { artifacts.reduce(0) { $0 + $1.size } }
    var pluginCount: Int { artifacts.filter { $0.kind == .plugins }.count }

    func artifacts(for kind: XcodeArtifactKind) -> [XcodeArtifact] {
        artifacts.filter { $0.kind == kind }.sorted { $0.size > $1.size }
    }

    func size(for kind: XcodeArtifactKind) -> Int64 {
        artifacts.filter { $0.kind == kind }.reduce(0) { $0 + $1.size }
    }
}
