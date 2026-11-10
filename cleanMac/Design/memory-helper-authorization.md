# 内存整理辅助服务

## 使用

Xcode 选择 `cleanMac-HelperAuthorization` Scheme，目标 My Mac，运行 Release（不附加调试器）。进入设备信息 → 内存状态 → 辅助服务 → 申请授权，按系统登录项与后台活动提示批准。回到应用后状态自动刷新；批准后整理按钮通过 XPC 调用后台服务，无需每次弹管理员脚本授权。移除后台服务入口在同一菜单。

Debug 版本保留正常调试，不允许连接 root 服务。Release 明确禁用 CODE_SIGN_INJECT_BASE_ENTITLEMENTS，避免开发签名自动带入 get-task-allow。不要修改 entitlement 或放宽连接约束来绕开该限制。

## 实现与范围

- 官方 SMAppService daemon，随应用嵌入 Contents/Library/LaunchDaemons；原生 Xcode 命令行工具目标嵌入 Contents/Library/HelperTools。仅 arm64，无新增生产依赖。
- 客户端及服务端分别使用 Foundation 的代码签名约束；要求 Apple 证书链、相同团队、准确标识符，并排除调试、关闭库验证和允许 DYLD 环境注入的客户端。
- 唯一 XPC 方法无路径、命令或任意参数输入，只运行固定 /usr/sbin/purge；无 shell。全局互斥、超时终止、单次回复处理；服务异常不回退到逐次管理员脚本。
- 系统缓存整理不释放应用匿名内存，不保证占用下降。首次批准仍由 macOS 完成。签名检查不等同 Apple 公证或信任验证。
- 更新应用路径或签名后，macOS 可能要求重新批准；当前 ad-hoc 发布包无法满足团队签名约束，需正式团队签名后使用该能力。

## 当前验证

Xcode 官方 MCP Release 构建成功；主程序和嵌入辅助程序的实际签名均满足运行时约束；helper 标识为 com.cleanMac.cache.cleanMac.memory-helper。186 项回归测试通过，包括签名约束语法解析、模拟整理、防重入及授权取消反馈。实际系统批准和授权后 root XPC 调用尚未验证：授权版本的 UI 读取连续超时。未安装/批准后台服务，未执行真实 purge，未生成安装包。

参考：
- https://developer.apple.com/documentation/servicemanagement/smappservice
- https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos

## 已授权但整理不返回的修复

实机 launchctl 显示批准后的 helper 反复退出，last exit code 1；Security 日志为 -67068/ENOENT。launchd 的 argv[0] 不能当作可靠绝对路径，改用 proc_pidpath 解析自身路径后严格验证签名；使用 dispatchMain 保持服务运行。主应用增加 5 秒 ping 握手，服务不可达及时恢复按钮，不等待长整理超时。新二进制替换后必须重启旧应用进程，否则运行中的旧代码签名会被拒绝。

本次实机：新版服务保持 running；Xcode Release 运行后点击整理，约一秒显示“系统缓存整理完成”，按钮恢复，无新的管理员授权框；内存估算 12.96 GB → 12.61 GB，不作为精确释放量承诺。186 项回归测试通过。设置 → 系统权限新增后台辅助服务状态、申请授权、系统设置和移除入口，回到应用自动刷新状态。测试后停止主应用，保留用户已批准的系统辅助服务。
