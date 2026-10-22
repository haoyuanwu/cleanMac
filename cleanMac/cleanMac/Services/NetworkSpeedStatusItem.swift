import AppKit
import Combine

/// 用原生状态项承载高频数值，避免实时数据触发 SwiftUI 场景重建。
@MainActor
final class NetworkSpeedStatusItem: NSObject {
    static let shared = NetworkSpeedStatusItem()
    private var item: NSStatusItem?
    private var speedView: MenuBarSpeedTextView?
    private var preferencesSubscription: AnyCancellable?
    private var speedSubscription: AnyCancellable?

    func start() {
        guard preferencesSubscription == nil else { return }
        preferencesSubscription = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateVisibility() }
        updateVisibility()
    }

    private func updateVisibility() {
        let enabled = UserDefaults.standard.bool(forKey: "com.cleanMac.showMenuBarNetworkSpeed")
        guard enabled else {
            guard let item else { return }
            speedSubscription = nil
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            speedView = nil
            NetworkSpeedMonitor.shared.release("menuBar")
            return
        }
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: 88)
        self.item = item
        item.button?.target = self
        item.button?.action = #selector(openMainWindow)
        if let button = item.button {
            button.title = ""
            let view = MenuBarSpeedTextView(frame: button.bounds)
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
            speedView = view
        }
        speedSubscription = NetworkSpeedMonitor.shared.$throughput
            .sink { [weak self] value in self?.render(value) }
        NetworkSpeedMonitor.shared.acquire("menuBar")
    }

    private func render(_ value: NetworkThroughput) {
        guard let button = item?.button else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.minimumLineHeight = 10
        paragraph.maximumLineHeight = 10
        speedView?.text = NSAttributedString(
            string: "↓ \(value.downloadText)\n↑ \(value.uploadText)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        button.toolTip = "下载 \(value.downloadText) · 上传 \(value.uploadText)（每秒刷新）"
        button.setAccessibilityLabel("下载 \(value.downloadText)，上传 \(value.uploadText)")
    }

    @objc private func openMainWindow() {
        AppActionCoordinator.shared.requestMainWindow()
    }
}

/// 使用实际文字高度居中，避开 NSButton 多行标题的顶部基线偏移。
private final class MenuBarSpeedTextView: NSView {
    var text = NSAttributedString() {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let width = max(0, bounds.width - 12)
        let measured = text.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let height = ceil(measured.height)
        // 翻转坐标下向下微调 1pt，让两行文字的视觉中心与邻近图标一致。
        let y = max(0, (bounds.height - height) / 2 + 1)
        text.draw(with: NSRect(x: 6, y: y, width: width, height: height),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
