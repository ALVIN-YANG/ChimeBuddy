# 声音与动作

打开菜单栏双气泡图标 → **设置…**。设置分为“形象与动作、声音、模型与记忆”，使用原生 AppKit、灰阶表面与单色 SF Symbols。日常伙伴仍是人物旁的紧凑气泡。

## 配置流式 TTS

1. 打开“声音”，选择服务商。
2. 填写完整接口地址、模型和 Voice ID，再填写自己的 API Key。地址、模型、音色都可修改，预设仅用于起步。
3. 选择“跟随系统”或一个输出设备。选定设备只影响伙伴，不改 macOS 默认设备。
4. 点击“试听”，确认出声；可随时点“停止”。试听使用表单当前值，不要求先保存。
5. 勾选“自动朗读新的吐槽和聊天回复”，点击“保存设置”。以后新的当前会话回复会自动朗读。

TTS 使用所选服务商的额度，与复用 Codex 登录的回复模型分别计费。只发送伙伴这次要朗读的文本，不发送画像、项目记忆或整段会话。API Key 与附加请求头保存到本机钥匙串，普通偏好文件不保存密钥。清空 Key、将请求头改为 `{}` 并保存，可删除该服务商的钥匙串条目。账号可用模型与音色以服务商实际权限为准。

| 预设 | 连接和流格式 | 需要填写 |
| --- | --- | --- |
| ElevenLabs | HTTP → PCM16 LE，24 kHz，单声道 | Key、模型、Voice ID；地址中的 `{voice}` 会自动替换 |
| OpenAI / 兼容接口 | HTTP → PCM16 LE，24 kHz，单声道 | Key、模型、音色、完整 `/audio/speech` 地址 |
| Azure Speech | SSML HTTP → raw PCM16 LE，24 kHz | Speech Key、区域对应的地址、音色 |
| MiniMax | HTTP SSE → Hex PCM16 LE，24 kHz | Key、模型、音色；国内/国际域名可改 |
| 火山豆包 | HTTP SSE → Base64 PCM16 LE，24 kHz | Key、Resource ID、speaker；兼容旧鉴权可填附加请求头 |
| 阿里云 CosyVoice | WebSocket → PCM16 LE，24 kHz | Key、模型、音色；可填工作空间专属 WSS 地址 |
| 自定义 HTTP 流 | 原始 PCM，或 SSE 中的 Base64 / Hex PCM | 地址、请求体、响应格式、采样率、音频字段路径、请求头 |

OpenAI 这个预设使用 Speech API，当前列出的 Speech 模型计划于 **2027-01-06** 关闭。兼容服务是否仍支持该协议取决于服务商；原生 OpenAI 后续需迁移到 Realtime。不要把该预设理解为已支持所有 OpenAI Realtime 协议。

自定义接口必须返回**无 WAV 文件头的 PCM16 LE 单声道**。采样率可选 8 / 16 / 22.05 / 24 / 32 / 44.1 / 48 kHz，不支持把 MP3 当 PCM 直接播放。地址使用 HTTPS；本机 `localhost`、`127.0.0.1`、`::1` 服务可用 HTTP。

请求体是 JSON，字符串值可包含 `${text}`、`${model}`、`${voice}`。替换在 JSON 解码后进行，文本中的引号、换行和同名占位符不会被再次解释。例如：

```json
{"input":"${text}","model":"${model}","voice":"${voice}","stream":true,"format":"pcm","sample_rate":24000}
```

附加请求头使用 JSON 字符串字典，例如 `{"Authorization":"Bearer ${key}"}`。凭据放在 Key 或请求头中，不要写进普通请求体或接口 URL。SSE 可将音频字段路径设为 `data.audio`，对应 `data: {"data":{"audio":"…"}}`。HTTP 重定向不会转发密钥。

## 绑定动作 GIF

1. 打开“形象与动作”，点击“新增”。
2. 填写标签和使用场景，例如 `嫌弃`、`用户重复推翻刚确认的要求时`。
3. 选择 GIF，可先点“预览”，再点“保存动作”。
4. 下一次请求会把已绑定 GIF 的标签与用途交给 AI。AI 返回独立的 `action` 字段，应用播放对应 GIF；标签不会出现在气泡或朗读文本中。

不限制动作数量；每个标签最多 64 字、用途最多 240 字，每张 GIF 最大 20 MB、4096 × 4096。标签不能重名。导入后 GIF 会复制到应用数据目录，原文件移动或删除不影响动作。所有可用动作均参与选择，数量很多会增加模型输入量。

可选中动作后改名、修改用途、替换 GIF 或删除。没有匹配的动作或文件缺失时，使用默认形象。开启朗读时，动作持续到朗读结束；关闭朗读时显示 6 秒后恢复默认。减少动态效果开启时，遵循系统设置。

## 会话与停止规则

只为新的当前会话回复播放声音和动作。后台会话不能抢占当前会话；切会话、隐藏伙伴、离开 Codex 或下一次请求开始时，会取消旧网络请求、清空音频队列并恢复默认形象。用户正在伙伴对话框直接聊天时可继续朗读。

回到某个会话只恢复最后一条文字气泡及动作标签缓存，不重播旧声音和 GIF。原有的最多 10 轮会话上下文、会话隔离和共享记忆限长保持不变。TTS 错误显示在设置页，不替换气泡中的伙伴回复。

## 验证与故障定位

```bash
bash scripts/test.sh                         # 本地状态、流解析、GIF 与设置操作回归
python3 scripts/test-voice-integration.py    # 本地 HTTP/SSE 到音频输出，含打断；会发声
bash scripts/probe-actions.sh               # 一次真实 Codex 调用，验证动作选择；消耗 Codex 用量
```

`ChimeBuddy --probe-voice` 从标准输入读取包含 provider、configuration、secrets 的 JSON，做连续播放、打断和再次播放。只用于显式本机验证；不要在命令参数、仓库或问题报告中粘贴真实密钥。

无声时先检查设置中显示的系统输出设备，蓝牙耳机未佩戴时也可能是默认输出。再对同一段音频使用系统播放器比较。播放缓冲区计数成功不等于人耳已听到。

目前真实账号和人耳验证覆盖 ElevenLabs；其他预设覆盖请求结构与本地 HTTP/SSE/WebSocket 到 AudioQueue 的测试，未用真实账号验证。各服务商模型与音色权限、特殊代理以及设备切换仍需在相应环境中测试。

协议来源：[ElevenLabs](https://elevenlabs.io/docs/api-reference/text-to-speech/stream)、[OpenAI](https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create)、[Azure](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech)、[MiniMax](https://platform.minimax.io/docs/api-reference/speech-t2a-http)、[豆包](https://www.volcengine.com/docs/6561/1598757)、[CosyVoice](https://help.aliyun.com/en/model-studio/cosyvoice-client-events)。
