import Foundation
import CoreWLAN
import IOBluetooth
import IOKit
import IOKit.ps

struct DeviceInfoField: Sendable {
    let label: String
    let value: String
}

struct DeviceInfoSnapshot: Sendable {
    let device: [DeviceInfoField]
    let software: [DeviceInfoField]
    let battery: [DeviceInfoField]
    let batteryLevel: Double?
    let wifi: [DeviceInfoField]
    let bluetooth: [DeviceInfoField]
    let connectedBluetoothDevices: [BluetoothConnectedDevice]
    let storage: [DeviceInfoField]
    let storageUsedFraction: Double?
    let capturedAt: Date
}

struct BluetoothConnectedDevice: Identifiable, Sendable {
    let id: String
    let name: String
    let batteryLevel: Int?
}

struct DeviceQuickStatus: Sendable {
    let deviceName: String
    let freeBytes: Int64
    let totalBytes: Int64
    let batteryLevel: Double?
    let batteryState: String
    let wifiState: String
    let wifiName: String?
    let bluetoothState: String
    let connectedBluetoothDevices: [BluetoothConnectedDevice]
    let capturedAt: Date

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(totalBytes - freeBytes) / Double(totalBytes)))
    }
}

enum DeviceInformationService {
    /// 菜单栏只读取快速状态，避免每次展开都执行硬件报告命令。
    nonisolated static func quickStatus() -> DeviceQuickStatus {
        let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: FileManager.default.homeDirectoryForCurrentUser.path
        )
        let total = (attributes?[.systemSize] as? Int64) ?? 0
        let free = (attributes?[.systemFreeSize] as? Int64) ?? 0
        let battery = batteryReading()
        let wifi = wifiFields()
        let bluetooth = bluetoothReading()

        return DeviceQuickStatus(
            deviceName: ProcessInfo.processInfo.hostName,
            freeBytes: free,
            totalBytes: total,
            batteryLevel: battery.level,
            batteryState: fieldValue("状态", in: battery.fields) ?? "未检测到电池",
            wifiState: fieldValue("状态", in: wifi) ?? "未检测到",
            wifiName: fieldValue("网络名称", in: wifi).flatMap { $0 == "未提供" ? nil : $0 },
            bluetoothState: fieldValue("状态", in: bluetooth.fields) ?? "未检测到",
            connectedBluetoothDevices: bluetooth.devices,
            capturedAt: Date()
        )
    }

    nonisolated private static func fieldValue(_ label: String, in fields: [DeviceInfoField]) -> String? {
        fields.first(where: { $0.label == label })?.value
    }

    nonisolated static func load() -> DeviceInfoSnapshot {
        let systemService = SystemInfoService()
        let system = systemService.getSystemInfo()
        let disk = systemService.getStorageInfo()
        let battery = batteryReading()
        let bluetooth = bluetoothReading()

        return DeviceInfoSnapshot(
            device: [
                .init(label: "设备名称", value: display(system.hostname)),
                .init(label: "机型标识", value: display(system.model)),
                .init(label: "芯片", value: display(system.chip)),
                .init(label: "处理器核心", value: system.cpuCores > 0 ? "\(system.cpuCores) 核" : "未提供"),
                .init(label: "内存", value: display(system.memory)),
                .init(label: "序列号", value: display(system.serialNumber))
            ],
            software: [
                .init(label: "操作系统", value: "macOS \(display(system.macOSVersion))"),
                .init(label: "系统版本号", value: display(system.buildNumber)),
                .init(label: "运行时间", value: display(system.uptime)),
                .init(label: "当前软件", value: display(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)),
                .init(label: "软件版本", value: display(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)),
                .init(label: "软件构建号", value: display(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String))
            ],
            battery: battery.fields,
            batteryLevel: battery.level,
            wifi: wifiFields(),
            bluetooth: bluetooth.fields,
            connectedBluetoothDevices: bluetooth.devices,
            storage: [
                .init(label: "磁盘卷", value: display(disk.volumeName)),
                .init(label: "总容量", value: disk.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: disk.totalBytes) : "未提供"),
                .init(label: "已使用", value: disk.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: disk.usedBytes) : "未提供"),
                .init(label: "可用空间", value: disk.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: disk.freeBytes) : "未提供")
            ],
            storageUsedFraction: disk.totalBytes > 0 ? min(1, max(0, Double(disk.usedBytes) / Double(disk.totalBytes))) : nil,
            capturedAt: Date()
        )
    }

    nonisolated private static func display(_ value: String?) -> String {
        guard let value, !value.isEmpty, value != "Unknown" else { return "未提供" }
        return value
    }

    nonisolated private static func batteryReading() -> (fields: [DeviceInfoField], level: Double?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return ([.init(label: "电池", value: "未检测到电池")], nil)
        }
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [AnyObject]
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        guard let description = descriptions.first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }),
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0 else {
            return ([.init(label: "电池", value: "未检测到电池")], nil)
        }

        let level = min(1, max(0, Double(current) / Double(maximum)))
        let percentage = Int((level * 100).rounded())
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
        let isAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let state = isCharging ? "正在充电" : (isCharged ? "已充满" : (isAC ? "已连接电源" : "使用电池"))
        var fields: [DeviceInfoField] = [
            .init(label: "电量", value: "\(percentage)%"),
            .init(label: "状态", value: state),
            .init(label: "供电", value: isAC ? "电源适配器" : "电池")
        ]

        if let details = batteryDetails() {
            fields.append(contentsOf: details)
        }

        let timeKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        if let minutes = description[timeKey] as? Int, minutes > 0 {
            fields.append(.init(label: isCharging ? "充满还需" : "预计剩余", value: "\(minutes / 60) 小时 \(minutes % 60) 分钟"))
        }
        return (fields, level)
    }

    nonisolated private static func batteryDetails() -> [DeviceInfoField]? {
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = properties?.takeRetainedValue() as? [String: Any] else { return nil }

        var fields: [DeviceInfoField] = []
        if let cycles = values["CycleCount"] as? Int, cycles >= 0 {
            fields.append(.init(label: "循环次数", value: "\(cycles) 次"))
        }
        if let data = values["BatteryData"] as? [String: Any],
           let full = data["FullChargeCapacity"] as? Int,
           let design = data["DesignCapacity"] as? Int,
           full > 0, design > 0 {
            let percentage = Int((Double(full) / Double(design) * 100).rounded())
            fields.append(.init(label: "容量保持率（估算）", value: "\(percentage)%"))
        }
        return fields
    }

    nonisolated private static func wifiFields() -> [DeviceInfoField] {
        let client = CWWiFiClient.shared()
        let connectedInterface = client.interfaces()?.first(where: { $0.powerOn() && $0.ssid() != nil })
        guard let interface = connectedInterface ?? client.interface() else {
            return [.init(label: "Wi‑Fi", value: "未检测到无线网卡")]
        }
        let enabled = interface.powerOn()
        var fields: [DeviceInfoField] = [
            .init(label: "状态", value: enabled ? "已开启" : "已关闭"),
            .init(label: "接口", value: display(interface.interfaceName))
        ]
        guard enabled else { return fields }

        fields.append(.init(label: "网络名称", value: display(interface.ssid())))
        if let channel = interface.wlanChannel() {
            fields.append(.init(label: "信道", value: "\(channel.channelNumber)"))
        }
        let rssi = interface.rssiValue()
        if rssi < 0 { fields.append(.init(label: "信号强度", value: "\(rssi) dBm")) }
        let rate = interface.transmitRate()
        if rate > 0 { fields.append(.init(label: "连接速率", value: "\(Int(rate)) Mbps")) }
        return fields
    }

    nonisolated private static func bluetoothReading() -> (fields: [DeviceInfoField], devices: [BluetoothConnectedDevice]) {
        guard let controller = IOBluetoothHostController.default() else {
            return ([.init(label: "蓝牙", value: "未检测到控制器")], [])
        }
        let enabled = controller.powerState == kBluetoothHCIPowerStateON
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let connected = paired.filter { $0.isConnected() }
        let batteryLevels = bluetoothBatteryLevels()
        let devices = connected.enumerated().map { index, device in
            let address = device.addressString
            return BluetoothConnectedDevice(
                id: address ?? "device-\(index)",
                name: display(device.name),
                batteryLevel: address.flatMap { batteryLevels[normalizedAddress($0)] }
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let fields: [DeviceInfoField] = [
            .init(label: "状态", value: enabled ? "已开启" : "已关闭"),
            .init(label: "控制器", value: display(controller.nameAsString())),
            .init(label: "已配对设备", value: "\(paired.count) 台"),
            .init(label: "已连接设备", value: "\(devices.count) 台")
        ]
        return (fields, devices)
    }

    nonisolated private static func normalizedAddress(_ address: String) -> String {
        address.lowercased().filter { $0.isHexDigit }
    }

    /// 仅使用与蓝牙地址能精确匹配的 HID 电量，避免把别的设备电量错配过来。
    nonisolated private static func bluetoothBatteryLevels() -> [String: Int] {
        var levels: [String: Int] = [:]
        for serviceClass in ["AppleDeviceManagementHIDEventService", "IOHIDDevice"] {
            guard let matching = IOServiceMatching(serviceClass) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let values = properties?.takeRetainedValue() as? [String: Any],
                      let level = values["BatteryPercent"] as? Int,
                      (0...100).contains(level) else { continue }

                let address = (values["DeviceAddress"] as? String)
                    ?? (values["SerialNumber"] as? String)
                if let address {
                    let key = normalizedAddress(address)
                    if key.count == 12 { levels[key] = level }
                }
            }
        }
        return levels
    }
}
