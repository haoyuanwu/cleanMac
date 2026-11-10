import Foundation
import Combine

@MainActor
final class MemoryMaintenanceService: ObservableObject {
    static let shared = MemoryMaintenanceService()
    private let operation: (@Sendable () -> String?)?
    init(operation: (@Sendable () -> String?)? = nil) {
        self.operation = operation
    }
    @Published private(set) var running = false
    @Published private(set) var message: String?

    func run() {
        guard !running else { return }
        running = true; message = nil
        Task {
            let before = DeviceMemoryReader.sample()
            if operation == nil, let issue = MemoryHelperController.shared.prepare() {
                message = issue; running = false; return
            }
            let operation = self.operation
            let error = await ScanTask.run {
                if let operation { return operation() }
                return MemoryHelperClient.purgeCaches()
            }
            let after = DeviceMemoryReader.sample()
            if let error { message = error }
            else {
                let sizes = before.flatMap { first in after.map { last in
                    "已用内存估算：\(FileSizeFormatter.string(fromByteCount: Int64(first.usedBytes))) → \(FileSizeFormatter.string(fromByteCount: Int64(last.usedBytes)))。"
                } } ?? ""
                message = "系统缓存整理完成。" + sizes + "此操作不释放应用正在使用的内存，内存数值可能不变。"
            }
            running = false
        }
    }
    func requestHelperAuthorization() {
        guard !running else { return }
        message = MemoryHelperController.shared.prepare() ?? "后台辅助服务已启用，可以直接整理。"
    }

    func removeHelper() {
        guard !running else { return }
        running = true
        Task { message = await MemoryHelperController.shared.unregister(); running = false }
    }
}
