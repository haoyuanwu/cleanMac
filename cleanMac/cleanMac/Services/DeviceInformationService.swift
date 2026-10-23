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
    let network: [DeviceInfoField]
    let bluetooth: [DeviceInfoField]
    let connectedBluetoothDevices: [BluetoothConnectedDevice]
    let storage: [DeviceInfoField]
    let storageInfo: StorageInfo
    let storageUsedFraction: Double?
    let capturedAt: Date
}

struct BluetoothConnectedDevice: Identifiable, Sendable {
    let id: String
    let name: String
    let batteryLevel: Int?
    let isCharging: Bool?
    let isConnectedViaUSB: Bool

    var needsCharge: Bool { isCharging != true && !isConnectedViaUSB && (batteryLevel ?? 100) < 20 }

    var batteryDescription: String {
        let level = batteryLevel.map { "\($0)%" }
        if isCharging == true { return [level, "正在充电"].compactMap { $0 }.joined(separator: " · ") }
        if isConnectedViaUSB { return [level, "已连接电源"].compactMap { $0 }.joined(separator: " · ") }
        if let level { return needsCharge ? "\(level) · 请充电" : level }
        return "电量未提供"
    }
}

struct DeviceQuickStatus: Sendable {
    let deviceName: String
    let freeBytes: Int64
    let totalBytes: Int64
    let batteryLevel: Double?
    let batteryState: String
    let batteryFields: [DeviceInfoField]

    var chargingTimeEstimate: String? {
        guard batteryState == "正在充电" else { return nil }
        return batteryFields.first { $0.label == "充满还需" }?.value
    }
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
    nonisolated static func load(previous: DeviceInfoSnapshot? = nil) -> DeviceInfoSnapshot {
        let systemService = SystemInfoService()
        let identity = previous.map { (device: $0.device, software: $0.software) } ?? identityFields()
        let disk = systemService.getStorageInfo()
        let battery = batteryReading()
        let bluetooth = bluetoothReading()

        return DeviceInfoSnapshot(
            device: identity.device,
            software: identity.software.map {
                $0.label == "运行时间" ? DeviceInfoField(label: $0.label, value: systemService.getUptime()) : $0
            },
            battery: battery.fields,
            batteryLevel: battery.level,
            wifi: wifiFields(),
            network: networkFields(),
            bluetooth: bluetooth.fields,
            connectedBluetoothDevices: bluetooth.devices,
            storage: [
                .init(label: "磁盘卷", value: display(disk.volumeName)),
                .init(label: "总容量", value: disk.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: disk.totalBytes) : "未提供"),
                .init(label: "已使用", value: disk.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: disk.usedBytes) : "未提供"),
                .init(label: "可用空间", value: disk.totalBytes > 0 ? FileSizeFormatter.string(fromByteCount: disk.freeBytes) : "未提供")
            ],
            storageInfo: disk,
            storageUsedFraction: disk.totalBytes > 0 ? min(1, max(0, Double(disk.usedBytes) / Double(disk.totalBytes))) : nil,
            capturedAt: Date()
        )
    }

    /// 机型、芯片等静态信息只在首次采集时执行系统查询。
    nonisolated private static func identityFields() -> (device: [DeviceInfoField], software: [DeviceInfoField]) {
        let system = SystemInfoService().getSystemInfo()
        return (
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
            ]
        )
    }

    /// 网络接口概况（不含实时速率；速率由 NetworkSpeedMonitor 持续采样）
    nonisolated static func networkFields() -> [DeviceInfoField] {
        let counters = NetworkSpeedService.readCounters()
        return [
            .init(label: "累计下载", value: FileSizeFormatter.string(fromByteCount: Int64(counters.rx))),
            .init(label: "累计上传", value: FileSizeFormatter.string(fromByteCount: Int64(counters.tx))),
            .init(label: "采样说明", value: "实时上下行见下方速度表（每秒刷新）")
        ]
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
        guard let description = descriptions.first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }) else {
            return ([.init(label: "电池", value: "未检测到电池")], nil)
        }
        return batteryReading(description: description, details: batteryDetails() ?? [])
    }

    nonisolated private static func batteryReading(
        description: [String: Any], details: [DeviceInfoField]
    ) -> (fields: [DeviceInfoField], level: Double?) {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0 else {
            return ([.init(label: "电池", value: "未检测到电池")], nil)
        }

        let level = min(1, max(0, Double(current) / Double(maximum)))
        let percentage = Int((level * 100).rounded())
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
        let isAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let state = isCharging ? "正在充电" : (isAC ? (isCharged ? "已充满" : "已连接电源，未充电") : "使用电池")
        var fields: [DeviceInfoField] = [
            .init(label: "电量", value: "\(percentage)%"),
            .init(label: "状态", value: state),
            .init(label: "供电", value: isAC ? "电源适配器" : "电池")
        ]

        fields.append(contentsOf: details)

        let timeKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        if isCharging || !isAC {
            if let minutes = description[timeKey] as? Int, minutes > 0, minutes < 65535 {
                let duration = minutes < 60 ? "\(minutes) 分钟"
                    : minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分钟"
                fields.append(.init(label: isCharging ? "充满还需" : "预计剩余", value: "约 \(duration)"))
            } else if isCharging {
                fields.append(.init(label: "充满还需", value: "正在估算…"))
            }
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
        let batteryReadings = bluetoothBatteryReadings()
        let connected = paired.filter { device in
            device.isConnected() || device.addressString.flatMap {
                batteryReadings[normalizedAddress($0)]?.isConnectedViaUSB
            } == true
        }
        let devices = connected.enumerated().map { index, device in
            let address = device.addressString
            let reading = address.flatMap { batteryReadings[normalizedAddress($0)] }
            return BluetoothConnectedDevice(
                id: address ?? "device-\(index)",
                name: display(device.name),
                batteryLevel: reading?.level,
                isCharging: reading?.isCharging,
                isConnectedViaUSB: reading?.isConnectedViaUSB ?? false
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
    private struct BluetoothBatteryReading {
        var level: Int?
        var isCharging: Bool?
        var isConnectedViaUSB: Bool
    }

    nonisolated private static func bluetoothBatteryReadings() -> [String: BluetoothBatteryReading] {
        var readings: [String: BluetoothBatteryReading] = [:]
        for serviceClass in ["AppleDeviceManagementHIDEventService", "IOHIDDevice"] {
            guard let matching = IOServiceMatching(serviceClass) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let values = properties?.takeRetainedValue() as? [String: Any] else { continue }

                let level = (values["BatteryPercent"] as? Int).flatMap { (0...100).contains($0) ? $0 : nil }
                var charging = (values["IsCharging"] as? Bool)
                    ?? (values[kIOPSIsChargingKey] as? Bool)
                    ?? (values["BatteryIsCharging"] as? Bool)
                // Apple 外设的 HID 电池报告：已观测的 3 为充电，0 为未充电。
                // 不把未知标志位或单纯 USB 连接猜测为“正在充电”。
                if charging == nil, let vendor = values["VendorID"] as? Int,
                   [76, 1452].contains(vendor),
                   let flags = values["BatteryStatusFlags"] as? Int {
                    if flags == 3 { charging = true }
                    if flags == 0 { charging = false }
                }
                let wired = values["Transport"] as? String == "USB"
                guard level != nil || charging != nil else { continue }

                let address = (values["DeviceAddress"] as? String)
                    ?? (values["SerialNumber"] as? String)
                if let address {
                    let key = normalizedAddress(address)
                    if key.count == 12 {
                        let previous = readings[key]
                        // 优先使用 USB 报告，避免蓝牙旧记录覆盖插线后的充电状态。
                        if previous?.isConnectedViaUSB == true && !wired { continue }
                        readings[key] = BluetoothBatteryReading(
                            level: level ?? previous?.level,
                            isCharging: charging ?? previous?.isCharging,
                            isConnectedViaUSB: wired
                        )
                    }
                }
            }
        }
        return readings
    }
}

extension DeviceInfoSnapshot {
    var quickStatus: DeviceQuickStatus {
        func value(_ label: String, in fields: [DeviceInfoField]) -> String? {
            fields.first { $0.label == label }?.value
        }
        return DeviceQuickStatus(
            deviceName: value("设备名称", in: device) ?? "Mac",
            freeBytes: storageInfo.freeBytes,
            totalBytes: storageInfo.totalBytes,
            batteryLevel: batteryLevel,
            batteryState: value("状态", in: battery) ?? "未检测到电池",
            batteryFields: battery,
            wifiState: value("状态", in: wifi) ?? "未检测到",
            wifiName: value("网络名称", in: wifi).flatMap { $0 == "未提供" ? nil : $0 },
            bluetoothState: value("状态", in: bluetooth) ?? "未检测到",
            connectedBluetoothDevices: connectedBluetoothDevices,
            capturedAt: capturedAt
        )
    }
}
