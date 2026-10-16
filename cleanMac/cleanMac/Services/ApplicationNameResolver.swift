import Foundation

enum ApplicationNameResolver {
    nonisolated static func displayName(atPath path: String) -> String {
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

        // 有些应用的包内英文名称会覆盖中文文件名；此时保留用户实际看到的中文名称。
        if fileName.range(of: "\\p{Han}", options: .regularExpression) != nil {
            return fileName
        }

        let localizedName = FileManager.default.displayName(atPath: path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return localizedName.isEmpty ? fileName : localizedName
    }
}
