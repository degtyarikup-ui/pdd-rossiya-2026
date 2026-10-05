"""Authored layouts of the first expansion batch; source text is never authored here.

Intersection coordinates use the factory frame (+X right), actor routes world
coordinates (+X left). Road coordinates use world axes, Z from question stop.
"""
from math import pi

def sign(code,z,**kw): return dict(code=code,z=z,**kw)
def actor(id,type,side,name,color='#0574F8',**kw):
    return dict(id=id,type=type,side=side,name=name,color=color,targetAction='straight',**kw)
def junction(maneuver='straight',yieldTo=None,**kw):
    return dict(route=dict(maneuver=maneuver,yieldTo=yieldTo or [],reviewed=True),
                layout=dict(geometry='cross',actorsConfig=[],signs=[],trafficLights=None,**kw))
def J(maneuver='straight',yieldTo=None,**kw):
    d=junction(maneuver,yieldTo); d['layout'].update(kw);return d

def walker(side): return actor('pedestrian','pedestrian','crosswalk_'+side,'Пешеход')
def yard(side,cyclist=False,oncoming=False):
    sx=1 if side=='left' else -1
    actors=[walker(side)]
    if cyclist: actors.append(actor('cyclist','cyclist','opposite' if side=='left' else 'cross_right_edge','Велосипедист','#2BC280',
                                   position=[-sx*(5.6 if side=="left" else 3.35),0,-11],rotationY=0,route=[[sx*(5.6 if side=="left" else 3.35),-4],[sx*(5.6 if side=="left" else 3.35),6],[sx*(5.6 if side=="left" else 3.35),42]]))
    if oncoming: actors.append(actor('oncoming','car','opposite','Автомобиль','#F2C230'))
    return J(side,[a['id'] for a in actors],geometry='courtyard_'+side,unmarkedCrossings=True,actorsConfig=actors)

JUNCTIONS={
 '3_2':J(signs=[dict(code='2.5',z=-17)],hasStopLine=False,requiredStop=-4.2,questionStop=-24,
          stopPositions=[dict(label='А',z=-20),dict(label='Б',z=-9),dict(label='В',z=-4.2)]),
 '3_6':J('right',['special','pedestrian'],trafficLights=dict(state='green'),crosswalks=['right'],
          actorsConfig=[actor('special','special','cross_left','Спецмашина',beacon='blue_red',siren=True),walker('right')]),
 '17_6':J(trafficLights=dict(state='red'),hasStopLine=False,requiredStop=-8.5,redWait=3,
           signs=[dict(code='6.16',z=-8.5,mountOnLight=True)]),
 '18_5':J('left',geometry='t_no_straight',signs=[dict(code='2.5',z=-8.4)],stopLineOffset=-4.4,requiredStop=-4.4,questionStop=-15),
 '21_8':yard('left',cyclist=True),
 '21_16':J('left',['left','right'],geometry='t_no_straight',signs=[dict(code='5.22',z=-13)],
            actorsConfig=[actor('left','car','cross_left','Автомобиль слева','#2BC280'),actor('right','car','cross_right','Автомобиль справа','#FFA53C')],residentialExit=True),
 '29_6':J(trafficLights=dict(state='red'),requiredStop=-8.5,redWait=3),
 '33_2':J('left',geometry='t_no_straight',signs=[dict(code='1.34.3',z=5.9,x=0)]),
 '35_8':yard('left',oncoming=True),
 '38_8':yard('right',cyclist=True),
 '40_2':J(signs=[dict(code='4.1.1',z=-5.5)],mainMedian=True),
}
for k in ['3_2','17_6','29_6']:
 JUNCTIONS[k]['route']['allowedManeuvers']=['straight','left','right','uturn']
for k in ['18_5','21_16','33_2']:
 JUNCTIONS[k]['route']['allowedManeuvers']=['left','right','uturn']

ROADS={
 '6_5':dict(kind='observe',yieldMarkingZ=20,junction=dict(z=62,priority='secondary'),note='1.20 before the row of 1.13 yield triangles; it is not a stop line.'),
 '7_2':dict(kind='observe',outsideSettlement=True,signs=[sign('2.4',8,stopDistance=250)],junction=dict(z=258,priority='stop'),zoneLength=295,note='2.4 with 8.1.2 STOP 250 m; mandatory stop at the actual STOP junction, not at the warning.'),
 '10_16':dict(kind='railway',railway=dict(z=24,barrier=True,barrierOpen=True,closed=True,train=True,after=60),note='Red crossing signals prohibit entering even with the barrier raised.'),
 '11_4':dict(kind='speed',signs=[sign('5.31',10)],limitKmH=30,endSign='5.32',zoneLength=160,junction=dict(z=60,priority='main'),speedZone=True,note='30 km/h zone survives the intermediate junction; ends at 5.32.'),
 '13_6':dict(kind='railway',railway=dict(z=25,after=55),note='White-moon flashing signal at an open single-track crossing; check for trains before proceeding.'),
 '14_2':dict(kind='observe',outsideSettlement=True,signs=[sign('1.25',8,plateSign='8.12')],shoulderWorks=True,vehicles=[dict(type='van',name='Встречный',lane='oncoming',z=24,speed=6,color='#BC5A6E')],note='Works on the dangerous shoulder; no invented obstacle in the travel lane.'),
 '15_3':dict(kind='speed',outsideSettlement=True,roadCurve={'from':0,'to':120,'offset':10},signs=[sign('3.24',10,speedValue=40)],limitKmH=40,endSign='5.23.1',zoneLength=150,vehicles=[dict(type='truck',name='Встречный',lane='oncoming',z=44,speed=8,color='#FFA53C')],note='Mandatory maximum 40, not a recommended or minimum speed.'),
 '18_2':dict(kind='observe',outsideSettlement=True,signs=[sign('1.18',8)],gravelZ=178,zoneLength=230,note='Loose gravel 170 m after the rural warning sign; no invented speed restriction.'),
 '18_16':dict(kind='bus_departure',cityCentre='dashed',wideCity=True,cityWidth=10.8,cityLanes=1,playerLane='left',busPriority=False,note='Bus leaving an unmarked curb must yield; no bus-stop sign or bay.'),
 '19_16':dict(kind='bus_departure',wideCity=True,playerLane='left',busPriority=True,signs=[sign('5.16',8,offsetX=-3)],note='Bus signals out from a designated urban stop; driver must give way.'),
 '20_16':dict(kind='railway',railway=dict(z=27,signals=False,closed=True,train=True,stopOffset=12,requireStop=True,after=65),signs=[sign('2.5',15)],note='Uncontrolled single track: stop at 2.5, wait until train clears.'),
 '24_2':dict(kind='observe',outsideSettlement=True,railway=dict(z=208,after=45),signs=[sign('1.2',8,plateSign='1.4.1'),sign('1.4.2',78),sign('1.2',148,plateSign='1.4.3')],note='Rural unbarred crossing 200 m past 1.2 with 1.4.1, repeated with one stripe.'),
 '24_16':dict(kind='railway',railway=dict(z=26,barrier=True,closed=True,train=True,whiteSignal=False,crossbuck=False,signalsUnlit=True,stopOffset=12,after=65),note='No stop line or STOP sign: stop at least 5 m before the nearer barrier (7 m before track).'),
 '25_16':dict(kind='railway',railway=dict(z=30,tracks=2,signals=False,closed=True,train=True,trainDeparting=True,stopOffset=15,requireStop=True,after=65),signs=[sign('2.5',15)],note='Multitrack 1.3.2 and STOP: stop at sign; check both tracks before crossing.'),
 '27_10':dict(kind='overtake',outsideSettlement=True,overtake=False,junction=dict(z=42,priority='main'),vehicles=[dict(type='truck',name='Грузовик',lane='ahead',z=17,speed=5,color='#FFA53C',blinker='left',maneuver='turn_left_at_junction')],note='Left-signalling truck turns away; wait behind it, never bypass along the shoulder.'),
 '27_16':dict(kind='railway',railway=dict(z=30,signals=False,closed=True,train=True,stopOffset=10.76,after=65),note='No lights, boom, stop line or STOP: at least 10 m before the nearest rail.'),
 '31_4':dict(kind='temporary_bypass',outsideSettlement=True,signs=[sign('6.19.1',8,plate='50 м',offsetX=-4.2)],zoneLength=190,note='Temporary bypass through a median opening 50 m after 6.19.1; own carriageway closed, opposing traffic retains its own lane.'),
 '36_6':dict(kind='emergency_lane',wideCity=True,playerLane='left',note='Police with blue/red beacon and siren approaches from behind; change to right lane and continue.'),
 '38_2':dict(kind='observe',outsideSettlement=True,railway=dict(z=208,barrier=True,barrierOpen=True,after=45),signs=[sign('1.1',8,plateSign='1.4.1'),sign('1.4.2',78),sign('1.1',148,plateSign='1.4.3'),sign('1.1',148,side='left',plateSign='1.4.6')],note='Rural barrier crossing 200 m after warning; repeat warnings on both sides.'),
}
assert len(JUNCTIONS)+len(ROADS)==30

# Reviewed source 21.8: pedestrians walk toward the player on the pavement.
JUNCTIONS['21_8']['layout']['openEntrance']=True
ped=JUNCTIONS['21_8']['layout']['actorsConfig'][0]
ped.update(position=[-5.6,.18,7],rotationY=3.141592653589793,route=[[5.6,1],[5.6,-8],[5.6,-25]])

ROADS['27_10']['junction'].update(noRight=True,rural=True,sideSigns=False)
ROADS['27_10']['vehicles'].append(dict(type='car',name='Встречный',lane='oncoming',z=58,speed=8,color='#943C3A'))

# Final manual review, 2026-10-05: preserve all source participants/rules.
JUNCTIONS['3_2']['layout']['stopPositions'][0]['z']=-17
JUNCTIONS['3_6']['layout'].update(mainWidth=16.8,mainLaneDividers=[3.6],playerStartX=-5.4,questionStop=-18)
JUNCTIONS['3_6']['layout']['actorsConfig'][0].update(position=[1.8,0,-13],rotationY=0,targetAction='turn_right',route=[[-1.8,-6],[-1.8,-2],[-5,-1.8],[-20,-1.8],[-60,-1.8]])
for key in ['35_8','38_8']: JUNCTIONS[key]['layout']['openEntrance']=True
JUNCTIONS['40_2']['layout']['signs'][0].update(x=0,z=-5.5)
JUNCTIONS['40_2']['layout'].update(mainMedianEnd=-4.2,mainMedianWidth=.85)

JUNCTIONS['3_6']['layout']['questionStop']=-14
for key in ['18_5','21_16','33_2']:
 JUNCTIONS[key]['route'].setdefault('paths',{})['uturn']=[[-1.8,-12],[-2.1,-5],[-2.1,-1],[0,1.3],[2.1,-1],[2.1,-5],[1.8,-16],[1.8,-26]]

# Opposing pavement users need distinct physical corridors to pass each other.
# Keeping both at x=5.6 creates a head-on deadlock even after the player leaves.
ped,bike=JUNCTIONS['21_8']['layout']['actorsConfig'][:2]
ped.update(position=[-5.1,.18,7],route=[[5.1,1],[5.1,-8],[5.1,-25]],pathHeight=.18)
bike.update(position=[-6.6,.18,-11],route=[[6.6,-4],[6.6,6],[6.6,42]],pathHeight=.18)
