import os
from PIL import Image, ImageDraw, ImageFont

FONTS_DIR = "/Users/sergei/Documents/pdd/assets/fonts"
USER_DESKTOP_SRC = "/Users/sergei/Desktop/Новая папка"

COLOR_BLUE = (5, 116, 248)       # #0574F8
COLOR_GREEN = (52, 168, 83)      # #34A853
COLOR_GOLD = (235, 130, 20)      # #EB8214

CARDS_CONFIG = [
    {
        "name_appstore": "01_AppStore_Лента_Reels.png",
        "name_rustore": "01_RuStore_Лента_Reels.jpg",
        "name_generic": "01_feed_reels",
        "src_img": "Screenshot_20260824-230004.png",
        "bg_color": COLOR_BLUE,
        "badge_text": "НОВИНКА 2026",
        "badge_text_color": COLOR_BLUE,
        "title": "Интерактивная\nлента ПДД",
    },
    {
        "name_appstore": "02_AppStore_Умная_Лента.png",
        "name_rustore": "02_RuStore_Умная_Лента.jpg",
        "name_generic": "02_offline_voice",
        "src_img": "Screenshot_20260824-225957.png",
        "bg_color": COLOR_BLUE,
        "badge_text": "УМНАЯ ЛЕНТА",
        "badge_text_color": COLOR_BLUE,
        "title": "Вопросы и знаки\nв формате ленты",
    },
    {
        "name_appstore": "03_AppStore_Экзамен_ГАИ.png",
        "name_rustore": "03_RuStore_Экзамен_ГАИ.jpg",
        "name_generic": "03_exam_gai",
        "src_img": "Screenshot_20260824-230018.png",
        "bg_color": COLOR_GREEN,
        "badge_text": "РЕГЛАМЕНТ ГИБДД",
        "badge_text_color": COLOR_GREEN,
        "title": "Экзамен ГАИ\nкак в реальности",
    },
    {
        "name_appstore": "04_AppStore_Билеты_ПДД.png",
        "name_rustore": "04_RuStore_Билеты_ПДД.jpg",
        "name_generic": "04_tickets_comments",
        "src_img": "Screenshot_20260824-230106.png",
        "bg_color": COLOR_BLUE,
        "badge_text": "КАТЕГОРИИ AB И CD",
        "badge_text_color": COLOR_BLUE,
        "title": "Актуальные\nбилеты и темы", # Fully compliant: 'Актуальные' instead of 'Официальные'
    },
    {
        "name_appstore": "05_AppStore_Дорожные_Знаки.png",
        "name_rustore": "05_RuStore_Дорожные_Знаки.jpg",
        "name_generic": "05_road_signs",
        "src_img": "Screenshot_20260824-230007.png",
        "bg_color": COLOR_GOLD,
        "badge_text": "ЗНАКИ И ШТРАФЫ",
        "badge_text_color": COLOR_GOLD,
        "title": "Дорожные знаки\nи викторины",
    },
    {
        "name_appstore": "06_AppStore_Умная_Статистика.png",
        "name_rustore": "06_RuStore_Умная_Статистика.jpg",
        "name_generic": "06_smart_progress",
        "src_img": "Screenshot_20260824-225947.png",
        "bg_color": COLOR_GREEN,
        "badge_text": "СДАЧА С 1-Й ПОПЫТКИ",
        "badge_text_color": COLOR_GREEN,
        "title": "Умная оценка\nготовности",
    },
]

def create_rounded_mask(size, radius):
    mask = Image.new('L', size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), size], radius=radius, fill=255)
    return mask

def generate_appstore():
    WIDTH, HEIGHT = 1242, 2688
    OUT_DIR = "/Users/sergei/Desktop/PDD_Release_v1.1.0/AppStore_Screenshots"
    os.makedirs(OUT_DIR, exist_ok=True)
    
    font_badge = ImageFont.truetype(f"{FONTS_DIR}/Onest-Bold.ttf", 32)
    font_title = ImageFont.truetype(f"{FONTS_DIR}/Onest-Bold.ttf", 102)
    
    for cfg in CARDS_CONFIG:
        card = Image.new("RGBA", (WIDTH, HEIGHT), cfg["bg_color"] + (255,))
        draw = ImageDraw.Draw(card)
        
        PILL_Y = 135
        PILL_HEIGHT = 64
        badge_text = cfg["badge_text"]
        bbox_b = font_badge.getbbox(badge_text)
        text_w = bbox_b[2] - bbox_b[0]
        pill_w = text_w + 72
        pill_x = (WIDTH - pill_w) // 2
        
        draw.rounded_rectangle([(pill_x, PILL_Y), (pill_x + pill_w, PILL_Y + PILL_HEIGHT)], radius=PILL_HEIGHT // 2, fill=(255, 255, 255))
        draw.text((pill_x + (pill_w - text_w) // 2 - bbox_b[0], PILL_Y + (PILL_HEIGHT // 2) - 20), badge_text, font=font_badge, fill=cfg["badge_text_color"])
        
        lines = cfg["title"].split("\n")
        line_height = 120
        ty_start = PILL_Y + PILL_HEIGHT + 45
        for i, line in enumerate(lines):
            bbox_l = font_title.getbbox(line)
            lw = bbox_l[2] - bbox_l[0]
            draw.text(((WIDTH - lw) // 2 - bbox_l[0], ty_start + (i * line_height) - bbox_l[1]), line, font=font_title, fill=(255, 255, 255))
        
        MARGIN = 160
        target_w = WIDTH - (2 * MARGIN)
        raw = Image.open(os.path.join(USER_DESKTOP_SRC, cfg["src_img"])).convert("RGBA")
        target_h = int(raw.height * (target_w / raw.width))
        raw_resized = raw.resize((target_w, target_h), Image.Resampling.LANCZOS)
        
        mask = create_rounded_mask((target_w, target_h), 72)
        card.paste(raw_resized, (MARGIN, HEIGHT - MARGIN - target_h), mask)
        
        card.convert("RGB").save(os.path.join(OUT_DIR, cfg["name_appstore"]), quality=96)
    print("AppStore screenshots regenerated!")

def generate_rustore_and_generic():
    WIDTH, HEIGHT = 1080, 1920
    DIR_RU = "/Users/sergei/Desktop/PDD_Release_v1.1.0/RuStore_Screenshots"
    DIR_GEN = "/Users/sergei/Desktop/PDD_Release_v1.1.0/Screenshots"
    os.makedirs(DIR_RU, exist_ok=True)
    os.makedirs(DIR_GEN, exist_ok=True)
    
    font_badge = ImageFont.truetype(f"{FONTS_DIR}/Onest-Bold.ttf", 26)
    font_title = ImageFont.truetype(f"{FONTS_DIR}/Onest-Bold.ttf", 72)
    
    for cfg in CARDS_CONFIG:
        card = Image.new("RGBA", (WIDTH, HEIGHT), cfg["bg_color"] + (255,))
        draw = ImageDraw.Draw(card)
        
        PILL_Y, PILL_HEIGHT = 60, 48
        badge_text = cfg["badge_text"]
        bbox_b = font_badge.getbbox(badge_text)
        text_w = bbox_b[2] - bbox_b[0]
        pill_w = text_w + 52
        pill_x = (WIDTH - pill_w) // 2
        
        draw.rounded_rectangle([(pill_x, PILL_Y), (pill_x + pill_w, PILL_Y + PILL_HEIGHT)], radius=PILL_HEIGHT // 2, fill=(255, 255, 255))
        draw.text((pill_x + (pill_w - text_w) // 2 - bbox_b[0], PILL_Y + (PILL_HEIGHT // 2) - 17), badge_text, font=font_badge, fill=cfg["badge_text_color"])
        
        lines = cfg["title"].split("\n")
        line_height = 84
        ty_start = PILL_Y + PILL_HEIGHT + 24
        for i, line in enumerate(lines):
            bbox_l = font_title.getbbox(line)
            lw = bbox_l[2] - bbox_l[0]
            draw.text(((WIDTH - lw) // 2 - bbox_l[0], ty_start + (i * line_height) - bbox_l[1]), line, font=font_title, fill=(255, 255, 255))
        
        raw = Image.open(os.path.join(USER_DESKTOP_SRC, cfg["src_img"])).convert("RGBA")
        target_h = 1490
        target_w = int(raw.width * (target_h / raw.height))
        raw_resized = raw.resize((target_w, target_h), Image.Resampling.LANCZOS)
        
        mask = create_rounded_mask((target_w, target_h), 52)
        sx = (WIDTH - target_w) // 2
        sy = HEIGHT - 70 - target_h
        card.paste(raw_resized, (sx, sy), mask)
        
        final_rgb = card.convert("RGB")
        final_rgb.save(os.path.join(DIR_RU, cfg["name_rustore"]), quality=96)
        final_rgb.save(os.path.join(DIR_GEN, cfg["name_generic"] + ".jpg"), quality=96)
        final_rgb.save(os.path.join(DIR_GEN, cfg["name_generic"] + ".png"), quality=96)
    print("RuStore and Generic screenshots regenerated!")

if __name__ == "__main__":
    generate_appstore()
    generate_rustore_and_generic()
