# Обложки мини-игр

Сгенерированы встроенным imagegen 2026-10-08. Итоговые ассеты: `assets/images/games/traffic_controller_cover.webp` и `assets/images/games/sign_swiper_cover.webp`, 1280×720, WebP. Названия, рекорды, градиент и размытие накладывает Flutter — в изображения они не вшиты.

Регулировщик: основа — настоящий крупный кадр `assets/game/traffic-controller.html`, снятый headless Chrome с сигналом `rightArmForward`, подходом `front` и камерой `(2.5, 2.3, 4.2)`, направленной на `(0, 1.05, 0)`. Свайпер: стиль первой обложки и SVG знаков 2.4, 2.5, 3.1 из базы приложения.

## Регулировщик — итоговый промпт

```text
Use case: ads-marketing. Asset type: horizontal mobile mini-game cover, 16:9, 1536x864.
Primary request: turn this REAL screenshot of the Russian traffic-controller mini-game into an appealing premium game key art cover. Input image 1 is the edit target and authentic game reference.
Preserve the distinctive recognizable low-poly 3D inspector: navy Russian peaked cap with red piping, navy uniform, fluorescent yellow reflective vest, black and white baton, two normal arms, the exact right-arm-forward traffic gesture and natural anatomy. Keep the real game's simple faceted aesthetic, sharpen and improve materials and lighting without turning him into a realistic person or replacing his face design.
Composition: much closer three-quarter hero shot, inspector large centered slightly right, cap/head and upper body in the upper 65% of the image, recognizable baton foreshortened toward lower left. Crop below knees if needed. Background is the same clean modern intersection with real zebra crossing, trees and modern buildings, artistically softened. Lower 25% visually calm asphalt, for app-rendered title overlay later.
Art direction for a matching pair: crisp premium stylized 3D game still, rich deep navy and cobalt blue twilight sky, cool blue ambient light with a restrained warm side light, fluorescent lime vest as focal accent. Beautiful tactile matte materials, photographic depth of field, strong silhouette, energetic diagonal composition. Tasteful contrast, no harsh oversaturation. Feels like polished actual video-game box art.
No text, no lettering, no badges, no logos, no UI, no floating symbols, no arrows, no extra traffic signs, no lens flares, no cartoon exaggerations, no particles, no neon outlines, no collage, no extra fingers or limbs, no glossy stock render. Do not burn in a title or bottom black gradient: actual UI will apply those. Strictly landscape 16:9.
```

## Знак-Свайпер — итоговый промпт

```text
Use case: ads-marketing. Asset type: horizontal mobile mini-game cover, strict 16:9, 1536x864.
Create the matching companion cover for a road-sign swipe game.
Input image 1 is ONLY the art direction reference: match its polished restrained 3D game rendering, cobalt blue dusk, navy asphalt, warm edge illumination, matte materials and photographic depth of field. Do not include the inspector.
Input image 2 is the exact road-sign graphic reference from the actual app. Keep these three sign designs: inverted triangular red-border white-center yield sign, red octagonal STOP with clean white uppercase STOP and thin white border, red circular no-entry sign with horizontal white rectangle. Signs must look correct for Russian traffic regulations, do not invent decorative details on sign faces.
Main composition: three thick matte-white rounded playing cards hovering in a loose diagonal fan above a clean dark-blue city road, large and readable upper 70% of image. Large central card with red STOP octagon, tilted about 7 degrees clockwise, slight perspective; card behind to the left has yield sign; card behind to the right has no-entry sign. Edges have tasteful warm reflections matching image 1. Show a clear swipe choice using ONLY two simple short substantial 3D directional arrows floating outside the cards: muted coral-red left-pointing arrow to the far left and vivid green right-pointing arrow far right. No screen, no phone, no hands. The arrows are gesture cues, not road signs.
Background same soft-focus modern Russian game city at blue dusk, tasteful warm window bokeh. Keep it subtle, clean and lightly blurred; no specific recognizable landmarks. Lower 25% calm asphalt with space for real UI title later. Main subjects large enough to read at mobile thumbnail size.
Exact only text: STOP, on the stop sign. No captions, no title, no logo, no badges, no numbers, no watermark, no invented glyphs. No flashy glows, no particles, no neon rims, no flares, no glossy plastic clutter. Professional cohesive game key art, appealing and simple.
```

