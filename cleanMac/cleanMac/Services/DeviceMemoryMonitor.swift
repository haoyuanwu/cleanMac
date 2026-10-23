import Foundation
import Combine
import Darwin

struct DeviceMemorySample: Identifiable, Sendable {
    let id = Date()
    let usedBytes: UInt64
    let totalBytes: UInt64
}

enum DeviceMemoryReader {
    nonisolated static func sample() -> DeviceMemorySample? {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS,
              host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }

        let total = ProcessInfo.processInfo.physicalMemory
        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        return DeviceMemorySample(
            usedBytes: min(total, usedPages * UInt64(pageSize)),
            totalBytes: total
        )
    }
}

/// 与页面生命周期无关的内存采样，只保留一分钟曲线所需的 60 个点。
@MainActor
final class DeviceMemoryMonitor: ObservableObject {
    static let shared = DeviceMemoryMonitor()
    static let historyLimit = 60
    @Published private(set) var history: [DeviceMemorySample] = []
    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        guard let sample = DeviceMemoryReader.sample() else { return }
        // 唤醒后丢弃超过显示窗口的旧点，不将睡眠前后的数据连成实时曲线。
        history.removeAll { sample.id.timeIntervalSince($0.id) >= 60 }
        history.append(sample)
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    }
}
