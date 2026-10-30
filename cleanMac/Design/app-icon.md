# App 图标与扫描入口

App 图标使用纯色浅背景、青紫粉拼色笔记本、深色屏幕和三颗星光。笔记本绘图区域占图标宽度的 84%，比上一版增加约 14%。各尺寸共用 `CleanMacLogo.swift` 矢量源，避免缩放后图形比例不一致。

重新生成 16–1024px 图标：

```sh
swiftc cleanMac/Views/Components/CleanMacLogo.swift Scripts/render_app_icon.swift -o /tmp/render-cleanmac-icon
/tmp/render-cleanmac-icon "$PWD"
```

首页“开始扫描”使用独立的巡检助手与放大镜，不复用 App 图标。待机和扫描保留同一绘图视图，点击后弹簧放大，文档逐渐出现，放大镜开始巡检；取消后回到待机。减少动态效果设置会停用位移动画，保留真实进度与路径反馈。

验证：Debug 构建成功，138 项核心与回归测试通过。已在独立测试应用中检查待机图形、启动扫描、实时进度和路径、取消恢复、模块切换与快捷键；关闭窗口后进程继续运行，重新打开能恢复主窗口。没有执行真实清理操作。
