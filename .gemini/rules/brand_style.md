# Brand Design System & Visual Guidelines

## 1. Brand Color Tokens
- **Accent Blue (Primary Brand)**: `#0574F8` (RGB: `5, 116, 248`)
- **Light Accent Surface**: `#E8F2FE` (RGB: `232, 242, 254`)
- **Accent Surface 10%**: `rgba(5, 116, 248, 0.10)`
- **Primary Dark / Black**: `#121212`
- **Background Light**: `#F8F8FA`
- **Card Background**: `#FFFFFF`
- **Muted Gray**: `#A1A6B7` (secondary text), `#64748B` (subtitles)
- **Divider**: `#E8E8E8` / `rgba(255, 255, 255, 0.12)`

## 2. Universal Rules for Web & App
1. **Never use random blues or cyans**: Always use the brand blue `#0574F8` for accents, glows, active states, and brand highlights.
2. **Strict Design Consistency**: Web landing pages, blog articles, and Flutter app components must follow identical token values from `lib/core/constants/app_colors.dart` and `web_landing/ru/assets/style.css`.
3. **CTA Banners in Articles**:
   - Dark background: `#121212` (deep clean black).
   - Glow effect: soft radial gradient using ONLY `#0574F8` brand blue (e.g. `rgba(5, 116, 248, 0.55)` to `transparent`).
   - Store buttons: Pure white background `#FFFFFF`, dark typography `#111827`, and official colored vector store logos (Google Play multicolor, Apple black, RuStore `#0574F8`).
