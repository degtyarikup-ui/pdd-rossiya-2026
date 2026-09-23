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
      type: s.type, reviewed: true, sourceQuestionId: s.sourceQuestionId, signs: (s.scene.signs || []).map(x => x.code) }));
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
      if (road) {
        const seg = buildStraightSegment(-45, 200, true); state.roadSegments.push(seg);
        state.exitRoad = currentCorridor = seg; nextSegmentZ = 155;
        const group = new THREE.Group(); scene.add(group); state.roadSegments.push(group);
        state.roadTurn = 1;
        const ev = state.roadEvent = buildQuestionEvent(group, -45, road);
        lab.group = group; lab.origin = ev.stopZ;
        playerCarGroup.position.set(-1.8, 0, drive ? -40 : ev.stopZ); playerCarGroup.rotation.set(0, 0, 0);
        if (!drive) startRoadQuestion();
      } else {
        const s = SITUATIONS.find(x => x.id === id);
        situationBag = [s]; buildInitialTrack();
        const it = state.intersections[0];
        lab.group = it.seg; lab.origin = it.centerZ;
        if (!drive) { playerCarGroup.position.z = it.stopZ; updatePlayerMovement(0); }
      }
      lab.orbit.target.set(0, 0, lab.origin);
      for (let i = 0; i < 120; i++) baseUpdateCamera(1 / 60);
      return { origin: lab.origin };
    }
    function describe(o) {
      if (!o) return null;
      return { key: o.userData.editKey, code: o.userData.signCode || null, kind: o.userData.decorKind || null,
        x: +o.position.x.toFixed(2), z: +(o.position.z - lab.origin).toFixed(2), rotY: +o.rotation.y.toFixed(3),
        visible: o.visible, label: o.userData.signCode ? 'Знак ' + o.userData.signCode : o.userData.decorKind || o.userData.editKey };
    }
    function setHelper(o) {
      if (lab.helper) { scene.remove(lab.helper); lab.helper = null; }
      if (!o) return;
      lab.helper = new THREE.BoxHelper(o, 0x0574F8); scene.add(lab.helper);
    }
    function find(key) {
      let hit = null;
      lab.group?.traverse(o => { if (o.userData.editKey === key && o.parent === lab.group) hit = o; });
      return hit;
    }
    const ray = new THREE.Raycaster();
    function pick(nx, ny) {
      if (!lab.group) return null;
      ray.setFromCamera(new THREE.Vector2(nx, ny), camera);
      const hits = ray.intersectObjects(lab.group.children, true);
      for (const h of hits) {
        let o = h.object;
        while (o && o.parent !== lab.group) o = o.parent;
        if (o && o.userData.editKey && !o.userData.actor) { lab.selected = o; setHelper(o); return describe(o); }
      }
      lab.selected = null; setHelper(null); return null;
    }
    function ground(nx, ny) {
      ray.setFromCamera(new THREE.Vector2(nx, ny), camera);
      const p = new THREE.Vector3();
      return ray.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), p) ? p : null;
    }
    function update(props) {
      let o = lab.selected;
      if (!o) return null;
      if (props.code && o.userData.signCode && props.code !== o.userData.signCode) {
        const sign = createRoadSign(props.code);
        sign.position.copy(o.position); sign.rotation.copy(o.rotation); sign.scale.copy(o.scale);
        sign.userData = { ...o.userData, signCode: props.code };
        lab.group.add(sign); lab.group.remove(o); o = lab.selected = sign;
      }
      if (props.x !== undefined) o.position.x = props.x;
      if (props.z !== undefined) o.position.z = lab.origin + props.z;
      if (props.rotY !== undefined) o.rotation.y = props.rotY;
      if (props.visible !== undefined) o.visible = props.visible;
      setHelper(o);
      return describe(o);
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
    return { run, junctions, roads, show, showModel, pickPart, models: () => Object.keys(MODELS), pick, ground, update, add, find, describe, lab, state,
      select(key) { lab.selected = find(key); setHelper(lab.selected); return describe(lab.selected); },
      signCodes: () => Object.keys(window.PDD_SIGN_TEXTURES || {}).sort(),
      decorKinds: () => Object.keys(EDITABLE_DECOR),
      player: () => ({ x: playerCarGroup.position.x, z: playerCarGroup.position.z }),
      tick: () => { if (lab.helper) lab.helper.update(); } };
  })();
