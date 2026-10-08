import SwiftUI
import AppKit

struct XcodeAnalysisView: View {
    @State private var result: XcodeAnalysisResult?
    @State private var isScanning = false
    @State private var expandedKinds = Set<XcodeArtifactKind>()
    private let service = XcodeAnalysisService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let result {
                    summary(result)
                    ForEach(XcodeArtifactKind.allCases) { kind in
                        group(kind, result: result)
                    }
                } else if isScanning {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在分析 Xcode 生成的文件和插件…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("尚未分析 Xcode 数据")
                            .font(.headline)
                        Text("扫描构建产物、缓存、归档、模拟器和编辑器扩展的占用。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            Task { await scan() }
                        } label: {
                            Label("开始分析", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .frame(maxWidth: 900)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Xcode 分析")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 22))
                .foregroundColor(.blue)
                .frame(width: 46, height: 46)
                .background(Color.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text("Xcode 空间分析")
                    .font(.system(size: 24, weight: .bold))
                Text("查看构建缓存、归档、模拟器数据、设备支持文件和插件的空间占用。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            if result != nil {
                Button {
                    Task { await scan() }
                } label: {
                    Label("重新分析", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isScanning)
            }
        }
    }

    private func summary(_ result: XcodeAnalysisResult) -> some View {
        CardView {
            HStack(spacing: 28) {
                summaryMetric("已分析空间", value: FileSizeFormatter.string(fromByteCount: result.totalSize))
                summaryMetric("文件与文件夹", value: "\(result.artifacts.count)")
                summaryMetric("插件与扩展", value: "\(result.pluginCount)")
                Spacer(minLength: 0)
            }
        }
    }

    private func summaryMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
        }
    }

    private func group(_ kind: XcodeArtifactKind, result: XcodeAnalysisResult) -> some View {
        let items = result.artifacts(for: kind)
        let isExpanded = expandedKinds.contains(kind)
        return CardView {
            VStack(alignment: .leading, spacing: 11) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedKinds.remove(kind)
                        } else {
                            expandedKinds.insert(kind)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(kind.rawValue)
                                .font(.headline)
                            Text(kind.note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(items.count) 项")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(FileSizeFormatter.string(fromByteCount: result.size(for: kind)))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.rawValue)，\(items.count) 项，\(isExpanded ? "收起" : "展开")")

                if isExpanded {
                    Divider()
                    if items.isEmpty {
                        Text("未发现相关文件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 32)
                    } else {
                        LazyVStack(spacing: 11) {
                            ForEach(items) { item in
                                artifactRow(item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func artifactRow(_ item: XcodeArtifact) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .plugins ? "puzzlepiece.extension" : "folder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detail ?? item.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path)
            }
            Spacer(minLength: 8)
            Text(item.sizeFormatted)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize()
            Button {
                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
            .accessibilityLabel("在 Finder 中显示 \(item.name)")
        }
    }

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        result = await service.analyze()
        isScanning = false
    }
}
