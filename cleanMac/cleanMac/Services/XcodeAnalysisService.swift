import Foundation

final class XcodeAnalysisService: @unchecked Sendable {
    nonisolated(unsafe) private let fileManager = FileManager.default
    nonisolated(unsafe) private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func analyze() async -> XcodeAnalysisResult {
        await Task.detached(priority: .utility) { [self] in
            scan()
        }.value
    }

    nonisolated private func scan() -> XcodeAnalysisResult {
        let developer = "\(home)/Library/Developer"
        var artifacts: [XcodeArtifact] = []

        func addChildren(_ path: String, kind: XcodeArtifactKind) {
            artifacts.append(contentsOf: directChildren(at: path, kind: kind))
        }

        addChildren("\(developer)/Xcode/DerivedData", kind: .derivedData)
        addChildren("\(home)/Library/Caches/com.apple.dt.Xcode", kind: .xcodeCaches)
        addChildren("\(home)/Library/Caches/org.swift.swiftpm", kind: .xcodeCaches)
        addChildren("\(developer)/Xcode/Archives", kind: .archives)
        addChildren("\(developer)/Xcode/iOS DeviceSupport", kind: .deviceSupport)
        addChildren("\(developer)/Xcode/watchOS DeviceSupport", kind: .deviceSupport)
        addChildren("\(developer)/Xcode/tvOS DeviceSupport", kind: .deviceSupport)
        addChildren("\(developer)/CoreSimulator/Devices", kind: .simulatorDevices)
        addChildren("\(developer)/CoreSimulator/Caches", kind: .simulatorCaches)
        addChildren("\(developer)/CoreSimulator/Temp", kind: .simulatorCaches)
        addChildren("\(developer)/Xcode/DeviceLogs", kind: .deviceLogs)

        let pluginRoots = [
            "\(home)/Library/Application Support/Developer/Shared/Xcode/Plug-ins",
            "\(home)/Library/Developer/Xcode/Plug-ins",
            "/Library/Application Support/Developer/Shared/Xcode/Plug-ins"
        ]
        for path in pluginRoots {
            addChildren(path, kind: .plugins)
        }
        artifacts.append(contentsOf: sourceEditorExtensions())

        var paths = Set<String>()
        return XcodeAnalysisResult(
            artifacts: artifacts.filter { paths.insert($0.path).inserted },
            scannedAt: Date()
        )
    }

    nonisolated private func directChildren(at path: String, kind: XcodeArtifactKind) -> [XcodeArtifact] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        return names.compactMap { name in
            let fullPath = (path as NSString).appendingPathComponent(name)
            return artifact(at: fullPath, name: name, kind: kind)
        }
    }

    nonisolated private func artifact(
        at path: String,
        name: String,
        kind: XcodeArtifactKind,
        detail: String? = nil
    ) -> XcodeArtifact? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeDirectory || type == .typeRegular else { return nil }
        let size = type == .typeDirectory
            ? FileHelper.directorySize(path)
            : (attributes[.size] as? Int64) ?? 0
        guard size > 0 else { return nil }

        let displayName: String
        if kind == .simulatorDevices,
           let device = NSDictionary(contentsOfFile: (path as NSString).appendingPathComponent("device.plist")),
           let deviceName = device["name"] as? String {
            displayName = deviceName
        } else {
            displayName = name
        }
        return XcodeArtifact(path: path, name: displayName, detail: detail, size: size, kind: kind)
    }

    /// Xcode 编辑器扩展通常嵌入第三方应用，读取 appex 的扩展点以避免误算其他插件。
    nonisolated private func sourceEditorExtensions() -> [XcodeArtifact] {
        let appRoots = ["/Applications", "\(home)/Applications"]
        var result: [XcodeArtifact] = []
        for root in appRoots {
            guard let apps = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for app in apps where app.lowercased().hasSuffix(".app") {
                let pluginDirectory = (root as NSString)
                    .appendingPathComponent(app + "/Contents/PlugIns")
                guard let extensions = try? fileManager.contentsOfDirectory(atPath: pluginDirectory) else { continue }
                for ext in extensions where ext.lowercased().hasSuffix(".appex") {
                    let path = (pluginDirectory as NSString).appendingPathComponent(ext)
                    let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
                    guard let plist = NSDictionary(contentsOfFile: plistPath),
                          let extensionInfo = plist["NSExtension"] as? [String: Any],
                          extensionInfo["NSExtensionPointIdentifier"] as? String
                            == "com.apple.dt.Xcode.extension.source-editor" else { continue }
                    if let item = artifact(
                        at: path,
                        name: (ext as NSString).deletingPathExtension,
                        kind: .plugins,
                        detail: "来自 \((app as NSString).deletingPathExtension)"
                    ) {
                        result.append(item)
                    }
                }
            }
        }
        return result
    }
}
