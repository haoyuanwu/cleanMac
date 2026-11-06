# 签名与权限连续性

## 当前诊断

2026-11-04 检查到本机安装副本和发布暂存副本均为 ad-hoc 签名，无 TeamIdentifier。`codesign -d -r-` 的 designated requirement 仅包含 cdhash，两个副本的 cdhash 不同。签名身份随具体构建改变，可以解释更新后先前授权不再匹配的现象；不能据此断言同一份未修改安装包每次重复安装都必然失去权限。

本机有效签名身份清单中只有 Apple Development，尚未发现 Developer ID Application。现有废纸篓扫描直接读取用户及外接卷废纸篓，没有会跨安装保存系统授权的 bookmark 逻辑；UserDefaults 标志不能代替系统的完全磁盘访问授权。

## 发布配置要求

1. 使用固定开发者团队的 Developer ID Application 身份，以及 `com.cleanMac.cache.cleanMac` Bundle ID；后续版本保持兼容的 designated requirement。不能仅指定一个没有证书约束的 identifier 来冒充稳定的发布身份。
2. 本机安装好证书及对应私钥后，现有打包脚本可使用以下参数签名、公证和验证：

   ```bash
   CODESIGN_IDENTITY="Developer ID Application: 开发者名称 (TEAMID)" \
   NOTARY_KEYCHAIN_PROFILE="cleanMac-notary" \
   ./Scripts/make_dmg.sh
   ```

3. 正式发布仍通过 `Scripts/publish_release.sh <新版本号>`。GitHub Actions 的构建环境也需配置同一团队的证书与公证凭据；仅在本机签名不会改变 Actions 重新构建的安装包身份。目前工作流未配置证书导入，默认仍为 ad-hoc，尚未解决正式发布的权限连续性。
4. 正式签名与公证完成后再更新实际版本的发布说明。完整性校验通过、Apple Development 签名、Developer ID 签名、Apple 公证应分别如实记录。
5. 从当前 ad-hoc 身份迁移到 Developer ID 后可能需要一次用户重新授权。以后是否保留授权仍由 macOS 根据签名身份和系统策略决定，不能承诺永不需要授权。

## 当前权限恢复

完全退出旧进程，将所需版本安装到 `/Applications/cleanMac.app`，在完全磁盘访问列表移除失效条目并重新添加该副本，开启权限后重启应用。仅替换当前应用的授权条目，无需重置整个隐私数据库、修改其内容或关闭系统安全机制。

检查签名身份可使用只读命令：

```bash
security find-identity -v -p codesigning
codesign -dv --verbose=2 /Applications/cleanMac.app
codesign -d -r- /Applications/cleanMac.app
```

## 官方依据

- [TN3127: Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
