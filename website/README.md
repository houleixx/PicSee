# PicSee 官网

这是一个零构建步骤的静态网站，可直接发布到 Cloudflare Pages。

## Cloudflare Pages 部署

1. 在 Cloudflare Dashboard 新建 **Pages** 项目，并连接此 GitHub 仓库。
2. Framework preset 选择 **None**。
3. Build command 留空。
4. Build output directory 填写 `website`。
5. 保存并部署。

网站的下载与 GitHub 链接均在新窗口/标签页打开。3 个最新版下载入口直接使用固定地址：
`https://github.com/houleixx/PicSee/releases/latest/download/PicSee.dmg`。
Release workflow 在最终 DMG 验证后复制并校验 `PicSee.dmg`，与带版本号的 DMG 一同上传。发布新版本无需修改网站下载 URL，也不需要 Worker、Pages Function 或 GitHub API 查询。
首次部署此链接前，Latest Release 需要已包含 `PicSee.dmg`。

## 当前配图

首页采用方案 2「柔和立体」，包含 Banner 和五个功能模块配图。
6 张图片均由生成原始 PNG 压缩为 WebP：Banner 为 1200×1000，功能配图为 1080×720，总体积约 421 KB。
资源文件名包含内容哈希，替换图片时应更新文件名和页面引用，以配合长期缓存。
选定方案的提示词及压缩参数保存在 `../docs/website/image-prompts.json`。

本地预览：`python3 -m http.server 8765 --bind 127.0.0.1 --directory website`，然后打开 `http://127.0.0.1:8765/`。

## 功能展示顺序

1. 滚轮缩放与拖动平移
2. 图片裁剪与标注
3. OCR 选字复制
4. 方向键切图
5. 设置默认图片查看器

配图位于 `assets/`，以 `index.html` 中的引用为准。修改 `index.html` 和资源文件即可更新网站，无需构建。
