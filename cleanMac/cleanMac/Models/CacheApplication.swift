import AppKit

nonisolated struct CacheApplication: Hashable, Codable, Sendable {
    let id: String
    let name: String
    let path: String?

    @MainActor var icon: NSImage? {
        let workspace = NSWorkspace.shared
        let appURL = path.map { URL(fileURLWithPath: $0) }
            ?? workspace.urlForApplication(withBundleIdentifier: id)
        return appURL.map { workspace.icon(forFile: $0.path) }
    }
}
