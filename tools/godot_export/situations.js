// In-page half of the situation export (see export_situations.cjs). Runs in
// the full game page with the engine internals exposed as window.__eng.
// One situation -> { glb: static scene, lights: [...], actors: [...], json }.
(function () {
  const U = THREE.BufferGeometryUtils, X = window.__exp;
  const LAYERS = Object.keys(PDD_ROADS.kinds);
  const r3 = v => Math.round(v * 1000) / 1000;
  const vec = v => [r3(v.x), r3(v.y), r3(v.z)];

  // World matrices of every drawn instance of a mesh (InstancedMesh too).
  function instances(mesh) {
    if (!mesh.isInstancedMesh) return [mesh.matrixWorld];
    const out = [], m = new THREE.Matrix4();
    for (let i = 0; i < mesh.count; i++) { mesh.getMatrixAt(i, m); out.push(new THREE.Matrix4().multiplyMatrices(mesh.matrixWorld, m)); }
    return out;
  }

  // Static scene -> one plain mesh (vertex colours + detail layer, the
  // scenery format) and one mesh per textured material (signs, plates,
  // zebra...). `origin` = world point that becomes (0, 0, 0).
  // Everything farther than CROP from the junction centre is ordinary street:
  // Godot's own street continues there (scripts/street.gd).
  const CROP = 90;
  function crop(g) {
    // Triangles are clipped to the square (Sutherland-Hodgman, attributes
    // interpolated): a road quad 400 m long must not vanish because its
    // centre lies outside.
    const names = Object.keys(g.attributes), pos = g.attributes.position, n = pos.count;
    const out = Object.fromEntries(names.map(k => [k, []]));
    const planes = [[0, 1], [0, -1], [2, 1], [2, -1]]; // axis, sign: sign * v <= CROP
    const vertex = i => Object.fromEntries(names.map(k => [k, Array.from({ length: g.attributes[k].itemSize }, (_, c) => g.attributes[k].array[i * g.attributes[k].itemSize + c])]));
    let kept = 0;
    for (let i = 0; i < n; i += 3) {
      let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
      for (let j = 0; j < 3; j++) { minX = Math.min(minX, pos.getX(i + j)); maxX = Math.max(maxX, pos.getX(i + j)); minZ = Math.min(minZ, pos.getZ(i + j)); maxZ = Math.max(maxZ, pos.getZ(i + j)); }
      if (minX > CROP || maxX < -CROP || minZ > CROP || maxZ < -CROP) continue;
      let poly = [vertex(i), vertex(i + 1), vertex(i + 2)];
      if (!(minX >= -CROP && maxX <= CROP && minZ >= -CROP && maxZ <= CROP)) {
        for (const [axis, sign] of planes) {
          const next = [];
          for (let a = 0; a < poly.length; a++) {
            const p = poly[a], q = poly[(a + 1) % poly.length];
            const dp = sign * p.position[axis] - CROP, dq = sign * q.position[axis] - CROP;
            if (dp <= 0) next.push(p);
            if ((dp < 0 && dq > 0) || (dp > 0 && dq < 0)) {
              const t = dp / (dp - dq);
              next.push(Object.fromEntries(names.map(k => [k, p[k].map((v, c) => v + (q[k][c] - v) * t)])));
            }
          }
          poly = next;
          if (poly.length < 3) break;
        }
        if (poly.length < 3) continue;
      }
      for (let a = 1; a < poly.length - 1; a++) for (const v of [poly[0], poly[a], poly[a + 1]]) for (const k of names) out[k].push(...v[k]);
      kept++;
    }
    const res = new THREE.BufferGeometry();
    for (const k of names) res.setAttribute(k, new THREE.BufferAttribute(new Float32Array(out[k]), g.attributes[k].itemSize));
    return res;
  }

  function bakeStatic(root, skip, origin) {
    root.updateMatrixWorld(true);
    const shift = new THREE.Matrix4().makeTranslation(-origin.x, -origin.y, -origin.z);
    const plain = [], textured = new Map();
    tally = {};
    const label = n => { const keys = Object.keys(n.userData).filter(k => !['registered', 'pddSkinned', 'pddFrame', 'editKey'].includes(k)).slice(0, 2).join(','); return (n.isMesh ? n.geometry.type : n.type) + ':' + keys; };
    const visit = (node, visible) => {
      if (skip.has(node) || node.isSprite || node.isLine || node.isPoints) return;
      visible = visible && node.visible !== false;
      if (!visible) return;
      if (node.isMesh && node.material && !Array.isArray(node.material)) {
        const m = node.material;
        const kind = m.userData?.pddKind;
        const tex = m.map && !kind;
        let host = node; while (host.parent && host.parent !== root && host.parent.parent !== root) host = host.parent;
        const lab = label(host) + ' > ' + label(node);
        tally[lab] = (tally[lab] || 0) + node.geometry.attributes.position.count * (node.isInstancedMesh ? node.count : 1);
        for (const world of instances(node)) {
          let g = node.geometry.index ? node.geometry.toNonIndexed() : node.geometry.clone();
          const own = g.attributes.color, side = g.attributes.pddSide;
          for (const name of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(name)) g.deleteAttribute(name);
          if (!g.attributes.normal) g.computeVertexNormals();
          const n = g.attributes.position.count;
          if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(n * 2), 2));
          g.applyMatrix4(new THREE.Matrix4().multiplyMatrices(shift, world));
          // A mirrored instance (registerRoadSegment flips X) turns faces inside out.
          if (world.determinant() < 0) {
            const pos = g.attributes.position, nor = g.attributes.normal, uv = g.attributes.uv;
            for (let i = 0; i < n; i += 3) for (const a of [pos, nor, uv]) {
              for (let k = 0; k < a.itemSize; k++) { const t = a.array[(i + 1) * a.itemSize + k]; a.array[(i + 1) * a.itemSize + k] = a.array[(i + 2) * a.itemSize + k]; a.array[(i + 2) * a.itemSize + k] = t; }
            }
          }
          if (tex) {
            // Many materials share one image (sceneryMat per mesh): group by look.
            const key = [m.map.uuid, m.color.getHex(), m.transparent, m.opacity, m.alphaTest, m.side, m.type].join('|');
            if (!textured.has(key)) textured.set(key, { m, list: [] });
            const c = crop(g); if (c.attributes.position.count) textured.get(key).list.push(c);
            continue;
          }
          const layer = kind && LAYERS.includes(kind) ? LAYERS.indexOf(kind) + 1 : 0;
          const col = new Float32Array(n * 4), uv2 = new Float32Array(n * 2);
          const alpha = m.transparent ? m.opacity : 1;
          for (let i = 0; i < n; i++) {
            const c = own ? new THREE.Color(own.getX(i), own.getY(i), own.getZ(i)).multiply(m.color) : m.color;
            // A = 0: plain (no tint). Transparent parts are rare in static scenes; kept opaque.
            col.set([c.r, c.g, c.b, 0], i * 4);
            uv2.set([layer, side ? side.getX(i) : 0], i * 2);
          }
          g.setAttribute('color', new THREE.BufferAttribute(col, 4));
          g.setAttribute('uv2', new THREE.BufferAttribute(uv2, 2));
          const c = crop(g); if (c.attributes.position.count) plain.push(c);
        }
      }
      for (const child of node.children) visit(child, visible);
    };
    visit(root, true);
    const out = new THREE.Group(); out.name = 'scene';
    if (plain.length) {
      // Indexed: shared corners stored once (about a third of the size).
      const mesh = new THREE.Mesh(U.mergeVertices(U.mergeBufferGeometries(plain, false), 1e-4), new THREE.MeshStandardMaterial({ vertexColors: true }));
      mesh.name = 'static'; mesh.material.name = 'scenery'; out.add(mesh);
    }
    let i = 0;
    for (const { m, list } of textured.values()) {
      if (!list.length) continue;
      const mat = m.clone(); mat.name = 'tex_' + (i++);
      // GLTFExporter needs a drawable image; DataTextures and images still
      // loading are drawn into a canvas (or dropped to colour only).
      mat.map = exportableMap(mat.map);
      const mesh = new THREE.Mesh(U.mergeVertices(U.mergeBufferGeometries(list, false), 1e-4), mat);
      mesh.name = mat.name; out.add(mesh);
    }
    return out;
  }

  function isShown(o) { for (let n = o; n; n = n.parent) if (n.visible === false) return false; return true; }

  function exportableMap(map) {
    const img = map && map.image;
    if (!img) return null;
    if (img instanceof HTMLCanvasElement || (img instanceof HTMLImageElement && img.complete && img.naturalWidth)) return map;
    if (img.data && img.width) {
      const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
      const d = new ImageData(new Uint8ClampedArray(img.data.buffer.slice(0)), img.width, img.height);
      c.getContext('2d').putImageData(d, 0, 0);
      const t = map.clone(); t.image = c; t.needsUpdate = true; return t;
    }
    if (img.width && img.height) {
      try { const c = document.createElement('canvas'); c.width = img.width; c.height = img.height; c.getContext('2d').drawImage(img, 0, 0); const t = map.clone(); t.image = c; return t; } catch (e) { return null; }
    }
    return null;
  }

  function sanitize(obj) {
    obj.traverse(o => { if (o.material && !Array.isArray(o.material) && o.material.map) { o.material = o.material.clone(); o.material.map = exportableMap(o.material.map); } });
    return obj;
  }

  // The name plate above an actor (createActorMesh): text per language,
  // plate colour, height; hidden plates are not exported.
  function badgeOf(a) {
    const sprite = a.mesh.userData.badge;
    if (!sprite || sprite.visible === false) return null;
    const cfg = a.config;
    const label = cfg.siren ? 'Маячок + сирена' : cfg.badge || (cfg.name ? (
      cfg.name.includes('Трамвай А') ? 'А' : cfg.name.includes('Трамвай Б') ? 'Б' : cfg.name.includes('Трамвай') ? 'Трамвай' :
      cfg.name.includes('Автобус') ? 'Автобус' : cfg.name.includes('Фургон') ? 'Фургон' : cfg.name.includes('Грузовик') ? 'Грузовик' :
      cfg.name.includes('Повозка') ? 'Повозка' : cfg.name.includes('Спец') ? 'Спец' : cfg.name.includes('Мотоцикл') ? 'Мото' :
      cfg.name.includes('Велосипед') ? 'Вело' : cfg.name.includes('Пешеход') ? 'Пешеход' : cfg.name.includes('Встреч') ? 'Встречный' : 'Авто') : 'Авто');
    const keep = window.PDD_LANG, text = {};
    for (const lang of ['ru', 'en', 'kk']) { window.PDD_LANG = lang; text[lang] = window.PDD_T(label); }
    window.PDD_LANG = keep;
    const color = typeof cfg.color === 'number' ? '#' + cfg.color.toString(16).padStart(6, '0') : (cfg.color || '#0574F8');
    return { text, color, height: r3(sprite.position.y) };
  }

  function pathPoints(path, step = 1) {
    const len = path.getLength(), n = Math.max(2, Math.ceil(len / step));
    return Array.from({ length: n + 1 }, (_, i) => vec(path.getPointAt(i / n)));
  }

  // Props tagged by the factories -> instances of the exported scenery
  // variants (scenery/index.json); nearest variant by style and size.
  function propOf(o, origin, catalog) {
    const t = o.userData.godotProp;
    const p = o.getWorldPosition(new THREE.Vector3()).sub(origin);
    const q = o.getWorldQuaternion(new THREE.Quaternion());
    const yaw = r3(new THREE.Euler().setFromQuaternion(q, 'YXZ').y);
    const s = o.getWorldScale(new THREE.Vector3());
    const base = { pos: vec(p), yaw, scale: vec(s) };
    const hex = c => '#' + c.getHexString();
    if (t.kind === 'building') {
      const [w = 12, h = 14, d = 12, style = 2] = t.args;
      const group = style === 1 ? 'home' : h > 26 ? 'tower' : 'block';
      let best = null, bestD = Infinity;
      for (const [name, info] of Object.entries(catalog)) {
        if (!name.startsWith('buildings/' + group)) continue;
        const f = info.footprint, dd = Math.abs(f[0] - w) + Math.abs(f[1] - h) * 0.5 + Math.abs(f[2] - d);
        if (dd < bestD) { bestD = dd; best = name; }
      }
      let body = null; o.traverse(m => { if (!body && m.isMesh && m.geometry.type === 'BoxGeometry') body = m; });
      const f = catalog[best].footprint;
      return { prop: best, ...base, scale: [r3(s.x * w / f[0]), r3(s.y * h / f[1]), r3(s.z * d / f[2])], tint: body ? hex(body.material.color) : '#FFFFFF' };
    }
    if (t.kind === 'tree') {
      let kind = 'pine', tint = null;
      o.traverse(m => { const k = m.material?.userData?.seasonal; if (k === 'birch') { kind = 'birch'; tint = hex(m.material.color); } else if (k === 'canopy') { kind = 'round'; tint = hex(m.material.color); } });
      if (kind === 'pine') o.traverse(m => { if (m.material?.userData?.pddKind === 'leaves') tint = hex(m.material.color); });
      return { prop: 'trees/' + kind + '_0', ...base, tint };
    }
    if (t.kind === 'bush') { let c = '#56764C'; o.traverse(m => { if (m.isMesh) c = hex(m.material.color); }); return { prop: 'street/bush', ...base, scale: vec(s.clone().multiply(new THREE.Vector3(1, 1 / 0.6, 1 / 1.3))), tint: c }; }
    if (t.kind === 'fence') { const L = t.args[0] || 12; return { prop: L < 13 ? 'street/fence_12' : 'street/fence_14', ...base, scale: [r3(s.x), r3(s.y), r3(s.z * L / (L < 13 ? 12 : 14))] }; }
    if (t.kind === 'kiosk') return { prop: 'street/kiosk_0', ...base };
    if (t.kind === 'lamp') return { prop: 'street/lamp', ...base };
    if (t.kind === 'parked') { let c = '#E8E8E8'; o.traverse(m => { if (m.material?.userData?.vehicleSurface === 'paint') c = hex(m.material.color); }); return { prop: 'parked', ...base, tint: c }; }
    return null;
  }

  let out_weight = null, tally = {};
  window.exportSituation = async function (index, catalog) {
    const E = window.__eng;
    // Deterministic scenes: the game's Math.random seeded per situation.
    const real = Math.random; let a = (index + 1) * 2654435761 >>> 0;
    Math.random = () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    try { E.select(index); E.drain(); E.approach(); E.drain(); } finally { Math.random = real; }
    const it = E.state.intersections[0];
    if (!it) return { error: 'no intersection' };
    const origin = new THREE.Vector3(0, 0, it.centerZ);
    const motions = E.ensureTraffic(it);
    const skip = new Set();
    motions.forEach(a => skip.add(a.mesh));
    if (it.guide) skip.add(it.guide);
    // Ambient life (walkers, cats, dogs) is Godot's own: not part of the scene.
    E.state.ambient.forEach(a => skip.add(a.mesh));
    const lights = [];
    it.seg.traverse(o => { if (o.setLightState) { skip.add(o); lights.push(o); } });
    it.seg.traverse(o => { if (o.userData.trajectoryLabel || o.userData.routeGuide) skip.add(o); });
    const props = [];
    it.seg.updateMatrixWorld(true);
    it.seg.traverse(o => {
      if (!o.userData.godotProp || skip.has(o) || !isShown(o)) return;
      skip.add(o);
      const p = propOf(o, origin, catalog);
      if (p && Math.abs(p.pos[0]) <= CROP && Math.abs(p.pos[2]) <= CROP) props.push(p);
    });
    // Question evidence: route guides (flat ribbons + arrow heads), letter
    // tokens (A, B, V...) and the actors' name badges.
    const labels = [];
    it.seg.traverse(o => {
      if (o.userData.isLabel && isShown(o)) {
        const p = o.getWorldPosition(new THREE.Vector3()).sub(origin);
        labels.push({ letter: o.userData.labelText || o.userData.trajectoryLabel, pos: vec(p) });
      }
    });
    let guideGlb = null;
    if (it.guide && it.guide.children.length) {
      it.guide.visible = true; it.seg.updateMatrixWorld(true);
      const g = bakeStatic(it.guide, new Set(), origin);
      if (g.children.length) guideGlb = await X.toGlb(g);
    }
    const scene = bakeStatic(it.seg, skip, origin);
    out_weight = Object.entries(tally).sort((a, b) => b[1] - a[1]).slice(0, 25);
    const out = { glb: await X.toGlb(scene), guide: guideGlb, lights: [], actors: [], weight: out_weight };
    // Traffic lights: lamps named lamp_red / lamp_yellow / lamp_green.
    for (const tl of lights) {
      const copy = tl.clone(true);
      copy.position.set(0, 0, 0); copy.rotation.set(0, 0, 0); copy.updateMatrixWorld(true);
      const lampColors = [0xFF3838, 0xFFD52A, 0x36FF88];
      let k = 0;
      copy.traverse(o => { if (o.isMesh && o.geometry.parameters?.radiusTop === 0.21) o.name = ['lamp_red', 'lamp_yellow', 'lamp_green'][k++]; });
      const flat = X.flatten(copy, n => /^lamp_/.test(n.name));
      flat.name = 'traffic_light';
      out.lights.push({ glb: await X.toGlb(sanitize(flat)), pos: vec(tl.getWorldPosition(new THREE.Vector3()).sub(origin)),
        yaw: r3(new THREE.Euler().setFromQuaternion(tl.getWorldQuaternion(new THREE.Quaternion()), 'YXZ').y), scale: r3(tl.scale.x),
        arrow: tl.userData.arrow || null });
    }
    for (const a of motions) {
      // Moving parts keep their own nodes: wheels spin, legs and arms swing.
      const ud = a.mesh.userData;
      (ud.wheels || []).forEach((w, n) => { w.name = 'wheel_' + n; });
      (ud.rims || []).forEach((w, n) => { w.name = 'wheel_rim_' + n; });
      (ud.legs || []).forEach((w, n) => { w.name = 'leg_' + n; });
      (ud.arms || []).forEach((w, n) => { w.name = 'arm_' + n; });
      if (ud.pedals) ud.pedals.name = 'pedals';
      const mesh = a.mesh.clone(true);
      mesh.position.set(0, 0, 0); mesh.rotation.set(0, 0, 0);
      mesh.name = a.config.id || 'actor';
      const flat = X.flatten(mesh, n => X.isDynamic(n) || n.name === 'pedals');
      out.actors.push({ glb: await X.toGlb(sanitize(flat)), id: a.config.id, type: a.config.type, name: a.config.name || '',
        config: a.config, halfLength: r3(a.halfLength || 0), halfWidth: r3(a.halfWidth || 0),
        badge: badgeOf(a),
        pos: vec(a.mesh.position.clone().sub(origin)), yaw: r3(a.mesh.rotation.y), scale: vec(a.mesh.scale),
        path: pathPoints(a.path).map(p => [p[0], p[1], r3(p[2] - origin.z)]), length: r3(a.length),
        clearDistance: r3(a.clearDistance), maxSpeed: a.maxSpeed, signalPlan: a.signalPlan || null,
        stopAtDistance: a.stopAtDistance ?? null, stopFor: a.stopFor === Infinity ? 'inf' : (a.stopFor ?? null), holdFor: a.holdFor || null,
        waitsForPlayer: a.waitsForPlayer, staysPut: !!a.config.staysPut });
    }
    // Drivable area as a mask (roadSupports sampled every 0.25 m inside the
    // road surfaces): Godot keeps the car on the road exactly like the game.
    E.refreshRoadBounds();
    const CELL = 0.25, R = CROP;
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    const boxes = E.state.roadBounds.map(b => b.box).filter(b => b.max.x > -R && b.min.x < R && b.max.z > origin.z - R && b.min.z < origin.z + R);
    boxes.forEach(b => { minX = Math.min(minX, b.min.x); maxX = Math.max(maxX, b.max.x); minZ = Math.min(minZ, b.min.z); maxZ = Math.max(maxZ, b.max.z); });
    minX = Math.max(minX, -R); maxX = Math.min(maxX, R); minZ = Math.max(minZ, origin.z - R); maxZ = Math.min(maxZ, origin.z + R);
    const W = Math.ceil((maxX - minX) / CELL), H = Math.ceil((maxZ - minZ) / CELL);
    const mask = new Uint8Array(W * H), probe = new THREE.Vector3();
    for (const b of boxes) {
      const x0 = Math.max(0, Math.floor((b.min.x - 0.1 - minX) / CELL)), x1 = Math.min(W - 1, Math.ceil((b.max.x + 0.1 - minX) / CELL));
      const z0 = Math.max(0, Math.floor((b.min.z - 0.1 - minZ) / CELL)), z1 = Math.min(H - 1, Math.ceil((b.max.z + 0.1 - minZ) / CELL));
      for (let zi = z0; zi <= z1; zi++) for (let xi = x0; xi <= x1; xi++) {
        const k = zi * W + xi; if (mask[k]) continue;
        probe.set(minX + (xi + 0.5) * CELL, 0, minZ + (zi + 0.5) * CELL);
        if (E.roadSupports(probe)) mask[k] = 255;
      }
    }
    const mc = document.createElement('canvas'); mc.width = W; mc.height = H;
    const md = mc.getContext('2d').createImageData(W, H);
    for (let k = 0; k < mask.length; k++) { md.data[k * 4] = md.data[k * 4 + 1] = md.data[k * 4 + 2] = mask[k]; md.data[k * 4 + 3] = 255; }
    mc.getContext('2d').putImageData(md, 0, 0);
    out.mask = mc.toDataURL('image/png').split(',')[1];
    // Framing for several heights of the question card (px of 844).
    const camSamples = [0, 150, 300, 380, 460, 540].map(b => { const c = E.questionCamera(it, b); return { bottom: b, look: [r3(c.look.x), r3(c.look.z - origin.z)], size: r3(c.size) }; });
    const spec = E.routeSpec(it.situation);
    const s = it.situation;
    const exits = {};
    for (const action of ['straight', 'left', 'right', 'uturn']) {
      try {
        const r = { intersection: it, spec };
        const { points, exitYaw } = E.maneuverPoints(r, action, E.player().position.clone());
        exits[action] = { points: points.map(p => [r3(p.x), r3(p.z - origin.z)]), exitYaw: r3(exitYaw) };
      } catch (e) { /* not offered here */ }
    }
    const texts = {};
    for (const lang of ['ru', 'en', 'kk']) {
      const t = lang === 'ru' ? s : (((window.PDD_SITUATION_I18N || {})[s.id] || {})[lang] || s);
      texts[lang] = { ticket: t.ticket, title: t.title, options: t.options, explanation: t.explanation, pddRule: t.pddRule || s.pddRule || '' };
    }
    const legendLabels = (s.legend || []).map(l => ({ ...l }));
    out.json = {
      props,
      labels,
      text: texts,
      correctAnswerIndex: s.correctAnswerIndex,
      sourceTextLength: s.title.length + s.options.reduce((n, o) => n + o.length, 0),
      legend: legendLabels,
      stopPositions: s.stopPositions || null,
      requiredStop: s.requiredStop ?? null,
      redWait: s.redWait ?? null,
      speedLimit: s.speedLimitKmH ?? null,
      id: s.id, geometry: s.geometry || null, type: s.type || null,
      centerZ: 0, startZ: r3(it.startZ - it.centerZ), stopZ: r3(it.stopZ - it.centerZ),
      playerStartX: it.playerStartX ?? null, playerStartRotY: it.playerStartRotY || 0,
      leftLane: it.leftLane, rightLane: it.rightLane, kerbZ: it.kerbZ ?? null, kerbX: it.kerbX ?? null,
      approachW: it.approachW, exitWidths: it.exitWidths || null,
      segmentLength: r3(it.seg.userData.length || 0),
      spec: { maneuver: spec.maneuver, yieldTo: spec.yieldTo, paths: spec.paths || null, pathRules: spec.pathRules || null },
      exits, trafficLights: s.trafficLights || null,
      crop: CROP,
      roadMask: { cell: CELL, x: r3(minX), z: r3(minZ - origin.z), width: W, height: H },
      questionCamera: camSamples,
      trajectories: (s.trajectories || []).map(t => ({ ...t, points: t.points.map(([x, z]) => [-x, z]) })),
    };
    return out;
  };

  window.situationCount = () => window.__eng.scenarios().length;
  window.situationIds = () => window.__eng.scenarios().map(s => s.id);
})();
