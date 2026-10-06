"""Trajectory/lane package. Geometry reviewed against the RU A/B photographs.

Paths use world X (right is negative); displayed trajectories use factory X.
Text and answers are always loaded by the generators from the ticket database.
"""
from first_batch import J, actor

def trajectory(label, points, **kw):
    return dict(label=label, points=[[-x,z] for x,z in points], **kw)

def scene(action, legal, alternatives=(), allowed=None, **layout):
    d=J(action, **layout)
    d['layout']['trajectories']=[trajectory(label,path) for label,path in alternatives]
    d['route'].update(paths={action:legal}, allowedManeuvers=allowed or [action],
                      pathRules=dict(paths=[dict(maneuver=action,points=legal)], tolerance=1.45, turnOnly=action in ['left','right']))
    return d

RIGHT=[[-1.8,-12],[-1.8,-6],[-4.8,-1.8],[-16,-1.8],[-26,-1.8]]
LEFT=[[-1.8,-12],[-1.8,-2],[2,1.8],[16,1.8],[26,1.8]]
UTURN=[[-1.8,-12],[-2.6,-3],[-2.6,1],[0,3.6],[2.6,1],[2.6,-3],[1.8,-12],[1.8,-26]]
WIDE_RIGHT=[[-1.8,-14],[-1.8,-9],[-5,-5.4],[-15,-5.4],[-26,-2.8],[-36,-1.8]]
INNER_RIGHT=[[-1.8,-14],[-1.8,-7],[-5,-1.8],[-16,-1.8],[-26,-1.1],[-36,-1.8]]
TRAM_LEFT=[[-5.4,-14],[-1.8,-9],[-1.8,-2],[2,1.8],[14,1.8],[26,1.0],[36,1.8]]
CAR_LEFT=[[-5.4,-14],[-5.4,-5],[-4,-1],[2,5.4],[14,5.4],[26,3.0],[36,1.8]]
DIVIDED_UTURN=[[-1.8,-17],[-1.8,-2],[-2.6,2],[-2.6,5.6],[0,8],[2.6,5.6],[2.6,2],[1.8,-12],[1.8,-26]]
SHORT_UTURN=[[-1.8,-17],[-2.6,-8],[0,-5.6],[2.6,-8],[1.8,-26]]

JUNCTIONS={
 '1_9':scene('uturn',UTURN,[('А',UTURN),('Б',[[-1.8,-12],[-2.6,-4],[0,-1.8],[2.6,-4],[1.8,-26]])],
             mainMedian=True,questionStop=-16),
 '3_8':scene('right',WIDE_RIGHT,[('А',WIDE_RIGHT),('Б',INNER_RIGHT)],crossWidth=16.8,signs=[dict(code='4.1.2')]),
 '3_9':scene('straight',[[-5.4,-14],[-5.4,0],[-5.4,12],[-2.8,22],[-1.8,30]],
             mainWidth=16.8,playerStartX=-5.4,mainCentre='double',questionStop=-16),
 '7_5':J('left',junctionLaneMarking=True,allowedDirections=['straight','left','right','uturn']),
 '8_4':J('right',signs=[dict(code='6.8.2')],deadEnd='right'),
 '8_8':scene('left',CAR_LEFT,[('А',TRAM_LEFT),('Б',CAR_LEFT)],mainWidth=21.6,crossWidth=16.8,playerStartX=-5.4,mainLaneDividers=[3.6,7.2],
             tramTracks=True,laneSign='left_straight_right',questionStop=-16,
             actorsConfig=[actor('tram','tram','opposite','Трамвай','#FFA53C',position=[1.8,0,22],rotationY=3.141592653589793)]),
 '11_2':scene('straight',[[-1.8,-14],[-1.8,0],[-1.8,28]],
              [('А',[[-1.8,-14],[-1.8,-5],[-5,-1.8],[-20,-1.8]]),('Б',[[-1.8,-14],[-1.8,18]]),('В',UTURN)],
              mainWidth=16.8,signs=[dict(code='4.1.4')],questionStop=-16,asymmetricCentre=True),
 '11_8':scene('right',WIDE_RIGHT,[('А',WIDE_RIGHT),('Б',INNER_RIGHT)],crossWidth=16.8),
 '12_5':scene('uturn',UTURN,[('А',[[16,-1.8],[5,-1.8],[1.8,3],[1.8,19]]),('Б',UTURN)],
              geometry='courtyard_left',asymmetricCentre=True,questionStop=-16,
              actorsConfig=[actor('yard_car','car','cross_left','Автомобиль','#E8EAEC',position=[-14,0,-1.8],rotationY=-1.5707963267948966,stationary=True)]),
 '16_2':scene('right',[[-1.8,-12],[-1.8,0],[-1.8,10],[-4.5,14.8],[-9,14.8],[-26,14.8]],signs=[dict(code='4.1.1',z=7)],yardAfter=16,yardSides=[-1,1],questionStop=-13),
 '17_8':scene('straight',[[-1.8,-14],[-1.8,0],[-1.8,28]],mainWidth=16.8,trafficLights=dict(state='red',arrow='right'),
              redWait=3,requiredStop=-8.5,questionStop=-16),
 '18_9':scene('uturn',UTURN,[('А',UTURN),('Б',[[-1.8,-18],[-2.5,-14],[0,-11],[2.5,-14],[1.8,-24]])],
              signs=[dict(code='4.1.1',z=-22)],questionStop=-24),
 '19_8':scene('left',TRAM_LEFT,[('А',TRAM_LEFT),('Б',CAR_LEFT)],mainWidth=21.6,crossWidth=16.8,playerStartX=-5.4,mainLaneDividers=[3.6,7.2],
              tramTracks=True,questionStop=-16,
              actorsConfig=[actor('tram','tram','opposite','Трамвай','#FFA53C',position=[1.8,0,22],rotationY=3.141592653589793)]),
 '20_2':scene('left',[[-1.8,-12],[-1.8,0],[-1.8,12],[-1.8,16],[1.8,19.2],[8,19.2],[26,19.2]],
              signs=[dict(code='4.1.1')],yardAfter=18),
 '20_6':scene('right',[[-5.4,-14],[-5.4,-7],[-7,-1.8],[-26,-1.8]],mainWidth=16.8,playerStartX=-5.4,
              trafficLights=dict(state='red',arrow='right'),laneSign='left_right',questionStop=-16),
 '22_8':scene('left',LEFT,[('А',[[-1.8,-12],[-2,-4],[4,-1.8],[26,-1.8]]),('Б',LEFT)]),
 '24_9':scene('uturn',UTURN,[('А',UTURN),('Б',[[-1.8,-18],[-2.6,-12],[0,-9],[2.6,-12],[1.8,-24]])],
              oneWay='to_left',signs=[dict(code='5.7.2'),dict(code='5.19.1',z=-12),dict(code='5.19.2',z=-12,x=-5.4)],
              unmarkedPedestrianCrossing=-12,questionStop=-23),
 '27_9':scene('uturn',DIVIDED_UTURN,[('А',DIVIDED_UTURN),('Б',SHORT_UTURN)],
              geometry='divided_road',medianSignals=False,signs=[dict(code='4.1.1',z=-14)],questionStop=-19),
 '28_2':scene('right',[[-1.8,-17],[-1.8,-10],[-5,-8.4],[-15,-8.4],[-26,-3.8],[-36,-1.8]],
              [('А',[[-1.8,-17],[-1.8,-10],[-5,-8.4],[-18,-8.4]]),('Б',[[-1.8,-17],[-1.8,0],[-5,4.2],[-18,4.2]])],
              geometry='divided_road',medianSignals=False,signs=[dict(code='4.1.2',z=-14)],questionStop=-19),
 '33_8':scene('right',INNER_RIGHT,crossWidth=16.8,
              actorsConfig=[actor('parked','car','cross_right','Автомобиль','#AF4D42',position=[9,0,-7.1],rotationY=-1.5707963267948966,stationary=True,hazard=True)]),
}

for key in ['8_8','19_8']:
    JUNCTIONS[key]['route']['yieldTo']=['tram']
    for item in JUNCTIONS[key]['layout']['trajectories']:
        uses_tram=item['label']=='А'
        # Same geometry labels A as the tram path in BOTH source pictures.
        item['labelPosition']=[.2 if uses_tram else 7.0,-7]

# Questions with several legal exits accept all of them. Path validation is
# applied only to the manoeuvres actually constrained by the source picture.
JUNCTIONS['7_5']['route']['allowedManeuvers']=['straight','left','right','uturn']
JUNCTIONS['8_4']['route']['allowedManeuvers']=['straight','left','right','uturn']
JUNCTIONS['12_5']['route']['allowedManeuvers']=['straight','uturn']
JUNCTIONS['16_2']['route']['allowedManeuvers']=['straight','right']
JUNCTIONS['20_2']['route']['exitOffsets']={'left':18}
JUNCTIONS['20_2']['route']['allowedManeuvers']=['straight','left']
JUNCTIONS['20_2']['route']['pathRules']['onlyManeuvers']=['left']
JUNCTIONS['20_2']['route']['pathRules']['turnOnly']=False
JUNCTIONS['12_5']['route']['pathRules']['onlyManeuvers']=['uturn']
JUNCTIONS['3_9']['layout']['trajectories']=[trajectory(None,[[-5.4,-14],[-5.4,-5],[-2,1],[2,1],[5.4,-5],[5.4,-24]])]
JUNCTIONS['17_8']['layout']['trajectories']=[trajectory(None,[[-1.8,-14],[-1.8,-5],[-6,-1.8],[-22,-1.8]])]
for key in ['20_2','33_8']:
    d=JUNCTIONS[key];d['layout']['trajectories']=[trajectory(None,d['route']['paths'][d['route']['maneuver']])]

# A traffic rule is distinct from the demonstration exit. Also accept lawful
# alternatives, while keeping the source-specific entry/turn corridors.
def allow_routes(key, paths):
    r=JUNCTIONS[key]['route'];r['paths'].update(paths)
    r['allowedManeuvers']=list(r['paths'])
    r['pathRules']['paths']=[dict(maneuver=a,points=p) for a,p in r['paths'].items()]

STRAIGHT=[[-1.8,-14],[-1.8,0],[-1.8,28]]
OUTER_STRAIGHT=[[-5.4,-14],[-5.4,0],[-5.4,12],[-2.8,22],[-1.8,30]]
OUTER_RIGHT=[[-5.4,-14],[-5.4,-7],[-7,-1.8],[-26,-1.8]]
CAR_UTURN=[[-5.4,-14],[-5.4,-5],[-4,-1],[-2,3.6],[0,5],[2,3.6],[4,-1],[5.4,-5],[5.4,-12],[1.8,-26]]
TRAM_UTURN=[[-5.4,-14],[-1.8,-9],[-2.6,-3],[-2.6,1],[0,3.6],[2.6,1],[4,-2],[5.4,-5],[5.4,-12],[1.8,-26]]
for key in ['1_9','18_9','11_8']:
    allow_routes(key,dict(straight=STRAIGHT,left=LEFT,right=RIGHT if key!='11_8' else WIDE_RIGHT,uturn=UTURN))
# The divider in 1.9 requires the turn to use the far side of the crossing.
# Keep each corridor; the short near-side U-turn remains outside them.
JUNCTIONS['11_8']['route']['pathRules']['paths'].append(dict(maneuver='left',points=[[-1.8,-14],[-1.8,-1],[0,3],[4,5.4],[14,5.4],[26,2.8],[36,1.8]]))
allow_routes('3_9',dict(right=OUTER_RIGHT))
allow_routes('17_8',dict(left=LEFT,uturn=UTURN))
allow_routes('24_9',dict(straight=STRAIGHT,left=LEFT))
allow_routes('8_8',dict(straight=OUTER_STRAIGHT,uturn=CAR_UTURN))
allow_routes('19_8',dict(straight=OUTER_STRAIGHT,uturn=TRAM_UTURN))
# Two approach lanes, as photographed; the rightmost exit lane is occupied.
EXCEPTION_RIGHT=[[-5.4,-14],[-5.4,-7],[-7,-1.8],[-16,-1.8],[-26,-1.1],[-36,-1.8]]
d=JUNCTIONS['33_8'];d['layout'].update(mainWidth=16.8,playerStartX=-5.4,questionStop=-16)
d['layout']['trajectories']=[trajectory(None,EXCEPTION_RIGHT)]
d['route']['paths']['right']=EXCEPTION_RIGHT
allow_routes('33_8',dict(straight=OUTER_STRAIGHT))

ROADS={
 '9_9':dict(kind='observe',signs=[dict(code='5.16',z=17,side='left')],forbidUturn=[6,29],
             trajectories=[dict(points=[[-1.8,6],[-2.6,13],[0,16],[2.6,13],[1.8,5]])],
             note='Bus stop on the opposite side: U-turn forbidden across the stop area; no invented yellow marking.'),
 '26_9':dict(kind='observe',signs=[dict(code='5.16',z=17)],forbidUturn=[6,29],busStopMarking=True,
              trajectories=[dict(points=[[-1.8,6],[-2.6,13],[0,16],[2.6,13],[1.8,5]])],
              note='Marked bus stop on the right; no U-turn through the stop area.'),
 '31_5':dict(kind='observe',wideCity=True,solidDividers=[dict(x=0,fromZ=-34,toZ=115)],
              note='Text-only source. Illustrative double solid centre on a four-lane road; crossing is forbidden in either direction.'),
 '32_9':dict(kind='observe',signs=[dict(code='5.5',z=10)],oneWayRoad=True,
              note='Two lanes in one direction, no centre line separating opposite flows; U-turn creates oncoming traffic.'),
 '32_5':dict(kind='observe',wideCity=True,playerLane='left',approachDivider=True,
              vehicles=[dict(type='truck',name='Грузовик',lane='ahead',z=17,speed=5,color='#C9C2B2')],
              solidDividers=[dict(x=-4.2,fromZ=34,toZ=100)],
              note='Same-direction divider: 1.6 uses 6 m strokes / 2 m gaps, then solid 1.1; centre remains double solid.'),
}
assert len(JUNCTIONS)+len(ROADS)==25

JUNCTIONS['16_2']['route']['exitOffsets']={'right':16}
JUNCTIONS['16_2']['route']['pathRules']['turnOnly']=False
for key in ['18_9','24_9']:
 for t in JUNCTIONS[key]['layout']['trajectories']:
  t['labelPosition']=[-4.5,4.2 if t['label']=='А' else -10]
JUNCTIONS['24_9']['layout']['signs'][0]['z']=-18

JUNCTIONS['16_2']['route']['pathRules']['onlyManeuvers']=['right']

JUNCTIONS['27_9']['layout']['noRight']=True
for t in JUNCTIONS['27_9']['layout']['trajectories']:
 t['labelPosition']=[-4.8,7.7 if t['label']=='А' else -7]

# Drawn U-turns are clean half circles between the two lanes: A in the far
# carriageway (second crossing, past the island), B in the near one. Each
# stops shortly after the turn so the two alternatives stay apart.
import math
def drawn_uturn(turn_z, end_z, start_z=-17):
 arc=[[-1.8*math.cos(a),turn_z+1.8*math.sin(a)] for a in [i*math.pi/12 for i in range(13)]]
 return [[-1.8,start_z],[-1.8,turn_z-2]]+arc+[[1.8,end_z]]
for t in JUNCTIONS['27_9']['layout']['trajectories']:
 t['points']=trajectory(None,drawn_uturn(5.4,2.6) if t['label']=='А' else drawn_uturn(-8.6,-11.8))['points']
 t['labelPosition']=[-4.6,7.2 if t['label']=='А' else -7.2]

# Final review: drawing annotations never extend into the camera's far horizon.
for key in ['3_8','11_8','8_8','19_8']:
 for t in JUNCTIONS[key]['layout']['trajectories']:t['points']=t['points'][:5 if key in ['8_8','19_8'] else 4]
JUNCTIONS['7_5']['layout'].update(hideGuide=True,mainWidth=16.8,mainLaneDividers=[3.6],junctionLaneMarkingPaths=[
 [[-5.4,-9],[-5.4,-4],[0,1.8],[14,1.8]],
 [[-1.8,-9],[-1.8,-3],[2,5.4],[14,5.4]]])
JUNCTIONS['12_5']['layout'].update(mainWidth=16.8,mainLaneDividers=[3.6],openEntrance=True,clearYard=True)
JUNCTIONS['12_5']['layout']['actorsConfig'][0].update(position=[-10.7,0,-1.8])
wide_uturn=[[-1.8,-12],[-1.8,-4],[-1,0],[2,3.6],[5.4,0],[5.4,-9],[3.8,-18],[1.8,-26]]
JUNCTIONS['12_5']['route']['paths']['uturn']=wide_uturn
JUNCTIONS['12_5']['route']['pathRules']['paths'][0]['points']=wide_uturn
JUNCTIONS['12_5']['layout']['trajectories']=[trajectory('А',[[10.7,-1.8],[5,-1.8],[-3,2],[-5.4,12]]),trajectory('Б',wide_uturn[:6])]
JUNCTIONS['1_9']['layout'].update(geometry='divided_main',mainWidth=20.8,mainLaneDividers=[6.2],playerStartX=-4.1,questionStop=-18,mainMedian=False)
# A (as on the source picture) ends in the far, outer lane of the opposite
# carriageway (8.3), then eases into the ordinary lane as the road narrows.
long_uturn=[[-4.1,-14],[-4.1,-5],[-3.6,1.5],[0,4.6],[4.6,3.4],[7.6,0],[8.3,-5],[8.3,-10],[6.6,-16],[3.6,-21.5],[1.8,-26]]
short_uturn=[[-4.1,-14],[-4.1,-6],[-2,-1.8],[2,-1.8],[4.1,-6]]
JUNCTIONS['1_9']['route'].update(paths={'uturn':long_uturn,'straight':[[-4.1,-14],[-4.1,0],[-4.1,12],[-3,21],[-1.8,28]],'left':[[-4.1,-14],[-4.1,-2],[2,1.8],[16,1.8],[26,1.8]],'right':[[-4.1,-14],[-4.1,-6],[-8,-1.8],[-18,-1.8],[-36,-1.8]]})
JUNCTIONS['1_9']['route']['pathRules']['paths'][0]['points']=long_uturn
JUNCTIONS['1_9']['layout']['trajectories']=[trajectory('А',long_uturn[:8],labelPosition=[-5,4.6]),trajectory('Б',short_uturn,labelPosition=[-5,-3])]
JUNCTIONS['28_2']['layout'].update(geometry='three_carriageways',crossWidth=29.2,questionStop=-23)
path28=[[-1.8,-22],[-1.8,-18],[-5,-12.5],[-18,-12.5],[-26,-6],[-36,-1.8]]
JUNCTIONS['28_2']['route']['paths']['right']=path28
JUNCTIONS['28_2']['route']['pathRules']['paths'][0]['points']=path28
# B ends in the right-hand lane of the middle carriageway (islands at ±5.23,
# 2.2 m wide; carriageways 8.27 m), not on its centre line.
JUNCTIONS['28_2']['layout']['trajectories']=[trajectory('А',path28[:4],labelPosition=[12,-14.6]),trajectory('Б',[[-1.8,-22],[-1.8,-8],[-5.5,-2.07],[-18,-2.07]],labelPosition=[12,-0.2])]

ROADS['9_9']['busBaySide']=1
ROADS['9_9']['signs'][0]['offsetX']=3.2
JUNCTIONS['12_5']['layout']['actorsConfig'][0]['rotationY']=3.141592653589793/2
JUNCTIONS['1_9']['route']['pathRules']['paths']=[dict(maneuver=a,points=v) for a,v in JUNCTIONS['1_9']['route']['paths'].items()]
JUNCTIONS['33_8']['layout']['actorsConfig'][0]['position'][2]=-5.4
# The parked car is always the compact hatchback: a random longer model
# reached into the turning path (the outcome depended on Math.random).
JUNCTIONS['33_8']['layout']['actorsConfig'][0]['model']='hatch'

# 11.2 is four lanes in the source. Removing a same-direction lane would
# invalidate why trajectory A is forbidden; keep the original lane position.
JUNCTIONS['11_2']['layout']['mainLaneDividers']=[3.6]
for item in JUNCTIONS['11_2']['layout']['trajectories']:
 item['points']=item['points'][:4 if item['label']=='А' else 6]

JUNCTIONS['28_2']['layout']['signs'][0]['z']=-20
# 33.8 starts in the outer approach lane; avoid the parked car during the
# turn itself instead of first moving into the left approach lane.
right33=[[-5.4,-14],[-5.4,-8],[-6,-3.5],[-10,-1.8],[-18,-1.8],[-26,-1.1],[-36,-1.8]]
JUNCTIONS['33_8']['route']['paths']['right']=right33
JUNCTIONS['33_8']['route']['pathRules']['paths'][0]['points']=right33
