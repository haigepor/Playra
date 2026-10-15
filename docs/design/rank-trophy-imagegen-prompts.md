# Playra 热播榜奖杯生成提示词

日期：2026-10-15。使用内置 `image_gen`，透明背景。用户选择奖杯造型，金、银、铜对应第 1/2/3 名；原盾牌 SVG 保留为备选素材。

当前应用尺寸：奖杯22×25，3px深色衬底内边距，整体28×31；海报左上内缩4px，解码宽度66px。排名读屏语义沿用海报外层。下方原始生成提示词保持不变。

素材：
- `assets/images/modern-rank-trophy-first.png`
- `assets/images/modern-rank-trophy-second.png`
- `assets/images/modern-rank-trophy-third.png`

## 金色母版

```text
Use case: stylized-concept.
Asset type: transparent PNG ranking TROPHY icon for the top three corner marks on movie posters in a dark cinema app. Generate one standalone FIRST PLACE TROPHY, not a UI mockup.
Input image: the approved Playra cinema paper collage is a MATERIAL AND LIGHTING reference only. Preserve its sophisticated matte grain, delicate layered edges and restrained shallow relief, but make the subject a miniature trophy cup, not a poster.
Primary request: a beautifully designed small champagne-gold trophy with a wide cup bowl, two elegant open side handles, a short narrow stem and a compact stable rounded rectangular base. Clean iconic silhouette, broad simple surfaces, restrained softly chamfered edges. One large dark umber numeral "1" centered directly on the cup bowl. The numeral is the main focal detail and remains instantly readable at 32 x 36 CSS pixels. Trophy design is refined and collectible, with a paper-grain ceramic body and subtle satin foil accents, not cartoonish.
Composition: portrait canvas, approximately 8:9. Exactly one symmetrical front-facing trophy, no tilt or perspective distortion. Cup and handles occupy the upper two thirds; stem and small base the lower third. Fill 90 percent of the width and 90 percent of the height, small consistent transparent margins. Shallow physical relief with a clean isolated silhouette. The two handle openings must have real transparency.
Palette: muted champagne gold #DDBA72, pale gold lip and edges #F0D69A, slightly deeper ochre recessed areas, dark umber numeral #513A18. Sophisticated low saturation.
Materials and lighting: fine matte paper-like texture from the reference, satin metal foil only on a thin rim, soft diffuse upper-left light, gentle attached contact shading, no dramatic shine. The texture and bevel must not obscure silhouette or numeral.
Text (verbatim): "1", exactly once, bold clean rounded sans-serif, centered on the upper cup body.
Constraints: true transparent alpha background; no solid or checkerboard backdrop. No shield badge, ribbons, laurel wreath, crown, stars, sparkles, confetti, floating particles, wings, extra trophies, extra text, labels, watermark, giant pedestal, glow, thick outline, glossy plastic, game loot styling or heavy shadow. No image of an app. All trophy edges fully inside frame.
```

## 银色派生

```text
Use case: precise-object-edit.
Asset type: transparent PNG silver second-place ranking trophy, one member of a matching trio for a dark cinema app.
Input image: edit target and exact visual master. It is the approved first-place gold trophy.
Change ONLY the following two things: recolor the gold trophy to cool muted fog-silver #B8C4D6, pale silver-blue edge highlights #DCE5F2, slate recesses and dark blue-slate number #304056; replace the large central numeral "1" with the exact numeral "2".
Keep unchanged: canvas dimensions and transparent margins, front-facing view, exact trophy silhouette, cup bowl, both open handles, stem, base, proportions, positions, thin rim details, fine matte paper grain, restrained satin edging, softly embossed depth and diffuse upper-left lighting. Preserve all original transparent areas including the handle openings. The numeral must be the same large size and dark contrast, centered in the same position, with matching clean bold rounded typography.
Text (verbatim): "2" exactly once. No other text.
Constraints: true transparent alpha background. One trophy only. No background, checkerboard, labels, ribbons, crowns, sparkles, laurels, other numbers or watermark. No redesign, no new ornament, no change of composition. This must feel like the exact same physical trophy in another finish and ranking number, readable at 32 x 36 CSS pixels.
```

## 铜色派生

```text
Use case: precise-object-edit.
Asset type: transparent PNG bronze third-place ranking trophy, one member of a matching trio for a dark cinema app.
Input image: edit target and exact visual master. It is the approved first-place gold trophy.
Change ONLY the following two things: recolor the gold trophy to warm muted copper-bronze #C49B83, soft pale copper edge highlights #E3B99E, warm brown recesses and dark umber number #56392B; replace the large central numeral "1" with the exact numeral "3".
Keep unchanged: canvas dimensions and transparent margins, front-facing view, exact trophy silhouette, cup bowl, both open handles, stem, base, proportions, positions, thin rim details, fine matte paper grain, restrained satin edging, softly embossed depth and diffuse upper-left lighting. Preserve all original transparent areas including the handle openings. The numeral must be the same large size and dark contrast, centered in the same position, with matching clean bold rounded typography.
Text (verbatim): "3" exactly once. No other text.
Constraints: true transparent alpha background. One trophy only. No background, checkerboard, labels, ribbons, crowns, sparkles, laurels, other numbers or watermark. No redesign, no new ornament, no change of composition. This must feel like the exact same physical trophy in another finish and ranking number, readable at 32 x 36 CSS pixels.
```

原始背景提示词继续完整保存在 [cinema-header-imagegen-prompt.md](cinema-header-imagegen-prompt.md)，没有修改其提示词正文。
