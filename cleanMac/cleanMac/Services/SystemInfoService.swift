import Foundation
import SwiftUI

/// 系统信息服务 - 获取 Mac 硬件和存储信息
final class SystemInfoService: @unchecked Sendable {
    
    /// 获取系统信息
    nonisolated func getSystemInfo() -> SystemInfo {
        let model = run("sysctl -n hw.model")
        let chip = getChipName()
        let cpuCores = Int(run("sysctl -n hw.ncpu")) ?? 0
        let memoryBytes = Int64(run("sysctl -n hw.memsize")) ?? 0
        let memory = FileSizeFormatter.string(fromByteCount: memoryBytes)
        let macOSVersion = run("sw_vers -productVersion")
        let buildNumber = run("sw_vers -buildVersion")
        let hostname = run("hostname -s")
        let serialNumber = getSerialNumber()
        let uptime = getUptime()
        
        return SystemInfo(
            model: model,
            chip: chip,
            cpuCores: cpuCores,
            memory: memory,
            macOSVersion: macOSVersion,
            buildNumber: buildNumber,
            hostname: hostname,
            serialNumber: serialNumber,
            uptime: uptime
        )
    }
    
    /// 获取存储信息
    nonisolated func getStorageInfo() -> StorageInfo {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        
        let totalBytes: Int64
        let freeBytes: Int64
        
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: homeDir.path) {
            totalBytes = (attrs[.systemSize] as? Int64) ?? 0
            freeBytes = (attrs[.systemFreeSize] as? Int64) ?? 0
        } else {
            totalBytes = 0
            freeBytes = 0
        }
        
        let usedBytes = max(0, totalBytes - freeBytes)
        let volumeName = run("diskutil info / | grep 'Volume Name' | sed 's/.*:\\s*//'").trimmingCharacters(in: .whitespaces)
        
        return StorageInfo(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            freeBytes: freeBytes,
            volumeName: volumeName.isEmpty ? "Macintosh HD" : volumeName
        )
    }
    
    /// 获取主要存储分类占用（通过 mdls 和 du 估算）
    nonisolated func getStorageBreakdown(usedBytes: Int64) -> [StorageCategory] {
        guard usedBytes > 0 else { return [] }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var categories: [StorageCategory] = []
        
        // 应用程序
        let appsSize = directorySize("/Applications")
        categories.append(StorageCategory(name: "应用程序", size: appsSize, color: .cyan, icon: "app.fill"))
        
        // 系统数据
        let systemSize = directorySize("/System") + directorySize("/Library")
        categories.append(StorageCategory(name: "系统数据", size: systemSize, color: .indigo, icon: "gearshape.fill"))
        
        // 文档
        let docsSize = directorySize("\(home)/Documents")
        categories.append(StorageCategory(name: "文档", size: docsSize, color: .orange, icon: "doc.fill"))
        
        // 下载
        let downloadsSize = directorySize("\(home)/Downloads")
        categories.append(StorageCategory(name: "下载", size: downloadsSize, color: .green, icon: "arrow.down.circle.fill"))
        
        // 影音
        let mediaSize = directorySize("\(home)/Movies") + directorySize("\(home)/Music")
        categories.append(StorageCategory(name: "影音", size: mediaSize, color: .purple, icon: "film.fill"))
        
        // 图片
        let photosSize = directorySize("\(home)/Pictures")
        categories.append(StorageCategory(name: "图片", size: photosSize, color: .pink, icon: "photo.fill"))
        
        // 其他
        // 目录大小是估算值，可能因 APFS 共享数据而超过实际已用量。
        // 超出时按比例校准，确保分类之和始终与系统已用量一致。
        let knownSize = categories.reduce(Int64(0)) { $0 + $1.size }
        if knownSize > usedBytes, usedBytes > 0 {
            let scale = Double(usedBytes) / Double(knownSize)
            categories = categories.map { category in
                StorageCategory(
                    name: category.name,
                    size: Int64(Double(category.size) * scale),
                    color: category.color,
                    icon: category.icon
                )
            }
            let roundingRemainder = usedBytes - categories.reduce(Int64(0)) { $0 + $1.size }
            if roundingRemainder > 0,
               let largestIndex = categories.indices.max(by: { categories[$0].size < categories[$1].size }) {
                let category = categories[largestIndex]
                categories[largestIndex] = StorageCategory(
                    name: category.name,
                    size: category.size + roundingRemainder,
                    color: category.color,
                    icon: category.icon
                )
            }
        }
        let adjustedKnownSize = categories.reduce(Int64(0)) { $0 + $1.size }
        let otherSize = max(0, usedBytes - adjustedKnownSize)
        if otherSize > 0 {
            categories.append(StorageCategory(name: "其他", size: otherSize, color: .gray, icon: "ellipsis.circle.fill"))
        }
        
        return categories.sorted { $0.size > $1.size }
    }
    
    // MARK: - Private
    
    nonisolated private func getChipName() -> String {
        let brand = run("sysctl -n machdep.cpu.brand_string")
        // 如果是 Apple Silicon，从 sysctl 获取
        if brand.contains("Apple") { return brand }
        // Intel Mac
        return brand.isEmpty ? "Unknown" : brand
    }
    
    nonisolated private func getSerialNumber() -> String {
        return run("system_profiler SPHardwareDataType | grep 'Serial' | awk '{print $NF}'")
    }
    
    nonisolated private func getUptime() -> String {
        let uptimeSeconds = ProcessInfo.processInfo.systemUptime
        let days = Int(uptimeSeconds) / 86400
        let hours = (Int(uptimeSeconds) % 86400) / 3600
        let minutes = (Int(uptimeSeconds) % 3600) / 60
        
        var parts: [String] = []
        if days > 0 { parts.append("\(days) 天") }
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 && days == 0 { parts.append("\(minutes) 分钟") }
        
        return parts.isEmpty ? "刚刚启动" : parts.joined(separator: " ")
    }
    
    nonisolated private func directorySize(_ path: String) -> Int64 {
        FileHelper.directorySize(path)
    }
    
    @discardableResult
    nonisolated private func run(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
