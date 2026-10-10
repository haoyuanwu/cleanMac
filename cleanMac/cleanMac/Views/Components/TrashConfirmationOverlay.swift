import SwiftUI

/// 全屏遮罩上的删除确认弹窗，完整展示本次冻结的待处理清单。
struct TrashConfirmationOverlay: View {
    let request: MainViewModel.DeleteRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var isPermanent: Bool { request.category == .trash }
    private var accent: Color { isPermanent ? .red : .orange }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.32))
                    .ignoresSafeArea()
                    .onTapGesture(perform: onCancel)

                VStack(spacing: 0) {
                    header
                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            summary
                            consequenceNote
                            fileList
                        }
                        .padding(24)
                    }

                    Divider()
                    footer
                }
                .frame(
                    width: min(820, max(0, geometry.size.width - 48)),
                    height: min(720, max(0, geometry.size.height - 48))
                )
                .background(Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .elevatedShadow()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onCancel)
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: isPermanent ? "trash.slash.fill" : "trash.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(isPermanent ? "确认永久删除" : "确认移到废纸篓")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(isPermanent ? "请核对以下项目；删除后无法撤销。" : "请核对以下项目；移入废纸篓后仍可恢复。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help("取消")
            .accessibilityLabel("取消删除")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Theme.surfaceRaised)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            summaryTile("项目数量", value: "\(request.files.count) 项", icon: "square.stack.3d.up")
            summaryTile("占用空间", value: request.totalSizeFormatted, icon: "externaldrive")
            summaryTile("所属类别", value: request.category.rawValue, icon: "folder")
        }
    }

    private func summaryTile(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardStroke))
    }

    private var consequenceNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isPermanent ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 15))
                .foregroundColor(accent)
            Text(isPermanent
                 ? "这些项目将从废纸篓永久删除，无法再从应用内恢复。"
                 : "项目会移入当前用户的废纸篓。如需调整清单，请取消后重新选择。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("待处理项目")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(request.files.count) 项")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            Divider()

            LazyVStack(spacing: 0) {
                ForEach(Array(request.files.enumerated()), id: \.element.id) { index, file in
                    HStack(spacing: 12) {
                        Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                            .font(.system(size: 16))
                            .foregroundColor(accent)
                            .frame(width: 34, height: 34)
                            .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text(file.path)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(file.path)
                        }

                        Spacer(minLength: 12)
                        Text(file.sizeFormatted)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)

                    if index < request.files.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
        }
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardStroke))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isPermanent ? "将永久删除" : "将移到废纸篓")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("\(request.files.count) 项 · \(request.totalSizeFormatted)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }

            Spacer(minLength: 16)

            Button(action: onCancel) {
                Text("取消")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 156, height: 42)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button(action: onConfirm) {
                Label(isPermanent ? "永久删除" : "移到废纸篓", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 156, height: 42)
                    .background(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Theme.surfaceRaised)
    }
}
