import Foundation
import Combine
import SwiftUI

/// Xcode 分析状态：挂在主层级上，切页后仍可继续分析并保留结果
@MainActor
final class XcodeAnalysisViewModel: ObservableObject {
    @Published var result: XcodeAnalysisResult?
    @Published var isScanning = false
    @Published var expandedKinds = Set<XcodeArtifactKind>()

    private let service = XcodeAnalysisService()
    private var scanTask: Task<Void, Never>?

    func scan() {
        guard !isScanning else { return }

        isScanning = true
        scanTask = Task { [service] in
            let analysis = await service.analyze()
            if Task.isCancelled { return }
            self.result = analysis
            self.isScanning = false
        }
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
}
