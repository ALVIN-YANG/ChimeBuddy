<p align="center">
  <img src="docs/media/app-icon.png" width="96" height="96" alt="ChimeBuddy 银白龙对话伙伴图标" />
</p>
<h1 align="center">ChimeBuddy</h1>
<p align="center">跟着当前会话走的 macOS 桌面伙伴。会吐槽，也能和你聊。</p>
<p align="center">
  <a href="https://github.com/ALVIN-YANG/ChimeBuddy/releases/tag/v0.1.1">下载原型</a> ·
  <a href="#安装">安装</a> ·
  <a href="#使用">使用</a> ·
  <a href="https://blog.mlxb.cc/projects/#chimebuddy">个人作品</a>
</p>
<p align="center">macOS 14+ · Apple Silicon · Swift / AppKit</p>

ChimeBuddy 悬浮在 Codex 旁边，根据当前会话的用户输入和 AI 最终回复接一句话。切换会话时同步切换上下文；你也可以右键打开对话框，直接和她说话。

<picture>
  <source media="(prefers-reduced-motion: reduce) and (prefers-color-scheme: dark)" srcset="docs/media/companion-dark.png" />
  <source media="(prefers-reduced-motion: reduce)" srcset="docs/media/companion-light.png" />
  <img src="docs/media/companion-demo.gif" width="752" alt="ChimeBuddy 原生界面演示：伙伴眨眼、思考、说话，以及气泡收起和展开" />
</picture>

*原生视图演示，文案为示例；动画时长不代表模型回复速度。[查看静态截图](#伙伴截图)。*

- **跟随会话**：只点评当前会话，后台回复不会把伙伴切走。
- **有来有回**：自动吐槽，也能直接聊天；气泡平时只放正文。
- **可以换形象**：内置四种表情，也可以导入自己的 GIF。
- **可以选模型**：从 Codex 读取可用模型和推理档位，使用本机登录。
- **上下文分清楚**：会话原话隔离，跨会话只共享限长概况。

## 安装

### 先准备好

- Apple Silicon Mac，macOS 14 或更高版本。当前安装包不支持 Intel Mac。
- 已安装并登录的 [Codex / ChatGPT 桌面版](https://chatgpt.com/download/)。当前原型寻找 `/Applications/ChatGPT.app` 内的 Codex CLI；其他安装位置尚未自动适配。
- 保留一个 Codex 主窗口，使用本机项目下的会话。远程会话和多主窗口尚未验证。

### 下载运行

1. 打开 [v0.1.1 Releases](https://github.com/ALVIN-YANG/ChimeBuddy/releases/tag/v0.1.1)，下载 `ChimeBuddy-v0.1.1-macos-arm64.zip`。
2. 解压，把 `ChimeBuddy.app` 拖到“应用程序”目录，然后打开。
3. 在 Codex 打开一个本机会话，保持 Codex 在前台。没有吐槽缓存时，先显示人物；发送一条新消息后才会请求新的吐槽。
4. 在 macOS 顶部菜单栏找到双气泡图标，打开“设置…”选择模型，或导入自己的 GIF。

这是**未公证、仅 ad-hoc 签名的第三方原型**。如果 macOS 阻止打开，确认来源后可在“系统设置 → 隐私与安全性”检查是否提供“仍要打开”；详见 [Apple 的说明](https://support.apple.com/zh-cn/102445)。也可以使用下方的源码构建方式。

安装包附有 `SHA256SUMS.txt`。将它与 ZIP 放在同一目录后，可以校验下载：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

<details>
<summary>从源码构建</summary>

先安装 Xcode Command Line Tools，已安装则跳过：

```sh
xcode-select --install
```

然后执行：

```sh
git clone https://github.com/ALVIN-YANG/ChimeBuddy.git
cd ChimeBuddy
bash scripts/test.sh
bash scripts/build.sh
open .build/ChimeBuddy.app
```

构建不需要 Electron、Node.js 或单独配置 API Key。只在重新导出 README GIF 时需要 `ffmpeg`。

</details>

## 使用

| 想做什么 | 怎么操作 |
| --- | --- |
| 自动听她吐槽 | 在当前 Codex 会话发送消息，或等 AI 最终回复完成 |
| 直接和她聊天 | 右键人物或气泡 → **和她聊聊…** |
| 收起 / 展开气泡 | 点击人物 |
| 移动伙伴 | 拖动人物 |
| 隐藏伙伴 | 右键人物或气泡 → **隐藏伙伴** |
| 重新显示 | 菜单栏双气泡图标 → **显示伙伴** |
| 退出程序 | 菜单栏 → **退出 ChimeBuddy** |

切到其他应用时伙伴隐藏，回到 Codex 才显示。切换 Codex 会话会恢复该会话自己的最后一条气泡缓存，关闭旧的伙伴对话框；不会把上一会话的聊天带进来。

### 设置

从菜单栏双气泡图标打开“设置…”。

- **形象**：导入不超过 20 MB 的 GIF，或恢复默认银白龙伙伴。
- **模型 / 推理档位**：读取 Codex 当前提供的选项，更改后从下一次请求生效；不会修改 Codex 原聊天的模型。
- **共享记忆**：查看、修改、清空用户画像和项目概况。画像最多 **400 字**，全部项目概况合计最多 **800 字**。

模型调用在独立的临时会话中进行，不往 Codex 原聊天发消息。使用已有的 [Codex 登录](https://learn.chatgpt.com/docs/auth)和用量；一次用户输入、一次 AI 最终回复各可触发一次调用，直接聊天也会调用模型。

### 上下文和数据

当前会话的 Codex 对话与伙伴对话共用最近**最多 10 轮**的窗口。不同会话的原话不混用；稳定偏好和项目概况可以共享。伙伴对话不另存长期档案，每个会话只保留最后一条气泡缓存供恢复。

本地数据位于 `~/Library/Application Support/ChimeBuddy/`，包含气泡缓存、限长共享记忆、自定义 GIF 和诊断回执。模型请求会把当前会话摘录与共享概况交给 Codex 处理。正常使用不依赖 Computer Use、屏幕录制或全局 Hooks。

## 伙伴截图

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/media/companion-dark.png" />
  <img src="docs/media/companion-light.png" width="752" alt="ChimeBuddy 原生气泡与默认银白龙伙伴，正文贴近人物，气泡内没有关闭按钮" />
</picture>

原生 AppKit 视图截图，使用演示文案。截图按 GitHub 的浅色 / 深色外观切换；[浅色原图](docs/media/companion-light.png) · [深色原图](docs/media/companion-dark.png)。

## 常见问题

<details>
<summary>打开后看不到伙伴？</summary>

确认程序仍在菜单栏运行，没有被手动隐藏；然后回到 Codex 的本机会话页面。伙伴只在 Codex 前台、且能确认当前会话时显示。多个主窗口、远程会话或日志格式变化时可能无法识别，它不会猜测你在看哪个会话。

源码目录可执行只读检查，不调用模型：

```sh
bash scripts/check-current.sh
```

</details>

<details>
<summary>发送了消息，但她没有说话？</summary>

自动吐槽允许没槽点时安静；直接对话应有回复。检查 Codex 登录、可用用量、所选模型和网络。Mac 的静态 HTTP/HTTPS 系统代理会传给 Codex 子进程；PAC 和仅 SOCKS 的自动转换尚未实现。

直接对话失败时，对话框显示错误，气泡保留上一次内容，不把连接状态说成角色台词。不要仅凭旧气泡判断这次请求已经成功。

</details>

<details>
<summary>这是 OpenAI 官方插件吗？兼容所有 Codex 版本吗？</summary>

不是。它是独立的原生 macOS 第三方原型，借助本机页面日志和 Codex App Server 识别会话。当前仅验证单主窗口、本机会话；日志格式受客户端版本影响，升级后可能需要适配。尚未完成多窗口、远程会话和其他 Mac 型号的兼容验收。

</details>

## 开发资料

- [实现、兼容边界与数据来源](docs/implementation.md)
- [验证记录](docs/verification/2026-11-09.md)
- [图标设计与生成来源](docs/design/app-icon.md)

重新导出原生截图与 GIF：

```sh
bash scripts/export-readme-media.sh
```

会话选择思路参考 [CoPets](https://github.com/ReiSuzunami/CoPets/blob/main/src-tauri/src/observer/selection.rs) 与 [streamdeckcodex](https://github.com/twidtwid/streamdeckcodex/blob/main/src/lib/desktop-active.ts)。没有引入它们的源代码或美术素材。
