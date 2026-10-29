import SwiftUI
import UniformTypeIdentifiers

struct ScanDiagnosticsView: View {
    let category: ScanCategory
    let diagnostics: ScanDiagnostics
    @Environment(\.dismiss) private var dismiss
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(category.rawValue) · 扫描诊断").font(.system(size: 20, weight: .bold))
                    Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }
                Spacer()
                Button("导出 JSON", action: export)
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 16) {
                Text("路径检查 \(diagnostics.visitedCount) 次")
                Text("跳过 \(diagnostics.skippedCount) 个")
                Text("耗时 \(diagnostics.elapsed, specifier: "%.1f") 秒")
            }.font(.system(size: 12)).monospacedDigit()
            Text("不存在的可选路径：\(diagnostics.missingCount) 个；读取问题：\(diagnostics.issues.count + diagnostics.omittedIssueCount) 处。检查次数包含目录枚举与大小计算，同一路径可能检查多次，不等于唯一文件或清理项目数。")
                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(diagnostics.issues) { issue in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(issue.permissionDenied ? "无权限读取" : "读取失败",
                                  systemImage: issue.permissionDenied ? "lock.fill" : "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .semibold))
                            Text(issue.path).font(.system(size: 12)).textSelection(.enabled)
                            Text(issue.message).font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if diagnostics.issues.isEmpty {
                        Text(diagnostics.status == .cancelled ? "已取消；未报告读取错误不代表扫描完整。" : "当前未记录读取问题。")
                            .font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary).padding()
                    }
                    if diagnostics.omittedIssueCount > 0 {
                        Text("另有 \(diagnostics.omittedIssueCount) 个问题路径，详情仅保留前 1000 条。")
                            .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    }
                }
            }
            if let exportError { Text(exportError).font(.caption).foregroundStyle(.red) }
            Text("导出文件包含本机路径；仅在你选择的位置保存。")
                .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
        }
        .padding(24).frame(width: 720, height: 520).background(Theme.canvas)
    }

    private var statusText: String {
        switch diagnostics.status {
        case .running: return "扫描进行中"
        case .complete: return "扫描完成 · 已完成配置范围内的检查"
        case .partial: return "扫描完成 · 存在无法读取的路径，结果不完整"
        case .cancelled: return "扫描已取消 · 仅保留取消前的结果"
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "cleanMac-\(category.rawValue)-扫描诊断.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(diagnostics).write(to: url, options: .atomic)
        } catch { exportError = "导出失败：\(error.localizedDescription)" }
    }
}

/// 扫描结束后的轻量通知；关闭不丢弃诊断，详情页工具栏仍可重新打开。
struct ScanDiagnosticsBar: View {
    let category: ScanCategory
    let diagnostics: ScanDiagnostics
    @State private var showingDetails = false
    @State private var dismissed = false

    var body: some View {
        Group {
            if !dismissed && (diagnostics.status == .partial || diagnostics.status == .cancelled) {
                HStack(spacing: 12) {
                    Image(systemName: diagnostics.status == .partial ? "exclamationmark.triangle" : "pause.circle")
                        .foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnostics.status == .partial ? "部分路径无法读取" : "扫描已取消")
                            .font(.system(size: 13, weight: .semibold))
                        Text(diagnostics.status == .partial ? "\(diagnostics.issues.count + diagnostics.omittedIssueCount) 处读取问题 · 当前结果不完整" : "仅保留取消前的结果")
                            .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    }
                    Spacer(minLength: 8)
                    Button("诊断详情") { showingDetails = true }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
                    }.buttonStyle(.plain).help("关闭通知").accessibilityLabel("关闭扫描诊断通知")
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .gradientGlass(cornerRadius: 16)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 5)
                .frame(maxWidth: 600)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: diagnostics.startedAt) { _ in dismissed = false }
        .onChange(of: diagnostics.status) { _ in dismissed = false }
        .sheet(isPresented: $showingDetails) { ScanDiagnosticsView(category: category, diagnostics: diagnostics) }
    }
}
