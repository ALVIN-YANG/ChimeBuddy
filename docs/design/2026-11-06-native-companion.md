# 原生会话伙伴交付

## 实现

- 透明角色独立于气泡，点击角色收起/展开气泡；气泡右上角关闭整个悬浮窗口。
- 气泡采用中性色、细边框，按内容测量高度，显示当前聊天名、点评及一个直接点评按钮。
- 默认角色为自己的银白龙四帧图集：睁眼、闭眼、思考、开口。原生按状态播放，待机约五秒眨眼一次，说话五秒后回到待机。系统减少动态效果时停在静帧；已有自定义 GIF 优先保留。
- 用户消息驱动跟随，先通过正式 thread/read 元数据验证身份；后台回复和输入建议不抢走会话。点评快照限定当前会话，旧结果不能覆盖新上下文。
- 短暂缺失的标题不会清空已知名称；尚未命名会话继续延迟重试。
- 原生程序仅在 Codex 应用前台时显示；关闭后须显式重新打开。当前仍需对应项目启用 Hooks，未改成读取页面点击的自动跟随。

## 开源参考及边界

- [CodingPet](https://github.com/leesta24/coding-pet)：参考名称缓存、延迟重试、状态驱动图集及非激活窗口结构。
- [CodePet](https://github.com/JellyTony/codepet)：参考透明角色与可折叠气泡组合。
- 本次实现是适配当前工程的独立代码，没有复制两者的源文件或受限角色素材；没有引入其完整应用、Rust 后端或浏览器原型。
- 我们的四帧图集不是 Codex 官方 9/11 行图集协议，当前只承诺默认四帧动画和原有 GIF 导入。

## 动画素材

内置 imagegen 以 `Assets/codex-companion.png` 为参考生成，保存为 `Assets/codex-companion-atlas.png`，由原生 CGImage 在运行时按 2×2 切帧并缓存。最终提示词如下：

Create a transparent PNG animation sprite atlas for the EXACT reference chibi white dragon girl. Four equal square cells in a strict 2 by 2 grid. Each cell contains the SAME full-body character at EXACT same size, position, silhouette and baseline with generous transparent margins, no frame borders or labels. Top-left: idle original open eyes, closed smiling mouth. Top-right: identical pose, eyes gently closed for a blink. Bottom-left: thoughtful, eyes looking slightly upward, closed mouth. Bottom-right: talking, eyes open and tiny smiling open mouth. Preserve all design: silver white hair, white horns, wings, white dress, blue orb, knot hairpin. Only change facial expression, never character scale or framing. Clean soft 2D anime game sprite, crisp grey outlines, genuinely transparent background. Canvas square, precisely four cells; no other objects, no text, no watermark. For programmatic cropping, equal dimensions and identical character placement in all four cells are crucial.

## 验证记录

- 会话跟随、上下文隔离、临时后台任务过滤、标题缓存及乱序恢复回归通过。
- 动画时间轴的待机眨眼、思考、说话和减少动态效果检查通过。
- 原生 AppKit 实际加载生成图集，确认待机/思考/说话三个图像数据不同，四帧素材不是未接入的静态占位。
- 浅色双段文字和深色实际气泡截图检查通过；透明角色位于气泡之外。
- 可访问性点击角色后，speechCollapsed/speechExpanded 回执与控件树同步改变。
- 在新气泡点击点评实际发起请求；reviewCompleted 回执显示当前会话、discarded=false，专家/吐槽均有返回；窗口读取到实际吐槽结果。
- 原生窗口的透明周边通过窗口本地鼠标位置切换穿透，不要求读取其他应用的辅助功能树。视觉预览模式停用穿透以便自动 UI 检查，正常运行保留穿透。
- 跨两个 Codex 桌面聊天的人工发消息、跨显示器拖动仍未在本轮重复验收，不把状态回归测试当成这些 UI 场景的实测。
