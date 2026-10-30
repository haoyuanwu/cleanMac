import Foundation
import Combine
import Darwin
import IOKit

nonisolated enum DeviceTelemetryReader {
    static func cpu() -> CPUTicks? {
        let host = mach_host_self(); defer { mach_port_deallocate(mach_task_self_, host) }
        var info = host_cpu_load_info_data_t(), count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return nil }
        let ticks = withUnsafeBytes(of: info.cpu_ticks) { Array($0.bindMemory(to: UInt32.self)) }
        guard ticks.count == 4 else { return nil }
        return CPUTicks(user: ticks[0], system: ticks[1], idle: ticks[2], nice: ticks[3])
    }
    static func disk() -> [UInt64: DiskByteCounter] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var counters: [UInt64: DiskByteCounter] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS,
                  let table = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let read = table["Bytes (Read)"] as? NSNumber, let written = table["Bytes (Write)"] as? NSNumber else { continue }
            counters[id] = DiskByteCounter(read: read.uint64Value, written: written.uint64Value)
        }
        return counters
    }
    static func volumes() -> [MountedDeviceVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: .skipHiddenVolumes) ?? []
        return urls.compactMap { url in
            guard let data = try? url.resourceValues(forKeys: keys), data.volumeIsLocal == true else { return nil }
            return MountedDeviceVolume(id: url.path, name: data.volumeName ?? url.lastPathComponent, url: url,
                internalVolume: data.volumeIsInternal, total: data.volumeTotalCapacity.map(Int64.init), free: data.volumeAvailableCapacity.map(Int64.init))
        }.sorted { ($0.internalVolume == true ? 0 : 1, $0.name) < ($1.internalVolume == true ? 0 : 1, $1.name) }
    }
}

/// 页面与功能卡片共享一个采样器；无页面订阅者时停止新采样。
@MainActor final class DeviceTelemetryMonitor: ObservableObject {
    static let shared = DeviceTelemetryMonitor()
    @Published private(set) var history: [TelemetryPoint] = []
    @Published private(set) var volumes: [MountedDeviceVolume] = []
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var isRefreshing = false
    private var clients = Set<UUID>()
    private var timer: Timer?
    private var work: Task<Void, Never>?
    private var previousCPU: CPUTicks?
    private var previousDisk: [UInt64: DiskByteCounter] = [:]
    private var previousTime: TimeInterval?
    private var volumeDate = Date.distantPast
    private var generation = 0
    var current: TelemetryPoint? { history.last }
    var thermalDescription: String {
        switch thermalState { case .nominal: "正常"; case .fair: "略高"; case .serious: "较高"; case .critical: "严重"; @unknown default: "未知" }
    }
    func retain(_ id: UUID) {
        clients.insert(id)
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        timer.tolerance = 0.4; RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func release(_ id: UUID) {
        clients.remove(id)
        if clients.isEmpty {
            generation += 1; timer?.invalidate(); timer = nil; work?.cancel(); work = nil
            previousCPU = nil; previousDisk = [:]; previousTime = nil; isRefreshing = false
        }
    }
    func refresh() {
        guard work == nil, !clients.isEmpty else { return }
        isRefreshing = true
        let token = generation, readVolumes = Date().timeIntervalSince(volumeDate) > 15
        work = Task {
            let reading = await ScanTask.run { (DeviceTelemetryReader.cpu(), DeviceTelemetryReader.disk(), readVolumes ? DeviceTelemetryReader.volumes() : nil) }
            guard !Task.isCancelled, token == generation else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = previousTime.map { now - $0 } ?? 0
            let cpu = elapsed > 0 && elapsed <= 8 ? previousCPU.flatMap { old in reading.0.flatMap { CPUUsage.between(old, $0) } } : nil
            let disk = DiskTransferRate.between(previousDisk, reading.1, seconds: elapsed)
            let date = Date()
            history.removeAll { date.timeIntervalSince($0.date) > 60 }
            history.append(TelemetryPoint(date: date, cpu: cpu, disk: disk))
            if history.count > 32 { history.removeFirst(history.count - 32) }
            previousCPU = reading.0; previousDisk = reading.1; previousTime = now
            if let volumes = reading.2 { self.volumes = volumes; volumeDate = date }
            thermalState = ProcessInfo.processInfo.thermalState
            isRefreshing = false; work = nil
        }
    }
}
