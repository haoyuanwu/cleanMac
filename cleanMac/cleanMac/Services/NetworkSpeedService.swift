import Foundation
import Combine
import Darwin

/// 网卡累计收发字节
struct NetworkByteCounters: Sendable, Equatable {
    var rx: UInt64
    var tx: UInt64
}

/// 瞬时网速
struct NetworkThroughput: Sendable, Equatable {
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double

    var downloadText: String {
        Self.format(bytesPerSecond: downloadBytesPerSecond)
    }

    var uploadText: String {
        Self.format(bytesPerSecond: uploadBytesPerSecond)
    }

    static func format(bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
        if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.2f MB/s", bytesPerSecond / (1024 * 1024))
    }

    nonisolated(unsafe) static let zero = NetworkThroughput(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
}

/// 网速监测：对网卡累计字节做差分
enum NetworkSpeedService {
    /// 读取启用中（非回环）网卡的累计收发字节
    nonisolated static func readCounters() -> NetworkByteCounters {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return NetworkByteCounters(rx: 0, tx: 0)
        }
        defer { freeifaddrs(ifaddr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            // 仅统计已启用的非回环接口
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            // getifaddrs 同时返回地址条目；只在链路层条目读取一次网卡计数。
            guard current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let dataPtr = current.pointee.ifa_data else { continue }

            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            // Darwin 的 if_data 计数是 32 位，短周期差分仍可用
            rx &+= UInt64(data.ifi_ibytes)
            tx &+= UInt64(data.ifi_obytes)
        }

        return NetworkByteCounters(rx: rx, tx: tx)
    }

    /// 两次采样之间的平均速度
    nonisolated static func throughput(from previous: NetworkByteCounters, to current: NetworkByteCounters, seconds: Double) -> NetworkThroughput {
        guard seconds > 0 else { return .zero }
        // 处理计数器回绕/重置
        let dRx = current.rx >= previous.rx ? current.rx - previous.rx : current.rx
        let dTx = current.tx >= previous.tx ? current.tx - previous.tx : current.tx
        return NetworkThroughput(
            downloadBytesPerSecond: Double(dRx) / seconds,
            uploadBytesPerSecond: Double(dTx) / seconds
        )
    }
}

/// 持续采样网速（1 秒一次）
@MainActor
final class NetworkSpeedMonitor: ObservableObject {
    static let shared = NetworkSpeedMonitor()
    private var consumers = Set<String>()

    func acquire(_ consumer: String) {
        consumers.insert(consumer)
        start()
    }

    func release(_ consumer: String) {
        consumers.remove(consumer)
        if consumers.isEmpty { stop() }
    }
    @Published private(set) var throughput: NetworkThroughput = .zero
    @Published private(set) var isActive = false
    @Published private(set) var history: [NetworkThroughput] = []

    private var timer: Timer?
    private var lastCounters: NetworkByteCounters?
    private var lastDate: Date?

    func start() {
        guard timer == nil else { return }
        isActive = true
        throughput = .zero
        history = []
        lastCounters = NetworkSpeedService.readCounters()
        lastDate = Date()

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        throughput = .zero
        lastCounters = nil
        lastDate = nil
    }

    private func tick() {
        let now = Date()
        let current = NetworkSpeedService.readCounters()
        if let lastCounters, let lastDate {
            let seconds = now.timeIntervalSince(lastDate)
            throughput = NetworkSpeedService.throughput(from: lastCounters, to: current, seconds: seconds)
            history.append(throughput)
            if history.count > 60 { history.removeFirst(history.count - 60) }
        }
        lastCounters = current
        lastDate = now
    }
}
