import Foundation
import Combine
import SwiftUI

/// Xcode 分析状态：挂在主层级上，切页后仍可继续分析并保留结果
@MainActor
final class XcodeAnalysisViewModel: ObservableObject {
    @Published var result: XcodeAnalysisResult? {
        didSet {
            selectedPaths.formIntersection(Set(result?.artifacts.map(\.path) ?? []))
        }
    }
    @Published private(set) var selectedPaths = Set<String>()
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var deletionError: String?
    @Published private(set) var pendingDeletion: [XcodeArtifact]?
    @Published var expandedKinds = Set<XcodeArtifactKind>()

    private let service = XcodeAnalysisService()
    private var scanTask: Task<Void, Never>?

    func scan() {
        guard !isScanning, !isDeleting, pendingDeletion == nil else { return }

        selectedPaths.removeAll()
        isScanning = true
        scanTask = Task { [service] in
            let analysis = await service.analyze()
            if Task.isCancelled { return }
            self.result = analysis
            self.isScanning = false
        }
    }

    func scanAndWait() async {
        scan()
        await scanTask?.value
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func toggleExpanded(_ kind: XcodeArtifactKind) {
        if expandedKinds.contains(kind) {
            expandedKinds.remove(kind)
        } else {
            expandedKinds.insert(kind)
        }
    }

    func canDelete(_ item: XcodeArtifact) -> Bool {
        let library = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/"
        return item.detail == nil
            && item.path.hasPrefix(library)
            && SafetyWhitelist.canDelete(path: item.path)
    }

    var selectedArtifacts: [XcodeArtifact] {
        result?.artifacts.filter { selectedPaths.contains($0.path) } ?? []
    }

    var selectedSize: Int64 {
        selectedArtifacts.reduce(0) { $0 + $1.size }
    }

    func selectableArtifacts(in kind: XcodeArtifactKind? = nil) -> [XcodeArtifact] {
        (result?.artifacts ?? []).filter { (kind == nil || $0.kind == kind) && canDelete($0) }
    }

    func toggleSelection(_ item: XcodeArtifact) {
        guard !isScanning, !isDeleting, canDelete(item),
              result?.artifacts.contains(where: { $0.path == item.path }) == true else { return }
        if selectedPaths.contains(item.path) {
            selectedPaths.remove(item.path)
        } else {
            selectedPaths.insert(item.path)
        }
    }

    func toggleSelectAll(in kind: XcodeArtifactKind? = nil) {
        guard !isScanning, !isDeleting else { return }
        let paths = Set(selectableArtifacts(in: kind).map(\.path))
        if paths.isSubset(of: selectedPaths) {
            selectedPaths.subtract(paths)
        } else {
            selectedPaths.formUnion(paths)
        }
    }

    func clearSelection() {
        guard !isDeleting else { return }
        selectedPaths.removeAll()
    }

    func requestTrash(_ items: [XcodeArtifact]) {
        guard !isScanning, !isDeleting, pendingDeletion == nil, let result else { return }
        let paths = Set(items.map(\.path))
        let targets = result.artifacts.filter { paths.contains($0.path) && canDelete($0) }
        guard !targets.isEmpty else { return }
        pendingDeletion = targets
    }

    func cancelTrash() {
        pendingDeletion = nil
    }

    func confirmTrash() {
        guard let items = pendingDeletion else { return }
        pendingDeletion = nil
        moveToTrash(items)
    }

    func moveToTrash(_ item: XcodeArtifact) {
        moveToTrash([item])
    }

    func moveToTrash(_ items: [XcodeArtifact]) {
        guard !isScanning, !isDeleting, let current = result else { return }
        let requestedPaths = Set(items.map(\.path))
        let targets = current.artifacts.filter { requestedPaths.contains($0.path) }
        guard !targets.isEmpty else { return }

        isDeleting = true
        deletionError = nil
        Task {
            let startedAt = Date()
            var failures: [String] = []
            var deletedPaths = Set<String>()
            for item in targets {
                guard canDelete(item) else {
                    failures.append("“\(item.name)”不在可删除范围内。")
                    continue
                }
                let decision = DeleteDryRun.validate(path: item.path, context: "xcode-analysis")
                guard decision.allowed else {
                    failures.append("无法删除“\(item.name)”：\(decision.reason)。")
                    continue
                }
                let path = item.path
                let failure = await Task.detached(priority: .utility) { () -> String? in
                    do {
                        try CleaningHistoryStore.shared.moveToTrash(path: path, size: item.size, category: "Xcode 文件")
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                }.value
                if let failure {
                    failures.append("无法将“\(item.name)”移到废纸篓：\(failure)")
                } else {
                    deletedPaths.insert(path)
                }
            }

            if let latest = result {
                result = XcodeAnalysisResult(
                    artifacts: latest.artifacts.filter { !deletedPaths.contains($0.path) },
                    scannedAt: latest.scannedAt
                )
            }
            // 与现有智能清理保持一致，避免快速操作时动画一闪而过。
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed < 1.2 {
                try? await Task.sleep(for: .seconds(1.2 - elapsed))
            }
            isDeleting = false
            if !failures.isEmpty {
                deletionError = failures.joined(separator: "\n")
            }
        }
    }
}
