#!/usr/bin/env python3
"""Build assets/game/road-situations.js: straight-road exam questions for the 3D game.

Question text, options, correct index and explanation are copied verbatim from
assets/countries/ru/questions/questions_ab.json. Only the scene layout below is
authored, after viewing each source image (see docs/game-scenario-audit.md).

Scene coordinates are world units relative to the point where the player stops
for the question (z = 0 there, positive = ahead). x follows the renderer:
driver's right is negative. Vehicle lanes: 'ahead' = player's lane, moving the
same way; 'oncoming' = opposite lane, moving towards the player.
"""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
q = json.loads((ROOT / 'assets/countries/ru/questions/questions_ab.json').read_text())

def V(type, name, lane, z, speed, color, **kw):
    d = {"type": type, "name": name, "lane": lane, "z": z, "speed": speed, "color": color}
    d.update(kw); return d
moto = lambda z=14, speed=4, **kw: V('motorcycle', 'Мотоцикл', 'ahead', z, speed, '#8B5CF6', **kw)
truck = lambda z=14, speed=4, name='Грузовик', color='#FFA53C', **kw: V('truck', name, 'ahead', z, speed, color, **kw)
tractor = lambda z=14, speed=3: V('tractor', 'Трактор', 'ahead', z, speed, '#F2B233', badge='Трактор')
oncoming = lambda z=130, speed=12: V('car', 'Встречный', 'oncoming', z, speed, '#2BC280')
sign = lambda code, z, side='right', **kw: dict(code=code, z=z, side=side, **kw)

SCENES = {
    # --- speed: the answer becomes the enforced limit after the sign is passed;
    # endSign at the end of the stretch returns the built-up-area limit (60).
    '1_16': dict(kind='speed', signs=[sign('5.21', 12)], limitKmH=20, endSign='5.22', zoneLength=48,
                 note='Sign 5.21 (residential zone): 20 km/h applies beyond the sign.'),
    '6_10': dict(kind='speed', signs=[sign('5.1', 12)], limitKmH=110, endSign='5.2',
                 note='Sign 5.1 (motorway): 110 km/h for a car; the two-lane road is schematic.'),
    '13_10': dict(kind='speed', signs=[sign('5.25', 12)], limitKmH=90, endSign='5.26',
                  note='Sign 5.25 (blue settlement name): rules of a built-up area do not apply, 90 km/h.'),
    '16_10': dict(kind='speed', signs=[sign('3.25', 12)], limitKmH=90, endSign='5.23.1',
                  note='Sign 3.25 ends the 70 limit outside a built-up area: 90 km/h.'),
    # --- overtaking: overtake = true | false | 'before_intersection' | 'after_crosswalk'
    '2_11': dict(kind='overtake', overtake=False, vehicles=[moto(14, 7, blinker='left', maneuver='turn_left_at_junction')],
                 note='Motorcycle ahead signals a left turn before the junction: overtaking prohibited (11.2).'),
    '4_11': dict(kind='overtake', overtake=True, signs=[sign('2.1', 60)], vehicles=[moto()],
                 note='Main road (2.1) through the junction ahead: overtaking a motorcycle allowed.'),
    '5_11': dict(kind='overtake', overtake=True, signs=[sign('1.6', 10)], vehicles=[truck()],
                 note='Sign 1.6 warns of an equal junction far ahead; overtaking on this stretch is allowed.'),
    '9_5': dict(kind='overtake', overtake=True, marking='double_dashed_right', vehicles=[tractor()],
                note='Marking 1.11 with the broken line on the player\'s side: crossing allowed.'),
    '16_11': dict(kind='overtake', overtake=True, signs=[sign('2.1', 40)], vehicles=[tractor()],
                  note='Tractor ahead, main road (2.1): overtaking allowed at the junction.'),
    '17_5': dict(kind='overtake', overtake=False, marking='double_solid_right', vehicles=[tractor()],
                 note='Marking 1.11 with the solid line on the player\'s side: crossing prohibited.'),
    '18_11': dict(kind='overtake', overtake=False,
                  vehicles=[truck(14, 8, 'Грузовик Б', '#C9C2B2', badge='Б', blinker='left', maneuver='overtake'),
                            truck(36, 5, 'Грузовик А', '#B8A98A', badge='А'), oncoming(260)],
                  note='Truck Б ahead has already started overtaking (left signal): prohibited (11.2).'),
    '20_11': dict(kind='overtake', overtake=False, signs=[sign('3.21', 30)],
                  vehicles=[truck(14, 8, color='#E05A4E', blinker='left', maneuver='overtake'), truck(36, 5, color='#9AA0A6')],
                  note='Truck ahead signals left: prohibited regardless of the 3.21 sign further on.'),
    '24_11': dict(kind='overtake', overtake=False, signs=[sign('3.20', 8)], vehicles=[truck(14, 5, color='#3E8E5E')],
                  note='Sign 3.20 "No overtaking": prohibited.'),
    '29_3': dict(kind='overtake', overtake=True, signs=[sign('3.20', 8)], vehicles=[moto(14, 4)],
                 note='Sign 3.20 still allows overtaking a two-wheeled motorcycle without a sidecar.'),
    '29_11': dict(kind='overtake', overtake=False, vehicles=[truck(14, 5, color='#E8E8E8')],
                  note='Equal unregulated junction ahead, no priority signs: overtaking prohibited (11.4).'),
    '38_11': dict(kind='overtake', overtake='before_intersection', signs=[sign('2.4', 8, plate='200 м')],
                  vehicles=[truck(14, 5, color='#D0D0D0')],
                  note='2.4 with plate 8.1.1 (200 m): overtaking allowed only if completed before the junction.'),
    '13_11': dict(kind='overtake', overtake='after_crosswalk', crosswalkZ=10,
                  signs=[sign('5.19.1', 10), sign('5.19.2', 10, side='left')],
                  vehicles=[moto(18, 4), truck(28, 4, color='#E39AA8'), V('car', 'Автомобиль', 'ahead', 38, 4, '#7A8A99')],
                  note='All three may be overtaken after the pedestrian crossing; not on it.'),
    '34_19': dict(kind='overtake', overtake=True, signs=[sign('3.21', 8)], vehicles=[truck(14, 5, color='#C9C2B2')],
                  note='End of the no-overtaking zone (3.21): lane change first, then closing in.'),
}

def rule(comment):
    m = re.search(r'[Пп]ункт[ыа]?\s*([\d.]+)', comment or '')
    return 'п. ' + m.group(1).rstrip('.') if m else ''

out = []
for key, scene in SCENES.items():
    t, i = map(int, key.split('_'))
    qq = q['tickets'][t - 1]['questions'][i - 1]
    legend = [{"label": "Вы", "color": "#ED4621"}] + [
        {"label": v['name'], "color": v['color']} for v in scene.get('vehicles', [])]
    out.append({
        "id": f"road_{key}", "ticket": f"Билет {t} · Вопрос {i}",
        "type": 'road_' + scene['kind'], "title": qq['question'], "explanation": qq['comment'],
        "pddRule": rule(qq['comment']), "options": [a['text'] for a in qq['answers']],
        "correctAnswerIndex": [k for k, a in enumerate(qq['answers']) if a['correct']][0],
        "legend": legend, "sourceImage": qq['image'],
        "scene": {k: v for k, v in scene.items() if k != 'note'}, "note": scene['note'],
    })
target = ROOT / 'assets/game/road-situations.js'
target.write_text('// Straight-road exam situations. Generated by tools/game_content/build_road_situations.py\n'
                  '// from questions_ab.json (verbatim text) + authored scene layouts — do not edit by hand.\n'
                  'window.PDD_ROAD_SITUATIONS = ' + json.dumps(out, ensure_ascii=False, indent=1) + ';\n')
print(len(out), 'road situations ->', target)
