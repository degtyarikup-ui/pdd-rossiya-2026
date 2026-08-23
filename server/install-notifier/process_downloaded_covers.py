#!/usr/bin/env python3
"""Process all 29 downloaded images from ~/Desktop/download into article covers."""

import os
from pathlib import Path
from PIL import Image

DOWNLOAD_DIR = Path(os.path.expanduser('~/Desktop/download'))
BLOG_DIR = Path('web_landing/ru/blog')

MAPPING = {
    'Applicant_taking_driving_test': 'shtrafnye-bally-ekzamen-gibdd-gorod',
    'Approaching_city_crossroad_traff': 'proezd-na-zheltyy-signal-svetofora-pdd',
    'Car_driving_on_urban_street': 'dvizhenie-po-tramvaynym-putyam-pdd',
    'Car_following_agricultural_tractor': 'obgon-tihohoda-cherez-sploshnuyu-pdd',
    'Car_performing_three-point_turn': 'razvorot-v-ogranichennom-prostranstve-ekzamen',
    'Car_reverse_parallel_parking': 'parallelnaya-parkovka-zadnim-hodom-orientiry',
    'Car_reversing_into_garage_bay': 'zaezd-v-boks-garazh-zadnim-hodom-ekzamen',
    'Cars_changing_lanes_on_highway': 'pomeha-sprava-odnovremennoe-perestroenie',
    'Cars_stopped_at_urban_intersection': 'vafelnaya-razmetka-1-26-shtraf-pdd',
    'Driver_approaching_city_roundabo': 'krugovoe-dvizhenie-pravila-2026',
    'Driver_holding_tablet_with_road': 'mnemoniki-dlya-pdd-kak-bystro-zapomnit',
    'Driver_making_left_turn': 'povorot-nalevo-razvorot-traektoriya-pdd',
    'Driver_stopping_at_pedestrian_cr': 'ustupit-dorogu-peshehodu-na-zebre-pdd',
    'Driver_taking_practical_driving': 'prakticheskiy-ekzamen-gibdd',
    'Driver_viewing_digital_speedometer': 'tablitsa-shtrafov-za-prevyshenie-skorosti-2026',
    'Driving_across_city_bridge': 'reversivnoe-dvizhenie-polosa-pdd',
    'Driving_on_asphalt_highway': 'vyezd-na-vstrechnuyu-polosu-lishenie-ili-shtraf',
    'Electric_bus_on_city_avenue': 'vydelennaya-polosa-dlya-avtobusov-pdd',
    'Electric_scooter_parked_beside_s': 'nuzhny-li-prava-na-elektrosamokat-2026',
    'Electric_scooter_riding_on_lane': 'pravila-dlya-elektrosamokatov-sim-2026',
    'Emergency_car_kit_in_trunk': 'aptechka-ognetushitel-znak-v-mashine-2026',
    'Hand_on_manual_gearbox': 'mehanika-ili-avtomat-na-chem-sdavat-na-prava',
    'Police_checking_driver_documents': 'shtraf-za-ezdu-bez-prav-2026-tablitsa',
    'Police_patrol_car_at_checkpoint': 'otkaz-ot-medosvidestvovaniya-nakazanie-2026',
    'Red-and-white_tram_crossing_inte': 'tramvay-i-avtomobil-kogda-tramvay-ustupaet',
    'Smartphone_showing_traffic_fine': 'skidka-na-shtrafy-gibdd-25-protsentov-2026',
    'Studded_winter_car_tire': 'zimnyaya-rezina-zakon-sroki-shtraf-2026',
    'Traffic_light_showing_green_arrow': 'strelka-svetofora-dop-sektsiya-prioritet',
    'Traffic_police_officer_directing': 'signaly-regulirovshchika-prostymi-slovami-stih'
}

def process_all():
    files = sorted(os.listdir(DOWNLOAD_DIR))
    print(f"Found {len(files)} files in {DOWNLOAD_DIR}")
    
    processed_count = 0
    for f in files:
        matched_slug = None
        for prefix, slug in MAPPING.items():
            if f.startswith(prefix):
                matched_slug = slug
                break
        
        if not matched_slug:
            print(f"⚠️ Unmatched file: {f}")
            continue

        src_path = DOWNLOAD_DIR / f
        target_dir = BLOG_DIR / matched_slug
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / 'cover.jpg'
        
        # Open image and resize to 1200x630 (center crop if needed)
        im = Image.open(src_path).convert('RGB')
        
        # Target size 1200x630
        tw, th = 1200, 630
        orig_w, orig_h = im.size
        
        # Calculate aspect ratio crop
        target_aspect = tw / th
        orig_aspect = orig_w / orig_h
        
        if orig_aspect > target_aspect:
            # Crop left/right
            new_w = int(orig_h * target_aspect)
            left = (orig_w - new_w) // 2
            im = im.crop((left, 0, left + new_w, orig_h))
        else:
            # Crop top/bottom
            new_h = int(orig_w / target_aspect)
            top = (orig_h - new_h) // 2
            im = im.crop((0, top, orig_w, top + new_h))
            
        im = im.resize((tw, th), Image.Resampling.LANCZOS)
        im.save(str(target_path), 'JPEG', quality=92, optimize=True)
        
        print(f"✓ [{matched_slug}] -> {target_path} ({os.path.getsize(target_path)} bytes)")
        processed_count += 1

    print(f"\n🎉 Successfully processed {processed_count} of {len(MAPPING)} covers!")

if __name__ == '__main__':
    process_all()
