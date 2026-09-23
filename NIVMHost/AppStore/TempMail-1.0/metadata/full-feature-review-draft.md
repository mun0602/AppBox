# 完整功能版提交资料草案

状态：用户于 2026-09-15 选择完整功能版。尚未上传构建或提交审核。

已完成：Apple Developer 后台确认 `com.tianya.tempmail` 已注册到 CHANDO VIETNAM COMPANY LIMITED（CGQ2C488AD），名称 TempMail。

App Store Connect 应用已创建：6811984656，商店名 `TempMail 临时邮箱`，SKU `tempmail-ios-001`，主要语言简体中文，版本 1.0，状态准备提交。原名称“临时邮箱”被 Apple 提示已占用。新名称和副标题已在后台保存并确认。

后台：https://appstoreconnect.apple.com/apps/6811984656/distribution

打包脚本已将 `TEAM_ID` 传入 archive 的 `DEVELOPMENT_TEAM`，避免 archive 继续使用工程原团队。已通过 `bash -n`。

2026-09-15 已完成手动发行签名：公司发行证书与 `TempMail AppStore CGQ2C488AD` 描述文件匹配，完整功能版 1.0（3）archive、export、深度签名及 ZIP 完整性验证通过。日志：`/tmp/tempmail-appstore-manual-build.log`。

IPA：`/Users/king/Documents/GitHub/AppBox/NIVMHost/dist/TempMail-appstore-optimized-20260915-100722/export/TempMail.ipa`

大小：117050828 字节；SHA-256：`3e90c68e47af5f5fd9a493eac1fdb456f1dce5a8d670bbf21906df550ef0f05f`。

尚未上传。Transporter 首次启动停在 EA1914 软件许可协议，已请求用户确认接受。

## 商店展示调整

用户要求不强调应用空间。商店名称已保存为 `TempMail 临时邮箱`；副标题已保存为“快速收取一次性邮件”，推广文本以邮箱功能为主。

## 商店描述

TempMail 临时邮箱为短期收信场景提供简洁、清晰的邮箱体验。

快速创建邮箱地址，复制后用于需要接收邮件的网站或服务。在收件箱中查看发件人、主题、时间与邮件正文，识别未读邮件和附件，管理多个邮箱地址，并按喜好切换浅色与深色外观。

临时邮箱适用于短期、非敏感的收信场景，请勿用于需要长期保存或涉及重要账户凭证的邮件。

除临时邮箱外，本应用还包含应用空间：从服务端目录查看可用应用、下载应用包、管理已下载应用，并通过内置运行环境运行受支持的应用。可用内容由服务端目录提供，实际功能取决于所运行的应用。

## 审核备注草案

临时邮箱功能测试步骤：

1. 首次打开 App 后会自动初始化邮箱会话，无需手动注册或登录。
2. 复制当前临时邮箱地址，使用其他邮箱向该地址发送测试邮件。
3. 打开“收件箱”，等待邮件自动刷新，或下拉刷新，然后点开邮件查看发件人、主题和正文。
4. 如测试邮件带有附件，可在邮件详情中查看并下载附件。
5. 在“管理”页面创建、切换或删除临时邮箱地址；在设置中切换浅色与深色外观。

测试收信需要网络连接。建议使用不包含敏感信息的测试邮件。

## 待完成

- 用户确认 Transporter 许可协议后上传构建，等待 App Store Connect 处理完成。
- 核对最终构建版本、完整功能、运行稳定性及所有实际网络服务。
- 补充真实应用空间截图；现有五张截图仅覆盖邮箱。
- 审核联系人已提供 CHANDO、4788746005、xgcgbllvk34455383@tmpbox.net；待补充姓氏与电话国家区号。版本表单因缺少姓氏保存失败，已保留页面，不能视为已保存。
- 核查邮箱内容、附件、匿名用户及设备标识、服务端日志和应用空间数据处理，填写准确的隐私声明。
- 按完整目录与可运行内容填写年龄分级、内容权利及相关问卷。
- 若分发到欧盟，完成后台提示的交易商状态申报。

参考：https://developer.apple.com/app-store/review/guidelines/ （2.3.1 要求完整披露功能）。

## 2026-09-15 支持网站部署

Cloudflare Worker `tempmail-support` 已部署，版本 `48547f8a-1bfa-473f-a0d8-4d49aec06d9b`。

- 支持网址：https://tempmail.9355.my/support
- 隐私网址：https://tempmail.9355.my/privacy
- 网站源代码：`/Users/king/Documents/GitHub/AppBox/tempmail-support-site`
- 9355.my 已有 A 记录，因此使用其子域名，不改动现有主域名记录。
- 公网页面浏览器验收完成；首页、支持、隐私、CSS 均已使用 curl 确認 HTTP 200。
- 支持内容包含使用方法、故障排查、删除请求联系方式。隐私政策依据客户端会话、邮件、远程图片和服务端软删除实现编写。
