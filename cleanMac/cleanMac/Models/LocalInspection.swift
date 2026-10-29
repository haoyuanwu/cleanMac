import Foundation

nonisolated struct InspectionItem: Identifiable, Sendable {
    let id: String
    let name: String
    let owner: String
    let kind: String
    let path: String
    var version = "未提供"
    var source = "本机文件"
    var size: Int64?
    var notes: [String] = []
    var application: CacheApplication?
    var startupLabel: String?
    var startupEnabled: Bool?
    var startupCanControl = false

    var softwareName: String { application?.name ?? owner }

}

nonisolated struct InspectionReport: Sendable {
    var items: [InspectionItem] = []
    var issues: [String] = []
    var scannedAt = Date()
    var cancelled = false
}

nonisolated enum InspectionFS {
    static func children(_ url: URL) -> [URL] {
        (try? ScanFileAccess().contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?.map {
            URL(fileURLWithPath: $0.path).standardizedFileURL
        } ?? []
    }
    static func attributes(_ url: URL) -> [FileAttributeKey: Any]? {
        guard let attrs = try? ScanFileAccess().attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType != .typeSymbolicLink,
              URL(fileURLWithPath: url.path).resolvingSymlinksInPath().path == url.standardizedFileURL.path else { return nil }
        return attrs
    }
    static func json(_ url: URL) -> [String: Any]? {
        guard let attrs = attributes(url), attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? Int64 ?? .max) <= 10 * 1024 * 1024 else { return nil }
        do { return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] }
        catch { ScanContext.diagnostics?.failure(url.path, error: error); return nil }
    }
    static func plist(_ url: URL) -> [String: Any]? {
        guard let attrs = attributes(url), attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? Int64 ?? .max) <= 10 * 1024 * 1024 else { return nil }
        do { return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil) as? [String: Any] }
        catch { ScanContext.diagnostics?.failure(url.path, error: error); return nil }
    }
    static func finish(_ items: [InspectionItem], collector: ScanDiagnosticsCollector, issues: [String] = []) -> InspectionReport {
        let diagnostic = collector.snapshot(finished: true, cancelled: Task.isCancelled)
        let unique = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        return InspectionReport(items: unique.sorted { ($0.owner, $0.name, $0.path) < ($1.owner, $1.name, $1.path) },
            issues: issues + diagnostic.issues.prefix(100).map { "\($0.path)：\($0.message)" }
                + (diagnostic.omittedIssueCount > 0 || diagnostic.issues.count > 100 ? ["部分读取问题已省略。"] : []),
            cancelled: Task.isCancelled)
    }
}
