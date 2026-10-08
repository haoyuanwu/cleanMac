import SwiftUI

/// 居中模态确认框（不依赖系统 alert，避免嵌进页面布局）
struct ModalDialogView: View {
    let title: String
    let message: String
    var confirmTitle: String = "确定"
    var cancelTitle: String = "取消"
    var isDestructive: Bool = false
    var showsCancel: Bool = true
    let onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: 12) {
                if showsCancel {
                    Button {
                        onCancel?()
                    } label: {
                        Text(cancelTitle)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isDestructive
                                        ? AnyShapeStyle(Color.red.opacity(0.92))
                                        : AnyShapeStyle(Theme.accentGradient)
                                )
                        )
                }
                .buttonStyle(.plain)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 420)
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
}

/// 全屏遮罩 + 居中弹窗
struct ModalHostView<Dialog: View>: View {
    let isPresented: Bool
    let onDismiss: () -> Void
    @ViewBuilder var dialog: () -> Dialog

    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                dialog()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}
