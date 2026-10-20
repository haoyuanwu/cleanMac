import SwiftUI
import ImageIO
import UniformTypeIdentifiers

private struct FileThumbnail: @unchecked Sendable {
    let image: CGImage

    nonisolated static func load(path: String) -> FileThumbnail? {
        guard !Task.isCancelled else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128
        ] as CFDictionary) else { return nil }
        return FileThumbnail(image: image)
    }
}

private final class CachedFileThumbnail: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

@MainActor
private final class FileThumbnailCache {
    static let shared = FileThumbnailCache()
    private let cache = NSCache<NSString, CachedFileThumbnail>()

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for key: String) -> CGImage? { cache.object(forKey: key as NSString)?.image }

    func insert(_ image: CGImage, for key: String) {
        cache.setObject(CachedFileThumbnail(image), forKey: key as NSString,
                        cost: image.width * image.height * 4)
    }
}

/// 扫描结果中的文件图标。图片缩略图仅在行出现时从磁盘异步读取。
struct FileItemIcon: View {
    let file: FileItem
    var size: CGFloat = 44

    @State private var thumbnail: CGImage?
    @State private var loadedKey: String?

    private var fileExtension: String { file.pathURL.pathExtension.lowercased() }
    private var isImage: Bool {
        !file.isDirectory && UTType(filenameExtension: fileExtension)?.conforms(to: .image) == true
    }
    private var thumbnailKey: String {
        "\(file.path)|\(file.size)|\(file.modificationDate?.timeIntervalSince1970 ?? 0)"
    }

    private var symbol: String {
        if file.isDirectory { return "folder.fill" }
        switch fileExtension {
        case "pdf": return "doc.richtext.fill"
        case "zip", "gz", "bz2", "xz", "7z", "rar", "tar": return "doc.zipper"
        case "dmg", "pkg", "iso": return "shippingbox.fill"
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": return "film.fill"
        case "mp3", "m4a", "wav", "aiff", "flac", "ogg": return "music.note"
        case "swift", "js", "ts", "py", "rb", "go", "rs", "java", "kt", "html", "css", "json", "xml", "sh":
            return "chevron.left.forwardslash.chevron.right"
        case "txt", "md", "rtf", "doc", "docx", "pages", "log": return "doc.text.fill"
        case "csv", "tsv", "xls", "xlsx", "numbers": return "tablecells.fill"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle"
        default: return isImage ? "photo.fill" : "doc.fill"
        }
    }

    private var tint: Color {
        if file.isDirectory { return .blue }
        switch fileExtension {
        case "pdf": return .red
        case "zip", "gz", "bz2", "xz", "7z", "rar", "tar", "dmg", "pkg", "iso": return .orange
        case "mp4", "mov", "m4v", "avi", "mkv", "webm": return .purple
        case "mp3", "m4a", "wav", "aiff", "flac", "ogg": return .pink
        case "swift", "js", "ts", "py", "rb", "go", "rs", "java", "kt", "html", "css", "json", "xml", "sh": return .mint
        case "csv", "tsv", "xls", "xlsx", "numbers": return .green
        case "ppt", "pptx", "key": return .yellow
        default: return isImage ? .cyan : .secondary
        }
    }

    var body: some View {
        Group {
            if let appIcon = file.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isImage, loadedKey == thumbnailKey, let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundColor(tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(tint.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .accessibilityHidden(true)
        .task(id: thumbnailKey) {
            loadedKey = nil
            thumbnail = nil
            guard isImage, file.appIcon == nil else { return }
            let key = thumbnailKey
            if let cached = FileThumbnailCache.shared.image(for: key) {
                thumbnail = cached
                loadedKey = key
                return
            }
            let path = file.path
            let work = Task.detached(priority: .utility) { FileThumbnail.load(path: path) }
            let result = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            guard !Task.isCancelled, let result else { return }
            FileThumbnailCache.shared.insert(result.image, for: key)
            thumbnail = result.image
            loadedKey = key
        }
    }
}
