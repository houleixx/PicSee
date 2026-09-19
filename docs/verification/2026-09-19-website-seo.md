# 官网结构与 SEO 验证

正式地址：`https://picsee.pages.dev/`。

## 修改范围

- 页面标题、描述、可见 H1、功能正文和六条常见问题覆盖真实使用场景。
- 添加 canonical、Open Graph、Twitter Card、WebSite / SoftwareApplication JSON-LD、robots 和 sitemap。
- 添加独立 404 页面；主内容语义、跳过导航、焦点样式与减少动画偏好。
- 清理未使用样式，使用 Grid 区域实现左右交错；窄屏隐藏导航副标题，下载区允许换行。
- favicon 从 186,693 字节缩小为 10,321 字节；品牌资源使用内容哈希；缓存规则消除重复 max-age。

## 已完成检查

- 本地资源引用、SEO 元数据、JSON-LD、下载链接、robots、sitemap、资源哈希与缓存规则检查：通过。
- `git diff --check`：通过。
- 本地独立无头 Chrome：320、375、480、768、800、1024、1440px，均无横向溢出，八张正文图片全部成功加载，桌面交错与移动端图片在前的顺序正确。
- Tab 首次定位「跳到主要内容」，Enter 后聚焦 main；FAQ 页脚锚点正确。
- `prefers-reduced-motion: reduce` 下平滑滚动关闭。
- 三个下载入口一致；canonical、robots、sitemap、favicon、分享图片可读取；404 返回首页链接正常。
- 浏览器无页面异常或资源请求错误。人工检查 375px、1440px 全页截图，布局正常。

## 验证边界

本次只修改本地文件，未部署或向搜索平台提交站点。Python 静态服务器不解释 Cloudflare `_headers`，没有验证线上缓存响应头和 Cloudflare 404 HTTP 状态；这些应在部署后复核。未运行与本次官网修改无关的 Swift 测试。

## 参考

- [Google 支持的 meta 标签](https://developers.google.com/search/docs/crawling-indexing/special-tags)
- [Google 软件应用结构化数据](https://developers.google.com/search/docs/appearance/structured-data/software-app)
- [Cloudflare Pages 响应头规则](https://developers.cloudflare.com/pages/configuration/headers/)
- [Cloudflare Pages 路由与 404 行为](https://developers.cloudflare.com/pages/configuration/serving-pages/)
