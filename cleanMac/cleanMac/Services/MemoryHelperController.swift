import Foundation
import Combine
import ServiceManagement

@MainActor
final class MemoryHelperController: ObservableObject {
    static let shared = MemoryHelperController()
    @Published private(set) var statusText = "尚未授权"
    private var service: SMAppService { .daemon(plistName: MemoryHelperIdentity.plist) }

    func prepare() -> String? {
        guard let app = MemoryHelperIdentity.signature(), !app.debuggable else {
            return "后台整理需要已签名且未启用调试授权的版本。请在 Xcode 使用 Release 配置运行后申请授权。"
        }
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/cleanMacMemoryHelper")
        guard let helper = MemoryHelperIdentity.signature(at: executable), helper.team == app.team, !helper.debuggable else {
            return "辅助服务缺失或签名不匹配，请重新构建应用。"
        }
        do {
            if service.status == .notRegistered || service.status == .notFound { try service.register() }
            refreshStatus()
            switch service.status {
            case .enabled: return nil
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
                return "已申请后台辅助服务，请在系统设置的登录项与后台活动中批准 cleanMac，完成后再次点击整理。"
            default: return "后台辅助服务尚未启用，请检查系统设置。"
            }
        } catch {
            refreshStatus()
            return "辅助服务授权申请未完成：" + error.localizedDescription
        }
    }
    func refreshStatus() {
        switch service.status {
        case .enabled: statusText = "后台整理已授权"
        case .requiresApproval: statusText = "等待系统批准"
        case .notRegistered: statusText = "尚未授权"
        case .notFound: statusText = "辅助服务未就绪"
        @unknown default: statusText = "授权状态未知"
        }
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
    func unregister() async -> String {
        do { try await service.unregister(); refreshStatus(); return "后台辅助服务已移除。" }
        catch { refreshStatus(); return "未能移除辅助服务：" + error.localizedDescription }
    }
}

/// 只在后台线程等待，连接双方都绑定签名身份；超时和错误只完成一次。
nonisolated enum MemoryHelperClient {
    private final class Reply: @unchecked Sendable {
        let lock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)
        private var finished = false
        private var result: String? = "辅助服务连接未完成。"
        func complete(_ message: String?) {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            finished = true; result = message; semaphore.signal()
        }
        func value() -> String? { lock.lock(); defer { lock.unlock() }; return result }
    }
    static func purgeCaches() -> String? {
        guard let identity = MemoryHelperIdentity.signature(), !identity.debuggable else { return "当前签名不允许调用后台整理服务。" }
        let result = Reply()
        let handshake = Reply()
        let connection = NSXPCConnection(machServiceName: MemoryHelperIdentity.service, options: .privileged)
        connection.setCodeSigningRequirement(MemoryHelperIdentity.requirement(identifier: MemoryHelperIdentity.service, team: identity.team))
        connection.remoteObjectInterface = NSXPCInterface(with: MemoryHelperProtocol.self)
        connection.invalidationHandler = { handshake.complete("后台服务未能启动。"); result.complete("后台服务连接已断开，请检查授权或重新申请。") }
        connection.interruptionHandler = { handshake.complete("后台服务连接中断。"); result.complete("后台服务连接中断，未确认整理完成。") }
        connection.resume()
        defer { connection.invalidate() }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
            handshake.complete("无法连接后台整理服务，请检查签名和系统授权。")
            result.complete("无法连接后台整理服务，请检查签名和系统授权。")
        }) as? MemoryHelperProtocol else { return "无法创建后台整理请求。" }
        proxy.ping { handshake.complete(nil) }
        guard handshake.semaphore.wait(timeout: .now() + 5) == .success else {
            return "后台服务已授权但未能启动，请在设置中移除后重新申请。"
        }
        if let error = handshake.value() { return error }
        proxy.purgeCaches { result.complete($0) }
        if result.semaphore.wait(timeout: .now() + 125) == .timedOut { result.complete("后台整理等待超时，未确认完成。") }
        return result.value()
    }
}
