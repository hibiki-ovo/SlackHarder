# SlackHarder

[English](README.md) | 简体中文

macOS 原生桌面遮罩，使用 Swift + AppKit，无第三方依赖。需要 macOS 13 或更高版本；从源码构建另需 Swift 6 工具链。

## 下载和安装

从 [GitHub Releases](https://github.com/hibiki-ovo/SlackHarder/releases/latest) 下载 `SlackHarder-版本号-macOS-universal.zip`，支持 Apple Silicon 和 Intel Mac。解压后将 `SlackHarder.app` 拖入「应用程序」。

免费分发版本使用临时签名（ad hoc），未经过 Apple 公证。若系统阻止打开，请确认下载来源后，在「系统设置 → 隐私与安全性」点击「仍要打开」。受管理设备可能不允许此操作。首次运行请在「隐私与安全性 → 辅助功能」中授权 SlackHarder；更新后若权限失效，请移除旧授权并重新添加。

启动后通过菜单栏鱼形图标操作，不显示 Dock 图标。界面支持英文和简体中文，跟随 macOS 语言偏好，其他语言默认显示英文。也可在「系统设置 → 通用 → 语言与地区 → 应用程序」中单独设置语言，重启 SlackHarder 后生效。

## 启动

```sh
git clone https://github.com/hibiki-ovo/SlackHarder.git
cd SlackHarder
swift run SlackHarder
```

通过菜单栏鱼形图标切换模式。启动默认进入自动模式，选择目标窗口后显示遮罩。

## 不透明度

通过「遮罩不透明度」滑块调节透明度（0%～100%），设置自动保存，两种模式共用。遮罩默认鼠标穿透，可操作下方应用。

## 手动模式

- 通过「显示遮罩 / 隐藏遮罩」控制显示。
- 勾选「编辑遮罩（移动 / 缩放）」后，可拖动标题栏移动、拖动边缘调整大小；结束编辑后恢复鼠标穿透。
- 位置和大小自动保存。「将遮罩移回当前屏幕」可找回移出屏幕的遮罩。

## 自动模式

- 选择目标窗口并点击「附着」，遮罩会跟随窗口移动和缩放。点击已附着窗口菜单项可更换目标。
- 切换到其他窗口、隐藏应用或最小化窗口时，遮罩自动隐藏；返回目标窗口后恢复。
- 鼠标前进键、后退键或菜单「鼠标侧键：隐藏 / 恢复」可隐藏或恢复目标应用的全部窗口。
- 「解除附着」停止跟随；切换手动模式则恢复手动布局。重启后需重新选择目标窗口。

首次使用需授予辅助功能权限（见安装说明）。窗口列表未更新时可点击「刷新列表」。

鼠标侧键仍可能触发浏览器前进 / 后退；若鼠标驱动将侧键映射为快捷键，需改回标准侧键。部分游戏、自绘窗口及全屏场景可能不兼容。

## 构建和测试

```sh
swift build
swift test
```

可用 Xcode 打开 `Package.swift`。辅助功能授权、鼠标和窗口交互需本机验证。

## 打包和发布

```sh
bash scripts/package.sh 0.1.0
```

生成 `dist/SlackHarder-0.1.0-macOS-universal.zip` 和 SHA-256 校验文件，包含双架构 `.app`。打包脚本使用本地临时签名，不需要开发者会员。

向 GitHub 推送 `v0.1.0` 格式的版本标签后，GitHub Actions 会运行测试、打包并发布 Release。后续版本使用新的版本号和标签。

已安装 GitHub CLI 并通过 `gh auth login` 登录具备仓库写入权限的账号后，也可以运行：

```sh
bash scripts/publish.sh 0.1.0
```

脚本在临时目录克隆远程仓库，复制当前源码、提交并推送版本标签；保留远程历史，不执行强制推送。工作流需要仓库允许 GitHub Actions 运行。
