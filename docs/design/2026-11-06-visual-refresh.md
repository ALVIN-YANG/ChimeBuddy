# Codex 伙伴视觉更新

原生 AppKit 实现，灰白/炭灰中性表面、14pt 圆角、1pt 细边框、系统字体。取消奶黄色底色、表情符号默认宠物和大块按钮底色。浅色与深色跟随系统；这是接近 Codex 的视觉方向，不声称复用了 Codex 私有设计令牌。

角色资源：`Assets/codex-companion.png`，1254×1254 RGBA，alpha 范围 0–255。内置 imagegen 生成，用户上传的银白龙女性图片作为角色设计参考。默认静态 PNG，自定义 GIF 导入/播放仍保留；用户已有 GIF 优先，不覆盖。

## 最终生成提示词

Create one transparent-background mascot PNG for a native macOS Codex companion app. Use the attached image as character design reference, NOT as a photorealistic edit. Transform the silver-white dragon woman into a charming 2-head-tall chibi full-body anime character, large expressive grey-blue eyes, silver white hair with readable chunky strands, two short curved pale dragon horns, small white dragon wings, a small curved dragon tail. Retain an understated interwoven knot hair ornament reminiscent of the reference, white high-neck fully covered simple dress and little white shoes. Friendly thoughtful smile, one hand near her cheek, other holds a tiny pale-blue orb. Polished softly shaded 2D anime sticker illustration with crisp dark grey fine outlines so the WHITE character remains legible on white and dark interfaces. Compact silhouette, centered full body including horns wings feet and tail, fills 90% of square canvas, small balanced transparent margins. Palette: white silver charcoal and tiny blue accents. Cute professional companion, no sensuality, no cleavage or slits, no photorealism, no elaborate jewelry, no scenery, no text, no watermark, no solid background, genuine alpha transparency. This is a single default character asset, not a sprite sheet.

## 本地视觉检查

- 默认运行：跟随当前系统深色，已通过实际窗口截图检查。
- `open -n .build/ChimeBuddy.app --args --preview-light`：仅用于浅色双段文字预览，不调用模型或写入会话。
- `--preview-dark`：对应深色预览。
- 最终交付恢复正常运行，仍使用真实会话状态。
