import SwiftUI

/// 居中模态确认框（不依赖系统 alert，避免嵌进页面布局）
struct ModalDialogView: View {
    let title: String
    let message: String
    var confirmTitle: String = "确定"
    var cancelTitle: String = "取消"
    var isDestructive: Bool = false
    var showsCancel: Bool = true
    var iconSystemName: String? = nil
    let onConfirm: () -> Void
    var onCancel: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            // 图标
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 64, height: 64)
                    .blur(radius: 10)
                Image(systemName: iconSystemName ?? (isDestructive ? "trash.fill" : "checkmark.circle.fill"))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(isDestructive ? .red : Color.accentColor)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.7)
            .animation(Theme.springSnappy.delay(0.02), value: appeared)

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 360)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .animation(Theme.easeSlow.delay(0.06), value: appeared)

            HStack(spacing: 12) {
                if showsCancel {
                    Button {
                        onCancel?()
                    } label: {
                        Text(cancelTitle)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundColor(.white)
                        .background(
                            Capsule()
                                .fill(
                                    isDestructive
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [Color.red.opacity(0.95), Color.red.opacity(0.75)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        : AnyShapeStyle(Theme.accentGradient)
                                )
                        )
                        .shadow(
                            color: (isDestructive ? Color.red : Color.blue).opacity(0.28),
                            radius: 12,
                            y: 5
                        )
                }
                .buttonStyle(.plain)
                .controlSize(.large)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(Theme.spring.delay(0.1), value: appeared)
        }
        .padding(26)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.primary.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .elevatedShadow()
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(Theme.spring) { appeared = true }
        }
    }

    private var iconBackground: some ShapeStyle {
        if isDestructive {
            return AnyShapeStyle(Color.red.opacity(0.16))
        }
        return AnyShapeStyle(Color.accentColor.opacity(0.14))
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
                    .opacity(isPresented ? 1 : 0)
                    .onTapGesture(perform: onDismiss)

                dialog()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .animation(Theme.spring, value: isPresented)
        }
    }
}
