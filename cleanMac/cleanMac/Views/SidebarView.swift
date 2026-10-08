import SwiftUI

/// 侧边栏视图
struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var selectedTab: SidebarTab
    
    enum SidebarTab: String, CaseIterable, Hashable, Identifiable {
        case dashboard = "概览"
        case category = "分类"
        case diskMap = "磁盘地图"
        case whitelist = "白名单"
        case xcode = "Xcode 分析"
        case settings = "设置"

        var id: String { rawValue }
    }
    
    var body: some View {
        List {
            Section("主页") {
                SidebarRow(
                    title: "概览",
                    icon: "SidebarOverview",
                    iconColor: .blue,
                    isSelected: selectedTab == .dashboard
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .dashboard
                    }
                }
            }

            Section("清理类别") {
                ForEach(ScanCategory.allCases) { category in
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

            Section("开发工具") {
                SidebarRow(
                    title: "磁盘地图",
                    icon: "SFSymbol:square.grid.3x3.topleft.filled",
                    iconColor: .purple,
                    isSelected: selectedTab == .diskMap
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .diskMap
                    }
                }

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
                    title: "Xcode 分析",
                    icon: "SidebarXcode",
                    iconColor: .indigo,
                    isSelected: selectedTab == .xcode
                )
                .onTapGesture {
                    withAnimation(Theme.spring) {
                        selectedTab = .xcode
                    }
                }
            }

            Section("偏好设置") {
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
}

// MARK: - 通用侧边栏行
struct SidebarRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    let isSelected: Bool

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
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))

            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? iconColor.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - 类别侧边栏行
struct CategorySidebarRow: View {
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
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? category.color : .primary)

                if let result = result {
                    Text(result.error != nil
                         ? (result.items.isEmpty ? "需要授权访问" : "部分内容无法读取")
                         : "\(result.itemCount) 个\(category.itemUnit) · \(result.totalSizeFormatted)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if result?.isScanning == true {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.accentColor)
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
                    .foregroundColor(category.color)
                    .background(category.color.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? category.color.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
