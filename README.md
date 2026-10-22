# cleanMac

cleanMac 是一款原生 macOS 空间清理工具，重点解决开发环境占用、日常缓存整理，以及应用卸载后的残留清理。扫描结果先展示给你，再由你选择要处理的项目。

## 重点功能

### Xcode 空间分析

按类别统计 Xcode 和开发环境占用，显示每项大小与路径：

- **构建产物**：DerivedData 中的编译、索引和依赖构建数据。
- **开发缓存**：Xcode 缓存与 Swift Package Manager 缓存。
- **归档与设备支持**：应用归档、iOS/watchOS/tvOS 调试支持文件。
- **模拟器数据**：模拟器设备、缓存和临时文件。
- **其他开发数据**：设备日志、Xcode 插件与编辑器扩展。

可展开分类查看明细，在 Finder 中定位；支持将符合清理范围的单个项目移到废纸篓。归档和模拟器数据可能仍有用途，请查看后再决定是否处理。

### 智能清理

概览扫描检查系统缓存、浏览器缓存、日志、应用残留和废纸篓。智能清理从扫描结果中筛选**低风险推荐项**，跳过受保护路径及白名单项目，并汇总预计可释放空间。

执行前会列出每个推荐项目。你可以取消勾选、将不想清理的项目加入白名单，确认后才会清理所选内容。下载文件、大文件、安装包和应用程序不会被加入智能清理推荐集。

### 卸载应用与清除残留

扫描已安装的应用后，可查看应用本体大小，并按应用标识或名称估算常见残留，包括应用数据、沙盒容器、缓存、偏好设置、状态存档和日志等。

卸载前可以核对并勾选残留。应用本体会移到废纸篓；确认清理的残留会单独删除。受系统保护或需要管理员权限的应用会按 macOS 的授权流程处理。

## 更多功能

- **深度清理**：扩展扫描下载文件夹、大文件、安装包和应用程序，并分析重复文件及 Xcode 数据。
- **磁盘与设备信息**：查看磁盘空间分布、占用变化和设备信息，设置空间增长及废纸篓提醒。
- **每日定时扫描**：可调整时间或关闭；定时任务只扫描，不自动删除文件。

## 界面预览

### 空间概览

![cleanMac 空间概览与清理入口](docs/screenshots/overview.png)

### 扫描结果与智能清理入口

![cleanMac 扫描后的空间统计与智能清理建议](docs/screenshots/scan-results.png)

## 下载与安装

从 [GitHub Releases](https://github.com/haoyuanwu/cleanMac/releases/latest) 下载对应芯片的安装包：Apple Silicon（M 系列）选择 `cleanMac-arm64.dmg`，Intel 选择 `cleanMac-x86_64.dmg`。打开 DMG 后将 `cleanMac.app` 拖入“应用程序”文件夹。

要求 **macOS 13.5 或更新版本**。部分受系统保护的位置可能需要“完全磁盘访问”或操作时的管理员授权。发布包的签名与公证状态请以对应 Release 说明为准。

### 首次打开与 macOS 安全设置

当前安装包尚未经过 Apple 公证，首次打开可能被 macOS 拦截。请从本项目的 GitHub Releases 下载最新版本，再按需设置。

1. 将 `cleanMac.app` 拖入“应用程序”，尝试打开一次。
2. 打开“系统设置 → 隐私与安全性”，找到 cleanMac 被阻止的提示，点击“仍要打开”，按系统提示确认。
3. 如果需要启用“任何来源”，可按下面的说明操作。只为打开本应用时，可以先使用上面的单应用授权方式。参见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

**显示并允许“任何来源”**

打开“终端”，执行：

```bash
sudo spctl --global-disable
```

输入 Mac 管理员密码并回车；输入时终端不会显示密码字符。较新的 macOS 中，此命令会显示“任何来源”选项，仍需前往“系统设置 → 隐私与安全性 → 安全性 → 允许从以下位置下载的应用程序”，选择“任何来源”并确认。若设置页面已打开，可关闭后重新打开。

旧版 macOS 如果不支持上述参数，可使用 [Apple 文档中的旧版命令](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)：

```bash
sudo spctl --master-disable
```

**注意：允许“任何来源”会放宽整台 Mac 的应用来源检查，不只影响 cleanMac。** 请仅打开可信来源的应用；这项设置不会修复真正损坏的文件或让应用获得 Apple 公证。若仍提示“已损坏”，请先删除旧副本并重新下载最新安装包。

**恢复系统的应用来源检查**

```bash
sudo spctl --global-enable
```

旧版 macOS 对应命令为 `sudo spctl --master-enable`。也可在“隐私与安全性”中恢复为“App Store 和被认可的开发者”。

## 使用方式

1. 打开 cleanMac，点击“开始清理”进行概览扫描，或选择“深度清理”。
2. 在智能清理清单或各分类页面核对内容，再选择需要处理的项目。
3. 通过侧边栏进入“Xcode 分析”或“应用程序”，查看开发数据与应用卸载结果。

## 隐私与安全

扫描结果保留在本机。清理前请核对待处理文件；应用本体移到废纸篓，勾选的应用残留会单独删除。定时扫描不会自动删除文件。

## 构建

进入 `cleanMac` 目录后，使用 Xcode 打开 `cleanMac.xcodeproj`，选择 `cleanMac` scheme。直接运行 `./Scripts/make_dmg.sh` 会生成 `build/cleanMac-arm64.dmg` 和 `build/cleanMac-x86_64.dmg`。可用 `BUILD_ARCH=arm64` 或 `BUILD_ARCH=x86_64` 只生成一个架构，`BUILD_ARCH=universal` 生成通用包。

脚本会为 app 添加完整签名，并挂载每个 DMG 检查包内签名、版本和架构；校验失败即停止。默认使用 ad-hoc 完整性签名，这不能替代 Developer ID 和 Apple 公证，下载后仍可能被 Gatekeeper 拦截。

配置发布证书与已存入钥匙串的公证凭据后，可运行 `CODESIGN_IDENTITY="Developer ID Application: ..." NOTARY_KEYCHAIN_PROFILE="配置名称" ./Scripts/make_dmg.sh`，生成签名并公证的两个安装包。公证完成后脚本还会验证公证票据和 Gatekeeper 评估结果。

## 发布新版本

先创建 `docs/releases/v<版本号>.md`，按 `1. `、`2. `、`3. ` 编写本版实际更新内容。在 `main` 分支的 `cleanMac` 目录运行：

```bash
RELEASE_COMMIT_MESSAGE="发布 v1.0.8：优化网速、设备仪表盘与充电状态" ./Scripts/publish_release.sh 1.0.8
```

脚本自动递增构建号、更新版本号、生成并校验两个架构的 DMG，创建中文 Git 提交和版本标签，通过 SSH 原子推送到 GitHub，再等待 Actions 构建并上传两个安装包。发布完成时自动核对线上标签、版本说明和附件，并输出下载链接。Xcode 用户状态和本地构建产物不会加入提交。

后续发布统一使用此脚本，校验由脚本和 Actions 自动执行。若提交完成后推送中断，运行 `./Scripts/publish_release.sh <版本号> --resume` 继续推送；若已推送后等待中断，运行 `./Scripts/publish_release.sh <版本号> --wait-only` 继续等待。若构建阶段失败，先修复问题并将项目版本号恢复到上个已发布版本后重新运行。需要可用的 GitHub SSH 推送权限；GitHub Actions 的发布工作流使用仓库自带的 `github.token`。

## 开发支持

首次完成手动完整扫描后，应用会展示一次自愿打赏提示；之后仍可从“设置 → 开发支持 → 请我喝杯咖啡”查看。打赏不影响任何清理功能。

![cleanMac 支付宝和微信打赏弹窗](docs/screenshots/first-scan-support.png)
