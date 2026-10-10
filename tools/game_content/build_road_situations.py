#!/usr/bin/env python3
"""Build assets/game/road-situations.js: straight-road exam questions for the 3D game.

Question text, options, correct index and explanation are copied verbatim from
assets/countries/ru/questions/questions_ab.json. Only the scene layout below is
authored, after viewing each source image (see docs/game/game-scenario-audit.md).

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
cart = lambda z=14, speed=4: V('cart', 'Повозка', 'ahead', z, speed, '#8B5A2B', badge='Повозка')
van = lambda z=8, speed=5, color='#E8EAEC': V('van', 'Фургон', 'ahead', z, speed, color)
sign = lambda code, z, side='right', **kw: dict(code=code, z=z, side=side, **kw)

SCENES = {
    # --- speed: the answer becomes the enforced limit after the sign is passed;
    # endSign at the end of the stretch returns the built-up-area limit (60).
    '1_16': dict(kind='speed', signs=[sign('5.21', 12)], limitKmH=20, endSign='5.22', zoneLength=48,
                 note='Sign 5.21 (residential zone): 20 km/h applies beyond the sign.'),
    '6_10': dict(kind='speed', motorway=True, signs=[sign('5.1', 12)], limitKmH=110, endSign='5.2',
                 note='Sign 5.1 (motorway): 110 km/h for a car; separate carriageways are rendered.'),
    '13_10': dict(kind='speed', signs=[sign('5.25', 12)], limitKmH=90, endSign='5.26',
                  note='Sign 5.25 (blue settlement name): rules of a built-up area do not apply, 90 km/h.'),
    '16_10': dict(kind='speed', outsideSettlement=True, approachLimitKmH=70, signs=[sign('5.24.1', -32), sign('3.24', -22, speedValue=70), sign('3.25', 12, speedValue=70)], limitKmH=90, endSign='5.23.1',
                  note='Sign 3.25 ends the 70 limit outside a built-up area: 90 km/h.'),
    # --- overtaking: overtake = true | false | 'before_intersection' | 'after_crosswalk'
    '2_11': dict(kind='overtake', overtake=False, junction=dict(z=24, priority='equal'),
                 vehicles=[moto(14, 5), V('van', 'Фургон', 'right', 24, 6, '#F2C230', x=-10)],
                 note='Equal junction: motorcycle ahead and bus approaching from the right; both player and motorcycle yield.'),
    '4_11': dict(kind='overtake', overtake=True, junction=dict(z=24, priority='main'), signs=[sign('2.1', 8)], vehicles=[moto()],
                 note='Main road (2.1) through the junction ahead: overtaking a motorcycle allowed.'),
    '5_11': dict(kind='overtake', overtake=True, junction=dict(z=60, priority='main'), signs=[sign('2.3.1', 8)], vehicles=[truck()],
                 note='Sign 2.3.1 warns of a secondary-road crossing ahead: overtaking on the main road is allowed.'),
    '9_5': dict(kind='overtake', overtake=True, marking='double_dashed_right', vehicles=[tractor()],
                note='Marking 1.11 with the broken line on the player\'s side: crossing allowed.'),
    '16_11': dict(kind='overtake', overtake=True, junction=dict(z=24, priority='main'), signs=[sign('2.1', 8)], vehicles=[dict(tractor(),color='#2F6FD6',paint='#2F6FD6')],
                  note='Tractor ahead, main road (2.1): overtaking allowed at the junction.'),
    '17_5': dict(kind='overtake', overtake=False, marking='double_solid_right', vehicles=[tractor()],
                 note='Marking 1.11 with the solid line on the player\'s side: crossing prohibited.'),
    '18_11': dict(kind='overtake', overtake=False,
                  vehicles=[truck(-40, 14, 'Грузовик Б', '#C9C2B2', badge='Б', blinker='left', maneuver='overtake', joinsAtQuestion=True),
                            truck(24, 5, 'Грузовик А', '#B8A98A', badge='А')],
                  note='Truck Б comes up behind the player as the question starts and signals left: it has begun overtaking, so the player may not (11.2).'),
    '20_11': dict(kind='overtake', overtake=False, signs=[sign('3.21', 8)],
                  vehicles=[truck(14, 8, color='#E05A4E', blinker='left', maneuver='overtake', alreadyOvertaking=True), truck(36, 5, color='#9AA0A6')],
                  note='Truck ahead signals left: prohibited regardless of the 3.21 sign further on.'),
    '24_11': dict(kind='overtake', overtake=False, signs=[sign('3.20', 8)], vehicles=[truck(14, 5, color='#3E8E5E')],
                  note='Sign 3.20 "No overtaking": prohibited.'),
    '29_3': dict(kind='overtake', overtake=True, signs=[sign('3.20', 8)], vehicles=[moto(14, 4)],
                 note='Sign 3.20 still allows overtaking a two-wheeled motorcycle without a sidecar.'),
    '29_11': dict(kind='overtake', overtake=False, junction=dict(z=24, priority='equal'), vehicles=[truck(14, 5, color='#E8E8E8')],
                  note='Equal unregulated junction ahead, no priority signs: overtaking prohibited (11.4).'),
    '38_11': dict(kind='overtake', overtake='before_intersection', junction=dict(z=208, priority='secondary'), signs=[sign('2.4', 8, plate='200 м')],
                  vehicles=[truck(14, 5, color='#D0D0D0')],
                  note='2.4 with plate 8.1.1 (200 m): overtaking allowed only if completed before the junction.'),
    '13_11': dict(kind='overtake', overtake='after_crosswalk', crosswalkZ=10,
                  markingBefore='double_solid_right', markingAfter='double_dashed_right',
                  signs=[sign('5.19.1', 10), sign('5.19.2', 10, side='left')],
                  vehicles=[moto(18, 4), truck(28, 4, color='#E39AA8'), V('car', 'Автомобиль', 'ahead', 38, 4, '#7A8A99')],
                  note='1.11 with the solid line on the player\'s side up to the crossing, the broken line on it after: '
                       'all three may be overtaken after the pedestrian crossing, not before it or on it.'),
    '34_19': dict(kind='overtake', overtake=True, signs=[sign('3.21', 8)], vehicles=[truck(14, 5, color='#C9C2B2')],
                  note='End of the no-overtaking zone (3.21): lane change first, then closing in.'),
    # --- railway crossings (11.4: no overtaking on it or within 100 m before it;
    # 15.3: no going round vehicles waiting at a closed one). railway.z is the
    # track, `after` how far the question's stretch runs past it.
    '10_11': dict(kind='overtake', overtake='before_crossing', outsideSettlement=True, railway=dict(z=210, after=30),
                  signs=[sign('1.2', 10, plateSign='1.4.1'), sign('1.4.2', 80), sign('1.2', 150, plateSign='1.4.3')],
                  vehicles=[tractor(14, 5)],
                  note='1.2 with 1.4.1 outside a built-up area: the crossing is 150-300 m on (here 200 m). The tractor may be '
                       'overtaken if the manoeuvre is over 100 m before the crossing; 1.4.2 and the repeated 1.2 + 1.4.3 follow.'),
    '17_11': dict(kind='overtake', overtake='after_crossing', railway=dict(z=78, after=60),
                  signs=[sign('1.2', 8)], vehicles=[truck(14, 5, color='#A3A7AA')],
                  note='In a built-up area 1.2 stands 50-100 m before the crossing (here 70 m): the truck ahead is already '
                       'inside the 100 m zone, so overtaking may start only past the crossing. The photo shows a truck '
                       '(the explanation calls it a tractor).'),
    '21_11': dict(kind='overtake', overtake='after_crossing', railway=dict(z=10, after=70,signalsUnlit=True,whiteSignal=False),
                  vehicles=[van(8, 5)],
                  note='The van is on the crossing; overtaking may start right after its boundary, the signal posts '
                       'with 1.3.1 just past the track.'),
    '2_16': dict(kind='railway', outsideSettlement=True, railway=dict(z=20, barrier=True, train=True, after=40),
                 signs=[sign('1.1', 3, plateSign='1.4.3')],
                 vehicles=[truck(9, 8, color='#4F7FB8', waitsAtCrossing=True)],
                 note='Closed barrier with the red signals on: the truck waits at the boom and may not be gone round '
                      'through the oncoming lane (15.3). A train passes, the booms rise and the truck moves off.'),
    # --- equal junction ahead (1.6 outside a built-up area: 150-300 m)
    '12_11': dict(kind='overtake', overtake='before_intersection', outsideSettlement=True,
                  junction=dict(z=158, priority='equal'), zoneLength=170, signs=[sign('1.6', 8)], vehicles=[cart(14, 5)],
                  note='1.6: an equal junction 150 m on. The horse-drawn cart may be overtaken if the manoeuvre is over '
                       'before the junction; overtaking on it is prohibited (11.4).'),
    # --- detour: sign 4.2.2 prevails over the solid centre line
    '35_5': dict(kind='detour', obstacleZ=24, obstacleX=-1.2, obstacleWidth=2.4,
                 marking='solid', signs=[sign('1.25', 12)],
                 # Both alternatives from the source picture, equally styled:
                 # A crosses the centre line to the left, B stays on the right.
                 trajectories=[
                     dict(label='А', points=[[-1.8, 5], [-1.8, 9], [0.5, 15], [1.8, 20], [1.8, 29]], labelPosition=[1.8, 31]),
                     dict(label='Б', points=[[-1.8, 5], [-1.8, 9], [-3.35, 15], [-3.35, 24], [-3.35, 29]], labelPosition=[-3.35, 31]),
                 ],
                 note='Road works barrier with 4.2.2 in the player\'s lane and a solid centre line: signs take precedence '
                      'over markings, so the way round is on the left (trajectory A). Both A and Б from the source '
                      'are drawn; the barrier leaves the pictured gap on the right for alternative Б.'),
}

from first_batch import ROADS
SCENES.update(ROADS)
from second_batch import ROADS as SECOND_ROADS
SCENES.update(SECOND_ROADS)

def rule(comment):
    m = re.search(r'[Пп]ункт[ыа]?\s*([\d.]+)', comment or '')
    return 'п. ' + m.group(1).rstrip('.') if m else ''

SCENES['29_3'].update(outsideSettlement=True,unmarkedRoad=True)
SCENES['2_16']['railway']['z']=30
out = []
for key, scene in SCENES.items():
    bend = scene.get('roadCurve')
    if bend:
        # Curves currently support rural sign questions with oncoming traffic.
        # Reject incompatible scene mechanics rather than draw a false layout.
        assert scene.get('outsideSettlement') and scene['kind'] in ('speed', 'observe'), key
        assert set(bend) == {'from', 'to', 'offset'}, key
        assert all(isinstance(v, (int, float)) and abs(v) < 10000 for v in bend.values()), key
        span = bend['to'] - bend['from']
        assert bend['from'] >= 0 and span >= 80 and bend['to'] <= scene['zoneLength'] - 10, key
        assert 4.1 * abs(bend['offset']) / span <= .4, key
        assert all(v['lane'] == 'oncoming' for v in scene.get('vehicles', [])), key
        assert not any(scene.get(k) for k in ('motorway', 'wideCity', 'junction', 'junctionZ', 'crosswalkZ', 'trajectories', 'markingBefore', 'markingAfter', 'endJunction', 'railway', 'humpZ', 'marking', 'shoulderWorks', 'gravelZ', 'endJunctionZ')), key
    t, i = map(int, key.split('_'))
    qq = q['tickets'][t - 1]['questions'][i - 1]
    legend = [{"label": "Вы", "color": "#ED4621"}] + [
        {"label": v['name'], "color": v['color']} for v in scene.get('vehicles', [])]
    out.append({
        "id": f"road_{key}", "ticket": f"Билет {t} · Вопрос {i}",
        "sourceQuestionId": qq['id'], "country": "ru", "category": "ab",
        "type": 'road_' + scene['kind'], "title": qq['question'], "explanation": qq['comment'],
        "pddRule": rule(qq['comment']), "options": [a['text'] for a in qq['answers']],
        "correctAnswerIndex": [k for k, a in enumerate(qq['answers']) if a['correct']][0],
        "legend": legend, "sourceImage": qq['image'],
        "scene": {k: v for k, v in scene.items() if k != 'note'}, "note": scene['note'],
    })
target = ROOT / 'assets/game/road-situations.js'
target.write_text('// Road exam situations. Generated by tools/game_content/build_road_situations.py\n'
                  '// from questions_ab.json (verbatim text) + authored scene layouts — do not edit by hand.\n'
                  'window.PDD_ROAD_SITUATIONS = ' + json.dumps(out, ensure_ascii=False, indent=1) + ';\n')
print(len(out), 'road situations ->', target)
