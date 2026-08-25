#!/usr/bin/env python3
"""Automate full Flow batch generation across all 29 article prompts."""

import subprocess
import json
import time

def run_chrome_js(js_code: str):
    script = f'''tell application "Google Chrome"
    set t to active tab of front window
    execute t javascript {json.dumps(js_code)}
end tell'''
    return subprocess.check_output(['osascript', '-e', script]).decode('utf-8')

PROMPTS = [
    ("krugovoe-dvizhenie-pravila-2026", "POV driver view approaching modern city multi-lane roundabout intersection, Russian traffic signs 4.3 and 2.4, clean asphalt with lane markings, sunny daylight, photorealistic automotive photography, 16:9"),
    ("povorot-nalevo-razvorot-traektoriya-pdd", "Driver perspective making a left turn across a wide urban intersection in modern Russian city, green traffic light, trajectory road markings, modern cars, realistic photography, 16:9"),
    ("strelka-svetofora-dop-sektsiya-prioritet", "Close POV inside car at intersection looking at modern traffic light showing glowing green right arrow additional section and red main circle, clean city street, photorealistic, 16:9"),
    ("tramvay-i-avtomobil-kogda-tramvay-ustupaet", "Modern stylish red-and-white city tram crossing intersection alongside modern car on asphalt road, Russian city backdrop, daytime realistic automotive photography, 16:9"),
    ("obgon-tihohoda-cherez-sploshnuyu-pdd", "Two-lane rural road in Russia with solid white center line, slow-moving modern agricultural tractor ahead with slow vehicle triangle, car behind maintaining distance, realistic, 16:9"),
    ("pomeha-sprava-odnovremennoe-perestroenie", "Two modern cars driving side-by-side on wide multi-lane Russian city highway changing lanes simultaneously, driver POV through windshield, photorealistic, 16:9"),
    ("proezd-na-zheltyy-signal-svetofora-pdd", "POV approaching city crossroad with glowing yellow traffic light and traffic camera mounted on pole above, wet evening asphalt reflections, photorealistic, 16:9"),
    ("vafelnaya-razmetka-1-26-shtraf-pdd", "Urban intersection with yellow grid waffle road markings on asphalt, cars stopped before the grid box junction, overhead traffic enforcement cameras, photorealistic, 16:9"),
    ("signaly-regulirovshchika-prostymi-slovami-stih", "Russian traffic police officer in modern uniform holding black-and-white striped baton wand directing traffic at busy city crossroad, Slavic officer, realistic photo, 16:9"),
    ("dvizhenie-po-tramvaynym-putyam-pdd", "Car driving along flush tram tracks on urban street in Moscow, tram visible behind, clear road layout, realistic automotive photography, 16:9"),
    ("reversivnoe-dvizhenie-polosa-pdd", "Multi-lane city bridge with overhead reversible lane traffic lights showing green arrow down, double broken line 1.9, driver perspective, 16:9"),
    ("mnemoniki-dlya-pdd-kak-bystro-zapomnit", "Driver inside modern car holding driving exam ticket guide tablet with road signs visible on screen, cozy cabin interior, photorealistic, 16:9"),
    ("razvorot-v-ogranichennom-prostranstve-ekzamen", "White modern training driving school car performing three-point turn between boundary cones on asphalt training ground, realistic photography, 16:9"),
    ("parallelnaya-parkovka-zadnim-hodom-orientiry", "Car reverse parallel parking between two parked vehicles along city curb, view looking into side wing mirror showing curb and bumper, realistic, 16:9"),
    ("zaezd-v-boks-garazh-zadnim-hodom-ekzamen", "Car reversing into marked garage bay parking slot with orange cones on driving exam test ground, view through rearview camera display and side mirror, 16:9"),
    ("mehanika-ili-avtomat-na-chem-sdavat-na-prava", "Close-up of hand on modern manual gearbox stick shift inside sleek car interior, pedals visible below, soft cabin lighting, 16:9"),
    ("tablitsa-shtrafov-za-prevyshenie-skorosti-2026", "Driver view looking at illuminated digital speedometer showing speed, highway stretch with speed limit sign and speed camera gantry ahead, photorealistic, 16:9"),
    ("skidka-na-shtrafy-gibdd-25-protsentov-2026", "Smartphone mounted on car dashboard showing Russian Gosuslugi traffic fine discount notification on screen, car interior background, 16:9"),
    ("vyezd-na-vstrechnuyu-polosu-lishenie-ili-shtraf", "Country asphalt highway with double solid white center line, traffic enforcement camera on overhead mast, driver POV, dramatic lighting, 16:9"),
    ("pravila-dlya-elektrosamokatov-sim-2026", "Modern sleek electric kick scooter riding on dedicated urban bike lane in modern Russian city park boulevard, summer daylight, photorealistic, 16:9"),
    ("nuzhny-li-prava-na-elektrosamokat-2026", "Heavy high-power electric scooter parked beside city street, Russian road signs in background, realistic automotive style, 16:9"),
    ("zimnyaya-rezina-zakon-sroki-shtraf-2026", "Close-up of modern studded winter car tire with aggressive tread pattern on snowy asphalt road, winter cityscape background, sharp details, 16:9"),
    ("aptechka-ognetushitel-znak-v-mashine-2026", "Neat emergency car kit in open car trunk: red first aid kit box, metal fire extinguisher, reflective warning triangle sign, clean trunk, realistic photo, 16:9"),
    ("otkaz-ot-medosvidestvovaniya-nakazanie-2026", "Russian traffic police patrol car with flashing blue-red emergency lights at night roadside checkpoint, officer standing by car window, 16:9"),
    ("shtraf-za-ezdu-bez-prav-2026-tablitsa", "Traffic police inspector checking driver documents through car window on city avenue, daytime realistic photography, Slavic inspector, 16:9"),
    ("ustupit-dorogu-peshehodu-na-zebre-pdd", "Driver POV stopping before marked pedestrian zebra crosswalk with pedestrians crossing safely, blue pedestrian sign 5.19.1, clean city street, 16:9"),
    ("vydelennaya-polosa-dlya-avtobusov-pdd", "City avenue with dedicated bus lane marked with large painted letter 'A' on asphalt and overhead sign 5.14, modern electric bus ahead, 16:9"),
    ("shtrafnye-bally-ekzamen-gibdd-gorod", "Driver test applicant sitting behind steering wheel during driving exam in city, examiner sitting in passenger seat with scoring checklist, realistic photo, 16:9"),
    ("prakticheskiy-ekzamen-gibdd", "Driver POV taking practical driving exam in urban traffic, instructor in passenger seat observing maneuvers, sunny day, realistic photography, 16:9")
]

if __name__ == '__main__':
    print(f"Total prompts to process: {len(PROMPTS)}")
    for idx, (slug, prompt) in enumerate(PROMPTS, 1):
        print(f"[{idx}/29] Submitting prompt for {slug}...")
        js = f"""(function() {{{{
            var promptText = {json.dumps(prompt)};
            var inputEl = document.querySelector('[contenteditable="true"]');
            if (!inputEl) return 'NO_INPUT';
            inputEl.focus();
            inputEl.innerText = promptText;
            inputEl.dispatchEvent(new InputEvent('input', {{ bubbles: true, data: promptText }}));
            
            var btns = Array.from(document.querySelectorAll('button'));
            var submitBtn = btns.find(b => b.innerText && (b.innerText.includes('arrow_forward') || b.innerText.includes('Create')));
            if (submitBtn) {{{{
                submitBtn.click();
                return 'OK';
            }}}}
            return 'NO_SUBMIT_BTN';
        }}}})()"""
        res = run_chrome_js(js).strip()
        print(f"  Result: {res}")
        time.sleep(4)
