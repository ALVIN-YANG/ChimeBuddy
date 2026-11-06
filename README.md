# ChimeBuddy 原生验证

原生 Swift / AppKit 桌面伴侣：Codex Hooks → 本地事件 → 悬浮气泡。支持自定义 GIF、专家/吐槽/双开模式，点评通过桌面内置 Codex CLI 发起。

## 运行

```sh
bash scripts/build.sh
open .build/ChimeBuddy.app
```

本机项目路径固定为 `/Users/USER/Documents/my-learn/ChimeBuddy`。移动项目时，需要同时修改 `Sources/main.swift` 的工作目录过滤值和 `.codex/hooks.json` 的可执行文件路径。

项目级 `.codex/hooks.json` 注册 `UserPromptSubmit` 和 `Stop`。在 Codex Settings → Hooks 或 Review hooks 信任两项后，在此项目聊天发送一句话。用户消息应显示 `[Hooks] 收到你的消息`；回合结束应显示 `[Hooks] Codex 回答结束`。如果 Hooks 未出现，检查项目是否受信任，以及当前会话是否重新加载了项目配置；不要使用绕过信任的启动参数。

窗口使用非激活 `NSPanel`，配置 `canJoinAllSpaces`、`fullScreenAuxiliary`、`canJoinAllApplications`。用户已确认当前 Codex 全屏时仍可见；多屏和其他桌面切换效果未验证。此版本全局悬浮，不跟踪 Codex 窗口边缘，也不只在 Codex 前台显示。

## 菜单栏功能

- 仅真实 `UserPromptSubmit` 自动切换跟随会话，`Stop` 和其他后台事件不能切走伙伴。移除手动会话选择，底部只显示当前会话名称。
- 点评上下文仅取跟随会话最近 6 条消息，切回时恢复该会话自己的历史；旧会话的在途点评不能覆盖新会话。新点评若需等待旧请求完成，只处理仍匹配当前消息的请求。
- 重启按最新用户消息的时间恢复会话，不依赖磁盘文件枚举顺序。仅点击 Codex 中另一个会话页面但未发消息时，不会切换。
- 当前只接入 ChimeBuddy 项目下已启用 Hooks 的会话。其他项目尚未接入，不扫描它们的历史。
- 气泡内的“设置”按钮与菜单栏 ChimeBuddy 提供相同菜单。
- 导入 GIF：选择不超过 20 MB 的有效 GIF，复制到应用数据目录，重启后恢复；可恢复默认 Codex 伙伴。
- 暂停消息显示：暂停弹出，仍在本地接收事件；不是停用 Hooks。
- 专家、吐槽、双开：双开并发两次独立请求。默认专家模式。
- 点评最新回合：取最近真实事件所属会话最多 6 条摘录，每条最多 500 字符；不混入其他会话或模拟事件。
- 自动点评：默认关闭，手动开启后在真实 `Stop` 事件触发；正在点评时不排队，过期结果不覆盖新消息。

点评复用本机 Codex 的 ChatGPT 登录，不读取或复制凭据，不需要 API Key。它使用 Codex 用量，独立于当前聊天；目前使用 CLI 默认模型（本机测试为 `gpt-6.1-sol`），不自动继承当前聊天的模型选择。执行目录为独立临时目录，使用只读沙箱、临时会话并要求不调用工具，不续写原聊天。`--ignore-user-config` 避免携带用户项目配置，登录仍由 CLI 管理。只读沙箱不是“完全不能读文件”的保证。

## 数据和退出

- Hooks 接收和 GIF 功能仅在本地运行；用户发起或开启自动点评后，摘录通过 Codex 发送给模型，不修改原聊天。
- 仅接受上述固定工作目录的两种事件，每条最多保存 500 个字符，气泡最多显示 130 个字符。
- 事件保存在 `~/Library/Application Support/ChimeBuddy/events/`，窗口处理回执在同目录的 `receipts.jsonl`；这是本地验证数据，不会自动清理。
- `last-hook-invocation.json` 只记录最近入口调用的时间、输入字节数及模拟标记，用于区分未调用和被过滤；不保存被拒绝的正文。
- 菜单栏 ChimeBuddy → 退出 ChimeBuddy。停止 Hook 接入时，在 Codex 禁用这两项或移除此项目的 `.codex/hooks.json`。
- `--hook --simulate` 只测试接收入口，模拟事件不加入会话列表，也不发送给模型，不能作为真实 Codex 接入证据。

## 本机验证（2026-11-05）

- 桌面应用：`/Applications/ChatGPT.app`，Bundle ID `com.openai.codex`，版本 `26.1029.61003`（24614）。
- 桌面内置引擎：`0.166.0-alpha.6`；`features list` 返回 `hooks stable true`。
- Swift 6.3.3 编译、应用启动成功。
- 模拟事件经同一原生 Hook 入口写入，文件监听收到并显示气泡；通过窗口可访问性树确认 `[模拟] 收到你的消息` 及模拟正文。
- 全屏显示：用户确认 Codex 全屏后气泡仍可见。
- 模型：ChatGPT 登录检查通过；独立 CLI 请求返回 `CHIMEBUDDY_OK`；生产 `CodexReviewer.review` 入口用虚构对话实际调用成功，返回专家建议。
- Hooks：用桌面内置引擎的公开 `hooks/list` 读到两项 `enabled: true`、`trustStatus: trusted`，无配置错误。两次独立 `codex exec` 探针均实际触发用户消息和回合结束事件，窗口回执和 UI 已验证。未绕过 Hooks 信任。
- 当前桌面聊天：2026-11-06 已收到本聊天真实消息；在桌宠选择“调研 Codex 对话助手可行性”后，实际窗口显示了用户关于会话名的最新反馈，桌面消息到气泡链路已验证。
- GIF：通过原生文件选择器实际导入两帧 GIF，截图确认两帧播放，恢复默认形象已验证。
- 双开：从桌宠菜单实际并发调用，窗口收到专家和吐槽两项输出。
- 会话隔离：第二个实际 CLI 会话的两项事件记录为 `receivedInBackground`，未覆盖第一个会话的点评；在下拉框选择第二个会话后显示 `SECOND_SESSION_OK`。
- `bash scripts/test.sh` 验证模拟隔离、后台隔离、选中会话历史、排序与去重。详情见 [验收记录](docs/verification/2026-11-05.md)。

参考：[Codex Hooks](https://learn.chatgpt.com/docs/hooks)、[Apple 全屏空间行为](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)。

## 界面与默认形象

2026-11-06 更新为中性灰白/炭灰、细边框和系统字体，跟随系统浅色/深色。默认形象为参考图生成的银白龙 Q 版静态 PNG；已有自定义 GIF 优先保留。右上角关闭按钮和底部会话名称和设置入口保留。角色资源与生成提示词见 [视觉记录](docs/design/2026-11-06-visual-refresh.md)。

## 2026-11-06 消息驱动跟随验收

`bash scripts/test.sh` 通过 A 发消息 → B 发消息 → A 后台回复 → B 回复 → A 再发消息的切换与上下文隔离检查，以及乱序恢复、去重和名称更新。实际窗口已显示当前用户消息对应的会话，辅助功能树确认没有会话选择器。跨两个桌面聊天的人工发送验收尚未重复执行。

跟随前还会通过 `thread/read` 验证会话身份。Codex 内部的输入建议任务也可能触发 UserPromptSubmit；无法被正式会话接口读取的临时任务不会切走伙伴。新会话元数据尚未落盘时会短暂重试，期间保留原上下文。
