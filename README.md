# PicSee

PicSee 是一个面向 macOS 的轻量级图片查看器，主打“Finder 双击即开、看完即退”。它支持滚轮缩放、键盘切图、OCR 选字复制，并同时兼容 Apple Silicon 与 Intel 芯片。

## 项目背景

macOS 自带的「预览」在快速看图时有两处常见不便：**鼠标滚轮无法缩放**，且**关闭窗口后主进程仍留在 Dock**，往往需要再手动退出一次。PicSee 正是为化解这些摩擦而做：在轻量前提下，提供 **滚轮缩放**、**`Esc` 退出**，以及**关闭窗口即结束当前应用实例**的一气呵成体验；并在此基础上集成了实用的 **OCR 文字复制**（拖选图片中的文字、`Cmd + C` 复制）。

## 应用预览

PicSee 提供简洁的无边框看图界面，可直接查看图片信息，并通过底部工具栏完成全屏、原始尺寸、缩放和旋转等操作。

<p align="center">
  <img src="Images/preview.png" alt="PicSee 图片查看界面" width="850">
</p>

### 设置为默认图片查看器

内置的默认打开方式设置窗口支持 JPEG、PNG、GIF、HEIC、TIFF、BMP、WebP 及常见 RAW 格式，可按需选择希望交给 PicSee 打开的图片类型。文件夹浏览也支持 AVIF、SVG、ICO/ICNS、JPEG 2000、PSD/PSB、TGA、DDS、EXR/HDR 和 JPEG XL；专业格式是否能完整解码取决于当前 macOS 的 ImageIO 解码器及文件内嵌预览。

<p align="center">
  <img src="Images/preview-default.png" alt="PicSee 设置默认图片打开方式窗口" width="700">
</p>

## 功能

- Finder 双击图片直接打开
- 可按图片格式将 PicSee 设置为默认图片查看器
- 多窗口独立查看，关闭一个窗口只退出当前进程
- 滚轮缩放图片
- 放大后拖动图片空白区域可平移图片
- 鼠标移动到文字区域时显示 I 形光标，可拖选并复制图片中文字
- `Cmd + C` 复制当前选中的图片文字
- `← → ↑ ↓` 切换同目录图片
- 切图顺序跟随 Finder 当前显示顺序（需授权自动化权限）；无法读取时安全回退到文件名顺序
- 双击图片进入或退出 macOS 原生全屏
- `Esc` 关闭当前图片并退出应用
- 右键菜单支持复制图片路径、切换跟随系统 / 浅色 / 深色主题

## 运行环境

- macOS 14 及以上
- Xcode Command Line Tools 或完整 Xcode
- Swift 6

## 本地开发

先运行测试：

```bash
swift test
```

本地构建应用：

```bash
Scripts/build-app.sh
```

构建完成后会得到：

- App Bundle: `build/PicSee.app`
- 本地安装副本: `~/Applications/PicSee.app`

如果只想构建，不自动安装到本机应用目录：

```bash
PICSEE_SKIP_LOCAL_INSTALL=1 Scripts/build-app.sh
```

指定版本号构建：

```bash
PICSEE_VERSION=0.2.43 PICSEE_BUILD_NUMBER=43 Scripts/build-app.sh
```

## 生成 DMG 安装包

生成 DMG：

```bash
Scripts/build-dmg.sh
```

构建完成后会得到：

- DMG: `build/dmg/PicSee-0.2.43.dmg`

同样可以指定版本号：

```bash
PICSEE_VERSION=0.2.43 Scripts/build-dmg.sh
```

## 使用方式

### 1. 从 Finder 打开

把 PicSee 设为默认图片查看器后，直接在 Finder 中双击图片即可打开。

### 2. 基本交互

- 拖动顶部标题区域：移动窗口
- 滚动鼠标滚轮：放大 / 缩小图片
- 双击图片：在适合窗口状态下进入或退出原生全屏；已缩放或平移时恢复适合窗口
- 放大后拖动非文字区域：移动图片可视区域
- 光标移到可识别文字上：显示 I 形光标，可拖选文字
- `Cmd + C`：复制选中的文字
- `Esc`：关闭当前窗口并退出当前实例

### 3. 切图

- `←` / `↑`：上一张
- `→` / `↓`：下一张

Finder 能通过系统脚本接口返回可靠顺序时，PicSee 会按该顺序切图。首次查询时，系统会弹出一次自动化授权请求；无法可靠读取时，PicSee 会立即使用文件名顺序，不阻塞翻页。

**回退到文件名排序的情况：**
- 未授权自动化权限
- Finder 窗口未打开或找不到对应文件夹
- 列视图（Column View）或画廊视图（Gallery View）
- 列表视图按"日期添加"排序
- Finder 使用分组或其他脚本接口无法可靠描述的排列方式
- 查询超时或失败

回退时使用文件名的自然排序（localized standard compare），与 Finder 的"按名称排序"一致。

## GitHub Actions 自动打包 DMG 并发布 Release

仓库内已经包含工作流：

- Workflow: `.github/workflows/release.yml`

这个工作流会在 **推送版本标签** 时自动：

1. 检出代码
2. 构建 Universal 2 的 `PicSee.app`
3. 打包生成 `dmg`
4. 创建对应的 GitHub Release
5. 把 `dmg` 作为 Release 附件上传

### 触发方式

先提交代码并推送：

```bash
git push origin master
```

再创建版本标签并推送：

```bash
git tag v0.2.43
git push origin v0.2.43
```

工作流会自动生成：

- Release: `v0.2.43`
- Asset: `PicSee-0.2.43.dmg`

## Release 说明

工作流默认使用 Developer ID 证书签名并提交 Apple notarization；如果未配置
证书 secrets，则自动回退到 **Ad-hoc 签名**（跳过 notarization），DMG 仍
会正常上传和发布。

### 配置证书（可选，用于正式发行）

如需使用 Apple 公证签名（用户打开时不会出现 Gatekeeper 拦截），需要在仓库
Settings → Secrets 中配置：

- `MACOS_CERTIFICATE_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

## 项目结构

```text
Sources/PicSee/App/         应用生命周期、窗口管理、打开图片路由
Sources/PicSee/Navigation/  同目录图片导航
Sources/PicSee/Viewer/      图片显示、缩放、OCR 选字、键盘交互
Scripts/                    本地构建脚本（app / dmg）
Tests/PicSeeTests/          单元测试与 OCR 回归测试
```
