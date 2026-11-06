# ChimeBuddy

原生 Swift / AppKit Codex 桌面伙伴。点击 Codex 中的会话时切换上下文；当前会话收到用户消息或 AI 最终回复时自动吐槽。气泡只有吐槽正文和隐藏按钮，按内容收紧尺寸并贴近人物脸侧。没有吐槽缓存时只显示角色。

## 运行与检查

```sh
bash scripts/test.sh
bash scripts/build.sh
open .build/ChimeBuddy.app
```

检查当前识别的会话和缓存，不调用模型：

```sh
bash scripts/check-current.sh
```

显式重放当前会话最新的一条真实消息，测试模型和缓存链路（使用 Codex 用量，不向原聊天发消息）：

```sh
bash scripts/check-current.sh --roast
```

检查脚本修改缓存后，重开伙伴即可读取它。日常自动触发不需要运行脚本。

## 当前行为

- 页面路由决定当前会话。用户消息、后台回复和内部临时任务都不能改变选择。
- 切换时立即清除上一会话的气泡，恢复新会话自己的缓存；未生成过则只显示角色。点击切换本身不调用模型。
- 只在当前会话的新用户消息、最终回复完成时自动调用模型。中间回复、工具输出、思考过程、历史补载和模拟事件不触发。
- 同一回合的多条用户输入使用独立消息 item ID；完成事件使用 turn ID。重复读取、切回和重启不重复生成。
- 上下文只包含这个会话最近最多 6 条用户消息与最终回复，每条最多 2000 字符。仅启动或切换时补载当前文件尾部最多 4 MiB；随后增量读取。
- 在途结果属于发起请求的会话。离开后完成只存入原会话缓存，不能显示到新会话，也不能覆盖较新结果。尚未开始的旧会话请求取消。
- 毒舌风格允许直接怼用户、骂 AI、适量粗口，针对对话中的具体槽点，不编造事实。新风格在后续触发时使用，已有会话缓存保留。
- 等待或失败时保留已有吐槽；没有缓存就不显示气泡。状态、引导和错误只进诊断记录。
- 伙伴仅在 Codex 前台且确认当前会话时显示。角色可拖动、点击收起/展开气泡；右上角隐藏整个伙伴，菜单栏可恢复。
- 菜单栏仅提供显示伙伴、隐藏伙伴、设置和退出。设置窗口提供形象预览、导入 GIF、恢复默认形象，以及吐槽模型和推理档位选择。没有暂停自动吐槽、手动选择会话、模式选择或点评按钮。
- 默认角色有待机眨眼、思考和说话表情；系统减少动态效果时静止。自定义 GIF 优先保留。

自动吐槽始终启用，旧版保存的暂停状态不再生效。一次用户输入和一次最终回复各可调用一次 Codex，使用本机已有 ChatGPT 登录和用量。调用在独立临时目录、只读沙箱、临时会话中执行，不续写原聊天、不复制凭据、不需要 API Key。未保存选择前使用 CLI 默认模型；在设置中选择后，使用保存的模型和推理档位，不继承当前聊天的模型设置。提示词要求不用工具；只读沙箱不等于文件读取完全禁用。

## 模型设置

打开菜单栏 → 设置。模型列表和每个模型的推理档位通过本机 Codex 的 `model/list` 读取，包含分页；不硬编码模型名单或允许的档位组合。每次打开设置都会读取，也可点击刷新。只显示接口返回的非隐藏文本模型。

选择模型时采用该模型返回的默认档位，档位列表随模型联动。更改自动保存，下次吐槽请求使用 `--model` 和 `model_reasoning_effort` 覆盖；在途请求和已有吐槽缓存保留。偏好只保存在 ChimeBuddy 自己的 macOS 偏好域，不改 Codex 全局配置或聊天的模型。

首次读取失败时不能选择未知模型，保留刷新入口；刷新失败保留上次选项。已保存的模型不在当前列表中时提示重新选择，不静默替换模型；已有模型的原档位不再受支持时，改用该模型当前返回的默认档位并显示提示。模型列表来自 Codex 当前客户端目录，实际调用仍受登录、服务可用性和用量限制。

## 观察来源与边界

当前安装的 Codex `26.1029.61003` 在桌面日志中输出页面路由，但不输出开源示例使用的窗口焦点字段。伙伴读取当前 Codex 主进程的 `IAB_LIFECYCLE received browser sidebar owner sync` 记录里的 `ownerRoutePath=/local/<UUID>`，再通过公开 `thread/read` 验证真实会话、读取名称及记录路径。这个日志名称来自宿主内部路由，伙伴界面仍是原生 NSPanel，不使用内置浏览器。

消息来源是被选中会话的本地记录：`event_msg.item_completed.UserMessage` 和 `event_msg.task_complete.last_agent_message`。只接受这些白名单事件，不把原始模型输入、工具记录或 commentary 当用户对话。该路径覆盖其他本机项目，不需要给每个项目新增 Hooks。

原有项目级 `UserPromptSubmit` / `Stop` Hooks 保留作为没有记录路径时的备用来源；同一会话只使用一种来源，避免重复。它们依旧只接收固定目录 `/Users/USER/Documents/my-learn/ChimeBuddy`，未安装全局 Hooks、未更改信任状态。移动项目时应修改 `Sources/main.swift` 的备用目录过滤和 `.codex/hooks.json` 中的可执行路径。

日志和消息记录格式都是版本相关的兼容接口。Codex 升级后若无法确认会话，伙伴隐藏，不能退回“最近发过消息”的猜测。当前版本缺少焦点字段，因此同一进程出现多个主窗口路由时返回未知；多窗口跟随不在本次已验证范围。仅支持能通过本机 `thread/read` 返回记录路径的会话；远程会话没有验证。

窗口使用 `nonactivatingPanel`、`canJoinAllSpaces`、`fullScreenAuxiliary` 和 `canJoinAllApplications`。用户此前已确认全屏可见；本次保留这些配置，多屏和全屏组合仍需人工验收。

## 本地数据

目录：`~/Library/Application Support/ChimeBuddy/`。

- `reviews.json`：按会话独立保存最近吐槽、来源事件 ID 和时间，原子写入；旧结果不能覆盖新结果。失败不覆盖缓存。
- `avatar.gif`：导入的 GIF，不超过 20 MB。
- `receipts.jsonl`：页面切换、缓存恢复及请求开始/结束的诊断记录，不含对话正文或模型请求内容。
- `events/`：原项目 Hooks 的历史事件；主消息来源可用时不读取它们。
- `last-hook-invocation.json`：原 Hook 入口的时间和字节数，不保存被拒绝的正文。

退出用菜单栏的“退出 ChimeBuddy”。停用原项目 Hooks 可在 Codex 设置中禁用这两项，或移除 `.codex/hooks.json`。这不会删除本地缓存。

## 验证与参考

模型接口参考 [Codex App Server](https://learn.chatgpt.com/docs/app-server)。

最新验证见 [2026-11-06 验证记录](docs/verification/2026-11-06.md)。历史原型验收在 [2026-11-05 记录](docs/verification/2026-11-05.md)，不代表当前交互。

会话选择思路参考 [CoPets selection.rs](https://github.com/ReiSuzunami/CoPets/blob/main/src-tauri/src/observer/selection.rs) 和 [streamdeckcodex desktop-active.ts](https://github.com/twidtwid/streamdeckcodex/blob/main/src/lib/desktop-active.ts)。本项目实现为独立 Swift 适配器，没有导入它们的源文件或美术素材。它们的 IPC 控制、Tauri 界面与 CDP 桥接没有引入。
