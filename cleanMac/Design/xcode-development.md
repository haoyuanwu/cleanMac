# 通过 Xcode 运行与验证

本机 Xcode 27.2 提供官方 MCP，入口为 `xcrun mcpbridge`。`Scripts/xcode_mcp.py` 使用标准库连接此入口，不安装依赖，不修改全局 Codex 配置。

1. 首次使用 `python3 Scripts/xcode_mcp.py XcodeOpenWorkspace '{"path":"/Users/why/Documents/Project/cleanMacApp/cleanMac/cleanMac.xcodeproj"}'`，Xcode 可能要求用户批准该代理及项目目录访问。
2. `python3 Scripts/xcode_mcp.py XcodeListWorkspaces` 获取当前工程标识，工具后续参数使用返回的 `workspaceIdentifier`，不要固定历史窗口标识。
3. `BuildProject` 在 Xcode 中构建；`RunProject` 构建并运行当前 Scheme；`StopProject` 停止调试实例。操作前核对当前 Scheme 和 My Mac（Apple Silicon）目标，避免影响其他项目。
4. 每次测试前关闭旧的 cleanMac 实例，测试后调用 `StopProject`；用户自行运行的其他软件不受影响。
5. 默认不生成 DMG。用户通过 Xcode 运行查看修改。需要预览时使用 `RenderPreview`，状态栏布局在 `MenuBarStatusView.swift` 中有专用预览。

参考：https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode
