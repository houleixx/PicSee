# PicSee

PicSee 是一个面向 macOS 的轻量级图片查看器，主打“Finder 双击即开、看完即退”。它支持滚轮缩放、键盘切图、OCR 选字复制，并同时兼容 Apple Silicon 与 Intel 芯片。

## 功能

- Finder 双击图片直接打开
- 多窗口独立查看，关闭一个窗口只退出当前进程
- 滚轮缩放图片
- 放大后拖动图片空白区域可平移图片
- 鼠标移动到文字区域时显示 I 形光标，可拖选并复制图片中文字
- `Cmd + C` 复制当前选中的图片文字
- `← → ↑ ↓` 切换同目录图片
- `Esc` 关闭当前图片并退出应用
- 右键菜单支持“复制图片路径”

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

- App Bundle: `/Users/holly/code/Demo/PicSee/build/PicSee.app`
- 本地安装副本: `/Users/holly/Applications/PicSee.app`

如果只想构建，不自动安装到本机应用目录：

```bash
PICSEE_SKIP_LOCAL_INSTALL=1 Scripts/build-app.sh
```

指定版本号构建：

```bash
PICSEE_VERSION=0.2.2 PICSEE_BUILD_NUMBER=1 Scripts/build-app.sh
```

## 生成 DMG 安装包

生成 DMG：

```bash
Scripts/build-dmg.sh
```

构建完成后会得到：

- DMG: `/Users/holly/code/Demo/PicSee/build/dmg/PicSee-0.2.2.dmg`

同样可以指定版本号：

```bash
PICSEE_VERSION=0.2.2 Scripts/build-dmg.sh
```

## 使用方式

### 1. 从 Finder 打开

把 PicSee 设为默认图片查看器后，直接在 Finder 中双击图片即可打开。

### 2. 基本交互

- 拖动顶部标题区域：移动窗口
- 滚动鼠标滚轮：放大 / 缩小图片
- 放大后拖动非文字区域：移动图片可视区域
- 光标移到可识别文字上：显示 I 形光标，可拖选文字
- `Cmd + C`：复制选中的文字
- `Esc`：关闭当前窗口并退出当前实例

### 3. 切图

- `←` / `↑`：上一张
- `→` / `↓`：下一张

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
git tag v0.2.2
git push origin v0.2.2
```

工作流会自动生成：

- Release: `v0.2.2`
- Asset: `PicSee-0.2.2.dmg`

## Release 说明

当前工作流生成的是 **未签名 DMG**。  
它适合内部使用或自有机器安装；如果要面向外部分发，建议后续补上：

- `Developer ID Application` 签名
- `Developer ID Installer` / `notarization`
- Staple notarization ticket

## 项目结构

```text
Sources/PicSee/App/         应用生命周期、窗口管理、打开图片路由
Sources/PicSee/Navigation/  同目录图片导航
Sources/PicSee/Viewer/      图片显示、缩放、OCR 选字、键盘交互
Scripts/                    本地构建脚本（app / dmg）
Tests/PicSeeTests/          单元测试与 OCR 回归测试
```
