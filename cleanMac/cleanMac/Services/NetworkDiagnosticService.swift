import Foundation
import Combine
import Network
import Darwin

nonisolated struct DiagnosticCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let succeeded: Bool?
}
nonisolated enum NetworkDiagnosticService {
    // 固定可执行文件与参数，超时后终止本次探测；不接受任意命令。
    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 5) -> (Int32, String) {
        if Task.isCancelled { return (-1, "已取消") }
        let task = Process(), output = Pipe()
        task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
        task.standardOutput = output; task.standardError = output
        do { try task.run() } catch { return (-1, error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline && !Task.isCancelled { Thread.sleep(forTimeInterval: 0.025) }
        if task.isRunning { task.terminate(); Thread.sleep(forTimeInterval: 0.05); if task.isRunning { kill(task.processIdentifier, SIGKILL) } }
        task.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (task.terminationStatus, String(text.prefix(12000)))
    }
    static func routing() -> [DiagnosticCheck] {
        let route = run("/sbin/route", ["-n", "get", "default"], timeout: 3)
        func field(_ key: String) -> String? {
            route.1.split(separator: "\n").compactMap { line -> String? in
                let pair = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return pair.count == 2 && pair[0] == key ? pair[1] : nil
            }.first
        }
        var checks = [DiagnosticCheck(id: "interface", title: "当前路由接口", detail: field("interface") ?? "未找到默认 IPv4 路由（可能仅使用 IPv6）", succeeded: nil)]
        if Task.isCancelled { return checks }
        if let gateway = field("gateway"), gateway.split(separator: ".").count == 4,
           gateway.allSatisfy({ $0.isNumber || $0 == "." }) {
            let ping = run("/sbin/ping", ["-n", "-c", "2", "-W", "1000", gateway], timeout: 4)
            let summary = ping.1.split(separator: "\n").last.map(String.init) ?? "未返回 ICMP 响应"
            checks.append(.init(id: "gateway", title: "网关响应", detail: ping.0 == 0 ? summary : "网关未响应 ICMP；设备可能禁用回应，不能据此判定断网。", succeeded: ping.0 == 0 ? true : nil))
        } else { checks.append(.init(id: "gateway", title: "网关响应", detail: "未取得可探测的 IPv4 网关", succeeded: nil)) }
        return checks
    }
    static func dns() -> DiagnosticCheck {
        let result = run("/usr/bin/dscacheutil", ["-q", "host", "-a", "name", "www.apple.com"], timeout: 5)
        let success = result.0 == 0 && (result.1.contains("ip_address:") || result.1.contains("ipv6_address:"))
        return .init(id: "dns", title: "DNS 名称解析", detail: success ? "www.apple.com 解析成功（可能命中系统缓存）" : "未取得解析结果；请检查 DNS 或网络连接。", succeeded: success)
    }
    static func external() async -> DiagnosticCheck {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5; config.timeoutIntervalForResource = 6
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
        request.httpMethod = "HEAD"; request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = ProcessInfo.processInfo.systemUptime
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
            return .init(id: "external", title: "外网 HTTPS 连通", detail: "Apple 测试端点 HTTP \(status) · 请求耗时 \(Int(ms)) ms（含连接与 TLS）", succeeded: (200..<400).contains(status))
        } catch {
            return .init(id: "external", title: "外网 HTTPS 连通", detail: Task.isCancelled ? "已取消" : "测试端点未完成连接：\(error.localizedDescription)", succeeded: Task.isCancelled ? nil : false)
        }
    }
}
@MainActor final class NetworkDiagnosticSession: ObservableObject {
    @Published private(set) var checks: [DiagnosticCheck] = []
    @Published private(set) var running = false
    @Published private(set) var completedAt: Date?
    private var work: Task<Void, Never>?
    private var generation = 0
    func start() {
        guard work == nil else { return }
        running = true; checks = []; completedAt = nil; let token = generation
        work = Task {
            let route = await ScanTask.run { NetworkDiagnosticService.routing() }
            guard !Task.isCancelled, token == generation else { return }; checks = route
            let dns = await ScanTask.run { NetworkDiagnosticService.dns() }
            guard !Task.isCancelled, token == generation else { return }; checks.append(dns)
            let external = await NetworkDiagnosticService.external()
            guard !Task.isCancelled, token == generation else { return }; checks.append(external)
            completedAt = Date(); running = false; work = nil
        }
    }
    func cancel() {
        generation += 1; work?.cancel(); work = nil; running = false
        checks.append(.init(id: "cancelled", title: "诊断已取消", detail: "以上可能仅为部分结果。", succeeded: nil))
    }
}
