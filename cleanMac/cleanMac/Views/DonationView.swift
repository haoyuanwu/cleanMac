import AppKit
import SwiftUI

/// 自愿打赏页面，首次完整扫描提示与设置入口共用。
struct DonationView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Theme.accentGradient)
                    .frame(width: 50, height: 50)
                    .background(Theme.accentGradientSoft, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 5) {
                    Text("请我喝杯咖啡")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text("感谢使用 cleanMac。如果它帮你腾出了空间，欢迎自愿支持后续开发。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityLabel("关闭打赏页面")
            }

            HStack(alignment: .top, spacing: 14) {
                paymentCard(title: "支付宝", subtitle: "打开支付宝扫一扫", imageName: "AlipayDonation",
                            crop: CGRect(x: 0.17, y: 0.35, width: 0.66, height: 0.44), tint: .blue)
                paymentCard(title: "微信支付", subtitle: "打开微信扫一扫", imageName: "WeChatDonation",
                            crop: CGRect(x: 0.26, y: 0.24, width: 0.48, height: 0.35), tint: .green)
            }

            Text("打赏完全自愿，不影响扫描、清理或任何其他功能。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button(action: onClose) {
                Text("稍后再说")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 570)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardStroke))
        .elevatedShadow()
    }

    private func paymentCard(title: String, subtitle: String, imageName: String, crop: CGRect, tint: Color) -> some View {
        VStack(spacing: 10) {
            Label(title, systemImage: title == "支付宝" ? "a.circle.fill" : "bubble.left.and.bubble.right.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
            donationQRCode(imageName: imageName, crop: crop)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 205, height: 205)
                .padding(9)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("\(title)收款二维码")
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func donationQRCode(imageName: String, crop: CGRect) -> Image {
        guard let source = NSImage(named: imageName),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Image(imageName)
        }
        let rect = CGRect(
            x: crop.minX * CGFloat(cgImage.width),
            y: crop.minY * CGFloat(cgImage.height),
            width: crop.width * CGFloat(cgImage.width),
            height: crop.height * CGFloat(cgImage.height)
        ).integral
        guard let clipped = cgImage.cropping(to: rect) else { return Image(imageName) }
        return Image(nsImage: NSImage(cgImage: clipped, size: NSSize(width: clipped.width, height: clipped.height)))
    }
}

struct DonationOverlay: View {
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.20))
                    .ignoresSafeArea()
                ScrollView {
                    DonationView(onClose: onClose)
                        .frame(maxWidth: 570)
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
        }
    }
}
