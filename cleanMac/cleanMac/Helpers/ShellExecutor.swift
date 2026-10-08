import Foundation

/// Shell 命令执行器
enum ShellExecutor {
    
    /// 执行 shell 命令，返回输出
    @discardableResult
    static func execute(_ command: String, asRoot: Bool = false) throws -> String {
        if asRoot {
            return try executeWithPrivileges(command)
        }
        
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard let output = String(data: data, encoding: .utf8) else {
            return ""
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 使用管理员权限执行命令
    private static func executeWithPrivileges(_ command: String) throws -> String {
        let appleScript = "do shell script \"\(command.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    /// 静默执行，忽略错误
    static func silent(_ command: String) {
        _ = try? execute(command)
    }
}
