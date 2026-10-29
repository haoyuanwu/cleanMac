import Foundation

struct ScanDiagnostics: Codable, Sendable {
    enum Status: String, Codable, Sendable { case running, complete, partial, cancelled }
    struct Issue: Codable, Identifiable, Sendable {
        let path: String
        let message: String
        let permissionDenied: Bool
        nonisolated var id: String { path + message }
    }
    let startedAt: Date
    let updatedAt: Date
    let status: Status
    let currentPath: String
    let visitedCount: Int
    let skippedCount: Int
    let missingCount: Int
    let issues: [Issue]
    let omittedIssueCount: Int
    nonisolated var elapsed: TimeInterval { max(0, updatedAt.timeIntervalSince(startedAt)) }
    nonisolated var summary: String? {
        switch status {
        case .cancelled: return "扫描已取消，当前结果不完整。"
        case .partial: return "部分路径无法读取：\(issues.count + omittedIssueCount) 处问题，扫描结果不完整。"
        default: return nil
        }
    }
}

final class ScanDiagnosticsCollector: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated private let startedAt = Date()
    nonisolated(unsafe) private var currentPath = ""
    // 统计读取检查次数，避免为数百万文件保存整份路径集合。
    nonisolated(unsafe) private var visitedCount = 0
    nonisolated(unsafe) private var skipped = Set<String>()
    nonisolated(unsafe) private var missing = Set<String>()
    nonisolated(unsafe) private var issues: [String: ScanDiagnostics.Issue] = [:]
    nonisolated(unsafe) private var omitted = Set<String>()
    nonisolated(unsafe) private var errorCount = 0
    nonisolated var errorRevision: Int { lock.lock(); defer { lock.unlock() }; return errorCount }

    nonisolated(unsafe) private var measurements: [String: FileStorageMeasurement] = [:]

    nonisolated(unsafe) private var cancellationRequested = false
    nonisolated(unsafe) private var cancellationHandlers: [UUID: @Sendable () -> Void] = [:]
    nonisolated func requestCancellation() {
        lock.lock()
        cancellationRequested = true
        let handlers = Array(cancellationHandlers.values)
        lock.unlock()
        handlers.forEach { $0() }
    }
    nonisolated func registerCancellation(_ handler: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        cancellationHandlers[id] = handler
        let cancelled = cancellationRequested
        lock.unlock()
        if cancelled { handler() }
        return id
    }
    nonisolated func unregisterCancellation(_ id: UUID) {
        lock.lock(); cancellationHandlers[id] = nil; lock.unlock()
    }

    nonisolated func measurement(for path: String) -> FileStorageMeasurement? {
        lock.lock(); defer { lock.unlock() }; return measurements[path]
    }
    nonisolated func remember(_ measurement: FileStorageMeasurement, for path: String) {
        lock.lock(); defer { lock.unlock() }; measurements[path] = measurement
    }
    nonisolated func visit(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        currentPath = path
        visitedCount += 1
    }
    nonisolated func skip(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        skipped.insert(path)
    }
    nonisolated func failure(_ path: String, error: Error) {
        let ns = error as NSError
        lock.lock(); defer { lock.unlock() }
        if (ns.domain == NSCocoaErrorDomain && [4, 260].contains(ns.code))
            || (ns.domain == NSPOSIXErrorDomain && ns.code == 2) {
            missing.insert(path)
            return
        }
        errorCount += 1
        guard issues[path] == nil else { return }
        if issues.count >= 1000 { omitted.insert(path); return }
        let permission = (ns.domain == NSPOSIXErrorDomain && [1, 13].contains(ns.code))
            || (ns.domain == NSCocoaErrorDomain && [257, 513].contains(ns.code))
        issues[path] = .init(path: path, message: ns.localizedDescription, permissionDenied: permission)
    }
    nonisolated func snapshot(finished: Bool = false, cancelled: Bool = false) -> ScanDiagnostics {
        lock.lock(); defer { lock.unlock() }
        let status: ScanDiagnostics.Status = cancelled || cancellationRequested ? .cancelled : !finished ? .running
            : (issues.isEmpty && omitted.isEmpty ? .complete : .partial)
        return ScanDiagnostics(startedAt: startedAt, updatedAt: Date(), status: status, currentPath: currentPath,
                               visitedCount: visitedCount, skippedCount: skipped.count, missingCount: missing.count,
                               issues: issues.values.sorted { $0.path < $1.path }, omittedIssueCount: omitted.count)
    }
}

enum ScanContext {
    @TaskLocal nonisolated static var diagnostics: ScanDiagnosticsCollector?

    nonisolated static func values(_ url: URL, keys: Set<URLResourceKey>) throws -> URLResourceValues {
        diagnostics?.visit(url.path)
        do { return try url.resourceValues(forKeys: keys) }
        catch { diagnostics?.failure(url.path, error: error); throw error }
    }
}

enum ScanTask {
    nonisolated static func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        let diagnostics = ScanContext.diagnostics
        let task = Task.detached(priority: .utility) {
            ScanContext.$diagnostics.withValue(diagnostics) { body() }
        }
        let registration = diagnostics?.registerCancellation { task.cancel() }
        defer { if let registration { diagnostics?.unregisterCancellation(registration) } }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
