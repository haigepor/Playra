# Playra 热播榜奖牌生成提示词

2026-10-15，使用内置 image_gen。三张原始透明 PNG 已保存到 assets/images/modern-rank-medal-{first,second,third}.png。圆章、大号数字、短靛紫绶带，金银铜同一系列。原奖杯与背景提示词保留。

应用展示：图片 24×27，2px 黄色衬底内边距，总体 28×31；海报左上贴边，黄色 #e7b65c 与其他排名一致，由海报裁切外角，右下内角 9px。源码与预览替换前副本在 .dart_tool/rank-medal-backup/。

验证：三张 RGBA PNG 的角落 alpha 为 0；预览实测图片 24×27，390px 无横向溢出、无缺失图片；Dart 单文件分析通过，Web 构建通过（95.6 秒）。生成原图分别为 1161×1355、1160×1355、1160×1355。使用 BoxFit.contain，保持比例；原奖杯文件保留用于回退。此次修改包括 MioPoster 素材映射/尺寸、ui-refinement-preview.html 与三张新增图片，不改变排名、点击或播放逻辑。

## Gold

```text
Use case: stylized-concept.
Asset type: one transparent PNG first-place MEDAL corner icon for a sophisticated dark cinema app. This is a production UI asset intended to be displayed only 24 by 28 pixels, not a mockup.
Subject: a front-facing round champagne-gold award medal with two very short muted indigo ribbon tails peeking out below. The circular medallion occupies the upper 80 percent of the total silhouette, the short notched tails occupy only the remaining 20 percent. A large deeply contrasting dark umber numeral "1" centered on the clean flat face occupies 60 percent of the disc height. Bold rounded sans-serif numeral, instantly readable at tiny size. Exactly one numeral.
Material: refined tactile matte paper-ceramic with restrained satin gold foil on a single softly beveled rim, delicate fine grain, shallow relief. Gold face #E3BF73, pale champagne rim #F8DFA1, dark numeral #493113, muted indigo ribbon #737BA9 with slightly lighter folded edge. Soft diffuse upper-left lighting, subtle attached shading. A thin dark outer edge helps separate the medal from bright poster art; the pale rim separates it from dark art.
Composition: portrait canvas approximately 6:7, single centered medal filling 92 percent of width and height, small even transparent margins. Perfectly frontal, symmetrical round disc, no rotation or perspective distortion. Simple coherent silhouette and broad calm surfaces. Keep the entire medal and ribbon tips inside frame.
Constraints: genuinely transparent alpha background, no backdrop and no checkerboard; no trophy, cup, handles, pedestal, shield, crown, laurel wreath, stars, sparkles, extra medals, decorative text, tiny lettering, watermark, glossy plastic, harsh reflections or heavy floating drop shadow. No app frame. Do not make a photorealistic sports trophy. Prioritize a large high-contrast "1" and the elegant round medal shape over intricate ornament.
```

## Silver

```text
Use case: precise-object-edit. Input image is the edit target and exact master for a set of three small cinema-app ranking medal icons.
Keep the exact same canvas, transparent margins, circular medal silhouette, short notched indigo ribbons, all geometry, face size, large centered numeral placement and size, tactile matte paper-ceramic grain, restrained beveled foil rim, frontal view and soft upper-left lighting. Keep ribbons muted indigo exactly as the original. Preserve true transparent alpha, including between ribbons.
Change ONLY the medal metal finish and central numeral as specified below. The new digit must retain the original large dark high-contrast rounded bold style, occupying the same face area for readability at 24 x 28 pixels. No trophy, new decoration, stars, laurels, words, other numerals, background, checkerboard or watermark.
Make the disc fog-silver #BBC8D8 with a pale silver #ECF1F7 rim and subtle cool slate recesses. Replace "1" with the exact numeral "2", once only, dark blue-slate #28394B.
```

## Bronze

```text
Use case: precise-object-edit. Input image is the edit target and exact master for a set of three small cinema-app ranking medal icons.
Keep the exact same canvas, transparent margins, circular medal silhouette, short notched indigo ribbons, all geometry, face size, large centered numeral placement and size, tactile matte paper-ceramic grain, restrained beveled foil rim, frontal view and soft upper-left lighting. Keep ribbons muted indigo exactly as the original. Preserve true transparent alpha, including between ribbons.
Change ONLY the medal metal finish and central numeral as specified below. The new digit must retain the original large dark high-contrast rounded bold style, occupying the same face area for readability at 24 x 28 pixels. No trophy, new decoration, stars, laurels, words, other numerals, background, checkerboard or watermark.
Make the disc warm copper-bronze #CDA184 with a pale copper #F0CFB6 rim and subtle warm brown recesses. Replace "1" with the exact numeral "3", once only, dark brown #4A2F23.
```


黄色贴边版回退副本：.dart_tool/rank-yellow-backup/。生成图片与原始提示词未修改。
