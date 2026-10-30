# Sidebar icons

## Current module navigation

The seven module navigation icons are original SwiftUI Canvas drawings in
`cleanMac/Views/Components/WorkspaceModuleIcon.swift`, on a 24pt grid with 1.7pt
rounded strokes. They inherit navigation colors and retain accessible module
names, tooltips, focus feedback and keyboard shortcuts.

| Module | Drawing |
| --- | --- |
| 一键清理 | Star inside a magnifying glass |
| 垃圾清理 | Broom and sparkle |
| 文件整理 | Layered folder and file lines |
| 应用与开发 | App grid and code brackets |
| 磁盘分析 | Partitioned disk |
| 偏好与保护 | Shield and adjustment sliders |
| 设备信息 | Monitor with a resource pulse |

## Existing category assets

The sidebar icons in `cleanMac/Assets.xcassets/Sidebar*.imageset` are from Iconfont. Most are from the [线性图标库 collection](https://www.iconfont.cn/collections/detail?cid=43240), created by 祁一吖. The trash and cleaned icons come from the [framework7 collection](https://www.iconfont.cn/collections/detail?cid=20048), created by tal007. All use their original 1024 × 1024 SVG paths and are rendered as template images so the app's existing colors still apply.

| Asset | Iconfont name | Icon ID | Collection |
| --- | --- | --- | --- |
| SidebarOverview | 首页_home | 33385459 | 线性图标库 |
| SidebarSystemCache | 文件柜_file-cabinet | 33385473 | 线性图标库 |
| SidebarLogs | 文档架子_document-folder | 33385465 | 线性图标库 |
| SidebarBrowserCache | 预览-打开_preview-open | 33385486 | 线性图标库 |
| SidebarTrash | trash | 12310509 | framework7 |
| SidebarAppLeftover | 链接断开_unlink | 33385435 | 线性图标库 |
| SidebarDownloads | 下载2_download-two | 33385478 | 线性图标库 |
| SidebarLargeFiles | 全局放大1_full-screen-one | 33385448 | 线性图标库 |
| SidebarApplications | 全部_all-application | 33385450 | 线性图标库 |
| SidebarInstallers | 压缩文件_file-zip | 33385484 | 线性图标库 |
| SidebarXcode | 代码文件夹_folder-code | 33385418 | 线性图标库 |
| SidebarSettings | 设置_setting-two | 33385472 | 线性图标库 |
| SidebarInfo | 信息_info | 33385490 | 线性图标库 |
| SidebarWarning | 注意_attention | 33385487 | 线性图标库 |
| SidebarCleaned | checkmark_alt_circle | 12309718 | framework7 |
