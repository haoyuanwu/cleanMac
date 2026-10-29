import SwiftUI

/// 固定图标导航栏，分类功能由右侧卡片页承载。
struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    let xcodeIsScanning: Bool
    let diskMapIsLoading: Bool
    let selectedGroup: WorkspaceGroup
    let onSelect: (WorkspaceGroup) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedGroup: WorkspaceGroup?

    enum SidebarTab: String, CaseIterable, Hashable, Identifiable {
        case dashboard = "一键清理"
        case deviceInfo = "设备信息"
        case category = "分类"
        case diskMap = "磁盘地图"
        case duplicates = "重复文件"
        case timeline = "占用变化"
        case whitelist = "白名单"
        case xcode = "Xcode 分析"
        case settings = "设置"
        case startup = "启动项检查"
        case privacy = "浏览器隐私"
        case extensions = "扩展与插件"
        case insights = "空间建议"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 18) {
            navigationButton(.overview, shortcut: 1)
                .padding(.top, 16)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(Array(WorkspaceGroup.allCases.filter { $0 != .overview }.enumerated()), id: \.element) { index, group in
                        navigationButton(group, shortcut: index + 2)
                    }
                }
                .padding(.vertical, 6)
            }
            Spacer(minLength: 0)
            Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .frame(width: 80)
        .backgroundPreferenceValue(SidebarButtonBoundsKey.self) { bounds in
            GeometryReader { geometry in
                if let anchor = bounds[selectedGroup] {
                    let frame = geometry[anchor]
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Theme.accentGradient)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.88), value: selectedGroup)
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }

    }

    private func navigationButton(_ group: WorkspaceGroup, shortcut: Int) -> some View {
        Button { onSelect(group) } label: {
            ZStack {
                Image(systemName: group.symbol)
                    .font(.system(size: 21, weight: selectedGroup == group ? .semibold : .medium))
                    .foregroundStyle(selectedGroup == group ? Color.white : Color.primary)
            }
            .frame(width: 48, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 15))
            .overlay(alignment: .topTrailing) {
                if isScanning(group) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.canvas, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(WorkspacePressStyle())
        .focused($focusedGroup, equals: group)
        .overlay(RoundedRectangle(cornerRadius: 15)
            .strokeBorder(focusedGroup == group ? Color.accentColor : .clear, lineWidth: 2))
        .keyboardShortcut(KeyEquivalent(Character(String(shortcut))), modifiers: .command)
        .help("\(group.rawValue)（⌘\(shortcut)）")
        .accessibilityLabel(group.rawValue)
        .accessibilityValue(isScanning(group) ? "正在扫描" : "")
        .accessibilityAddTraits(selectedGroup == group ? .isSelected : [])
        .anchorPreference(key: SidebarButtonBoundsKey.self, value: .bounds) { [group: $0] }
    }

    private func isScanning(_ group: WorkspaceGroup) -> Bool {
        if group == .overview { return viewModel.isScanning || viewModel.isCleaning }
        if group == .applications { return xcodeIsScanning || viewModel.scanResults[.applications]?.isScanning == true }
        if group == .storage { return diskMapIsLoading }
        return group.destinations.contains { destination in
            guard case let .category(category) = destination else { return false }
            return viewModel.scanResults[category]?.isScanning == true
        }
    }
}


/// 在同一坐标系中定位所有图标，选中背景不随按钮跨越滚动视图的裁切层。
private struct SidebarButtonBoundsKey: PreferenceKey {
    static let defaultValue: [WorkspaceGroup: Anchor<CGRect>] = [:]
    static func reduce(value: inout [WorkspaceGroup: Anchor<CGRect>], nextValue: () -> [WorkspaceGroup: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
