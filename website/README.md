# PicSee 官网

这是一个零构建步骤的静态网站，可直接发布到 Cloudflare Pages。

## Cloudflare Pages 部署

1. 在 Cloudflare Dashboard 新建 **Pages** 项目，并连接此 GitHub 仓库。
2. Framework preset 选择 **None**。
3. Build command 留空。
4. Build output directory 填写 `website`。
5. 保存并部署。

网站中的下载按钮会指向 GitHub 的最新 Release 页面。

## 功能展示顺序

1. 滚轮缩放与拖动平移
2. 图片裁剪与标注
3. OCR 选字复制
4. 方向键切图
5. 设置默认图片查看器

裁剪与标注配图位于 `assets/feature-crop-annotate-v6.png`。修改 `index.html` 和资源文件即可更新网站，无需构建。
