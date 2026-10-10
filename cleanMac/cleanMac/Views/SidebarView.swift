import SwiftUI

/// 侧边栏视图
struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    let xcodeIsScanning: Bool
    let diskMapIsLoading: Bool
    @Binding var selectedTab: SidebarTab
    
    enum SidebarTab: String, CaseIterable, Hashable, Identifiable {
        case dashboard = "概览"
        case deviceInfo = "设备信息"
        case category = "分类"
        case diskMap = "磁盘地图"
        case duplicates = "重复文件"
        case timeline = "占用变化"
        case whitelist = "白名单"
        case xcode = "Xcode 分析"
        case settings = "设置"

        var id: String { rawValue }
    }
    
    var body: some View {
        List {
            Section("总览") {
                SidebarRow(
                    title: "概览",
                    icon: "SidebarOverview",
                    iconColor: .blue,
                    isSelected: selectedTab == .dashboard,
                    isScanning: viewModel.isScanning
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .dashboard
                    }
                }

                SidebarRow(
                    title: "设备信息",
                    icon: "SidebarInfo",
                    iconColor: .cyan,
                    isSelected: selectedTab == .deviceInfo
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .deviceInfo
                    }
                }
            }

            Section("垃圾清理") {
                ForEach([ScanCategory.systemCache, .browserCache, .logFiles, .appLeftover, .trash]) { category in
                    categoryRow(category)
                }
            }

            Section("文件整理") {
                ForEach([ScanCategory.downloads, .largeFiles, .installers]) { category in
                    categoryRow(category)
                }

                SidebarRow(
                    title: "重复文件",
                    icon: "SFSymbol:doc.on.doc.fill",
                    iconColor: .orange,
                    isSelected: selectedTab == .duplicates
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .duplicates
                    }
                }
            }

            Section("应用与开发") {
                categoryRow(.applications)

                SidebarRow(
                    title: "Xcode 分析",
                    icon: "SidebarXcode",
                    iconColor: .indigo,
                    isSelected: selectedTab == .xcode,
                    isScanning: xcodeIsScanning
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .xcode
                    }
                }
            }

            Section("磁盘分析") {
                SidebarRow(
                    title: "磁盘地图",
                    icon: "SFSymbol:square.grid.3x3.topleft.filled",
                    iconColor: .purple,
                    isSelected: selectedTab == .diskMap,
                    isScanning: diskMapIsLoading
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .diskMap
                    }
                }

                SidebarRow(
                    title: "占用变化",
                    icon: "SFSymbol:chart.line.uptrend.xyaxis",
                    iconColor: .blue,
                    isSelected: selectedTab == .timeline
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .timeline
                    }
                }
            }

            Section("偏好与保护") {
                SidebarRow(
                    title: "白名单",
                    icon: "SFSymbol:shield.lefthalf.filled",
                    iconColor: .green,
                    isSelected: selectedTab == .whitelist
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .whitelist
                    }
                }

                SidebarRow(
                    title: "设置",
                    icon: "SidebarSettings",
                    iconColor: .gray,
                    isSelected: selectedTab == .settings
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .settings
                    }
                }
            }

            // 底部仅显示版本
            Section {
                HStack {
                    Text("cleanMac v1.0")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.85))
                    Spacer()
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebarGradient.ignoresSafeArea())
        .frame(minWidth: 200, idealWidth: 232, maxWidth: 260)
    }

    private func categoryRow(_ category: ScanCategory) -> some View {
        CategorySidebarRow(
            category: category,
            result: viewModel.scanResults[category],
            isSelected: selectedTab == .category && viewModel.selectedCategory == category
        )
        .onTapGesture {
            withAnimation(Theme.spring) {
                viewModel.selectedCategory = category
                selectedTab = .category
            }
        }
        .contextMenu {
            Button {
                Task { await viewModel.scanCategory(category) }
            } label: {
                Label("扫描", systemImage: "magnifyingglass")
            }
            .disabled(viewModel.scanResults[category]?.isScanning == true)

            Button {
                if category == .trash {
                    viewModel.selectedCategory = .trash
                    selectedTab = .category
                } else if category == .applications {
                    viewModel.requestDeleteFiles(viewModel.scanResults[category]?.items ?? [], from: category)
                } else {
                    Task { await viewModel.cleanCategory(category) }
                }
            } label: {
                Label(category == .trash ? "查看并清空废纸篓" : (category == .applications ? "卸载" : "清理"), systemImage: "trash")
            }
            .disabled(viewModel.isScanning || viewModel.scanResults[category]?.items.isEmpty != false)
        }
    }
}

// MARK: - 通用侧边栏行
struct SidebarRow: View {
    @Environment(\.controlActiveState) private var controlActiveState
    let title: String
    let icon: String
    let iconColor: Color
    let isSelected: Bool
    var isScanning = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                .frame(width: 3, height: 18)

            Group {
                if icon.hasPrefix("SFSymbol:") {
                    Image(systemName: String(icon.dropFirst("SFSymbol:".count)))
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                }
            }
            .foregroundColor(isSelected ? .white : iconColor)
            .frame(width: 15, height: 15)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? iconColor : iconColor.opacity(0.12))
            )
            .overlay(alignment: .topTrailing) {
                if isScanning {
                    SidebarScanBadge(color: iconColor)
                        .offset(x: 5, y: -5)
                }
            }
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(controlActiveState == .inactive ? .secondary : .primary)

            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? iconColor.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityValue(isScanning ? "正在扫描" : "")
    }
}

// MARK: - 类别侧边栏行
struct CategorySidebarRow: View {
    @Environment(\.controlActiveState) private var controlActiveState
    let category: ScanCategory
    let result: ScanResult?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? AnyShapeStyle(category.color) : AnyShapeStyle(Color.clear))
                .frame(width: 3, height: 20)

            Image(category.iconAsset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(isSelected ? .white : category.color)
                .frame(width: 15, height: 15)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(category.color.opacity(isSelected ? 0.95 : 0.12))
                )
                .overlay(alignment: .topTrailing) {
                    if result?.isScanning == true {
                        SidebarScanBadge(color: category.color)
                            .offset(x: 5, y: -5)
                    }
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(controlActiveState == .inactive
                                     ? .secondary
                                     : (isSelected ? category.color : .primary))

                if let result = result {
                    Text(result.isScanning
                         ? "正在扫描…"
                         : result.error != nil
                         ? (result.items.isEmpty ? "需要授权访问" : "部分内容无法读取")
                         : "\(result.itemCount) 个\(category.itemUnit) · \(result.totalSizeFormatted)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if result?.isScanning == true {
                Text("扫描中")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(controlActiveState == .inactive ? .secondary : category.color)
            } else if result?.error != nil {
                Image("SidebarWarning")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundColor(.orange)
                    .accessibilityLabel("需要注意")
            } else if result?.isCleaned == true {
                Image("SidebarCleaned")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundColor(.green)
                    .accessibilityLabel("已清理")
            } else if let count = result?.itemCount, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundColor(controlActiveState == .inactive ? .secondary : category.color)
                    .background(category.color.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? category.color.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityValue(result?.isScanning == true ? "正在扫描" : "")
    }
}

private struct SidebarScanBadge: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                badge(rotation: 0)
            } else {
                TimelineView(.animation) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.2) / 1.2
                    badge(rotation: phase * 360)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func badge(rotation: Double) -> some View {
        Image(systemName: "arrow.2.circlepath")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .rotationEffect(.degrees(rotation))
            .frame(width: 16, height: 16)
            .background(color, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
    }
}
