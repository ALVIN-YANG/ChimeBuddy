# ChimeBuddy 原生验证

用 Swift / AppKit 验证 Codex Hooks → 本地事件 → 悬浮气泡。当前没有 AI 分析、GIF 导入或模式切换。

## 运行

```sh
bash scripts/build.sh
open .build/ChimeBuddy.app
```

本机项目路径固定为 `/Users/USER/Documents/my-learn/ChimeBuddy`。移动项目时，需要同时修改 `Sources/main.swift` 的工作目录过滤值和 `.codex/hooks.json` 的可执行文件路径。

项目级 `.codex/hooks.json` 注册 `UserPromptSubmit` 和 `Stop`。在 Codex Settings → Hooks 或 Review hooks 信任两项后，在此项目聊天发送一句话。用户消息应显示 `[Hooks] 收到你的消息`；回合结束应显示 `[Hooks] Codex 回答结束`。如果 Hooks 未出现，检查项目是否受信任，以及当前会话是否重新加载了项目配置；不要使用绕过信任的启动参数。

窗口使用非激活 `NSPanel`，配置 `canJoinAllSpaces`、`fullScreenAuxiliary`、`canJoinAllApplications`。这允许尝试加入其他应用的全屏空间，但当前机器的全屏、多屏和桌面切换效果需要真实验收。此版本全局悬浮，不跟踪 Codex 窗口边缘，也不只在 Codex 前台显示。

## 数据和退出

- 不联网、不调用模型、不修改 Codex 对话。
- 仅接受上述固定工作目录的两种事件，每条最多保存 500 个字符，气泡最多显示 130 个字符。
- 事件保存在 `~/Library/Application Support/ChimeBuddy/events/`，窗口处理回执在同目录的 `receipts.jsonl`；这是本地验证数据，不会自动清理。
- 菜单栏 🐥 → 退出 ChimeBuddy。停止 Hook 接入时，在 Codex 禁用这两项或移除此项目的 `.codex/hooks.json`。
- `--hook --simulate` 只能验证传输和渲染，气泡和回执明确标记模拟，不能作为真实 Codex 接入证据。

## 本机验证（2026-11-05）

- 桌面应用：`/Applications/ChatGPT.app`，Bundle ID `com.openai.codex`，版本 `26.1029.61003`（24614）。
- 桌面内置引擎：`0.166.0-alpha.6`；`features list` 返回 `hooks stable true`。
- Swift 6.3.3 编译、应用启动成功。
- 模拟事件经同一原生 Hook 入口写入，文件监听收到并显示气泡；通过窗口可访问性树确认 `[模拟] 收到你的消息` 及模拟正文。
- 真实桌面消息触发、全屏显示：待用户信任 Hooks 并发送测试消息后验证。电脑控制工具明确禁止操作 Codex 自身，不能自动完成该步骤。

参考：[Codex Hooks](https://learn.chatgpt.com/docs/hooks)、[Apple 全屏空间行为](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)。
