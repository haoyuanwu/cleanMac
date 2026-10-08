import Foundation

struct AdministratorMoveOutcome: Sendable {
    let succeeded: Bool
    let message: String?
}

/// Finder 无法回收受权限保护的应用时，请求管理员授权后移入当前用户的废纸篓。
enum ApplicationUninstallService {
    nonisolated static func moveToTrashWithAdministratorPrivileges(appPath: String) -> AdministratorMoveOutcome {
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: appPath).standardizedFileURL
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let allowedParents = [
            URL(fileURLWithPath: "/Applications").standardizedFileURL.path,
            home.appendingPathComponent("Applications", isDirectory: true).path
        ]

        guard allowedParents.contains(source.deletingLastPathComponent().path),
              source.pathExtension.lowercased() == "app",
              source.path != Bundle.main.bundleURL.standardizedFileURL.path,
              let attributes = try? fileManager.attributesOfItem(atPath: source.path),
              (attributes[.type] as? FileAttributeType) == .typeDirectory else {
            return AdministratorMoveOutcome(succeeded: false, message: "应用路径无效或不在受支持的应用程序目录中。")
        }

        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        guard let trashAttributes = try? fileManager.attributesOfItem(atPath: trash.path),
              (trashAttributes[.type] as? FileAttributeType) == .typeDirectory else {
            return AdministratorMoveOutcome(succeeded: false, message: "无法访问当前用户的废纸篓。")
        }

        var destination = trash.appendingPathComponent(source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            let name = source.deletingPathExtension().lastPathComponent
            destination = trash.appendingPathComponent("\(name)-\(UUID().uuidString).app")
        }

        let script = """
        on run argv
            set sourcePath to item 1 of argv
            set destinationPath to item 2 of argv
            do shell script "/bin/mv -n " & quoted form of sourcePath & " " & quoted form of destinationPath with administrator privileges
        end run
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, source.path, destination.path]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               !fileManager.fileExists(atPath: source.path),
               fileManager.fileExists(atPath: destination.path) {
                return AdministratorMoveOutcome(succeeded: true, message: nil)
            }
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return AdministratorMoveOutcome(
                succeeded: false,
                message: detail?.isEmpty == false ? detail : "管理员授权后仍未能移动应用。"
            )
        } catch {
            return AdministratorMoveOutcome(succeeded: false, message: error.localizedDescription)
        }
    }
}
