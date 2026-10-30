import Foundation
import Darwin

nonisolated struct ResourceAppDescriptor: Sendable, Identifiable {
    let pid: Int32
    let launchDate: Date
    let bundleID: String
    let name: String
    let path: String
    var id: String { "\(pid):\(launchDate.timeIntervalSince1970)" }
}

nonisolated struct ResourceProcessSample: Sendable {
    let pid: Int32
    let parent: Int32
    let birth: UInt64
    let path: String
    let cpuNanoseconds: UInt64
    let memory: UInt64
    var id: String { "\(pid):\(birth)" }
}

nonisolated enum ResourceResponsiveness: Sendable { case unknown, responsive, unresponsive }

nonisolated struct ResourceProcessDetail: Identifiable, Sendable {
    var id: String { "\(pid):\(birth)" }
    let pid: Int32
    let birth: UInt64
    let path: String
    let memory: UInt64
    let cpuPercent: Double?
}
nonisolated struct ApplicationUsagePoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let cpu: Double?
    let memory: UInt64
}
nonisolated struct ApplicationResourceUsage: Identifiable, Sendable {
    let application: ResourceAppDescriptor
    let cpuPercent: Double?
    let memory: UInt64
    let processCount: Int
    var sampleAvailable = true
    var responsiveness: ResourceResponsiveness = .unknown
    var alertReason: String?
    var processes: [ResourceProcessDetail] = []
    var id: String { application.id }
}

nonisolated enum ApplicationResourceReader {
    static func processes() -> [ResourceProcessSample] {
        let count = max(256, Int(proc_listallpids(nil, 0)) + 256)
        var pids = [Int32](repeating: 0, count: count)
        let size = pids.count * MemoryLayout<Int32>.size
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32(size)) }
        guard found > 0 else { return [] }
        var samples: [ResourceProcessSample] = []
        for pid in pids.prefix(min(Int(found), pids.count)) where pid > 0 {
            if Task.isCancelled { break }
            var bsd = proc_bsdinfo()
            let bytes = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bytes) == bytes, bsd.pbi_uid == getuid() else { continue }
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            let pathSize = pathBuffer.count
            let read = pathBuffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32(pathSize)) }
            guard read > 0 else { continue }
            var usage = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard status == 0 else { continue }
            // rusage contains the process birth token as well, preventing mixed PID-reuse samples.
            samples.append(ResourceProcessSample(pid: pid, parent: Int32(bsd.pbi_ppid), birth: usage.ri_proc_start_abstime,
                path: String(decoding: pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
                cpuNanoseconds: usage.ri_user_time &+ usage.ri_system_time, memory: usage.ri_phys_footprint))
        }
        return samples
    }
    static func aggregate(applications: [ResourceAppDescriptor], current: [ResourceProcessSample], previous: [ResourceProcessSample], elapsed: TimeInterval) -> [ApplicationResourceUsage] {
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let processes = Dictionary(current.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let roots = applications.sorted { $0.path.count > $1.path.count }
        let appByPID = Dictionary(applications.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        func owner(_ process: ResourceProcessSample) -> ResourceAppDescriptor? {
            if let app = appByPID[process.pid], process.path.hasPrefix(app.path + "/") { return app }
            if let app = roots.first(where: { process.path.hasPrefix($0.path + "/") }) { return app }
            var parent = process.parent
            var visited: Set<Int32> = [process.pid]
            for _ in 0..<32 {
                guard parent > 1, visited.insert(parent).inserted else { break }
                guard let ancestor = processes[parent] else { break }
                if let app = appByPID[parent], ancestor.path.hasPrefix(app.path + "/") { return app }
                parent = ancestor.parent
            }
            return nil
        }
        var buckets: [String: [ResourceProcessSample]] = [:]
        for process in current { if let app = owner(process) { buckets[app.id, default: []].append(process) } }
        return applications.map { app in
            let rows = buckets[app.id] ?? []
            var cpu: Double = 0
            var measured = false
            if elapsed > 0 && elapsed <= 12 {
                for row in rows {
                    if let old = previousByID[row.id], old.path == row.path, row.cpuNanoseconds >= old.cpuNanoseconds {
                        cpu += Double(row.cpuNanoseconds - old.cpuNanoseconds) / (elapsed * 1_000_000_000) * 100
                        measured = true
                    }
                }
            }
            return ApplicationResourceUsage(application: app, cpuPercent: measured ? cpu : nil,
                memory: rows.reduce(0) { $0 &+ $1.memory }, processCount: rows.count, sampleAvailable: !rows.isEmpty,
                processes: rows.map { row in
                    let cpu: Double? = elapsed > 0 && elapsed <= 12 ? previousByID[row.id].flatMap { old in
                        guard old.path == row.path, row.cpuNanoseconds >= old.cpuNanoseconds else { return nil }
                        return Double(row.cpuNanoseconds - old.cpuNanoseconds) / (elapsed * 1_000_000_000) * 100
                    } : nil
                    return ResourceProcessDetail(pid: row.pid, birth: row.birth, path: row.path, memory: row.memory, cpuPercent: cpu)
                }.sorted { $0.memory > $1.memory })
        }
    }
}

nonisolated struct ResourceAlertPolicy {
    var cpuThreshold: Double = 400
    var memoryThreshold: UInt64
    var duration: TimeInterval = 60
    var burstDuration: TimeInterval = 30
    var stallDuration: TimeInterval = 30
    var cooldown: TimeInterval = 1800
    private var highSince: [String: TimeInterval] = [:]
    private var lastAlert: [String: TimeInterval] = [:]
    private var lastSample: TimeInterval?
    private var previousUsage: [String: ApplicationResourceUsage] = [:]
    private var burstSince: [String: TimeInterval] = [:]
    private var memoryGrowthSince: [String: TimeInterval] = [:]
    private var memoryHistory: [String: [(time: TimeInterval, bytes: UInt64)]] = [:]
    private var unresponsiveSince: [String: TimeInterval] = [:]
    private var notifiedEpisodes = Set<String>()

    mutating func evaluate(_ usages: [ApplicationResourceUsage], now: TimeInterval, notificationsEnabled: Bool = true) -> (high: [ApplicationResourceUsage], notify: [ApplicationResourceUsage]) {
        if let lastSample, now - lastSample > 12 || now < lastSample {
            highSince = [:]; previousUsage = [:]; burstSince = [:]
            memoryGrowthSince = [:]; memoryHistory = [:]; unresponsiveSince = [:]
        }
        lastSample = now
        let live = Set(usages.map(\.id))
        notifiedEpisodes.formIntersection(live)
        highSince = highSince.filter { live.contains($0.key) }
        burstSince = burstSince.filter { live.contains($0.key) }
        memoryGrowthSince = memoryGrowthSince.filter { live.contains($0.key) }
        memoryHistory = memoryHistory.filter { live.contains($0.key) }
        unresponsiveSince = unresponsiveSince.filter { live.contains($0.key) }
        defer { previousUsage = Dictionary(usages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
        lastAlert = lastAlert.filter { now >= $0.value && now - $0.value < cooldown }
        var high: [ApplicationResourceUsage] = [], notify: [ApplicationResourceUsage] = []
        for usage in usages {
            let cpuHigh = usage.cpuPercent.map { $0 >= cpuThreshold } ?? false
            if cpuHigh {
                if highSince[usage.id] == nil { highSince[usage.id] = now }
                if let old = previousUsage[usage.id]?.cpuPercent, let cpu = usage.cpuPercent,
                   cpu >= max(old * 2, old + cpuThreshold * 0.75), burstSince[usage.id] == nil {
                    burstSince[usage.id] = now
                }
            } else { highSince[usage.id] = nil; burstSince[usage.id] = nil }

            // 大型应用的稳定内存用量不等于异常；需超过阈值且在 90 秒内明显增长。
            var history = (memoryHistory[usage.id] ?? []).filter { now - $0.time <= 90 }
            let baseline = history.map(\.bytes).min()
            let growth = baseline.map { usage.memory > $0 && usage.memory - $0 >= max(1024 * 1024 * 1024, memoryThreshold / 4) } ?? false
            let memoryGrowing = usage.memory >= memoryThreshold && growth
            if memoryGrowing {
                if memoryGrowthSince[usage.id] == nil { memoryGrowthSince[usage.id] = now }
            } else { memoryGrowthSince[usage.id] = nil }
            history.append((now, usage.memory)); memoryHistory[usage.id] = history

            if usage.responsiveness == .unresponsive {
                if unresponsiveSince[usage.id] == nil { unresponsiveSince[usage.id] = now }
            } else { unresponsiveSince[usage.id] = nil }
            if !cpuHigh && !memoryGrowing && usage.responsiveness != .unresponsive { notifiedEpisodes.remove(usage.id) }
            let sustained = highSince[usage.id].map { now - $0 >= duration } ?? false
            let burst = burstSince[usage.id].map { now - $0 >= burstDuration } ?? false
            let growing = memoryGrowthSince[usage.id].map { now - $0 >= burstDuration } ?? false
            let stalled = unresponsiveSince[usage.id].map { now - $0 >= stallDuration } ?? false
            guard sustained || burst || growing || stalled else { continue }
            var entry = usage
            entry.alertReason = stalled ? "疑似无响应 · 连续响应超时" : growing ? "内存持续明显增长" : burst ? "CPU 突增且持续偏高" : "CPU 持续高占用"
            high.append(entry)
            if notificationsEnabled, lastAlert[usage.id] == nil, !notifiedEpisodes.contains(usage.id) {
                notify.append(entry); lastAlert[usage.id] = now; notifiedEpisodes.insert(usage.id)
            }
        }
        high.sort {
            if ($0.responsiveness == .unresponsive) != ($1.responsiveness == .unresponsive) { return $0.responsiveness == .unresponsive }
            return ($0.cpuPercent ?? 0) / cpuThreshold + Double($0.memory) / Double(memoryThreshold) > ($1.cpuPercent ?? 0) / cpuThreshold + Double($1.memory) / Double(memoryThreshold) }
        return (high, notify)
    }
}
