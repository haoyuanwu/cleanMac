import Foundation

/// 保留 FileManager 的调用语义，同时记录读取失败，防止 try? 把失败伪装为空结果。
struct ScanFileAccess: Sendable {
    nonisolated init() {}
    nonisolated func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        ScanContext.diagnostics?.visit(path)
        do { return try FileManager.default.attributesOfItem(atPath: path) }
        catch { ScanContext.diagnostics?.failure(path, error: error); throw error }
    }
    nonisolated func contentsOfDirectory(atPath path: String) throws -> [String] {
        ScanContext.diagnostics?.visit(path)
        do { return try FileManager.default.contentsOfDirectory(atPath: path) }
        catch { ScanContext.diagnostics?.failure(path, error: error); throw error }
    }
    nonisolated func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
                                         options: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
        ScanContext.diagnostics?.visit(url.path)
        do { return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options) }
        catch { ScanContext.diagnostics?.failure(url.path, error: error); throw error }
    }
    nonisolated func fileExists(atPath path: String) -> Bool {
        (try? attributesOfItem(atPath: path)) != nil
    }
    nonisolated func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
                               options: FileManager.DirectoryEnumerationOptions = [],
                               errorHandler: ((URL, Error) -> Bool)? = nil) -> FileManager.DirectoryEnumerator? {
        let diagnostics = ScanContext.diagnostics
        diagnostics?.visit(url.path)
        // 明确读取根目录，确保无法建立枚举器也有诊断。
        guard (try? contentsOfDirectory(atPath: url.path)) != nil else { return nil }
        return FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: options) { failed, error in
            diagnostics?.failure(failed.path, error: error)
            return errorHandler?(failed, error) ?? true
        }
    }
    nonisolated func enumerator(atPath path: String) -> FileManager.DirectoryEnumerator? {
        enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
    }
}
