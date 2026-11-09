import Foundation
import Combine

@MainActor
final class DevelopmentStorageSession: ObservableObject {
    @Published var selections: [DevelopmentStorageKind: Set<String>] = [:]
    @Published var expandedTools: [DevelopmentStorageKind: Set<String>] = [:]
    @Published var reports: [DevelopmentStorageKind: DevelopmentStorageReport] = [:]
    @Published private(set) var loading = Set<DevelopmentStorageKind>()
    @Published private(set) var cancelling = Set<DevelopmentStorageKind>()
    @Published private(set) var cleaning: DevelopmentStorageKind?
    @Published private(set) var progress: [DevelopmentStorageKind: ScanDiagnostics] = [:]
    @Published private(set) var pendingReview: DevelopmentStorageReview?
    @Published private(set) var celebrationToken = 0
    @Published private(set) var messages: [DevelopmentStorageKind: String] = [:]
    @Published private(set) var failures: [DevelopmentStorageKind: [String]] = [:]
    @Published var completionMessage: String?
    @Published private(set) var completionHadFailures = false
    private let scanner: @Sendable (DevelopmentStorageKind, ScanDiagnosticsCollector) -> DevelopmentStorageReport
    private let cleaner: @Sendable (DevelopmentStorageEntry, DevelopmentStorageKind) throws -> Void
    init(scanner: @escaping @Sendable (DevelopmentStorageKind, ScanDiagnosticsCollector) -> DevelopmentStorageReport = { DevelopmentStorageScanner.scan($0, diagnostics: $1) },
         cleaner: @escaping @Sendable (DevelopmentStorageEntry, DevelopmentStorageKind) throws -> Void = { entry, kind in
            guard entry.cleanable, DevelopmentStorageScanner.isCleanablePath(entry.id) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "路径或保护状态已变化，请重新扫描。"])
            }
            try CleanService.cleanSingle(item: entry.file, category: kind.rawValue)
         }) {
        self.scanner = scanner
        self.cleaner = cleaner
    }
    private var tasks: [DevelopmentStorageKind: Task<Void, Never>] = [:]
    private var removalsDuringScan: [DevelopmentStorageKind: Set<String>] = [:]
    private var collectors: [DevelopmentStorageKind: ScanDiagnosticsCollector] = [:]

    var busy: Bool { !loading.isEmpty || cleaning != nil }
    func busy(for kind: DevelopmentStorageKind) -> Bool { loading.contains(kind) || cleaning == kind }
    func requestReview(_ review: DevelopmentStorageReview) {
        guard !busy(for: review.kind), cleaning == nil, pendingReview == nil, !review.entries.isEmpty else { return }
        let entries = DevelopmentStorageSelection.eligible(review.entries)
        guard !entries.isEmpty else { return }
        pendingReview = DevelopmentStorageReview(kind: review.kind, entries: entries)
    }
    func cancelReview() { pendingReview = nil }
    func confirmReview() {
        guard let review = pendingReview else { return }
        pendingReview = nil
        clean(review)
    }

    func scan(_ kind: DevelopmentStorageKind) {
        guard !busy(for: kind) else { return }
        let collector = ScanDiagnosticsCollector()
        collectors[kind] = collector
        loading.insert(kind); cancelling.remove(kind); progress[kind] = collector.snapshot()
        removalsDuringScan[kind] = []
        messages[kind] = nil; failures[kind] = nil
        let scanner = self.scanner
        tasks[kind] = Task {
            let ticker = Task {
                while !Task.isCancelled {
                    progress[kind] = collector.snapshot()
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                }
            }
            let scanned = await ScanTask.run { scanner(kind, collector) }
            let result = DevelopmentStorageReport(entries: scanned.entries.compactMap { $0.removing(removalsDuringScan[kind] ?? []) }, diagnostics: scanned.diagnostics, docker: scanned.docker)
            ticker.cancel()
            // 取消重新扫描时保留上一份完整结果，避免用残缺清单覆盖它。
            if result.diagnostics.status != .cancelled || reports[kind] == nil { reports[kind] = result }
            if result.diagnostics.status == .cancelled { messages[kind] = "扫描已取消。" + (reports[kind]?.diagnostics.status == .cancelled ? "当前结果不完整，可重新扫描。" : "已保留上次扫描结果。") }
            selections[kind] = DevelopmentStorageSelection.reconcile(selections[kind] ?? [], visible: reports[kind]?.entries.flatMap(\.descendants) ?? [])
            progress[kind] = nil; loading.remove(kind); cancelling.remove(kind); collectors[kind] = nil; tasks[kind] = nil; removalsDuringScan[kind] = nil
        }
    }
    func cancelScan(_ kind: DevelopmentStorageKind) {
        guard loading.contains(kind), !cancelling.contains(kind) else { return }
        cancelling.insert(kind); collectors[kind]?.requestCancellation(); tasks[kind]?.cancel()
    }
    func clean(_ review: DevelopmentStorageReview) {
        guard !busy(for: review.kind), cleaning == nil, !review.entries.isEmpty else { return }
        cleaning = review.kind; messages[review.kind] = nil; failures[review.kind] = nil
        let cleaner = self.cleaner
        tasks[review.kind] = Task {
            let startedAt = Date()
            let result = await ScanTask.run { () -> (Set<String>, [String]) in
                var removed = Set<String>(), failures: [String] = []
                for entry in review.entries {
                    do {
                        try cleaner(entry, review.kind)
                        removed.insert(entry.id)
                    } catch { failures.append(entry.id + "：" + error.localizedDescription) }
                }
                return (removed, failures)
            }
            for kind in Array(reports.keys) {
                if let old = reports[kind] {
                    reports[kind] = DevelopmentStorageReport(entries: old.entries.compactMap { $0.removing(result.0) }, diagnostics: old.diagnostics, docker: old.docker)
                }
            }
            for kind in Array(selections.keys) { selections[kind] = selections[kind]?.filter { path in !result.0.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) } }
            for kind in loading { removalsDuringScan[kind, default: []].formUnion(result.0) }
            messages[review.kind] = "已移到废纸篓 \(result.0.count) 项" + (result.1.isEmpty ? "，清空废纸篓后释放空间。" : "，\(result.1.count) 项未能处理。")
            failures[review.kind] = result.1
            let remaining = 1.2 - Date().timeIntervalSince(startedAt)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            completionHadFailures = !result.1.isEmpty
            completionMessage = review.kind.rawValue + "：" + (messages[review.kind] ?? "处理完成。")
            if !result.0.isEmpty, result.1.isEmpty { celebrationToken += 1 }
            cleaning = nil; tasks[review.kind] = nil
        }
    }
}
