# Design System — PicSee Website

## Product Context

- **What this is:** PicSee 是一款原生 macOS 图片查看器，解决快速看图时打开慢、操作绕、关闭后仍留在 Dock 的问题。
- **Who it's for:** 希望从 Finder 快速浏览图片的 macOS 用户。
- **Project type:** 产品介绍与下载落地页。

## Aesthetic Direction

- **Direction:** Quiet Gallery（安静画廊）。
- **Decoration level:** Intentional。页面像一面留白充足的画墙，截图是主角，色彩只承担导航和信息层级。
- **Mood:** 清醒、快速、有质感，不做 macOS 官网的复制品。

## Typography

- **Display / Body:** `-apple-system, BlinkMacSystemFont, "PingFang SC"`。网站服务 macOS 用户，采用系统字形能使中文阅读与应用体验连续。
- **Scale:** 12 / 13 / 14 / 16 / 17 / 20 / 23 / 50–86px，标题使用紧凑字距，正文保持舒展行高。

## Color

- **Approach:** 克制的中性色加单一功能蓝。
- **Canvas:** `#F7F7F4`
- **Surface:** `#FFFFFF`
- **Ink:** `#171716`
- **Muted:** `#6C6C68`
- **Primary:** `#1677E8`，仅用于行动按钮、链接和关键状态。
- **Warm marker:** `#FC543D`，仅用于叙事编号，帮助扫读。
- **Dark surface:** `#161715`，用于 OCR 功能段，形成一次明确的节奏切换。

## Layout

- **Approach:** 画廊式编辑布局，首屏信息优先，应用截图承担证明作用。
- **Grid:** 桌面端首屏与故事段使用 2 栏；平板及手机端自然折叠为单栏。
- **Max content width:** 由页面内边距 `clamp(22px, 5.5vw, 88px)` 控制，避免内容贴边。
- **Border radius:** 截图 15px，内容面板不使用普遍圆角，避免模板化。

## Motion

- **Approach:** Minimal-functional。
- **Duration:** 200ms hover，仅用于按钮和信息面板，页面不使用干扰阅读的滚动动画。

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-08-24 | 使用 Quiet Gallery 方向 | 让用户在首屏即理解产品与三个关键功能，同时保持应用截图的视觉分量。 |
