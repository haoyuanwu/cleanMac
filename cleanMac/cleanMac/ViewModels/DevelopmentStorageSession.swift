import Foundation
import Combine

@MainActor
final class DevelopmentStorageSession: ObservableObject {
    @Published var reports: [DevelopmentStorageKind: DevelopmentStorageReport] = [:]
    @Published private(set) var loading: DevelopmentStorageKind?
    @Published private(set) var cancelling = false
    @Published private(set) var cleaning: DevelopmentStorageKind?
    @Published private(set) var progress: ScanDiagnostics?
    @Published private(set) var messages: [DevelopmentStorageKind: String] = [:]
    @Published private(set) var failures: [DevelopmentStorageKind: [String]] = [:]
    private var task: Task<Void, Never>?
    private var collector: ScanDiagnosticsCollector?

    var busy: Bool { loading != nil || cleaning != nil }

    func scan(_ kind: DevelopmentStorageKind) {
        guard !busy else { return }
        let collector = ScanDiagnosticsCollector()
        self.collector = collector
        loading = kind; cancelling = false; progress = collector.snapshot()
        messages[kind] = nil; failures[kind] = nil
        task = Task {
            let ticker = Task {
                while !Task.isCancelled {
                    progress = collector.snapshot()
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                }
            }
            let result = await ScanTask.run { DevelopmentStorageScanner.scan(kind, diagnostics: collector) }
            ticker.cancel()
            // 取消重新扫描时保留上一份完整结果，避免用残缺清单覆盖它。
            if result.diagnostics.status != .cancelled || reports[kind] == nil { reports[kind] = result }
            if result.diagnostics.status == .cancelled { messages[kind] = "扫描已取消。" + (reports[kind]?.diagnostics.status == .cancelled ? "当前结果不完整，可重新扫描。" : "已保留上次扫描结果。") }
            progress = nil; loading = nil; cancelling = false; self.collector = nil; task = nil
        }
    }
    func cancelScan() {
        guard loading != nil, !cancelling else { return }
        cancelling = true; collector?.requestCancellation(); task?.cancel()
    }
    func clean(_ review: DevelopmentStorageReview) {
        guard !busy, !review.entries.isEmpty else { return }
        cleaning = review.kind; messages[review.kind] = nil; failures[review.kind] = nil
        task = Task {
            let result = await ScanTask.run { () -> (Set<String>, [String]) in
                var removed = Set<String>(), failures: [String] = []
                for entry in review.entries {
                    guard entry.cleanable, DevelopmentStorageScanner.isCleanablePath(entry.id) else {
                        failures.append(entry.id + "：路径或保护状态已变化，请重新扫描。")
                        continue
                    }
                    do {
                        try CleanService.cleanSingle(item: entry.file, category: review.kind.rawValue)
                        removed.insert(entry.id)
                    } catch { failures.append(entry.id + "：" + error.localizedDescription) }
                }
                return (removed, failures)
            }
            if let old = reports[review.kind] {
                reports[review.kind] = DevelopmentStorageReport(entries: old.entries.compactMap { $0.removing(result.0) }, diagnostics: old.diagnostics, docker: old.docker)
            }
            messages[review.kind] = "已移到废纸篓 \(result.0.count) 项" + (result.1.isEmpty ? "，清空废纸篓后释放空间。" : "，\(result.1.count) 项未能处理。")
            failures[review.kind] = result.1
            cleaning = nil; task = nil
        }
    }
}
