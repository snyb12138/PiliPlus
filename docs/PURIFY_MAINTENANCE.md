# PiliPlus 净化增强版维护说明

## 分支约定

- `main`：保留个人 fork 的上游跟踪分支。
- `feat/danmaku-filter-assistant`：原 PR #3222 的提交分支，继续用于与上游沟通。
- `purify`：净化增强版的长期发行分支，包含评论净化和弹幕屏蔽增强。
- `upstream/main`：原项目 `bggRGjQaUbCoE/PiliPlus` 的主分支。

发行标签统一使用 `purify-vX.Y.Z`，避免与上游版本号混淆。

## 同步上游

```powershell
git fetch upstream main
git switch purify
git merge --no-ff upstream/main
flutter pub get
flutter analyze
flutter test
```

发生冲突时，优先保留上游的结构调整，再重新接入以下净化版入口：

1. `ReplyGrpc.needRemoveGrpc` 中的评论账号过滤。
2. 评论长按菜单中的“仅屏蔽其评论”。
3. 设置页中的“净化中心”。
4. `DanmakuAssistantConfig` 与播放器加载弹幕时的本地匹配。
5. 本仓库的应用 ID、更新地址和发行文件名。

## 首次发行

1. 在 `purify` 分支完成 `flutter analyze` 与 `flutter test`。
2. 在 GitHub Actions 手动运行 `Build`，至少启用 Android，并把 `tag` 设为 `purify-v0.1.0`。
3. 检查三个 Android ABI 安装包均已附加到 Release。
4. 在真实设备确认净化版可与上游版共存、登录正常、评论账号屏蔽可撤销、弹幕规则可保存。
5. 发布说明中保留上游项目链接、GPL-3.0 许可和“非官方社区分支”声明。

## 产品边界

净化版只提供用户可见、可关闭、可撤销的本地规则。不要内置特定观点、用户或群体名单，也不要把文风当作 AI 内容的确定证据。若以后加入相似文本检测，应默认折叠并展示命中原因，不应默认永久删除。
