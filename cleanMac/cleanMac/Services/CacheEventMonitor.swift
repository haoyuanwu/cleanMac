import Foundation
import CoreServices

nonisolated struct CacheEventToken: Codable, Equatable, Sendable {
    let session: UUID
    let epoch: UInt64
    let revision: UInt64
    let available: Bool
}

/// 仅监视变化，不安装服务。重新启动后不信任跨会话事件间隙。
final class CacheEventMonitor: @unchecked Sendable {
    nonisolated static let shared = CacheEventMonitor()
    nonisolated private let lock = NSLock()
    nonisolated private let session = UUID()
    nonisolated private let queue = DispatchQueue(label: "cleanMac.cacheEvents")
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    nonisolated(unsafe) private var epoch: UInt64 = 0
    nonisolated(unsafe) private var revisions: [String: UInt64] = [:]

    nonisolated private init() {
        let roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path, "/Library/Caches", "/Library/Application Support", "/Library/Containers", "/Library/Group Containers"]
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let monitor = Unmanaged<CacheEventMonitor>.fromOpaque(info).takeUnretainedValue()
            let names = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let lossMask = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
            let lost = names.count != count || (0..<count).contains { flags[$0] & lossMask != 0 }
            monitor.record(paths: names, eventLoss: lost)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        if let stream = FSEventStreamCreate(nil, callback, &context, roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags) {
            FSEventStreamSetDispatchQueue(stream, queue)
            if FSEventStreamStart(stream) { self.stream = stream }
            else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        }
    }
    nonisolated func record(paths: [String], eventLoss: Bool) {
        lock.lock(); defer { lock.unlock() }
        if eventLoss { epoch &+= 1 }
        for root in Array(revisions.keys) where paths.contains(where: { $0 == root || $0.hasPrefix(root + "/") || root.hasPrefix($0 + "/") }) {
            revisions[root, default: 0] &+= 1
        }
    }
    nonisolated func invalidateAll() {
        lock.lock(); epoch &+= 1; lock.unlock()
    }
    nonisolated func token(for root: String) -> CacheEventToken {
        // FlushSync 不持有锁，回调可安全更新版本。
        if let stream { FSEventStreamFlushSync(stream) }
        lock.lock(); defer { lock.unlock() }
        if revisions[root] == nil { revisions[root] = 0 }
        return CacheEventToken(session: session, epoch: epoch, revision: revisions[root] ?? 0, available: stream != nil)
    }
}
