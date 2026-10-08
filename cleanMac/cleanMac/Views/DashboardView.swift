import SwiftUI

/// 概览仪表盘 - 系统信息 + 存储信息 + 开始扫描
struct DashboardView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 扫描按钮（融合进度）
                scanButtonCard
                
                // 系统信息卡片
                systemInfoCard
                
                // 存储信息卡片
                storageCard
                
                // 扫描结果概览（扫描后显示）
                if viewModel.hasScanned {
                    scanResultsOverview
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - 系统信息卡片
    private var systemInfoCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("系统信息")
                        .font(.headline)
                    Spacer()
                    if viewModel.isLoadingSystemInfo {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                if let info = viewModel.systemInfo {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 12) {
                        InfoRow(icon: "laptopcomputer", label: "机型", value: info.model)
                        InfoRow(icon: "cpu", label: "芯片", value: info.chip)
                        InfoRow(icon: "memorychip", label: "内存", value: info.memory)
                        InfoRow(icon: "core.mediaprocessor", label: "CPU 核心", value: "\(info.cpuCores) 核")
                        InfoRow(icon: "gearshape.2", label: "macOS", value: "\(info.macOSVersion) (\(info.buildNumber))")
                        InfoRow(icon: "clock", label: "运行时间", value: info.uptime)
                        InfoRow(icon: "desktopcomputer", label: "主机名", value: info.hostname)
                        InfoRow(icon: "barcode", label: "序列号", value: info.serialNumber)
                    }
                } else {
                    HStack {
                        Spacer()
                        Text("正在获取系统信息...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
        }
    }
    
    // MARK: - 存储信息卡片
    private var storageCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("存储空间")
                        .font(.headline)
                    Spacer()
                    if let storage = viewModel.storageInfo {
                        Text(storage.volumeName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let storage = viewModel.storageInfo {
                    // 使用/总量大数字
                    HStack(alignment: .bottom, spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已使用")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(storage.usedFormatted)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("可用")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(storage.freeFormatted)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("总容量")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(storage.totalFormatted)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // 圆形使用率
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.15), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: storage.usedPercentage)
                                .stroke(
                                    storage.usedPercentage > 0.9 ? Color.red :
                                    storage.usedPercentage > 0.75 ? Color.orange : Color.accentColor,
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(storage.usedPercentage * 100))%")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(width: 60, height: 60)
                    }
                    
                    // 整条表示总容量，彩色部分表示已用空间
                    GeometryReader { geo in
                        let breakdown = viewModel.storageBreakdown.filter { $0.size > 0 }
                        let total = max(storage.totalBytes, 1)
                        
                        HStack(spacing: 0) {
                            if breakdown.isEmpty {
                                Rectangle()
                                    .fill(Color.accentColor.opacity(0.35))
                                    .frame(width: geo.size.width * storage.usedPercentage)
                            }
                            ForEach(breakdown) { cat in
                                let width = geo.size.width * CGFloat(Double(cat.size) / Double(total))
                                if width > 0 {
                                    Rectangle()
                                        .fill(cat.color)
                                        .frame(width: width)
                                }
                            }
                            Rectangle()
                                .fill(Color.primary.opacity(0.1))
                                .frame(maxWidth: .infinity)
                        }
                        .frame(width: geo.size.width, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(height: 10)
                    
                    // 分类图例
                    if !viewModel.storageBreakdown.isEmpty {
                        Text("空间分类为估算值")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ForEach(viewModel.storageBreakdown) { cat in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(cat.color)
                                        .frame(width: 8, height: 8)
                                    Text(cat.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(cat.sizeFormatted)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .monospacedDigit()
                                }
                            }
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(width: 8, height: 8)
                                Text("可用空间")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(storage.freeFormatted)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                        }
                    }
                } else {
                    HStack {
                        Spacer()
                        Text("正在获取存储信息...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
        }
    }
    
    // MARK: - 扫描结果概览
    private var scanResultsOverview: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    Text("扫描结果")
                        .font(.headline)
                    Spacer()
                    StatItem(title: "文件数", value: "\(viewModel.totalFileCount)")
                    StatItem(title: "可清理", value: viewModel.totalCleanableSizeFormatted, color: .orange)
                        .padding(.leading, 16)
                }
                
                // 类别结果列表
                VStack(spacing: 8) {
                    ForEach(ScanCategory.allCases) { category in
                        if let result = viewModel.scanResults[category] {
                            ScanResultRow(category: category, result: result) {
                                viewModel.selectedCategory = category
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 扫描按钮卡片（融合进度）
    private var scanButtonCard: some View {
        CardView {
            VStack(spacing: 16) {
                // 扫描状态信息
                if viewModel.isScanning {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("正在扫描...")
                                .font(.headline)
                            Text("已完成 \(Int(viewModel.overallProgress * 100))%")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        ProgressView()
                            .scaleEffect(1.2)
                    }
                    
                    // 进度条
                    ProgressView(value: viewModel.overallProgress)
                        .progressViewStyle(.linear)
                        .animation(.easeInOut, value: viewModel.overallProgress)
                    
                } else if viewModel.hasScanned {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("扫描完成")
                                .font(.headline)
                            Text("发现 \(viewModel.totalFileCount) 个文件，可清理 \(viewModel.totalCleanableSizeFormatted)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task { await viewModel.scanAll() }
                        } label: {
                            Label("重新扫描", systemImage: "arrow.clockwise")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isScanning || viewModel.isCleaning)
                    }
                    
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("开始扫描")
                                .font(.headline)
                            Text("扫描系统中的缓存、日志、大文件等可清理内容")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            Task { await viewModel.scanAll() }
                        } label: {
                            Label("开始扫描", systemImage: "magnifyingglass")
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isScanning || viewModel.isCleaning)
                    }
                }
            }
        }
    }
}

// MARK: - 扫描结果行
struct ScanResultRow: View {
    let category: ScanCategory
    let result: ScanResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundColor(category.color)
                    .frame(width: 32, height: 32)
                    .background(category.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                Text(category.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if result.isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if result.error != nil {
                    StatusBadge(text: result.items.isEmpty ? "需要授权" : "部分不可读",
                                color: .orange, icon: "exclamationmark.triangle.fill")
                } else if result.isCleaned {
                    StatusBadge(text: "已清理", color: .green, icon: "checkmark.circle.fill")
                } else {
                    Text("\(result.itemCount) 个\(category.itemUnit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(result.totalSizeFormatted)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(category.color)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
