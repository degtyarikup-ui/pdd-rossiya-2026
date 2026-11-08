#!/usr/bin/env python3
"""Complete generator of unique 1200x630 covers for all 29 blog articles."""

import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

# Import locate and raster from tools.signs_reel
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.signs_reel import locate, raster

BLOG_DIR = Path('web_landing/ru/blog')
BG_DIR = Path('tools/signs_reel/backgrounds')
Q_IMG_DIR = Path('assets/countries/ru/images/questions_ab')
FONT_PATH = Path('tools/signs_reel/fonts/Onest[wght].ttf')

if not FONT_PATH.exists():
    FONT_PATH = Path('/System/Library/Fonts/Supplemental/Arial Bold.ttf')

def get_font(size: int, bold: bool = True):
    try:
        return ImageFont.truetype(str(FONT_PATH), size)
    except Exception:
        return ImageFont.load_default()

def hex_to_rgb(hex_str: str):
    hex_str = hex_str.lstrip('#')
    return tuple(int(hex_str[i:i+2], 16) for i in (0, 2, 4))

def create_gradient_bg(w: int, h: int, top_color: str, bot_color: str, bg_image_path: Path = None):
    top_rgb = hex_to_rgb(top_color)
    bot_rgb = hex_to_rgb(bot_color)
    
    base = Image.new('RGBA', (w, h), (11, 15, 25, 255))
    
    if bg_image_path and bg_image_path.exists():
        try:
            bg = Image.open(bg_image_path).convert('RGBA')
            bg = bg.resize((w, h), Image.Resampling.LANCZOS)
            bg = bg.filter(ImageFilter.GaussianBlur(radius=10))
            enhancer = ImageEnhance.Brightness(bg)
            bg = enhancer.enhance(0.24)
            base = Image.alpha_composite(base, bg)
        except Exception:
            pass

    grad = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(grad)
    for y in range(h):
        ratio = y / h
        r = int(top_rgb[0] * (1 - ratio) + bot_rgb[0] * ratio)
        g = int(top_rgb[1] * (1 - ratio) + bot_rgb[1] * ratio)
        b = int(top_rgb[2] * (1 - ratio) + bot_rgb[2] * ratio)
        draw.line([(0, y), (w, y)], fill=(r, g, b, 215))
        
    return Image.alpha_composite(base, grad)

def wrap_text(text: str, font: ImageFont.FreeTypeFont, max_width: int):
    words = text.split()
    lines = []
    current_line = []
    
    for word in words:
        test_line = ' '.join(current_line + [word])
        bbox = font.getbbox(test_line)
        w = bbox[2] - bbox[0]
        if w <= max_width or not current_line:
            current_line.append(word)
        else:
            lines.append(' '.join(current_line))
            current_line = [word]
    if current_line:
        lines.append(' '.join(current_line))
    return lines

def generate_cover(cfg: dict):
    slug = cfg['slug']
    category = cfg['category']
    title = cfg['title']
    subtitle = cfg['subtitle']
    badge_color = cfg.get('badge_color', '#38bdf8')
    accent_color = cfg.get('accent_color', '#0284c7')
    sign_number = cfg.get('sign')
    diagram_filename = cfg.get('diagram')
    bg_filename = cfg.get('bg', 'bridge_fog.png')

    W, H = 1200, 630
    
    # 1. Base background
    bg_path = BG_DIR / bg_filename if bg_filename else None
    img = create_gradient_bg(W, H, '#0f172a', '#070a14', bg_path)

    # 2. Glowing ambient lights
    glow_color = hex_to_rgb(accent_color)
    glow_layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_layer)
    glow_draw.ellipse([W - 460, -80, W + 150, 480], fill=(glow_color[0], glow_color[1], glow_color[2], 30))
    glow_draw.ellipse([-80, H - 220, 260, H + 180], fill=(glow_color[0], glow_color[1], glow_color[2], 20))
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=60))
    img = Image.alpha_composite(img, glow_layer)

    # 3. Right showcase card
    right_card_w = 470
    right_card_h = 440
    right_card_x = W - right_card_w - 55
    right_card_y = (H - right_card_h) // 2

    card_bg = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    card_draw = ImageDraw.Draw(card_bg)
    card_draw.rounded_rectangle(
        [right_card_x, right_card_y, right_card_x + right_card_w, right_card_y + right_card_h],
        radius=20,
        fill=(15, 23, 42, 235),
        outline=hex_to_rgb(accent_color) + (110,),
        width=2
    )
    img = Image.alpha_composite(img, card_bg)
    draw = ImageDraw.Draw(img)

    # Place Diagram or Sign
    if diagram_filename:
        diag_path = Q_IMG_DIR / diagram_filename
        if diag_path.exists():
            try:
                diag_img = Image.open(diag_path).convert('RGBA')
                dw = right_card_w - 28
                dh = right_card_h - 28
                diag_img.thumbnail((dw, dh), Image.Resampling.LANCZOS)
                
                dx = right_card_x + (right_card_w - diag_img.width) // 2
                dy = right_card_y + (right_card_h - diag_img.height) // 2
                
                mask = Image.new('L', diag_img.size, 0)
                mask_draw = ImageDraw.Draw(mask)
                mask_draw.rounded_rectangle([0, 0, diag_img.width, diag_img.height], radius=14, fill=255)
                
                img.paste(diag_img, (dx, dy), mask)
            except Exception as e:
                print(f"Error loading diagram {diagram_filename}: {e}")

    elif sign_number:
        svg_path = locate.sign_image(sign_number)
        if svg_path:
            try:
                sign_img = raster.rasterize(svg_path, 340)
                if sign_img:
                    sx = right_card_x + (right_card_w - sign_img.width) // 2
                    sy = right_card_y + (right_card_h - sign_img.height) // 2
                    
                    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                    s_draw = ImageDraw.Draw(shadow)
                    s_draw.ellipse([sx - 15, sy + sign_img.height - 25, sx + sign_img.width + 15, sy + sign_img.height + 25], fill=(0, 0, 0, 150))
                    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=18))
                    img = Image.alpha_composite(img, shadow)
                    
                    img.paste(sign_img, (sx, sy), sign_img)
            except Exception as e:
                print(f"Error rasterizing sign {sign_number}: {e}")

    # 4. Left side: Typography & Badges
    left_x = 65
    max_title_w = right_card_x - left_x - 35
    
    # A. Category Pill Badge
    cat_font = get_font(14, bold=True)
    cat_bbox = cat_font.getbbox(category.upper())
    cat_w = cat_bbox[2] - cat_bbox[0]
    cat_h = cat_bbox[3] - cat_bbox[1]
    
    badge_x = left_x
    badge_y = 65
    badge_pad_x = 13
    badge_pad_y = 6
    
    b_rgb = hex_to_rgb(badge_color)
    draw.rounded_rectangle(
        [badge_x, badge_y, badge_x + cat_w + badge_pad_x * 2, badge_y + cat_h + badge_pad_y * 2 + 2],
        radius=7,
        fill=(b_rgb[0], b_rgb[1], b_rgb[2], 35),
        outline=b_rgb + (170,),
        width=1
    )
    draw.text((badge_x + badge_pad_x, badge_y + badge_pad_y - 1), category.upper(), font=cat_font, fill=b_rgb)

    # B. Main Article Title
    title_font_size = 44 if len(title) < 42 else (38 if len(title) < 62 else 33)
    title_font = get_font(title_font_size, bold=True)
    title_lines = wrap_text(title, title_font, max_title_w)
    
    title_y = badge_y + 44
    line_h = title_font_size + 10
    
    for line in title_lines:
        draw.text((left_x, title_y), line, font=title_font, fill=(255, 255, 255))
        title_y += line_h

    # C. Subtitle / Law Citation
    if subtitle:
        title_y += 10
        sub_font = get_font(20, bold=False)
        sub_lines = wrap_text(subtitle, sub_font, max_title_w)
        for line in sub_lines[:3]:
            draw.text((left_x, title_y), line, font=sub_font, fill=(156, 175, 204))
            title_y += 27

    # D. Branded Footer
    footer_font = get_font(14, bold=True)
    footer_text = "ПДД РОССИЯ 2026 · РАЗБОР БИЛЕТОВ И ПРАВИЛ"
    footer_y = H - 70
    
    draw.ellipse([left_x, footer_y + 4, left_x + 8, footer_y + 12], fill=hex_to_rgb(accent_color))
    draw.text((left_x + 18, footer_y), footer_text, font=footer_font, fill=(115, 140, 170))

    # Save
    out_dir = BLOG_DIR / slug
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / 'cover.jpg'
    
    final_rgb = img.convert('RGB')
    final_rgb.save(str(out_path), 'JPEG', quality=92, optimize=True)
    print(f"✓ [{slug}] -> {out_path} ({os.path.getsize(out_path)} bytes)")

ARTICLES = [
    {
        'slug': 'krugovoe-dvizhenie-pravila-2026',
        'category': 'МАНЕВРЫ И ПРИОРИТЕТ',
        'title': 'Круговое движение в 2026 году',
        'subtitle': 'Кто уступает, въезд и съезд по п. 13.11(1) ПДД РФ',
        'badge_color': '#38bdf8',
        'accent_color': '#0284c7',
        'sign': '4.3',
        'bg': 'tunnel.png'
    },
    {
        'slug': 'povorot-nalevo-razvorot-traektoriya-pdd',
        'category': 'МАНЕВРИРОВАНИЕ',
        'title': 'Поворот налево и разворот',
        'subtitle': 'Малый или большой радиус: п. 8.6 ПДД и ст. 12.15 КоАП',
        'badge_color': '#38bdf8',
        'accent_color': '#0ea5e9',
        'diagram': '0de3a44f154b8a1dc98c83ccb64a0c6c.jpg',
        'bg': 'bridge_fog.png'
    },
    {
        'slug': 'strelka-svetofora-dop-sektsiya-prioritet',
        'category': 'СВЕТОФОРЫ И ПРИОРИТЕТ',
        'title': 'Стрелка доп. секции светофора',
        'subtitle': 'Кто кому уступает дорогу по п. 13.5 ПДД РФ',
        'badge_color': '#34d399',
        'accent_color': '#10b981',
        'diagram': 'd67f11a6e67191503276e8e32a58f4f4.jpg',
        'bg': 'night_rain.png'
    },
    {
        'slug': 'tramvay-i-avtomobil-kogda-tramvay-ustupaet',
        'category': 'ПРИОРИТЕТ ДВИЖЕНИЯ',
        'title': 'Трамвай и автомобиль по ПДД',
        'subtitle': '3 ситуации, когда трамвай обязан уступить дорогу авто',
        'badge_color': '#c084fc',
        'accent_color': '#a855f7',
        'diagram': '657506834f78d08a97983b19a4cfd256.jpg',
        'bg': 'tunnel.png'
    },
    {
        'slug': 'obgon-tihohoda-cherez-sploshnuyu-pdd',
        'category': 'ОБГОН И ШТРАФЫ',
        'title': 'Обгон тихохода через сплошную',
        'subtitle': 'Знак 3.20 Обгон запрещен, разметка 1.1 и решения суда',
        'badge_color': '#fb7185',
        'accent_color': '#e11d48',
        'diagram': '5b0fd17cc1af4de1d099c6868930117d.jpg',
        'bg': 'autumn.png'
    },
    {
        'slug': 'pomeha-sprava-odnovremennoe-perestroenie',
        'category': 'ПЕРЕСТРОЕНИЕ И ПОЛОСЫ',
        'title': 'Помеха справа при перестроении',
        'subtitle': 'Кто уступает при взаимном перестроении по п. 8.4 ПДД',
        'badge_color': '#38bdf8',
        'accent_color': '#0284c7',
        'diagram': 'a450a0e7eb0e4235fa9bec6c20dfa1ff.jpg',
        'bg': 'bridge_fog.png'
    },
    {
        'slug': 'proezd-na-zheltyy-signal-svetofora-pdd',
        'category': 'СВЕТОФОР И КАМЕРЫ',
        'title': 'Проезд на желтый сигнал светофора',
        'subtitle': 'Пункт 6.14 ПДД, экстренное торможение и штрафы с камер',
        'badge_color': '#fbbf24',
        'accent_color': '#d97706',
        'diagram': 'd67f11a6e67191503276e8e32a58f4f4.jpg',
        'bg': 'night_rain.png'
    },
    {
        'slug': 'vafelnaya-razmetka-1-26-shtraf-pdd',
        'category': 'РАЗМЕТКА И ШТРАФЫ',
        'title': 'Вафельная разметка 1.26',
        'subtitle': 'Правила выезда на перекресток в заторе и штрафы с камер',
        'badge_color': '#fb7185',
        'accent_color': '#e11d48',
        'diagram': '6a8f690af1b507fc0b56db742709f1e8.jpg',
        'bg': 'tunnel.png'
    },
    {
        'slug': 'signaly-regulirovshchika-prostymi-slovami-stih',
        'category': 'РЕГУЛИРОВЩИК',
        'title': 'Сигналы регулировщика',
        'subtitle': 'Простые стихи и схемы жезла для быстрого запоминания',
        'badge_color': '#38bdf8',
        'accent_color': '#0ea5e9',
        'diagram': '1416a3e01503045460c35a1b174b65e9.jpg',
        'bg': 'bridge_fog.png'
    },
    {
        'slug': 'dvizhenie-po-tramvaynym-putyam-pdd',
        'category': 'ТРАМВАЙНЫЕ ПУТИ',
        'title': 'Движение по трамвайным путям',
        'subtitle': 'Когда разрешено ехать по путям и когда грозит лишение прав',
        'badge_color': '#c084fc',
        'accent_color': '#a855f7',
        'diagram': '1517fd90f3391baa0f81dd87d68d740b.jpg',
        'bg': 'tunnel.png'
    },
    {
        'slug': 'reversivnoe-dvizhenie-polosa-pdd',
        'category': 'РЕВЕРСИВНЫЕ ПОЛОСЫ',
        'title': 'Реверсивное движение по ПДД',
        'subtitle': 'Знак 5.8, реверсивные светофоры и разметка 1.9',
        'badge_color': '#34d399',
        'accent_color': '#10b981',
        'diagram': 'bbec994b533287b90e72eb935af6e333.jpg',
        'bg': 'bridge_fog.png'
    },
    {
        'slug': 'mnemoniki-dlya-pdd-kak-bystro-zapomnit',
        'category': 'ЛАЙФХАКИ ДЛЯ СДАЧИ',
        'title': '10 мнемоник для сдачи ПДД',
        'subtitle': 'Простые стихи и ассоциации для запоминания сложных билетов',
        'badge_color': '#38bdf8',
        'accent_color': '#0284c7',
        'sign': '2.1',
        'bg': 'meadow.png'
    },
    {
        'slug': 'razvorot-v-ogranichennom-prostranstve-ekzamen',
        'category': 'ПРАКТИКА ВОЖДЕНИЯ',
        'title': 'Разворот в ограниченном месте',
        'subtitle': 'Пошаговый алгоритм выполнения упражнения в городе и на площадке',
        'badge_color': '#34d399',
        'accent_color': '#059669',
        'diagram': '0de3a44f154b8a1dc98c83ccb64a0c6c.jpg',
        'bg': 'garage.png'
    },
    {
        'slug': 'parallelnaya-parkovka-zadnim-hodom-orientiry',
        'category': 'ПАРКОВКА',
        'title': 'Параллельная парковка задом',
        'subtitle': 'Ориентиры по зеркалам и стойкам: безошибочный заезд',
        'badge_color': '#34d399',
        'accent_color': '#059669',
        'diagram': '10c93fd2e8cb0fc0fb705d68be3d970e.jpg',
        'bg': 'garage.png'
    },
    {
        'slug': 'zaezd-v-boks-garazh-zadnim-hodom-ekzamen',
        'category': 'УПРАЖНЕНИЯ ГИБДД',
        'title': 'Заезд в бокс задним ходом',
        'subtitle': 'Инструкция для экзамена ГИБДД: парковка под 90 градусов',
        'badge_color': '#34d399',
        'accent_color': '#059669',
        'diagram': '10c93fd2e8cb0fc0fb705d68be3d970e.jpg',
        'bg': 'garage.png'
    },
    {
        'slug': 'mehanika-ili-avtomat-na-chem-sdavat-na-prava',
        'category': 'ВЫБОР ОБУЧЕНИЯ',
        'title': 'Механика или автомат (МКПП vs АКПП)',
        'subtitle': 'На чем проще сдавать экзамен на права и отметка АТ',
        'badge_color': '#38bdf8',
        'accent_color': '#0284c7',
        'sign': '3.24',
        'bg': 'tunnel.png'
    },
    {
        'slug': 'tablitsa-shtrafov-za-prevyshenie-skorosti-2026',
        'category': 'ТАБЛИЦА ШТРАФОВ',
        'title': 'Штрафы за скорость в 2026 году',
        'subtitle': 'Таблица сумм от +20 до +80 км/ч, повторные нарушения и лишение',
        'badge_color': '#fb7185',
        'accent_color': '#e11d48',
        'sign': '3.24',
        'bg': 'bridge_fog.png'
    },
    {
        'slug': 'skidka-na-shtrafy-gibdd-25-protsentov-2026',
        'category': 'НОВЫЕ ЗАКОНЫ 2026',
        'title': 'Скидка 25% на штрафы ГИБДД',
        'subtitle': 'Новый закон: 30 дней на льготную оплату через Госуслуги',
        'badge_color': '#34d399',
        'accent_color': '#10b981',
        'sign': '3.1',
        'bg': 'autumn.png'
    },
    {
        'slug': 'vyezd-na-vstrechnuyu-polosu-lishenie-ili-shtraf',
        'category': 'СТАТЬЯ 12.15 КОАП',
        'title': 'Выезд на встречную полосу',
        'subtitle': 'Когда штраф 5000 рублей, а когда лишение прав до 6 месяцев',
        'badge_color': '#fb7185',
        'accent_color': '#e11d48',
        'sign': '3.20',
        'bg': 'bridge_fog.png'
    },
    {
        'slug': 'pravila-dlya-elektrosamokatov-sim-2026',
        'category': 'СИМ И САМОКАТЫ',
        'title': 'Правила для электросамокатов (СИМ)',
        'subtitle': 'Скорость до 25 км/ч, вес до 35 кг, зоны и штрафы',
        'badge_color': '#38bdf8',
        'accent_color': '#0284c7',
        'sign': '5.19.1',
        'bg': 'sunflowers.png'
    },
    {
        'slug': 'nuzhny-li-prava-na-elektrosamokat-2026',
        'category': 'КАТЕГОРИИ ПРАВ',
        'title': 'Нужны ли права на электросамокат?',
        'subtitle': 'Мощность свыше 250 Вт, категория М и ответственность водителя',
        'badge_color': '#38bdf8',
        'accent_color': '#0ea5e9',
        'sign': '3.1',
        'bg': 'night_rain.png'
    },
    {
        'slug': 'zimnyaya-rezina-zakon-sroki-shtraf-2026',
        'category': 'СЕЗОННЫЕ ТРЕБОВАНИЯ',
        'title': 'Зимняя резина в 2026 году',
        'subtitle': 'Обязательные месяцы по Техрегламенту, шипы и штрафы ГИБДД',
        'badge_color': '#38bdf8',
        'accent_color': '#0284c7',
        'diagram': 'c2975107ea070a3ffd8713df2de2354f.jpg',
        'bg': 'snow.png'
    },
    {
        'slug': 'aptechka-ognetushitel-znak-v-mashine-2026',
        'category': 'КОМПЛЕКТАЦИЯ АВТО',
        'title': 'Аптечка, огнетушитель, знак',
        'subtitle': 'Новые требования Минздрава № 260н к аварийному набору водителя',
        'badge_color': '#fbbf24',
        'accent_color': '#d97706',
        'diagram': '9e6a35bbbb7b463adf4264050cc26763.jpg',
        'bg': 'autumn.png'
    },
    {
        'slug': 'otkaz-ot-medosvidestvovaniya-nakazanie-2026',
        'category': 'СТАТЬЯ 12.26 КОАП',
        'title': 'Отказ от медосвидетельствования',
        'subtitle': 'Штраф 30 000 рублей и лишение прав на срок до 2 лет',
        'badge_color': '#fb7185',
        'accent_color': '#e11d48',
        'sign': '3.1',
        'bg': 'night_rain.png'
    },
    {
        'slug': 'shtraf-za-ezdu-bez-prav-2026-tablitsa',
        'category': 'ТАБЛИЦА ШТРАФОВ',
        'title': 'Штрафы за езду без прав 2026',
        'subtitle': 'Забыл дома (500 ₽), не получал (до 15 000 ₽), лишен (до 30 000 ₽)',
        'badge_color': '#fb7185',
        'accent_color': '#e11d48',
        'sign': '3.1',
        'bg': 'bridge_fog.png'
    },
    {
        'slug': 'ustupit-dorogu-peshehodu-na-zebre-pdd',
        'category': 'ПЕШЕХОДНЫЕ ПЕРЕХОДЫ',
        'title': 'Пешеход на зебре: п. 14.1 ПДД',
        'subtitle': 'Определение Уступить дорогу и фиксация нарушения камерами',
        'badge_color': '#34d399',
        'accent_color': '#10b981',
        'sign': '5.19.1',
        'bg': 'autumn.png'
    },
    {
        'slug': 'vydelennaya-polosa-dlya-avtobusov-pdd',
        'category': 'ПОЛОСА ДЛЯ МТС',
        'title': 'Выделенная полоса для автобусов',
        'subtitle': 'Знак 5.14 Полоса А, выезд для посадки и штрафы с камер',
        'badge_color': '#38bdf8',
        'accent_color': '#0284c7',
        'sign': '5.14',
        'bg': 'tunnel.png'
    },
    {
        'slug': 'shtrafnye-bally-ekzamen-gibdd-gorod',
        'category': 'РЕГЛАМЕНТ ГИБДД',
        'title': 'Штрафные баллы в ГИБДД (город)',
        'subtitle': 'Порог 7 баллов в 2026 году: таблица грубых, средних и мелких ошибок',
        'badge_color': '#fb7185',
        'accent_color': '#e11d48',
        'diagram': '6990f25d7841de055ce96398249f4608.jpg',
        'bg': 'bridge_fog.png'
    },
    {
        'slug': 'prakticheskiy-ekzamen-gibdd',
        'category': 'ПРАКТИЧЕСКИЙ ЭКЗАМЕН',
        'title': 'Практический экзамен ГИБДД 2026',
        'subtitle': 'Маршрут, регламент, чек-лист обязательных маневров и сдача',
        'badge_color': '#34d399',
        'accent_color': '#10b981',
        'diagram': '0de3a44f154b8a1dc98c83ccb64a0c6c.jpg',
        'bg': 'bridge_fog.png'
    }
]

if __name__ == '__main__':
    print(f"Starting generation of {len(ARTICLES)} article covers...")
    for cfg in ARTICLES:
        generate_cover(cfg)
    print("All 29 covers generated successfully!")
