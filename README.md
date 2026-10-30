<p align="center">
  <img src="Resources/AppIcon.icns" width="128" height="128" alt="PureZip Icon" />
</p>

<h1 align="center">PureZip</h1>

<p align="center">
  <strong>专为 macOS 打造的现代化、高颜值、极速双模态原生归档与解压工具</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-success" alt="Architecture" />
  <img src="https://img.shields.io/badge/Swift-5.10%2B-orange?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

---

## 🌟 核心理念与亮点

传统的 macOS 压缩解压工具要么只能全量解压到文件夹、缺少交互；要么界面陈旧、功能臃肿。**PureZip** 采用现代 SwiftUI + AppKit 深度混编架构，结合后台独立 XPC 隔离服务，带来颠覆性的归档管理体验：

* 💊 **即用即走（Pure Capsule）**：双击压缩包默认唤起轻巧精悍的胶囊浮窗，直接预览内部文件、按需拖出提取，零负担不占桌面。
* 🖥️ **深度掌控（Pure Desk）**：大型多层级归档一键无缝展开为专业工作区，支持图标/列表/分栏三栏视图、SQLite WAL 高性能目录检索与平滑缩放。
* 📦 **随航暂存台（Pure Shelf）**：主窗口欢迎首页与 macOS 顶部菜单栏深度联动，零散文件随时拖入收集，一键打包为 ZIP/7z/Tarball。
* 🔍 **嵌套压缩包深度穿透**：直接在归档内双击展开子压缩包，支持多层级无缝面包屑导航、悬浮实时透视卡片与一键递归完全解压。
* 👁️ **全能多媒体与 3D 即时预览**：
  * **3D 模型**：集成 Google `<model-viewer>` 与 macOS 原生 `SceneKit` 引擎，可直接渲染查看 `.glb`、`.gltf`、`.obj`、`.dae`、`.usdz` 等。
  * **音视频**：支持 4K/8K 视频低分辨率流畅轮播预览，以及原生音频真实声学 RMS 波形采样播放器。
  * **文档与代码**：PDF 矢量高清渲染、Office/Keynote 缩略图、带高亮与格式化表格的 Markdown/代码查看器。
* 💿 **DMG 拟物安装画布**：自动识别 `.dmg` 磁盘镜像结构，提取内部应用的真实高分辨率图标，呈现原生拖拽安装交互。
* 🛡️ **生产级安全与稳健架构**：
  * 彻底防御 Zip-Slip 目录穿越漏洞。
  * 智能剔除 macOS `__MACOSX`、`.DS_Store`、`._*` 噪音元数据。
  * 自动智能识别并解码 GB18030、GBK、Big5、Shift-JIS、EUC-KR 等旧式 Windows 中日韩非 UTF-8 乱码文件名。
* 🔌 **系统原生深度融合**：
  * 访达（Finder）右键折叠菜单扩展。
  * 系统空格键 QuickLook 插件支持。
  * 独立命令行工具 `purezip-cli`。

---

## 📦 支持的格式

| 分类 | 格式扩展名 | 功能支持 |
| :--- | :--- | :--- |
| **主流归档** | `.zip`, `.zipx`, `.7z`, `.tar` | 浏览、流式解压、事务打包、追加更新、密码保护 |
| **高压缩率 / 常见** | `.rar`, `.cbr`, `.cbz` | 浏览、解压、分卷合并查看、密码解密 |
| **压缩流 / 归档流** | `.gz`, `.tgz`, `.bz2`, `.tbz2`, `.xz`, `.txz`, `.lzma`, `.lz` | 极速流式解压缩与打包 |
| **磁盘镜像 / 安装包** | `.dmg`, `.iso`, `.pkg`, `.app` | 智能结构透视、应用提取、虚拟化画布 |
| **分卷切片** | `.7z.001`, `.part1.rar`, `.z01`, `.zip.001` 等 | 智能分卷家族识别与自动去重解压 |

---

## 🚀 快速开始与构建

### 系统要求
* macOS 14.0 (Sonoma) 或更高版本
* Xcode 15.0+ 或 Command Line Tools
* 支持 Apple Silicon (M1-M4) 及 Intel (x86_64)

### 编译与打包
项目提供了全自动编译、签名与组装脚本：

```bash
# 克隆仓库
git clone https://github.com/Minato-chen/PureZip.git
cd PureZip

# 自动编译所有 Target 并组装 App Bundle、XPC 及 App Extensions
./scripts/build_app.sh

# 编译完成后直接启动
open dist/PureZip.app
```

### 运行自动化测试套件
```bash
swift test
```

---

## 🛠️ 项目架构

```
PureZip/
├── Sources/
│   ├── ArchiveCore/          # 核心数据模型、SQLite 目录索引、编码识别与配置存储
│   ├── ArchiveEngines/       # 调度中心 (Broker)、原生 ZIP 引擎、7zz 封装、DMG/Tar 引擎
│   ├── PureZipApp/           # SwiftUI + AppKit 视图层 (Pure Shelf / Capsule / Desk / 预览器)
│   ├── PureZipArchiveService/# 独立后台 XPC 沙盒工作进程
│   ├── PureZipCLI/           # purezip-cli 命令行与完整自检测试链
│   ├── PureZipFinderSupport/ # 跨进程访达交互通信通道
│   ├── PureZipFinderSync/    # macOS Finder 扩展
│   └── PureZipQuickLook/     # 系统原生空格键 QuickLook 预览插件
├── Support/                  # Info.plist 与 Entitlements 签名配置
├── Resources/                # 图标及必要辅助资源
└── scripts/                  # 自动化构建与分发脚本
```

---

## 📄 开源许可证

本项目基于 [MIT 许可证](LICENSE) 开源。欢迎提交 Issue 与 Pull Request 共同完善 PureZip！
