import SwiftUI
import ImageIO
import AppKit

private struct PreviewBitmap: @unchecked Sendable {
    let image: CGImage
    let pixelWidth: Int
    let pixelHeight: Int

    nonisolated static func load(at url: URL) -> PreviewBitmap? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        return PreviewBitmap(
            image: image,
            pixelWidth: properties?[kCGImagePropertyPixelWidth as String] as? Int ?? image.width,
            pixelHeight: properties?[kCGImagePropertyPixelHeight as String] as? Int ?? image.height
        )
    }
}

/// 图片列表的应用内预览：双击缩放、捏合缩放、放大后拖动、适应窗口时横向滑动切图。
struct ImagePreviewView: View {
    let files: [FileItem]
    @State private var index: Int
    @State private var bitmap: PreviewBitmap?
    @State private var isLoading = true
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.dismiss) private var dismiss

    init(files: [FileItem], initialPath: String) {
        self.files = files
        _index = State(initialValue: files.firstIndex(where: { $0.path == initialPath }) ?? 0)
    }

    private var current: FileItem? {
        files.indices.contains(index) ? files[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geometry in
                ZStack {
                    Color(red: 0.10, green: 0.12, blue: 0.16)

                    if let bitmap {
                        Image(decorative: bitmap.image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(effectiveZoom)
                            .offset(limitedOffset(
                                CGSize(width: pan.width + drag.width, height: pan.height + drag.height),
                                zoom: effectiveZoom,
                                in: geometry.size,
                                bitmap: bitmap
                            ))
                            .contentShape(Rectangle())
                            .gesture(dragGesture(in: geometry.size, bitmap: bitmap))
                            .simultaneousGesture(magnificationGesture(in: geometry.size, bitmap: bitmap))
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    zoom = zoom > 1 ? 1 : 2
                                    pan = .zero
                                }
                            }
                    } else if isLoading && current != nil {
                        ProgressView("正在载入图片…")
                            .foregroundStyle(.white)
                    } else if current != nil {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 32))
                            Text("无法预览这张图片")
                            Text("文件可能已移动，或格式暂不受支持。")
                                .font(.caption)
                        }
                        .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text("没有可预览的图片")
                            .foregroundColor(.white.opacity(0.7))
                    }

                    if bitmap != nil {
                        navigationButtons
                    }
                }
                .clipped()
            }

            footer
        }
        .frame(minWidth: 720, minHeight: 540)
        .background(Color(red: 0.14, green: 0.16, blue: 0.20))
        .onExitCommand { dismiss() }
        .task(id: current?.path) {
            resetZoom()
            bitmap = nil
            isLoading = true
            guard let path = current?.path else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                PreviewBitmap.load(at: URL(fileURLWithPath: path))
            }.value
            guard !Task.isCancelled, current?.path == path else { return }
            bitmap = loaded
            isLoading = false
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo")
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(current?.name ?? "图片预览")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadataText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.62))
            }
            Spacer(minLength: 8)
            Text("\(files.isEmpty ? 0 : index + 1) / \(files.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
                .monospacedDigit()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("关闭预览")
            .accessibilityLabel("关闭预览")
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var metadataText: String {
        guard let current else { return "" }
        let size = current.sizeFormatted
        guard let bitmap else { return size }
        return "\(bitmap.pixelWidth) × \(bitmap.pixelHeight) · \(size)"
    }

    private var navigationButtons: some View {
        HStack {
            navigationButton("chevron.left", help: "上一张", enabled: index > 0) { move(by: -1) }
            Spacer()
            navigationButton("chevron.right", help: "下一张", enabled: index < files.count - 1) { move(by: 1) }
        }
        .padding(.horizontal, 14)
    }

    private func navigationButton(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 48)
                .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .help(help)
        .accessibilityLabel(help)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("双击或捏合缩放 · 放大后拖动 · 横向滑动切图")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.58))
            Spacer()
            toolbarButton("minus.magnifyingglass", help: "缩小", enabled: zoom > 1) {
                changeZoom(to: zoom / 1.5)
            }
            Text(zoom <= 1 ? "适应窗口" : "\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 72)
            toolbarButton("plus.magnifyingglass", help: "放大", enabled: zoom < 5) {
                changeZoom(to: zoom * 1.5)
            }
            toolbarButton("arrow.down.right.and.arrow.up.left", help: "适应窗口", enabled: zoom > 1) {
                withAnimation(.easeInOut(duration: 0.2)) { resetZoom() }
            }
            if let current {
                toolbarButton("folder", help: "在 Finder 中显示", enabled: true) {
                    NSWorkspace.shared.selectFile(current.path, inFileViewerRootedAtPath: "")
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func toolbarButton(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(help)
    }

    private var effectiveZoom: CGFloat {
        min(5, max(1, zoom * pinch))
    }

    private func dragGesture(in size: CGSize, bitmap: PreviewBitmap) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($drag) { value, state, _ in
                if zoom > 1 { state = value.translation }
            }
            .onEnded { value in
                if zoom > 1 {
                    pan = limitedOffset(
                        CGSize(width: pan.width + value.translation.width, height: pan.height + value.translation.height),
                        zoom: zoom, in: size, bitmap: bitmap
                    )
                } else if abs(value.translation.width) > 80,
                          abs(value.translation.width) > abs(value.translation.height) * 1.4 {
                    move(by: value.translation.width < 0 ? 1 : -1)
                }
            }
    }

    private func magnificationGesture(in size: CGSize, bitmap: PreviewBitmap) -> some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                zoom = min(5, max(1, zoom * value))
                pan = limitedOffset(pan, zoom: zoom, in: size, bitmap: bitmap)
                if zoom == 1 { pan = .zero }
            }
    }

    private func limitedOffset(_ offset: CGSize, zoom: CGFloat, in viewport: CGSize, bitmap: PreviewBitmap) -> CGSize {
        guard bitmap.pixelWidth > 0, bitmap.pixelHeight > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let fit = min(viewport.width / CGFloat(bitmap.pixelWidth), viewport.height / CGFloat(bitmap.pixelHeight))
        let limitX = max(0, (CGFloat(bitmap.pixelWidth) * fit * zoom - viewport.width) / 2)
        let limitY = max(0, (CGFloat(bitmap.pixelHeight) * fit * zoom - viewport.height) / 2)
        return CGSize(width: min(limitX, max(-limitX, offset.width)), height: min(limitY, max(-limitY, offset.height)))
    }

    private func changeZoom(to value: CGFloat) {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoom = min(5, max(1, value))
            if zoom == 1 { pan = .zero }
        }
    }

    private func resetZoom() {
        zoom = 1
        pan = .zero
    }

    private func move(by step: Int) {
        let next = index + step
        guard files.indices.contains(next) else { return }
        index = next
    }
}
