import Foundation
import CryptoKit

struct CleaningRecord: Codable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case movedToTrash, permanentlyDeleted, failed, restored, alreadyMissing }
    let id: UUID
    let date: Date
    let originalPath: String
    let category: String
    let logicalBytes: Int64
    let trashPath: String?
    let originalParent: String
    let fingerprint: String?
    var state: State
    var message: String?
    var restoredAt: Date?
}

/// 操作历史仅保存在本机。恢复必须校验原路径、废纸篓身份和文件元数据。
final class CleaningHistoryStore: @unchecked Sendable {
    nonisolated static let shared = CleaningHistoryStore()
    nonisolated static let didChange = Notification.Name("cleanMac.cleaningHistoryChanged")
    nonisolated private let lock = NSRecursiveLock()
    nonisolated private let fileURL: URL
    nonisolated private let testTrashRoot: URL?
    nonisolated(unsafe) private var entries: [CleaningRecord] = []
    nonisolated(unsafe) private(set) var persistenceError: String?

    nonisolated init(fileURL: URL? = nil, testTrashRoot: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/cleanMac/cleaning-history.json")
        self.testTrashRoot = testTrashRoot
        do {
            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                entries = try JSONDecoder().decode([CleaningRecord].self, from: Data(contentsOf: self.fileURL))
            }
        } catch { persistenceError = "清理记录读取失败：\(error.localizedDescription)" }
    }

    nonisolated var records: [CleaningRecord] {
        lock.lock(); defer { lock.unlock() }; return entries.reversed()
    }

    @discardableResult
    nonisolated func record(path: String, size: Int64, category: String, state: CleaningRecord.State,
                            trashPath: String? = nil, message: String? = nil) -> CleaningRecord {
        lock.lock(); defer { lock.unlock() }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path
        let fingerprint = trashPath.flatMap { try? Self.fingerprint(URL(fileURLWithPath: $0)) }
        let entry = CleaningRecord(id: UUID(), date: Date(), originalPath: path, category: category,
                                   logicalBytes: size, trashPath: trashPath, originalParent: parent,
                                   fingerprint: fingerprint, state: state,
                                   message: message ?? (state == .movedToTrash && fingerprint == nil
                                       ? "无法完整校验废纸篓项目，请在 Finder 中手动核对和恢复。" : nil), restoredAt: nil)
        entries.append(entry)
        save()
        return entry
    }

    /// 返回系统实际生成的废纸篓路径，绝不根据文件名猜测目标。
    nonisolated func moveToTrash(path: String, size: Int64, category: String) throws {
        var destination: NSURL?
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &destination)
        } catch {
            record(path: path, size: size, category: category, state: .failed, message: error.localizedDescription)
            throw error
        }
        record(path: path, size: size, category: category, state: .movedToTrash, trashPath: destination?.path,
               message: destination == nil ? "系统未返回废纸篓路径，请在 Finder 中检查。" : nil)
    }

    nonisolated func restore(_ id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw failure("找不到这条清理记录。") }
        let record = entries[index]
        guard record.state == .movedToTrash, let path = record.trashPath, let expected = record.fingerprint else {
            throw failure("此项目没有可验证的废纸篓副本，无法自动恢复。")
        }
        let trashURL = URL(fileURLWithPath: path).standardizedFileURL
        let parent = trashURL.deletingLastPathComponent()
        let accepted = testTrashRoot.map { parent.path == $0.standardizedFileURL.path }
            ?? isDirectTrashEntry(path)
        guard accepted, parent.path == parent.resolvingSymlinksInPath().path else {
            throw failure("废纸篓路径已变化，请在 Finder 中检查。")
        }
        let original = URL(fileURLWithPath: record.originalPath).standardizedFileURL
        let originalParent = original.deletingLastPathComponent()
        guard originalParent.resolvingSymlinksInPath().path == record.originalParent else {
            throw failure("原目录的路径或符号链接已变化，请手动恢复。")
        }
        let fm = FileManager.default
        do {
            _ = try fm.attributesOfItem(atPath: original.path)
            throw failure("原位置已有同名项目。为避免覆盖，请先在 Finder 中处理同名文件。")
        } catch {
            let ns = error as NSError
            guard (ns.domain == NSCocoaErrorDomain && [4, 260].contains(ns.code))
                    || (ns.domain == NSPOSIXErrorDomain && ns.code == 2) else { throw error }
        }
        guard fm.fileExists(atPath: trashURL.path) else { throw failure("废纸篓中的项目已不存在，可能已被清空。") }
        guard try Self.fingerprint(trashURL) == expected else {
            throw failure("废纸篓中的项目已发生变化。请在 Finder 中核对后手动恢复。")
        }
        // moveItem 不覆盖现有文件；父目录不存在或权限不足时直接报错，不创建目录或自动提权。
        try fm.moveItem(at: trashURL, to: original)
        entries[index].state = .restored
        entries[index].restoredAt = Date()
        entries[index].message = nil
        save()
    }

    nonisolated private func save() {
        do {
            // 无法读取旧文件时保留它，避免用空记录覆盖历史。
            guard persistenceError == nil else { return }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { persistenceError = "清理记录保存失败：\(error.localizedDescription)" }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    nonisolated private func failure(_ message: String) -> NSError {
        NSError(domain: "cleanMac.restore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// 只校验元数据，不读取缓存内容；目录内文件变化也会使恢复校验失败。
    nonisolated private static func fingerprint(_ url: URL) throws -> String {
        let fm = FileManager.default
        var urls = [url]
        let rootAttributes = try fm.attributesOfItem(atPath: url.path)
        if rootAttributes[.type] as? FileAttributeType == .typeDirectory {
            var enumerationError: Error?
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, errorHandler: { _, error in
                enumerationError = error; return false
            }) else { throw CocoaError(.fileReadUnknown) }
            for case let child as URL in enumerator { urls.append(child) }
            if let enumerationError { throw enumerationError }
        }
        var hash = SHA256()
        for child in urls.sorted(by: { $0.path < $1.path }) {
            let attrs = try fm.attributesOfItem(atPath: child.path)
            let row = "\(child.path.dropFirst(url.path.count))|\(attrs[.systemFileNumber] ?? "?")|\(attrs[.size] ?? "?")|\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(attrs[.type] ?? "?")\n"
            hash.update(data: Data(row.utf8))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
