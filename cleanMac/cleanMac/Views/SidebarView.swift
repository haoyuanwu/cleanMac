import SwiftUI

/// 侧边栏视图
struct SidebarView: View {
    @ObservedObject var viewModel: MainViewModel
    @Binding var selectedTab: SidebarTab
    
    enum SidebarTab: String, CaseIterable, Hashable, Identifiable {
        case dashboard = "概览"
        case category = "分类"
        case xcode = "Xcode 分析"
        case settings = "设置"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        List {
            Section("主页") {
                SidebarRow(
                    title: "概览",
                    icon: "chart.pie.fill",
                    iconColor: .blue,
                    isSelected: selectedTab == .dashboard
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
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
                        withAnimation(.spring(response: 0.3)) {
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
                        .disabled(viewModel.isScanning)
                        
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
                    title: "Xcode 分析",
                    icon: "hammer.fill",
                    iconColor: .blue,
                    isSelected: selectedTab == .xcode
                )
                .onTapGesture {
                    selectedTab = .xcode
                }
            }

            Section("偏好设置") {
                SidebarRow(
                    title: "设置",
                    icon: "gearshape.fill",
                    iconColor: .gray,
                    isSelected: selectedTab == .settings
                )
                .onTapGesture {
                    selectedTab = .settings
                }
            }
            
            // 底部信息
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("cleanMac v1.0")
                            .font(.system(size: 11))
                    }
                    Text("专业的 Mac 系统清理工具")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
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
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : iconColor)
                .frame(width: 26, height: 26)
                .background(isSelected ? iconColor : iconColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? iconColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            Image(systemName: category.icon)
                .font(.system(size: 14))
                .foregroundColor(category.color)
                .frame(width: 26, height: 26)
                .background(category.color.opacity(isSelected ? 0.2 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? category.color : .primary)
                
                if let result = result {
                    Text(result.error != nil
                         ? (result.items.isEmpty ? "需要授权访问" : "部分内容无法读取")
                         : "\(result.itemCount) 个\(category.itemUnit) · \(result.totalSizeFormatted)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if result?.isScanning == true {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.accentColor)
            } else if result?.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            } else if result?.isCleaned == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
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
