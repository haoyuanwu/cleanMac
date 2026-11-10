import Foundation
import Security
import Darwin

final class MemoryHelper: NSObject, NSXPCListenerDelegate, MemoryHelperProtocol, @unchecked Sendable {
    private let team: String
    private let lock = NSLock()
    private var running = false
    init(team: String) { self.team = team }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        connection.setCodeSigningRequirement(MemoryHelperIdentity.requirement(identifier: MemoryHelperIdentity.client, team: team))
        connection.exportedInterface = NSXPCInterface(with: MemoryHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
    func ping(reply: @escaping () -> Void) { reply() }
    func purgeCaches(reply: @escaping (String?) -> Void) {
        lock.lock()
        guard !running else { lock.unlock(); reply("已有整理正在执行，请稍候。"); return }
        running = true
        lock.unlock()
        // 无命令、路径或参数输入；唯一能力是运行系统固定的 purge。
        DispatchQueue.global(qos: .utility).async { [self] in
            let error = Self.performPurge()
            lock.lock(); running = false; lock.unlock()
            reply(error)
        }
    }
    private static func performPurge() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
        process.arguments = []
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "无法启动系统缓存整理。" }
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            let stopDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < stopDeadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return "整理超时，未能确认完成。"
        }
        return process.terminationStatus == 0 ? nil : "系统缓存整理失败，请稍后重试。"
    }
}

guard getuid() == 0 else { NSLog("cleanMacMemoryHelper: refusing non-root launch"); exit(1) }
var executablePath = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
guard proc_pidpath(getpid(), &executablePath, UInt32(executablePath.count)) > 0 else {
    NSLog("cleanMacMemoryHelper: cannot resolve own executable"); exit(1)
}
let executableURL = URL(fileURLWithPath: String(cString: executablePath))
guard let identity = MemoryHelperIdentity.signature(at: executableURL), !identity.debuggable else {
    NSLog("cleanMacMemoryHelper: own code signature rejected"); exit(1)
}
let delegate = MemoryHelper(team: identity.team)
let listener = NSXPCListener(machServiceName: MemoryHelperIdentity.service)
listener.delegate = delegate
listener.resume()
dispatchMain()
