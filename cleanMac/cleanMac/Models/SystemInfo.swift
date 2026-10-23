import Foundation
import SwiftUI

/// 系统信息模型
struct SystemInfo {
    let model: String           // MacBook Pro 16-inch, 2023
    let chip: String            // Apple M2 Pro
    let cpuCores: Int           // 12
    let memory: String          // 32 GB
    let macOSVersion: String    // 15.0
    let buildNumber: String     // 24A5331b
    let hostname: String        // MacBook-Pro
    let serialNumber: String    // C02X12345678
    let uptime: String          // 3 天 12 小时
}

/// 存储信息模型
struct StorageInfo: Sendable {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
    let volumeName: String
    
    var totalFormatted: String { FileSizeFormatter.string(fromByteCount: totalBytes) }
    var usedFormatted: String { FileSizeFormatter.string(fromByteCount: usedBytes) }
    var freeFormatted: String { FileSizeFormatter.string(fromByteCount: freeBytes) }
    
    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

/// 存储分类
struct StorageCategory: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let color: Color
    let icon: String
    
    var sizeFormatted: String { FileSizeFormatter.string(fromByteCount: size) }
}
