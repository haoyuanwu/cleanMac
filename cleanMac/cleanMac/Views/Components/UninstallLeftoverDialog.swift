import SwiftUI

/// 卸载确认：展示残留路径/大小列表，可勾选随卸载删除
struct UninstallLeftoverDialog: View {
    let estimates: [AppLeftoverEstimate]
    @Binding var selectedLeftoverPaths: Set<String>
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var totalAppSize: Int64 {
        estimates.reduce(0) { $0 + $1.appSize }
    }

    private var selectedLeftoverSize: Int64 {
        estimates
            .flatMap(\.leftovers)
            .filter { selectedLeftoverPaths.contains($0.path) }
            .reduce(0) { $0 + $1.size }
    }

    private var allLeftovers: [AppLeftoverItem] {
        estimates.flatMap(\.leftovers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(estimates.count == 1 ? "卸载 \(estimates[0].appName)？" : "卸载 \(estimates.count) 个应用？")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text("应用将移到废纸篓。下方为检测到的相关残留，默认不勾选，请按需删除。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }

            // 汇总
            HStack(spacing: 10) {
                summaryChip(title: "应用本体", value: FileSizeFormatter.string(fromByteCount: totalAppSize), color: Theme.accentGradient)
                summaryChip(title: "残留合计", value: FileSizeFormatter.string(fromByteCount: allLeftovers.reduce(0) { $0 + $1.size }), color: Theme.warmGradient)
                summaryChip(title: "勾选删除", value: FileSizeFormatter.string(fromByteCount: selectedLeftoverSize), color: Theme.successGradient)
            }

            // 应用列表
            ForEach(Array(estimates.enumerated()), id: \.element.appPath) { _, estimate in
                HStack(spacing: 10) {
                    Image(systemName: "app.fill")
                        .foregroundColor(.indigo)
                    Text(estimate.appName)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(estimate.appSizeFormatted)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )
            }

            // 残留列表
            if allLeftovers.isEmpty {
                Text("未检测到明显残留数据")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                HStack {
                    Toggle(isOn: Binding(
                        get: { !allLeftovers.isEmpty && allLeftovers.allSatisfy { selectedLeftoverPaths.contains($0.path) } },
                        set: { on in
                            if on {
                                selectedLeftoverPaths.formUnion(allLeftovers.map(\.path))
                            } else {
                                selectedLeftoverPaths.removeAll()
                            }
                        }
                    )) {
                        Text("全选残留")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .toggleStyle(.checkbox)

                    Spacer()

                    Text("共 \(allLeftovers.count) 处")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(allLeftovers) { item in
                            leftoverRow(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 240)
            }

            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button {
                    onConfirm()
                } label: {
                    Text(selectedLeftoverPaths.isEmpty
                         ? "仅卸载应用"
                         : "卸载并删除 \(selectedLeftoverPaths.count) 处残留")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .elevatedShadow()
    }

    private func leftoverRow(_ item: AppLeftoverItem) -> some View {
        Toggle(isOn: Binding(
            get: { selectedLeftoverPaths.contains(item.path) },
            set: { on in
                if on {
                    selectedLeftoverPaths.insert(item.path)
                } else {
                    selectedLeftoverPaths.remove(item.path)
                }
            }
        )) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(item.path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.path)
                }

                Spacer(minLength: 8)

                Text(item.categoryLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))

                Text(item.sizeFormatted)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 72, alignment: .trailing)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func summaryChip(title: String, value: String, color: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accentGradientSoft.opacity(0.45))
        )
    }
}
