import Foundation
import Combine
import SwiftUI

/// Xcode 分析状态：挂在主层级上，切页后仍可继续分析并保留结果
@MainActor
final class XcodeAnalysisViewModel: ObservableObject {
    @Published var result: XcodeAnalysisResult?
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var deletionError: String?
    @Published var expandedKinds = Set<XcodeArtifactKind>()

    private let service = XcodeAnalysisService()
    private var scanTask: Task<Void, Never>?

    func scan() {
        guard !isScanning, !isDeleting else { return }

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

    func moveToTrash(_ item: XcodeArtifact) {
        guard !isScanning, !isDeleting,
              result?.artifacts.contains(where: { $0.path == item.path }) == true else { return }
        guard canDelete(item) else {
            deletionError = "此项目不在可删除范围内。"
            return
        }
        let decision = DeleteDryRun.validate(path: item.path, context: "xcode-analysis")
        guard decision.allowed else {
            deletionError = "无法删除：\(decision.reason)。"
            return
        }

        isDeleting = true
        let path = item.path
        Task {
            let failure = await Task.detached(priority: .utility) { () -> String? in
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value

            isDeleting = false
            if let failure {
                deletionError = "无法将“\(item.name)”移到废纸篓：\(failure)"
            } else if let current = result {
                result = XcodeAnalysisResult(
                    artifacts: current.artifacts.filter { $0.path != path },
                    scannedAt: current.scannedAt
                )
            }
        }
    }
}
