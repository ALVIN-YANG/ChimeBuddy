# ChimeBuddy 图标

让用户把 ChimeBuddy 记成“陪着当前会话说话的银白龙伙伴”。图标使用龙角头像与对话气泡尾巴，不使用全身角色、细小代码或 OpenAI 标志。

## 方向与选定

使用内置 ImageGen 分别生成三个方向：平面头像、瓷质立体头像、带气泡尾巴的简化头像。第三个方向在 16 / 32 / 64 像素下仍保留龙角、眼睛及对话轮廓，最终采用它。默认桌面伙伴素材未被替换。

- 主图：`Assets/AppIcon.png`，1024×1024、不透明 PNG。
- macOS 图标：`Assets/AppIcon.icns`，包含 16–1024 像素表示，构建时复制并配置 `CFBundleIconFile`。
- README：`docs/media/app-icon.png`，256×256。
- 个人作品卡片使用同一主图的 192×192 WebP。

参考图仅提供银白头发、龙角和灰蓝眼睛等角色特征。选定的生成结果保留完整画布缩放到 1024 像素，没有裁切角色或替换其身份。原始生成结果仍保留在本机生成目录，淘汰方案不随项目分发。

## 最终提示词

使用内置 ImageGen，非 API / CLI fallback。选定结果的完整提示词：

```text
Use case: logo-brand. Create ONE finished Apple macOS application icon, square 1024x1024 master artwork, for ChimeBuddy, a native Codex conversation companion. The reference is the project's existing mascot, use it only for identity cues: silver-white bangs, two pale dragon horns, large grey-blue eyes, mischievous friendly expression. Do not copy the intricate hairpin logo or dress or full body. A single dominant mark, bold clean silhouette, legible at 16 and 32 px. Restrained charcoal, ivory and one pale blue accent. No text, letters, typography, watermarks, UI, screenshots, extra objects, tiny details, or generic AI sparkle. Fully opaque square background, no baked iOS mask. Direction C: a distinctive ivory speech-bubble creature symbol on charcoal. The single speech bubble has two small dragon horns on top and a minimal silver fringe, two large blue-grey eyes, small mischievous mouth. Reads as one horned talking companion silhouette rather than two separate icons. Large flat graphic mark with subtly tactile edge, friendly, sharp and highly recognizable at tiny sizes.
```

## README 媒体

`scripts/export-readme-media.sh` 从实际生产 AppKit 视图生成截图和 GIF；没有绘制虚构的 Codex 界面，没有使用个人聊天或操作用户桌面。GIF 使用生产动画帧与时序，演示眨眼、思考、说话、气泡收起和展开。静态 PNG 是动画的替代素材，原生导出代码是可编辑源。

GIF 为 752×420、10 fps、12 秒、120 帧，约 516 KiB；首尾状态相同。README 对减少动态效果的读者提供静态截图，安装命令、使用说明和兼容限制均保留为可复制文本。
