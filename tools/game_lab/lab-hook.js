  // ---- Game lab hook: injected by tools/game_lab/server.py only. ----
  // Runs inside the engine closure, so it can reach its internals.
  window.FlutterChannel = { postMessage: m => window.parent.postMessage({ labEvent: JSON.parse(m) }, '*') };
  window.__lab = (() => {
    const lab = { freeCam: false, orbit: { yaw: 0, pitch: 0.85, dist: 80, size: 42, target: new THREE.Vector3() },
      id: null, group: null, origin: 0, selected: null, helper: null };
    const baseUpdateCamera = updateCamera;
    // No new junctions while a model stands in the showroom.
    const baseSpawn = checkAndSpawnNext;
    checkAndSpawnNext = function () { if (!lab.model) baseSpawn(); };
    updateCamera = function (dt) {
      if (!lab.freeCam) return baseUpdateCamera(dt);
      const o = lab.orbit;
      const w = container.clientWidth || innerWidth, h = container.clientHeight || innerHeight, a = w / h;
      camera.left = -o.size * a / 2; camera.right = o.size * a / 2; camera.top = o.size / 2; camera.bottom = -o.size / 2;
      camera.updateProjectionMatrix();
      camera.position.set(o.target.x + Math.sin(o.yaw) * Math.cos(o.pitch) * o.dist,
        o.target.y + Math.sin(o.pitch) * o.dist, o.target.z - Math.cos(o.yaw) * Math.cos(o.pitch) * o.dist);
      camera.lookAt(o.target);
      const labelScale = Math.max(2.2, 34 * o.size / h);
      lab.group?.traverse(c => {
        if (c.userData?.isLabel || c.userData?.trajectoryLabel) c.scale.setScalar(labelScale);
      });
    };
    const junctions = () => SITUATIONS.map(s => {
      const spec = routeSpec(s);
      return { id: s.id, kind: 'junction', ticket: s.ticket, title: s.title, options: s.options,
        correct: s.correctAnswerIndex, explanation: s.explanation, pddRule: s.pddRule, type: s.type,
        reviewed: spec.reviewed === true, reason: spec.reason || '', maneuver: spec.maneuver, yieldTo: spec.yieldTo || [],
        regulator: isRegulatorSituation(s), signs: ((spec.overrides && spec.overrides.signs) || s.signs || []).map(x => x.code) };
    });
    const roads = () => (window.PDD_ROAD_SITUATIONS || []).map(s => ({ id: s.id, kind: 'road', ticket: s.ticket,
      title: s.title, options: s.options, correct: s.correctAnswerIndex, explanation: s.explanation, pddRule: s.pddRule,
      type: s.type, reviewed: s.enabled !== false, sourceQuestionId: s.sourceQuestionId, signs: (s.scene.signs || []).map(x => x.code) }));
    const EVENT_BUILDERS={busstop:buildBusStopEvent,crosswalk:buildCrosswalkEvent,roadworks:buildRoadworksEvent,
      obstacle:buildObstacleEvent,courtyard:buildCourtyardEvent,cyclist:buildCyclistEvent,emergency:buildEmergencyEvent};
    const EVENT_NAMES={busstop:'Автобусная остановка',crosswalk:'Пешеходный переход',roadworks:'Дорожные работы',
      obstacle:'Препятствие',courtyard:'Выезд из двора',cyclist:'Велосипедист',emergency:'Спецавтомобиль'};
    const events=()=>Object.keys(EVENT_BUILDERS).map(k=>({id:'event_'+k,kind:'event',title:EVENT_NAMES[k],reviewed:true,options:[],signs:[]}));
    function clearWorld() {
      resetGame(); state.attract = false;
      state.roadSegments.forEach(disposeSegment);
      state.roadSegments = []; state.actors = []; state.intersections = []; state.ambient = [];
      state.activeIntersection = null; state.occluders = []; state.roadEvent = null;
      state.exitRoad = currentCorridor = null;
      lab.selected = null; setHelper(null);
    }
    function show(id, drive = false) {
      lab.model = null;
      if (showroom) { scene.remove(showroom); showroom = null; }
      clearWorld();
      playerCarGroup.visible = true;
      lab.id = id;
      const road = (window.PDD_ROAD_SITUATIONS || []).find(s => s.id === id);
      if(id.startsWith('event_')) {
        const kind=id.slice(6),seg=buildStraightSegment(-45,240,true);
        state.roadSegments.push(seg);state.exitRoad=currentCorridor=seg;nextSegmentZ=195;
        const group=new THREE.Group();scene.add(group);state.roadSegments.push(group);
        state.roadEvent=EVENT_BUILDERS[kind](group,40);
        refreshRoadBounds();lab.group=group;lab.origin=40;
        playerCarGroup.position.set(-1.8,0,drive?-35:20);playerCarGroup.rotation.set(0,0,0);
      } else if (road) {
        const seg = buildStraightSegment(-45, 200, true); state.roadSegments.push(seg);
        state.exitRoad = currentCorridor = seg; nextSegmentZ = 155;
        const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
        state.roadTurn = 1;
        const ev = state.roadEvent = buildQuestionEvent(group, -45, road);
        lab.group = group; lab.origin = group.userData.stopZ ?? ev.stopZ;
        playerCarGroup.userData.posEdited = !!group.userData.playerEdit;
        playerCarGroup.position.set(ev.playerStartX ?? -1.8, 0, drive ? -40 : ev.stopZ);
        playerCarGroup.rotation.set(0, ev.playerStartRotY || 0, 0);
        if (!drive) startRoadQuestion();
      } else {
        const s = SITUATIONS.find(x => x.id === id);
        situationBag = [s]; buildInitialTrack();
        const it = state.intersections[0];
        lab.group = it.seg; lab.origin = it.centerZ;
        playerCarGroup.userData.posEdited = !!it.seg?.userData?.playerEdit;
        if (!drive) {
          playerCarGroup.position.set(it.playerStartX ?? it.situation.playerStartX ?? -1.8, 0, it.stopZ);
          playerCarGroup.rotation.set(0, it.playerStartRotY || 0, 0);
          updatePlayerMovement(0);
          clearMistakeHighlight();
        }
      }
      const pBlinker = lab.group?.userData?.playerBlinker || null;
      lab.playerBlinker = pBlinker;
      if (pBlinker) {
        state.blinker = { side: pBlinker, remaining: Infinity, elapsed: 0, fromSituation: true };
      } else {
        state.blinker = null;
        playerCarGroup.blinkerL.visible = playerCarGroup.blinkerR.visible = false;
      }
      lab.orbit.target.set(0, 0, lab.origin);
      for (let i = 0; i < 120; i++) baseUpdateCamera(1 / 60);
      applyWeather();
      return { origin: lab.origin };
    }
    function describe(o) {
      if (!o) return null;
      if (o === playerCarGroup) {
        return { key: 'player', isPlayer: true, isActor: false, label: 'Моё авто', actorName: 'Моё авто', actorType: 'car',
          blinker: lab.playerBlinker || 'none',
          x: +playerCarGroup.position.x.toFixed(2), z: +(playerCarGroup.position.z - lab.origin).toFixed(2), rotY: +playerCarGroup.rotation.y.toFixed(3),
          posEdited: !!(lab.group?.userData?.playerEdit || playerCarGroup.userData.posEdited),
          visible: true };
      }
      const isActor = !!(o.userData.isActorRoot || (o.userData.editKey && o.userData.editKey.startsWith('actor:')));
      const actorType = o.userData.actorType || o.userData.actorConfig?.type || (isActor ? 'car' : null);
      const actorName = o.userData.actorName || o.userData.actorConfig?.name;
      let label;
      const isLabel = !!(o.userData.isLabel || (o.userData.editKey && o.userData.editKey.startsWith('label:')));
      const labelText = o.userData.labelText || o.userData.trajectoryLabel || (isLabel ? o.userData.editKey.replace(/^label:(stop:)?/, '') : null);
      if (isLabel) {
        return {
          key: o.userData.editKey,
          isLabel: true,
          labelText,
          label: 'Метка ' + labelText,
          x: +o.position.x.toFixed(2),
          z: +(o.position.z - lab.origin).toFixed(2),
          rotY: +o.rotation.y.toFixed(3),
          visible: o.visible
        };
      }
      if (o.userData.signCode) label = 'Знак ' + o.userData.signCode;
      else if (isActor) label = actorName || ('Участник ' + (actorType || ''));
      else if (o.userData.isRoute) label = 'Синяя стрелка ' + (Number(o.userData.editKey.split(':')[1]) + 1);
      else label = o.userData.decorKind || o.userData.editKey;
      const blinker = isActor ? (o.userData.blinkerOverride !== undefined ? (o.userData.blinkerOverride || 'none') : (o.userData.blinkerSide || 'none')) : null;
      const isRoute = !!o.userData.isRoute;
      const curPts = isRoute ? (o.userData.routePath?.points || []).map(p => [+p.x.toFixed(2), +(p.z - lab.origin).toFixed(2)]) : null;
      return { key: o.userData.editKey, code: o.userData.signCode || null, kind: isActor ? 'actor' : (o.userData.decorKind || null),
        isActor, actorType, actorName, blinker, isRoute,
        length: isRoute ? o.userData.routeLength : undefined,
        startOffset: isRoute ? (o.userData.routeStart || 0) : undefined,
        bend: isRoute ? (o.userData.routeBend || 0) : undefined,
        hasCustomPoints: isRoute ? !!o.userData.hasCustomPoints : undefined,
        points: isRoute ? (o.userData.customPoints || curPts) : undefined,
        x: +o.position.x.toFixed(2), z: +(o.position.z - lab.origin).toFixed(2), rotY: +o.rotation.y.toFixed(3),
        visible: o.visible, label };
    }
    function setHelper(o) {
      if (lab.helper) { scene.remove(lab.helper); lab.helper = null; }
      if (!o) return;
      if (o.userData?.isLabel || o.userData?.editKey?.startsWith('label:')) {
        const radius = Math.max(1.15, (o.scale.x || 2.2) * 0.55);
        const ringGeo = new THREE.RingGeometry(radius, radius + 0.35, 32);
        ringGeo.rotateX(-Math.PI / 2);
        const ringMat = new THREE.MeshBasicMaterial({ color: 0x0574F8, side: THREE.DoubleSide });
        const ring = new THREE.Mesh(ringGeo, ringMat);
        ring.position.set(o.position.x, 0.04, o.position.z);
        ring.renderOrder = 999;
        lab.helper = ring;
        scene.add(ring);
        return;
      }
      if (o.userData?.isRoute) {
        const group = new THREE.Group();
        const box = new THREE.BoxHelper(o, 0x0574F8);
        group.add(box);
        const pts = o.userData.routePath?.points || [];
        const handleGeo = new THREE.SphereGeometry(0.4, 16, 16);
        pts.forEach((p, idx) => {
          const isSel = lab.selectedPoint && lab.selectedPoint.route === o && lab.selectedPoint.index === idx;
          const handleMat = new THREE.MeshBasicMaterial({ color: isSel ? 0xFF0055 : 0xFFB703, depthTest: false });
          const m = new THREE.Mesh(handleGeo, handleMat);
          m.position.copy(p);
          m.renderOrder = 1002;
          m.userData = { isRouteHandle: true, pointIndex: idx, route: o };
          group.add(m);
        });
        lab.helper = group;
        scene.add(group);
        return;
      }
      lab.helper = new THREE.BoxHelper(o, 0x0574F8); scene.add(lab.helper);
    }
    function find(key) {
      if (key === 'player') return playerCarGroup;
      let hit = null;
      lab.group?.traverse(o => { if (o.userData?.editKey === key) hit = o; });
      return hit;
    }
    function labels() {
      if (!lab.group) return [];
      const list = [];
      const seen = new Set();
      lab.group.traverse(o => {
        if ((o.userData?.isLabel || (o.userData?.editKey && o.userData.editKey.startsWith('label:'))) && !seen.has(o.userData.editKey)) {
          seen.add(o.userData.editKey);
          list.push(describe(o));
        }
      });
      return list;
    }
    function actors() {
      if (!lab.group) return [];
      const list = [];
      lab.group.children.forEach(o => {
        if (o.userData.isActorRoot || (o.userData.editKey && o.userData.editKey.startsWith('actor:'))) {
          list.push(describe(o));
        }
      });
      return list;
    }
    const ray = new THREE.Raycaster();
    function pick(nx, ny) {
      if (!lab.group) return null;
      ray.setFromCamera(new THREE.Vector2(nx, ny), camera);
      const targets = [playerCarGroup, ...lab.group.children];
      if (lab.helper) targets.push(lab.helper);
      const hits = ray.intersectObjects(targets, true);
      for (const h of hits) {
        let o = h.object;
        let isPlayer = false;
        if (o.userData?.isRouteHandle) {
          lab.selected = o.userData.route;
          lab.selectedPoint = { route: o.userData.route, index: o.userData.pointIndex };
          setHelper(o.userData.route);
          return { ...describe(o.userData.route), selectedPointIndex: o.userData.pointIndex };
        }
        while (o) {
          if (o === playerCarGroup) { isPlayer = true; break; }
          if (o.userData?.isLabel || (o.userData?.editKey && o.userData.editKey.startsWith('label:'))) {
            lab.selected = o;
            lab.selectedPoint = null;
            setHelper(o);
            return describe(o);
          }
          if (o.parent === lab.group || o.userData?.isRoute) break;
          o = o.parent;
        }
        if (isPlayer) {
          lab.selected = playerCarGroup;
          lab.selectedPoint = null;
          setHelper(playerCarGroup);
          return describe(playerCarGroup);
        }
        if (o && o.userData?.editKey) {
          lab.selected = o;
          lab.selectedPoint = null;
          setHelper(o);
          return describe(o);
        }
      }
      const gp = ground(nx, ny);
      if (gp) {
        let nearestLabel = null, minDist = 2.5;
        lab.group.traverse(o => {
          if (o.visible !== false && (o.userData?.isLabel || (o.userData?.editKey && o.userData.editKey.startsWith('label:')))) {
            const dist = Math.hypot(o.position.x - gp.x, o.position.z - gp.z);
            if (dist < minDist) { minDist = dist; nearestLabel = o; }
          }
        });
        if (nearestLabel) {
          lab.selected = nearestLabel;
          lab.selectedPoint = null;
          setHelper(nearestLabel);
          return describe(nearestLabel);
        }
      }
      lab.selected = null;
      lab.selectedPoint = null;
      setHelper(null);
      return null;
    }
    function ground(nx, ny) {
      ray.setFromCamera(new THREE.Vector2(nx, ny), camera);
      const p = new THREE.Vector3();
      return ray.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), p) ? p : null;
    }
    function update(props) {
      let o = lab.selected;
      if (!o) return null;
      if (o === playerCarGroup) {
        if (props.blinker !== undefined) {
          lab.playerBlinker = props.blinker === 'none' ? null : props.blinker;
          if (lab.group) lab.group.userData.playerBlinker = lab.playerBlinker;
          if (lab.playerBlinker) {
            state.blinker = { side: lab.playerBlinker, remaining: Infinity, elapsed: 0, fromSituation: true };
          } else {
            state.blinker = null;
            playerCarGroup.blinkerL.visible = playerCarGroup.blinkerR.visible = false;
          }
        }
        if (props.x !== undefined || props.z !== undefined || props.rotY !== undefined) {
          playerCarGroup.userData.posEdited = true;
          if (props.x !== undefined) playerCarGroup.position.x = props.x;
          if (props.z !== undefined) playerCarGroup.position.z = lab.origin + props.z;
          if (props.rotY !== undefined) playerCarGroup.rotation.y = props.rotY;
          if (lab.group) {
            lab.group.userData.playerEdit = {
              x: +playerCarGroup.position.x.toFixed(2),
              z: +(playerCarGroup.position.z - lab.origin).toFixed(2),
              rotY: +playerCarGroup.rotation.y.toFixed(3)
            };
          }
          if (state.intersections?.[0]) {
            state.intersections[0].stopZ = playerCarGroup.position.z;
            state.intersections[0].playerStartX = playerCarGroup.position.x;
            state.intersections[0].playerStartRotY = playerCarGroup.rotation.y;
          }
          if (state.roadEvent) {
            state.roadEvent.stopZ = playerCarGroup.position.z;
            state.roadEvent.playerStartX = playerCarGroup.position.x;
            state.roadEvent.playerStartRotY = playerCarGroup.rotation.y;
          }
        }
        setHelper(playerCarGroup);
        return describe(playerCarGroup);
      }
      if (props.code && o.userData.signCode && props.code !== o.userData.signCode) {
        const sign = createRoadSign(props.code);
        sign.position.copy(o.position); sign.rotation.copy(o.rotation); sign.scale.copy(o.scale);
        sign.userData = { ...o.userData, signCode: props.code };
        lab.group.add(sign); lab.group.remove(o); o = lab.selected = sign;
      }
      if (o.userData.isRoute) {
        if (props.startOffset !== undefined || props.length !== undefined) {
          const newLen = props.length !== undefined ? props.length : o.userData.routeLength;
          const newStart = props.startOffset !== undefined ? props.startOffset : (o.userData.routeStart || 0);
          setRouteRange(o, newLen, newStart);
        }
        if (props.bend !== undefined) {
          setRouteBend(o, props.bend);
        }
        if (props.resetPoints) {
          o.userData.customPoints = null;
          o.userData.hasCustomPoints = false;
          if (o.userData.origPoints) {
            o.userData.routePath = curve(o.userData.origPoints.map(p => p.clone()));
            o.position.set(o.userData.origPoints[0].x, 0, o.userData.origPoints[0].z);
            setRouteBend(o, o.userData.routeBend || 0);
          }
        }
        if (props.points !== undefined && Array.isArray(props.points)) {
          setRoutePoints(o, props.points, lab.origin);
        }
        if (props.pointIndex !== undefined && props.pointX !== undefined && props.pointZ !== undefined) {
          setRoutePoint(o, props.pointIndex, props.pointX, props.pointZ, lab.origin);
          lab.selectedPoint = { route: o, index: props.pointIndex };
        }
      }
      if (props.blinker !== undefined) {
        o.userData.blinkerOverride = props.blinker === 'none' ? null : props.blinker;
      }
      if (props.x !== undefined || props.z !== undefined) {
        const newX = props.x !== undefined ? props.x : o.position.x;
        const newZ = props.z !== undefined ? lab.origin + props.z : o.position.z;
        const dx = newX - o.position.x;
        const dz = newZ - o.position.z;
        o.position.x = newX;
        o.position.z = newZ;
        if (o.userData.isRoute && o.userData.routePath?.points && (Math.abs(dx) > 0.001 || Math.abs(dz) > 0.001)) {
          o.userData.routePath.points.forEach(p => { p.x += dx; p.z += dz; });
          if (o.userData.customPoints) {
            o.userData.customPoints = o.userData.routePath.points.map(p => [+p.x.toFixed(2), +(p.z - lab.origin).toFixed(2)]);
          }
          if (o.userData.origPoints) {
            o.userData.origPoints.forEach(p => { p.x += dx; p.z += dz; });
          }
        }
      }
      if (props.rotY !== undefined) o.rotation.y = props.rotY;
      if (props.visible !== undefined) o.visible = props.visible;
      if (o.userData.isActorRoot || (o.userData.editKey && o.userData.editKey.startsWith('actor:'))) {
        const findActor = a => a.mesh === o;
        const actor = state.actors?.find(findActor) || state.intersections?.flatMap(it => it.actors || []).find(findActor);
        if (actor) {
          const dx = o.position.x - actor.initialPos.x;
          const dz = o.position.z - actor.initialPos.z;
          actor.initialPos.copy(o.position);
          if (actor.viewBounds) actor.viewBounds.setFromObject(o);
          if (actor.path && actor.path.points && (Math.abs(dx) > 0.001 || Math.abs(dz) > 0.001)) {
            actor.path.points.forEach(p => { p.x += dx; p.z += dz; });
            actor.length = actor.path.getLength();
          }
        }
      }
      setHelper(o);
      const res = describe(o);
      if (lab.selectedPoint && lab.selectedPoint.route === o) res.selectedPointIndex = lab.selectedPoint.index;
      return res;
    }
    function add(spec, nx = 0, ny = 0) {
      const o = createEditable(spec);
      if (!o) return null;
      o.userData.editKey = 'add:' + Date.now().toString(36);
      const p = ground(nx, ny) || new THREE.Vector3(-5.4, 0, lab.origin);
      o.position.set(p.x, 0, p.z);
      if (spec.type === 'sign' && lab.group.userData.roadEvent) o.scale.setScalar(1.35);
      lab.group.add(o); lab.selected = o; setHelper(o);
      return describe(o);
    }
    // ---- Model workshop: one model on a turntable, edited as a draft. ----
    const MODELS = {
      'vehicle:hatch': () => window.PDD_VEHICLES.create('hatch'), 'vehicle:sedan': () => window.PDD_VEHICLES.create('sedan'),
      'vehicle:coupe': () => window.PDD_VEHICLES.create('coupe'), 'vehicle:wagon': () => window.PDD_VEHICLES.create('wagon'),
      'vehicle:suv': () => window.PDD_VEHICLES.create('suv'), 'vehicle:pickup': () => window.PDD_VEHICLES.create('pickup'),
      'vehicle:cyber': () => window.PDD_VEHICLES.create('cyber'),
      car: () => createNpcCar(0x2BC280), bus: () => createBus(0xF59E0B), truck: () => createTruck(0x3B82F6),
      tractor: () => createTractor(0xF2B233), special: () => createSpecialCar(0xFFFFFF), motorcycle: () => createMotorcycle(0xF59E0B),
      tram: () => createTram(), pedestrian: () => createPedestrian(0x0574F8, 0), cyclist: () => createCyclist(0x10B981, 0),
      cone: () => createTrafficCone(), barrier: () => createRoadworksBarrier(2.4), traffic_light: () => createTrafficLight('green'),
      tree: () => createTree('pine'), lamp: () => createLampPost(), kiosk: () => createKiosk(), building: () => createBuilding(8, 7, 8, 1),
    };
    let showroom = null;
    function meshesOf(root) { const list = []; root.traverse(o => { if (o.isMesh) list.push(o); }); return list; }
    function palette(root) {
      const seen = new Map();
      meshesOf(root).forEach(m => {
        const attr = m.geometry.attributes.color;
        if (attr && m.material.vertexColors) {
          const c = new THREE.Color();
          for (let k = 0; k < attr.count; k += 3) { c.setRGB(attr.getX(k), attr.getY(k), attr.getZ(k)); seen.set(c.getHex(), (seen.get(c.getHex()) || 0) + 1); }
        } else if (m.material?.color) seen.set(m.material.color.getHex(), (seen.get(m.material.color.getHex()) || 0) + 1);
      });
      return [...seen].sort((a, b) => b[1] - a[1]).map(([hex]) => '#' + hex.toString(16).padStart(6, '0'));
    }
    function showModel(id, draft) {
      clearWorld();
      state.roadSegments.forEach(disposeSegment); state.roadSegments = [];
      playerCarGroup.visible = false;
      if (showroom) scene.remove(showroom);
      showroom = new THREE.Group(); scene.add(showroom);
      const floor = new THREE.Mesh(new THREE.CircleGeometry(9, 48), new THREE.MeshLambertMaterial({ color: 0xE9ECEF }));
      floor.rotation.x = -Math.PI / 2; floor.position.y = 0.01; floor.receiveShadow = true; showroom.add(floor);
      // The original palette: built once without any edits.
      const saved = window.PDD_MODEL_EDITS[id];
      delete window.PDD_MODEL_EDITS[id];
      const plain = MODELS[id]();
      const original = palette(plain);
      if (draft) window.PDD_MODEL_EDITS[id] = draft; else if (saved) window.PDD_MODEL_EDITS[id] = saved;
      const root = MODELS[id]();
      root.position.set(0, 0, 0); showroom.add(root);
      lab.model = { id, root, meshes: meshesOf(root) };
      const box = new THREE.Box3().setFromObject(root), size = box.getSize(new THREE.Vector3());
      lab.freeCam = true;
      lab.orbit.target.set(0, size.y / 2, 0);
      lab.orbit.size = Math.max(size.x, size.y, size.z) * 1.5 + 1;
      lab.orbit.yaw = 0.75; lab.orbit.pitch = 0.45;
      lab.selected = null; setHelper(null);
      const spec = id.startsWith('vehicle:') ? { ...window.PDD_VEHICLES.specs[id.slice(8)], ...(draft?.spec || saved?.spec || {}) } : null;
      return { id, parts: lab.model.meshes.length, original, spec,
        size: size.toArray().map(v => +v.toFixed(2)) };
    }
    function pickPart(nx, ny) {
      if (!lab.model) return null;
      ray.setFromCamera(new THREE.Vector2(nx, ny), camera);
      const hit = ray.intersectObjects(lab.model.meshes, false).find(h => h.object.visible);
      if (!hit) { setHelper(null); return null; }
      const i = lab.model.meshes.indexOf(hit.object);
      setHelper(hit.object);
      const m = hit.object;
      const color = m.material.vertexColors ? null : '#' + m.material.color.getHex().toString(16).padStart(6, '0');
      return { index: i, color, merged: !!m.material.vertexColors };
    }
    // Direct eval for scripted checks (tools/game_lab only, never shipped).
    const run = code => eval(code);
    return { run, junctions, roads, events, show, showModel, pickPart, models: () => Object.keys(MODELS), pick, ground, update, add, find, describe, lab, state,
      select(key) { lab.selected = find(key); setHelper(lab.selected); return describe(lab.selected); },
      signCodes: () => Object.keys(window.PDD_SIGN_TEXTURES || {}).sort(),
      decorKinds: () => Object.keys(EDITABLE_DECOR),
      actors: () => actors(),
      labels: () => labels(),
      routes: () => { const list = []; lab.group?.traverse(o => { if (o.userData.isRoute) list.push(describe(o)); }); return list; },
      player: () => ({ x: playerCarGroup.position.x, z: playerCarGroup.position.z }),
      tick: () => {
        // Freeze traffic in inspection mode, but keep the canvas and camera live.
        if(state.paused) { updateWeather(1/60); updateCamera(1/60); updateBlinkers(1/60); renderer.render(scene,camera); }
        if (lab.helper) lab.helper.update?.();
      } };
  })();
