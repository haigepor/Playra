# Playra 影院片单背景生成记录

日期：2026-10-15。使用内置 `image_gen`，透明背景；未使用 CLI/API fallback。

用途：发现页与搜索页的轻量页头背景。原图提供纸张、胶片与光影细节；Flutter 控制低透明度、裁切与底部淡出。功能图标使用手写 SVG；前三名后来按用户要求改为生成式奖杯，提示词见 `rank-trophy-imagegen-prompts.md`。下方原始背景提示词正文保持不变。

最终素材：`assets/images/modern-cinema-header-art.png`，2172×724、约 1.05 MiB，RGBA；左侧抽样 alpha=0，主体抽样 alpha=253。原始生成文件保留在 Codex generated_images 目录，项目使用工作区副本。

## 最终提示词

```text
Use case: stylized-concept.
Asset type: a transparent PNG decorative background for the top-right header of Playra, a dark anime and film browsing app. Generate the artwork only, not a UI mockup.
Primary request: a refined, detailed yet quiet cinema paper collage that looks designed specifically for a small app header. Three overlapping rounded film-program cards / miniature poster sheets, each slightly tilted, with a short elegant strip of film tucked between two layers. The foremost sheet contains an abstract cinematic landscape with an indigo crescent-like hill and a tiny moon, no recognizable movie artwork. Fine inset frame, subtle film perforations and crisp paper edges, controlled shallow relief, matte surfaces, beautifully restrained editorial illustration.
Composition: very wide horizontal canvas, approximately 3:1. All objects clustered in the rightmost 40 percent, strongest detail in the upper-right quadrant. The left 55 percent must be entirely transparent negative space, with no floating specks. Leave the lower 25 percent transparent. Keep all important objects inside the canvas with a narrow clear margin. Open airy asymmetrical silhouette; do not make one closed rectangular border around the whole composition.
Palette: muted periwinkle, dusty lavender, slate blue and indigo, compatible with dark background #11141C and accent #A7B7FF; pale blue highlights #C9D3FF. Controlled tonal range with no pure white highlights. Medium local contrast on the objects, suitable for later reducing overall opacity in the app.
Materials and light: fine paper texture visible at full size, delicate layered edges, soft contact shadows between sheets, subtle diffuse light from upper left; calm and sophisticated, shallow depth rather than chunky 3D toy shapes.
Constraints: genuine transparent alpha background, no solid background, no checkerboard pattern, no text, letters, numbers, typography, watermark, brand logo, UI controls, search box, buttons, playback triangle, crown, large sparkle, stars, people, faces, giant film reel, confetti, random nodes, connecting wires, neon, excessive glow or heavy blur. Do not draw an app screen. The collage is background decoration; preserve a strong readable silhouette when reduced to roughly 150 pixels wide.
```

## 接入约束

- 装饰跟随内容栏右缘，限制在页头，不包围搜索或排期按钮。
- 以原图透明通道叠加，避免染成统一色导致纹理层次消失。
- 控制显示透明度和解码尺寸；仅出现一次，不在结果卡中反复铺图。
- 忽略点击与读屏，正文与操作仍由原组件承担。
