# PicSee 官网

这是一个零构建步骤的静态网站，可直接发布到 Cloudflare Pages。

## 中英文版本

- 中文首页为 `/`（`index.html`），英文首页为 `/en/`（`en/index.html`）。导航栏通过「中文 / EN」链接切换。根地址 `/`（含 `/index.html`）优先使用 `localStorage` 中的 `picsee-language` 手动选择；没有有效偏好时，按浏览器首选语言判断：`zh` 及其地区变体使用中文，其余使用英文。浏览器通常跟随系统语言，但可单独设置。
- 直接访问 `/en/` 保持英文，不覆盖用户已保存的偏好；只有手动点击语言选项才保存偏好。自动跳转使用 `location.replace()`，保留查询参数和锚点，避免返回时反复跳转。
- 语言脚本 `assets/language-*.js` 在页面头部执行，尽早决定语言。存储不可用时，手动切换通过 `?lang=zh-CN` 或 `?lang=en` 保持有效，但无法跨访问记住选择；禁用 JavaScript 时仍可通过普通链接浏览两页。
- 两页共用 `assets/styles-*.css` 和图片。资源引用使用 `/assets/` 绝对路径，确保英文子目录也能正确加载。
- 修改功能文案时需同步更新两份 HTML，包括图片 alt、辅助功能标签、标题、描述、分享卡片和 JSON-LD。英文页的中文语言选项有意保留中文。
- 两页使用各自的 canonical，通过相同的 `hreflang` 链接关联 `zh-CN`、`en` 和指向中文首页的 `x-default`；站点地图包含两个首页。共用 404 页面提供中英文返回入口。
- 修改共用 CSS 或语言脚本后，按文件内容的 SHA-256 前 8 位重命名，并同步更新两页引用，避免长期缓存旧样式。

语言逻辑回归检查：在仓库根目录执行 `node --test Tests/Website/language.test.cjs`（仅使用 Node 内置模块，无需安装依赖）。

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

## 搜索与分享

正式地址为 `https://picsee.pages.dev/`。首页包含 canonical、Open Graph、Twitter Card，以及 `WebSite` / `SoftwareApplication` JSON-LD。JSON-LD 只提供机器可读数据，不执行页面逻辑。应用信息使用真实功能、免费价格和系统要求，不添加虚构评分，也不承诺获得搜索富结果。

关键词自然分布在页面标题、描述和原有功能介绍中，围绕 Mac 图片查看、OCR 图片文字识别、图片裁剪标注和默认打开方式展开；H1 保持产品名 PicSee。不为 SEO 增加副标题、系统信息标题或 FAQ 板块。不依赖 `meta keywords`：[Google 明确不使用该标签进行索引或排名](https://developers.google.com/search/docs/crawling-indexing/special-tags)。

- `robots.txt` 允许抓取，并指向 `sitemap.xml`；站点地图列出中英文首页。
- `404.html` 提供不存在页面的返回入口，避免 Cloudflare Pages 将未知路径当作单页应用首页返回；错误页带 `noindex`。
- 分享预览使用 JPEG 版本的首页插画，不额外加载到页面正文中。
- 正式域名变更时，需要同步修改中英文首页 canonical、hreflang、`og:url`、分享图片绝对地址、JSON-LD、`robots.txt` 和 `sitemap.xml`。

部署后可在 Google Search Console 和 Bing Webmaster Tools 中验证站点并提交 `https://picsee.pages.dev/sitemap.xml`，随后检查实际抓取与索引结果。文件更新本身不代表搜索引擎已经完成收录。

## 资源与缓存

`assets/` 中发布的资源统一使用 SHA-256 前 8 位作为文件名后缀，并设置一年 `immutable` 缓存；替换内容时必须更换文件名及引用。96×96 favicon 约 10 KB，原始品牌图保存在 `../docs/website/brand-icon-source.png`，不随网页发布。

中英文首页每次使用缓存前重新验证，robots 和 sitemap 缓存一小时。缓存规则使用互不重叠的路径，避免 Cloudflare Pages 将重复的 `Cache-Control` 值合并。[规则说明](https://developers.cloudflare.com/pages/configuration/headers/)。`README.md` 通过响应头设置 `noindex`。

本地 Python 服务器不解析 Cloudflare 的 `_headers`，响应头和线上 404 状态仍需在部署后核实。

## 功能展示顺序

1. 滚轮缩放与拖动平移
2. 图片裁剪与标注
3. OCR 选字复制
4. 方向键切图
5. 设置默认图片查看器

配图位于 `assets/`，以 `index.html` 中的引用为准。同步修改 `index.html`、`en/index.html` 和共用资源文件即可更新网站，无需构建。
