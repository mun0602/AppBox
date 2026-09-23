# 临时邮箱 1.0 商店素材

这里包含 iPhone App Store 产品页的第一轮验收素材。

## 文件

- `screenshots/contact-sheet.png`：五张截图总览，优先用于验收。
- `screenshots/iphone-6.9/*.png`：1320 × 2868 px 单张文件。
- `screenshots/source/real-device.html`：以 iPhone 15 真机截图为主体的视觉源文件。
- `screenshots/source/render.mjs`：本地渲染与尺寸/透明度检查脚本。
- `metadata/zh-Hans.md`：中文元数据草案。

## 当前状态

外层商店排版、文案和产品界面层级已经完成。产品画面来自连接的 iPhone 15（1179 × 2556 px）实际运行截图；仅将真实邮箱地址和随手测试邮件替换为安全的演示内容，避免泄露个人信息。最终输出为 iPhone 6.9 英寸商店规格 1320 × 2868 px。

## 重新生成

```bash
NODE_PATH=/Users/king/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
  /Users/king/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
  screenshots/source/render.mjs
```
