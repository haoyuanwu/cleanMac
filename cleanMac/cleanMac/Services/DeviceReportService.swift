import AppKit
import CoreGraphics
import UniformTypeIdentifiers

@MainActor enum DeviceReportService {
    static func displays() -> [DisplayDeviceInfo] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let mode = CGDisplayCopyDisplayMode(id) else { return nil }
            return .init(id: id, name: screen.localizedName, logicalWidth: mode.width, logicalHeight: mode.height,
                         pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                         refreshRate: mode.refreshRate > 0 ? mode.refreshRate : nil, builtIn: CGDisplayIsBuiltin(id) != 0)
        }
    }
    static func report(_ snapshot: DeviceInfoSnapshot) -> String {
        let allowed = Set(["机型标识", "芯片", "处理器核心", "内存", "操作系统", "系统版本号", "运行时间", "软件版本", "软件构建号"])
        let identity = (snapshot.device + snapshot.software).filter { allowed.contains($0.label) }.map { ($0.label, $0.value) }
        var sections: [(String, [(String, String)])] = [("系统档案", identity), ("电源", snapshot.battery.map { ($0.label, $0.value) }),
            ("存储容量", snapshot.storage.filter { $0.label != "磁盘卷" }.map { ($0.label, $0.value) })]
        for (index, display) in displays().enumerated() {
            sections.append(("显示器 \(index + 1)", [("类型", display.builtIn ? "内置" : "外接"),
                ("逻辑分辨率", "\(display.logicalWidth) × \(display.logicalHeight)"),
                ("像素分辨率", "\(display.pixelWidth) × \(display.pixelHeight)"),
                ("刷新率", display.refreshRate.map { String(format: "%.1f Hz", $0) } ?? "系统未提供固定值")]))
        }
        return DeviceReportRedactor.render(sections: sections, date: Date())
    }
    static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    static func export(_ text: String) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "cleanMac-设备报告.txt"; panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { try text.write(to: url, atomically: true, encoding: .utf8); return "报告已保存" }
        catch { return "保存失败：\(error.localizedDescription)" }
    }
}
