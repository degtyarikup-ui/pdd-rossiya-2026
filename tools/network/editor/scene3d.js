// The 3D view of the editor: the scene as the game draws it (road surfaces from the build,
// the baked scene, roadside props, participants and lights from their GLB models) with the
// routes, the stop line and the handles drawn over it. It reports pointer events in metres;
// what they mean (select, move, draw) is decided by ui.js.
const Scene3D = (() => {
  const KIND_COLOUR = {
    manoeuvre: 0x2f6fed, choice: 0xe0533d, approach: 0x1f9d67, actor: 0xe09a2a,
  };
  const SELECTED_BOOST = 1.45;
  const ROUTE_WIDTH = 0.7;
  const ASPHALT = 0x2c2f36, GROUND = 0xc9d2a6, WATER = 0x9fb0c4;
  const TYPE_COLOUR = { car: 0x4a7fd6, truck: 0xd98b3a, bus: 0xe8c44a, tram: 0xc94a4a, pedestrian: 0x8e5fc9,
    cyclist: 0x3ea37a, motorcycle: 0x2b2f36, special: 0xf0f0f0, van: 0x7c8a99, tanker: 0x6a7c4a, cart: 0x9a7b4f };

  let container, renderer, scene, camera, labelsEl, ground = null;
  let mode = "plan";                       // "plan" (top-down, orthographic) or "3d" (orbit)
  let pxPerM = 6, target = new THREE.Vector3(0, 0, 0), orbitYaw = 0, orbitPitch = 0.9, orbitDist = 260;
  let width = 1, height = 1, needsRender = true, frame = 0;
  let model = null, build = null, sel = null, draft = null, cursor = null, stopCursor = null;
  let groups = {}, labels = [], handlesObj = null, gltfCache = new Map(), loadToken = 0;
  const listeners = {};
  const emit = (name, data) => (listeners[name] || []).forEach((fn) => fn(data));
  const loader = new THREE.GLTFLoader();
  const tmp = new THREE.Vector3();
  const materials = new Map();

  function mat(colour, opts = {}) {
    const key = colour + JSON.stringify(opts);
    if (!materials.has(key)) materials.set(key, new THREE.MeshLambertMaterial({ color: colour, ...opts }));
    return materials.get(key);
  }

  function lineMat(colour) {
    const key = "line" + colour;
    if (!materials.has(key)) materials.set(key, new THREE.MeshBasicMaterial({ color: colour, side: THREE.DoubleSide }));
    return materials.get(key);
  }

  function circleTexture() {
    const c = document.createElement("canvas");
    c.width = c.height = 64;
    const x = c.getContext("2d");
    x.fillStyle = "#ffffff";
    x.beginPath();
    x.arc(32, 32, 26, 0, Math.PI * 2);
    x.fill();
    x.lineWidth = 6;
    x.strokeStyle = "#1d2430";
    x.stroke();
    return new THREE.CanvasTexture(c);
  }
  let circleTex = null;

  // A flat ribbon along a polyline (x, z), `width` metres wide, at height y.
  function ribbon(points, w, y) {
    const pos = [];
    for (let i = 0; i + 1 < points.length; i++) {
      const [ax, az] = points[i], [bx, bz] = points[i + 1];
      const dx = bx - ax, dz = bz - az, len = Math.hypot(dx, dz) || 1;
      const nx = (-dz / len) * (w / 2), nz = (dx / len) * (w / 2);
      pos.push(ax + nx, y, az + nz, ax - nx, y, az - nz, bx + nx, y, bz + nz,
        ax - nx, y, az - nz, bx - nx, y, bz - nz, bx + nx, y, bz + nz);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    return g;
  }

  function arrowhead(points, w, y) {
    const n = points.length;
    if (n < 2) return null;
    const [ex, ez] = points[n - 1], [sx, sz] = points[n - 2];
    const dx = ex - sx, dz = ez - sz, len = Math.hypot(dx, dz) || 1, ux = dx / len, uz = dz / len;
    const back = 1.6, side = w * 1.6;
    const bx = ex - ux * back, bz = ez - uz * back;
    const pos = [ex, y, ez, bx - uz * side, y, bz + ux * side, bx + uz * side, y, bz - ux * side];
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    return g;
  }

  function polyPoints(list, y, lift = 0) {
    return list.map((p) => new THREE.Vector3(p[0], y + lift, p[1]));
  }

  function setGroup(name) {
    if (groups[name]) {
      scene.remove(groups[name]);
      groups[name].traverse((o) => { if (o.geometry && o.userData.own) o.geometry.dispose(); });
    }
    groups[name] = new THREE.Group();
    scene.add(groups[name]);
    return groups[name];
  }

  function loadGltf(url) {
    if (!gltfCache.has(url)) {
      gltfCache.set(url, new Promise((resolve) => {
        loader.load(url, (g) => resolve(g.scene), undefined, () => resolve(null));
      }));
    }
    return gltfCache.get(url).then((root) => (root ? root.clone(true) : null));
  }

  function box(colour, size) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(size[0], size[1], size[2]), mat(colour));
    m.position.y = size[1] / 2;
    return m;
  }

  function anchorFor(kind, item) {
    const g = new THREE.Group();
    g.userData.anchor = { kind, id: item.id };
    return g;
  }

  // ---- model -------------------------------------------------------------------------

  // Detail maps of the game (game_godot/textures/detail): their red channel is the fine grain,
  // read as a grey map, with the same contrast the game uses (scenery.gd GAIN).
  const DETAIL = { asphalt: { period: 6.4, gain: 4 }, pavement: { period: 5.6, gain: 3.5 }, grass: { period: 4.8, gain: 3 } };
  const detailMaps = {};
  let detailLoaded = false;
  function loadDetail() {
    const kinds = Object.keys(DETAIL);
    Promise.all(kinds.map((kind) => new Promise((resolve) => {
      const img = new Image();
      img.onload = () => {
        const c = document.createElement("canvas");
        c.width = img.width; c.height = img.height;
        const x = c.getContext("2d");
        x.drawImage(img, 0, 0);
        const data = x.getImageData(0, 0, c.width, c.height);
        for (let i = 0; i < data.data.length; i += 4) {
          const v = Math.max(0, Math.min(1, 0.5 + (data.data[i] / 255 - 0.5) * DETAIL[kind].gain));
          data.data[i] = data.data[i + 1] = data.data[i + 2] = Math.round(v * 255);
        }
        x.putImageData(data, 0, 0);
        const tex = new THREE.CanvasTexture(c);
        tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
        tex.anisotropy = 8;
        detailMaps[kind] = tex;
        resolve();
      };
      img.onerror = resolve;
      img.src = `/asset/texture/${kind}.png`;
    }))).then(() => {
      detailLoaded = true;
      if (model) { rebuildRoads(); rebuildGround(); needsRender = true; }
    });
  }

  // A surface's colour multiplied by its detail map (the map averages to 0.5, hence x2).
  function surfaceMaterial(kind, colour) {
    const c = new THREE.Color(colour).multiplyScalar(2);
    const map = detailMaps[kind] || null;
    return new THREE.MeshLambertMaterial({ color: map ? c : new THREE.Color(colour), map, side: THREE.DoubleSide });
  }

  function rebuildGround() {
    if (!ground) return;
    const grass = detailMaps.grass;
    ground.material = grass ? surfaceMaterial("grass", GROUND) : mat(GROUND);
    if (grass) {
      grass.repeat.set(4000 / DETAIL.grass.period, 4000 / DETAIL.grass.period);
      grass.needsUpdate = true;
    }
  }

  // One material per layer of the network (build.py): asphalt, pavement, lawns (grass detail) and
  // paint (flat). Every network layer takes a polygon offset, so where a copy of the same ground
  // is left in the baked scene, the network's surface wins the depth test instead of flickering.
  const OFFSET = { polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 };
  function layerMaterial(s) {
    if (s.layer === "") return new THREE.MeshLambertMaterial({ color: s.colour, side: THREE.DoubleSide, ...OFFSET });
    const kind = s.layer === "grass" ? "grass" : s.id === "asphalt" ? "asphalt" : "pavement";
    const m = surfaceMaterial(kind, s.layer === "grass" ? "#86a97a" : s.colour);
    Object.assign(m, OFFSET);
    return m;
  }

  function rebuildRoads() {
    const g = setGroup("roads");
    if (!build) return;
    for (const s of build.surfaces) {
      if (!s.idx.length) continue;
      const kind = s.layer === "" ? null : s.layer === "grass" ? "grass" : s.id === "asphalt" ? "asphalt" : "pavement";
      const period = kind ? DETAIL[kind].period : 1;
      const geo = new THREE.BufferGeometry();
      const pos = [], uv = [];
      const verts = s.verts;
      for (let k = 0; k < s.idx.length; k++) {
        const i = s.idx[k] * 2;
        pos.push(verts[i], s.y, verts[i + 1]);
        uv.push(verts[i] / period, verts[i + 1] / period);
      }
      geo.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
      geo.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
      geo.computeVertexNormals();
      const m = new THREE.Mesh(geo, layerMaterial(s));
      m.userData.own = true;
      g.add(m);
    }
    const kerbs = build.kerbs, kc = kerbs.colour, segs = kerbs.segs;
    const pos = [];
    for (let j = 0; j < segs.length; j += 4) {
      const ax = segs[j], az = segs[j + 1], bx = segs[j + 2], bz = segs[j + 3];
      const y0 = kerbs.y0, y1 = kerbs.y1;
      pos.push(ax, y0, az, bx, y0, bz, bx, y1, bz, ax, y0, az, bx, y1, bz, ax, y1, az);
    }
    const kg = new THREE.BufferGeometry();
    kg.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    kg.computeVertexNormals();
    const km = new THREE.Mesh(kg, new THREE.MeshLambertMaterial({ color: kc, side: THREE.DoubleSide }));
    km.userData.own = true;
    g.add(km);
  }

  // The game's filter of the baked scene (game_godot/scripts/situation.gd _without_baked_ground):
  // the static mesh loses the flat triangles the network draws itself, so the editor shows what the
  // game shows. Textured meshes (the dirt overlay) are kept, as the game keeps them.
  const COVER_CELL = 5;
  function coverIndex(B) {
    const cover = new Map();
    for (const s of B.surfaces) {
      const v = s.verts;
      for (let k = 0; k + 2 < s.idx.length; k += 3) {
        const a = s.idx[k] * 2, b = s.idx[k + 1] * 2, c = s.idx[k + 2] * 2;
        const t = [v[a], v[a + 1], v[b], v[b + 1], v[c], v[c + 1]];
        const x0 = Math.min(t[0], t[2], t[4]), x1 = Math.max(t[0], t[2], t[4]);
        const z0 = Math.min(t[1], t[3], t[5]), z1 = Math.max(t[1], t[3], t[5]);
        for (let i = Math.floor(x0 / COVER_CELL); i <= Math.floor(x1 / COVER_CELL); i++) {
          for (let j = Math.floor(z0 / COVER_CELL); j <= Math.floor(z1 / COVER_CELL); j++) {
            const key = i + "," + j;
            if (!cover.has(key)) cover.set(key, []);
            cover.get(key).push(t);
          }
        }
      }
    }
    return cover;
  }
  function covered(cover, x, z) {
    for (const t of cover.get(Math.floor(x / COVER_CELL) + "," + Math.floor(z / COVER_CELL)) || []) {
      const d = (t[3] - t[5]) * (t[0] - t[4]) + (t[4] - t[2]) * (t[1] - t[5]);
      if (Math.abs(d) < 1e-12) continue;
      const w1 = ((t[3] - t[5]) * (x - t[4]) + (t[4] - t[2]) * (z - t[5])) / d;
      const w2 = ((t[5] - t[1]) * (x - t[4]) + (t[0] - t[4]) * (z - t[5])) / d;
      if (w1 >= -1e-6 && w2 >= -1e-6 && 1 - w1 - w2 >= -1e-6) return true;
    }
    return false;
  }
  function filterBaked(root, B) {
    const cover = coverIndex(B);
    root.traverse((o) => {
      if (!o.isMesh || o.name !== "static" || !o.geometry || !o.geometry.index) return;
      // The loader's cache shares geometry with its clones: filter a copy, so a redraw starts afresh.
      const geo = o.geometry = o.geometry.clone(), pos = geo.attributes.position, index = geo.index.array;
      const keep = [];
      for (let k = 0; k < index.length; k += 3) {
        const a = index[k], b = index[k + 1], c = index[k + 2];
        const ya = pos.getY(a), yb = pos.getY(b), yc = pos.getY(c);
        const flat = Math.abs(ya - yb) < 0.001 && Math.abs(ya - yc) < 0.001;
        const lo = Math.min(ya, yb, yc), hi = Math.max(ya, yb, yc);
        let drop = false;
        if (flat && ya < -0.001 && ya > -0.5) drop = true;
        else if (flat && ya > 0.17 && ya < 0.215) drop = true;
        else if (flat && ya >= -0.001 && ya < 0.035) {
          const cx = (pos.getX(a) + pos.getX(b) + pos.getX(c)) / 3, cz = (pos.getZ(a) + pos.getZ(b) + pos.getZ(c)) / 3;
          drop = covered(cover, cx, cz);
        } else if (!flat && lo > -0.02 && hi < 0.215) drop = true;
        if (!drop) keep.push(a, b, c);
      }
      geo.setIndex(keep);
    });
  }

  function rebuildStatic() {
    const g = setGroup("static");
    if (!model) return;
    const url = `/asset/scene/${model.id}/scene.glb`;
    const token = loadToken;
    loadGltf(url).then((root) => {
      if (!root || token !== loadToken || groups.static !== g) return;
      if (build) filterBaked(root, build);
      root.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
      g.add(root);
      needsRender = true;
    });
  }

  function dropLabels(cls) {
    labels = labels.filter((l) => {
      if (l.cls !== cls) return true;
      if (l.el) l.el.remove();
      return false;
    });
  }

  // What the colours mean: exits blue; the answers A, B, V... in their letter's colour (the same
  // as on the road in the game); the stop lane green; a participant's path thin and dashed orange.
  const LETTER_COLOUR = { "А": 0xe0533d, "Б": 0x8b5cf6, "В": 0x0891b2, "Г": 0xd98e04, "Д": 0x16a34a };
  const EXIT_COLOUR = 0x2f6fed, APPROACH_COLOUR = 0x16a34a, ACTOR_COLOUR = 0xe09a2a;
  const ROUTE_LIFT = 0.12;
  const lineMaterials = new Set();
  let hoverId = null;

  // Answers and participant paths run alongside the exit lanes they share a road with, a little
  // to either side, so every route can be seen and picked. The data keeps the true points.
  const SIDE = { choice: 0.35, actor: -0.35 };
  function routeOffset(r, i) {
    const side = SIDE[r.kind];
    if (!side) return [0, 0];
    const pts = r.points;
    const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
    const dx = b[0] - a[0], dz = b[1] - a[1], len = Math.hypot(dx, dz) || 1;
    return [(-dz / len) * side, (dx / len) * side];
  }
  function displayPoints(r) {
    return r.points.map((p, i) => {
      const o = routeOffset(r, i);
      return [p[0] + o[0], p[1] + o[1]];
    });
  }

  function routeStyle(r) {
    if (r.kind === "manoeuvre") return { colour: EXIT_COLOUR, px: r.exit === model?.question?.maneuver ? 3 : 2 };
    if (r.kind === "choice") return { colour: LETTER_COLOUR[r.label] || EXIT_COLOUR, px: 2.5 };
    if (r.kind === "approach") return { colour: APPROACH_COLOUR, px: 3 };
    return { colour: ACTOR_COLOUR, px: 1.5, dashed: true };
  }

  function lineMaterialFor(style, opacity) {
    const m = new THREE.LineMaterial({
      color: style.colour, linewidth: style.px, transparent: true, opacity,
      dashed: !!style.dashed, dashScale: 1, dashSize: 0.9, gapSize: 0.6,
      resolution: new THREE.Vector2(width, height),
    });
    lineMaterials.add(m);
    return m;
  }

  // Which route the attention is on: the selected one (or the participant's own path), else the
  // one under the pointer. Every other route is faded so the chosen one reads clearly.
  function focusRoute() {
    if (sel && sel.t === "route") return sel.id;
    if (sel && sel.t === "actor") return `actor_${sel.id}`;
    return hoverId;
  }

  function rebuildRoutes() {
    const g = setGroup("routes");
    dropLabels("route");
    if (!model) return;
    const focus = focusRoute();
    for (const r of model.routes) {
      const style = routeStyle(r);
      const dim = focus && r.id !== focus;
      const opacity = dim ? 0.22 : 1;
      const shown = displayPoints(r);
      const flat = [];
      shown.forEach((p) => flat.push(p[0], ROUTE_LIFT, p[1]));
      const geo = new THREE.LineGeometry();
      geo.setPositions(flat);
      const line = new THREE.Line2(geo, lineMaterialFor(style, opacity));
      if (style.dashed) line.computeLineDistances();
      line.userData = { own: true, routeId: r.id };
      g.add(line);
      const head = arrowhead(shown, dim ? 0.3 : 0.45, ROUTE_LIFT);
      if (head) {
        const hm = new THREE.Mesh(head, new THREE.MeshBasicMaterial({ color: style.colour, transparent: true, opacity, side: THREE.DoubleSide }));
        hm.userData.own = true;
        g.add(hm);
      }
      const name = routeName(r);
      if (name && shown.length > 1 && !dim) {
        const mid = shown[Math.floor(shown.length / 2)];
        labels.push({ text: name, colour: style.colour, world: [mid[0], 0.6, mid[1]], cls: "route", anchor: { kind: "route", id: r.id } });
      }
    }
    if (draft && draft.points.length) {
      const pts = draft.cursor ? [...draft.points, draft.cursor] : draft.points;
      const geo = new THREE.LineGeometry();
      geo.setPositions(pts.flatMap((p) => [p[0], ROUTE_LIFT, p[1]]));
      const line = new THREE.Line2(geo, lineMaterialFor({ colour: 0x6b7685, px: 1.5, dashed: true }, 1));
      line.computeLineDistances();
      line.userData.own = true;
      g.add(line);
    }
  }

  function routeName(r) {
    if (r.kind === "manoeuvre") return { left: "налево", right: "направо", straight: "прямо", uturn: "разворот" }[r.exit] || "";
    if (r.kind === "choice") return r.label;
    if (r.kind === "approach") return "подъезд";
    const a = model && model.actors.find((x) => x.route === r.id);
    return a ? (a.name || a.id) : "путь";
  }

  function rebuildAnchors() {
    const g = setGroup("anchors");
    if (!model) return;
    const stop = model.stop;
    // stop line: a bar across the lane and an arrow for the driving direction
    const sg = anchorFor("stop", { id: "stop" });
    sg.position.set(stop.x, 0, stop.z);
    sg.rotation.y = stop.yaw;
    const bar = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.05, 0.5), mat(0xe8e8e8));
    bar.position.set(0, 0.12, 0);
    sg.add(bar);
    sg.add(box(0xf6c744, [0.5, 0.25, 1.2]).translateZ(-0.5));
    g.add(sg);
    labels.push({ text: "стоп / старт", colour: 0x7b5cd6, world: [stop.x, 1.8, stop.z], cls: "stop", anchor: { kind: "stop", id: "stop" } });

    for (const l of model.lights) {
      const lg = anchorFor("light", l);
      lg.position.set(l.pos[0], 0, l.pos[1]);
      lg.rotation.y = l.yaw;
      lg.scale.setScalar(l.scale || 1);
      g.add(lg);
      const fallback = box(0x3a3f47, [0.3, 3.4, 0.3]);
      lg.add(fallback);
      const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.22, 12, 8), mat(lampColour(l.state)));
      lamp.position.y = 3.2;
      lg.add(lamp);
      const url = `/asset/scene/${l.asset}`;
      if (l.asset) {
        loadGltf(url).then((root) => {
          if (!root || groups.anchors !== g) return;
          lg.remove(fallback, lamp);
          lg.add(root);
          needsRender = true;
        });
      }
      labels.push({ text: "светофор", colour: 0x6b5a10, world: [l.pos[0], 4.2, l.pos[1]], cls: "light", anchor: { kind: "light", id: l.id } });
    }

    for (const d of model.decor) {
      const dg = anchorFor("decor", d);
      dg.position.set(d.pos[0], 0, d.pos[1]);
      dg.rotation.y = d.yaw;
      dg.scale.set(d.scale[0], d.scale[1], d.scale[2]);
      g.add(dg);
      const fallback = box(0xb9b4ab, [2, 3, 2]);
      dg.add(fallback);
      // A parked car is the traffic sedan model in the game (scripts/situation.gd).
      const modelUrl = d.prop === "parked" ? "/asset/models/traffic/sedan.glb" : `/asset/scenery/${d.prop}.glb`;
      loadGltf(modelUrl).then((root) => {
        if (!root || groups.anchors !== g) return;
        dg.remove(fallback);
        if (d.tint) {
          root.traverse((o) => {
            if (o.isMesh && o.material && o.material.color) {
              o.material = o.material.clone();
              o.material.color.set(d.tint);
            }
          });
        }
        dg.add(root);
        needsRender = true;
      });
    }

    for (const a of model.actors) {
      const ag = anchorFor("actor", a);
      ag.position.set(a.pos[0], 0, a.pos[1]);
      ag.rotation.y = a.yaw;
      ag.scale.set(a.scale[0], a.scale[1], a.scale[2]);
      g.add(ag);
      const colour = TYPE_COLOUR[a.type] || 0x888888;
      const fallback = box(colour, [a.type === "pedestrian" ? 0.6 : 1.9, a.type === "pedestrian" ? 1.7 : 1.4, a.type === "pedestrian" ? 0.6 : 4.2]);
      ag.add(fallback);
      loadGltf(`/asset/scene/${a.asset}`).then((root) => {
        if (!root || groups.anchors !== g) return;
        ag.remove(fallback);
        ag.add(root);
        needsRender = true;
      });
      labels.push({ text: a.name || a.type, colour: 0x1d2430, world: [a.pos[0], 3.2, a.pos[1]], cls: "actor", anchor: { kind: "actor", id: a.id } });
    }
  }

  function lampColour(state) {
    return { red: 0xff3b30, yellow: 0xffcc00, green: 0x34c759, flashing_yellow: 0xffcc00 }[state] || 0x555555;
  }

  function rebuildHandles() {
    if (handlesObj) { scene.remove(handlesObj); handlesObj.geometry.dispose(); handlesObj = null; }
    if (!model || !sel) return;
    const pts = [];
    const selPoints = pointsOf(sel);
    selPoints.forEach((p) => pts.push(p[0], 0.4, p[1]));
    if (!pts.length) return;
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(pts, 3));
    if (!circleTex) circleTex = circleTexture();
    const m = new THREE.Points(g, new THREE.PointsMaterial({ size: 11, sizeAttenuation: false, map: circleTex, transparent: true, alphaTest: 0.3, color: 0xffffff }));
    m.renderOrder = 10;
    handlesObj = m;
    scene.add(m);
  }

  // The points of the selected object (route, road or lawn ring, a marking's line), as [x, z].
  function pointsOf(s) {
    if (!model || !s) return [];
    if (s.t === "route") {
      const r = model.routes.find((x) => x.id === s.id);
      return r ? displayPoints(r) : [];
    }
    if (s.t === "road") {
      const r = model.roads[s.i];
      if (!r) return [];
      return s.part === -1 ? r.outer : (r.holes[s.part] || []);
    }
    if (s.t === "lawn") {
      const l = (model.lawns || [])[s.i];
      if (!l) return [];
      return s.part === -1 ? l.outer : (l.holes[s.part] || []);
    }
    if (s.t === "marking") {
      const m = (model.markings || []).find((x) => x.id === s.id);
      return m && m.points ? m.points : [];
    }
    return [];
  }

  // ---- public ------------------------------------------------------------------------

  function mount(el) {
    container = el;
    renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
    renderer.setClearColor(0xe6ebdf, 1);
    el.appendChild(renderer.domElement);
    labelsEl = document.getElementById("labels");
    scene = new THREE.Scene();
    scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8f78, 0.9));
    const sun = new THREE.DirectionalLight(0xffffff, 0.55);
    sun.position.set(-40, 120, 60);
    scene.add(sun);
    ground = new THREE.Mesh(new THREE.PlaneGeometry(4000, 4000), mat(GROUND));
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -0.15;   // the world's lawn (game_godot/scripts/world.gd), under the junction's own lawn
    scene.add(ground);
    loadDetail();
    camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 5000);
    resize();
    new ResizeObserver(resize).observe(el);
    bindPointer();
    loop();
  }

  function resize() {
    if (!container) return;
    width = container.clientWidth || 1;
    height = container.clientHeight || 1;
    renderer.setSize(width, height);
    lineMaterials.forEach((m) => m.resolution.set(width, height));
    applyCamera();
    needsRender = true;
  }

  function applyCamera() {
    if (mode === "plan") {
      const hw = width / 2 / pxPerM, hh = height / 2 / pxPerM;
      camera = camera.isOrthographicCamera ? camera : new THREE.OrthographicCamera();
      camera.left = -hw; camera.right = hw; camera.top = hh; camera.bottom = -hh;
      camera.near = 0.1; camera.far = 5000;
      camera.updateProjectionMatrix();
      camera.position.set(target.x, 1000, target.z);
      camera.up.set(0, 0, 1);
      camera.lookAt(target.x, 0, target.z);
    } else {
      if (!camera.isPerspectiveCamera) camera = new THREE.PerspectiveCamera(40, width / height, 0.5, 5000);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      const cp = Math.cos(orbitPitch), sp = Math.sin(orbitPitch);
      camera.position.set(target.x + Math.sin(orbitYaw) * cp * orbitDist, sp * orbitDist, target.z + Math.cos(orbitYaw) * cp * orbitDist);
      camera.up.set(0, 1, 0);
      camera.lookAt(target.x, 0, target.z);
    }
    camera.updateMatrixWorld();
    needsRender = true;
  }

  function loop() {
    requestAnimationFrame(loop);
    if (!needsRender) return;
    needsRender = false;
    frame++;
    renderer.render(scene, camera);
    placeLabels();
  }

  // Labels keep apart: the selected object, then the stop, participants and lights, then the
  // route names; a label that would sit on another one is hidden (its object stays visible).
  const LABEL_PRIORITY = { stop: 0, actor: 1, light: 2, route: 3 };
  function placeLabels() {
    if (!labelsEl) return;
    const show = mode === "plan" ? pxPerM >= 1.2 : true;
    const placed = [];
    const isSel = (l) => !!(sel && l.anchor && sel.t === l.anchor.kind && sel.id === l.anchor.id);
    const order = labels.slice().sort((a, b) => (isSel(b) - isSel(a)) || ((LABEL_PRIORITY[a.cls] ?? 9) - (LABEL_PRIORITY[b.cls] ?? 9)));
    order.forEach((l) => {
      if (!l.el) {
        l.el = document.createElement("div");
        l.el.className = "tag " + (l.cls || "");
        l.el.textContent = l.text;
        l.el.style.setProperty("--c", "#" + new THREE.Color(l.colour || 0x1d2430).getHexString());
        labelsEl.appendChild(l.el);
      }
      tmp.set(l.world[0], l.world[1], l.world[2]).project(camera);
      const x = (tmp.x + 1) / 2 * width, y = (1 - tmp.y) / 2 * height;
      const w = l.text.length * 6.6 + 14, h = 19;
      const box = { x0: x + 6, y0: y - h / 2 - 8, x1: x + 6 + w, y1: y + h / 2 - 8 };
      const clash = placed.some((b) => box.x0 < b.x1 && box.x1 > b.x0 && box.y0 < b.y1 && box.y1 > b.y0);
      const inside = x > -40 && x < width + 40 && y > -20 && y < height + 20;
      const visible = show && tmp.z < 1 && inside && (isSel(l) || !clash);
      if (visible) placed.push(box);
      l.el.style.display = visible ? "" : "none";
      l.el.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`;
      l.el.classList.toggle("sel", isSel(l));
    });
  }

  function clearLabels() {
    labels.forEach((l) => l.el && l.el.remove());
    labels = [];
  }

  function load(S, B) {
    loadToken++;
    model = S; build = B;
    clearLabels();
    rebuildStatic();
    rebuildRoads();
    rebuildRoutes();
    rebuildAnchors();
    rebuildHandles();
    if (!S) return;
    fit();
  }

  function refresh(S) {
    if (S) model = S;
    clearLabels();
    rebuildRoutes();
    rebuildAnchors();
    rebuildHandles();
    needsRender = true;
  }

  function setBuild(B) {
    build = B;
    rebuildRoads();
    needsRender = true;
  }

  function setSelection(s) {
    sel = s;
    rebuildRoutes();
    rebuildHandles();
    labels.forEach((l) => { if (l.el) l.el.classList.toggle("sel", !!(sel && l.anchor && sel.t === l.anchor.kind && sel.id === l.anchor.id)); });
    needsRender = true;
  }

  function setDraft(d) {
    draft = d;
    rebuildRoutes();
    needsRender = true;
  }

  function setMode(m) {
    mode = m;
    applyCamera();
    emit("mode", m);
  }

  // Centres the plan on a point (metres) without changing the zoom.
  function focus(x, z) {
    target.set(x, 0, z);
    applyCamera();
    emit("zoom", pxPerM);
  }

  function fit() {
    target.set(0, 0, 0);
    pxPerM = Math.min(width, height) / 190;
    orbitDist = 260;
    applyCamera();
    emit("zoom", pxPerM);
  }

  function zoomBy(f, at) {
    if (mode === "plan") {
      const before = at ? worldAt(at.x, at.y) : null;
      pxPerM = Math.max(0.8, Math.min(60, pxPerM * f));
      applyCamera();
      if (before && at) {
        const after = worldAt(at.x, at.y);
        target.x += before.x - after.x;
        target.z += before.z - after.z;
        applyCamera();
      }
    } else {
      orbitDist = Math.max(40, Math.min(900, orbitDist / f));
      applyCamera();
    }
    emit("zoom", pxPerM);
  }

  // World (x, z) at a screen point (plan mode and the ground plane in 3D).
  function worldAt(sx, sy) {
    const ndc = new THREE.Vector2((sx / width) * 2 - 1, -(sy / height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, camera);
    const hit = new THREE.Vector3();
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    if (!ray.ray.intersectPlane(plane, hit)) return null;
    return { x: hit.x, z: hit.z };
  }

  function screenOf(x, z, y = 0) {
    tmp.set(x, y, z).project(camera);
    return { x: (tmp.x + 1) / 2 * width, y: (1 - tmp.y) / 2 * height };
  }

  // What is under the pointer, in order of priority: the selected object's handles, anchors
  // (stop, lights, participants, props), route and outline lines, the inside of a road.
  function hitAt(sx, sy) {
    if (!model) return null;
    let best = null, bd = 10;
    for (const p of pointsOf(sel)) {
      const s = screenOf(p[0], p[1], 0.4);
      const d = Math.hypot(s.x - sx, s.y - sy);
      if (d < bd) { bd = d; best = { kind: "vertex", owner: { ...sel }, index: pointsOf(sel).indexOf(p) }; }
    }
    if (best) return best;
    const anchors = [{ kind: "stop", id: "stop", x: model.stop.x, z: model.stop.z }];
    model.lights.forEach((l) => anchors.push({ kind: "light", id: l.id, x: l.pos[0], z: l.pos[1] }));
    model.actors.forEach((a) => anchors.push({ kind: "actor", id: a.id, x: a.pos[0], z: a.pos[1] }));
    model.decor.forEach((d) => anchors.push({ kind: "decor", id: d.id, x: d.pos[0], z: d.pos[1] }));
    bd = 16;
    for (const a of anchors) {
      const s = screenOf(a.x, a.z, 0.5);
      const d = Math.hypot(s.x - sx, s.y - sy) - (a.kind === "decor" ? 4 : 0);
      if (d < bd) { bd = d; best = { kind: "anchor", t: a.kind, id: a.id }; }
    }
    if (best) return best;
    const lines = [];
    model.routes.forEach((r) => lines.push({ kind: "route", id: r.id, points: displayPoints(r) }));
    model.roads.forEach((r, i) => {
      lines.push({ kind: "road", i, part: -1, points: r.outer });
      r.holes.forEach((h, k) => lines.push({ kind: "road", i, part: k, points: h }));
    });
    (model.lawns || []).forEach((l, i) => {
      lines.push({ kind: "lawn", i, part: -1, points: l.outer });
      l.holes.forEach((h, k) => lines.push({ kind: "lawn", i, part: k, points: h }));
    });
    (model.markings || []).forEach((m) => { if (m.points) lines.push({ kind: "marking", id: m.id, points: m.points }); });
    bd = 7;
    for (const l of lines) {
      for (let k = 0; k + 1 < l.points.length; k++) {
        const a = screenOf(l.points[k][0], l.points[k][1]), b = screenOf(l.points[k + 1][0], l.points[k + 1][1]);
        const d = segDist(sx, sy, a, b);
        if (d < bd) {
          bd = d;
          if (l.kind === "route") best = { kind: "route", id: l.id, seg: k };
          else if (l.kind === "marking") best = { kind: "marking", id: l.id, seg: k };
          else best = { kind: l.kind, i: l.i, part: l.part, seg: k };
        }
      }
    }
    if (best) return best;
    const w = worldAt(sx, sy);
    if (w) {
      for (let i = (model.lawns || []).length - 1; i >= 0; i--) {
        const l = model.lawns[i];
        if (inside(w, l.outer) && !l.holes.some((h) => inside(w, h))) return { kind: "lawn", i, part: -1 };
      }
      for (let i = model.roads.length - 1; i >= 0; i--) {
        const r = model.roads[i];
        if (inside(w, r.outer) && !r.holes.some((h) => inside(w, h))) return { kind: "road", i, part: -1 };
      }
    }
    return null;
  }

  function segDist(px, py, a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy || 1;
    const t = Math.max(0, Math.min(1, ((px - a.x) * dx + (py - a.y) * dy) / l2));
    return Math.hypot(px - (a.x + t * dx), py - (a.y + t * dy));
  }

  function inside(p, poly) {
    let c = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const [xi, zi] = poly[i], [xj, zj] = poly[j];
      if ((zi > p.z) !== (zj > p.z) && p.x < ((xj - xi) * (p.z - zi)) / (zj - zi) + xi) c = !c;
    }
    return c;
  }

  function bindPointer() {
    const el = renderer.domElement;
    let down = null, panning = false, last = null;
    const local = (e) => { const r = el.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const snapWorld = (w, e) => (e.altKey ? w : { x: Math.round(w.x * 20) / 20, z: Math.round(w.z * 20) / 20 });
    el.addEventListener("contextmenu", (e) => e.preventDefault());
    el.addEventListener("pointerdown", (e) => {
      const p = local(e);
      last = p;
      const w = worldAt(p.x, p.y);
      if (e.button === 1 || e.button === 2 || (e.button === 0 && spaceDown)) {
        panning = true;
        el.setPointerCapture(e.pointerId);
        return;
      }
      if (e.button !== 0) return;
      down = { x: p.x, y: p.y, hit: hitAt(p.x, p.y), t: performance.now() };
      el.setPointerCapture(e.pointerId);
      emit("pointer", { type: "down", world: w && snapWorld(w, e), hit: down.hit, shift: e.shiftKey, alt: e.altKey, native: e });
    });
    el.addEventListener("pointermove", (e) => {
      const p = local(e);
      if (panning && last) {
        const dx = p.x - last.x, dy = p.y - last.y;
        if (mode === "plan") {
          const w0 = worldAt(last.x, last.y), w1 = worldAt(p.x, p.y);
          if (w0 && w1) { target.x += w0.x - w1.x; target.z += w0.z - w1.z; }
        } else if (e.buttons & 2) {
          orbitYaw -= dx * 0.008;
          orbitPitch = Math.max(0.15, Math.min(1.5, orbitPitch + dy * 0.008));
        } else {
          target.x -= dx * orbitDist * 0.0016 * Math.cos(orbitYaw) + dy * orbitDist * 0.0016 * Math.sin(orbitYaw);
          target.z += dx * orbitDist * 0.0016 * Math.sin(orbitYaw) - dy * orbitDist * 0.0016 * Math.cos(orbitYaw);
        }
        last = p;
        applyCamera();
        return;
      }
      last = p;
      const w = worldAt(p.x, p.y);
      if (!down) {
        // Hovering a route fades the others, so the one under the pointer can be followed.
        const h = hitAt(p.x, p.y);
        const id = h && h.kind === "route" ? h.id : null;
        if (id !== hoverId) { hoverId = id; rebuildRoutes(); needsRender = true; }
      }
      emit("pointer", { type: "move", world: w && snapWorld(w, e), buttons: e.buttons, shift: e.shiftKey, alt: e.altKey, native: e });
      if (down && Math.hypot(p.x - down.x, p.y - down.y) > 3) {
        emit("pointer", { type: "drag", world: w && snapWorld(w, e), hit: down.hit, start: down, shift: e.shiftKey, alt: e.altKey, native: e });
        down.dragging = true;
      }
    });
    el.addEventListener("pointerup", (e) => {
      if (panning) { panning = false; return; }
      if (!down) return;
      const p = local(e);
      const w = worldAt(p.x, p.y);
      emit("pointer", { type: "up", world: w && snapWorld(w, e), hit: down.hit, dragged: !!down.dragging, shift: e.shiftKey, alt: e.altKey, native: e });
      down = null;
    });
    el.addEventListener("dblclick", (e) => {
      const p = local(e);
      const w = worldAt(p.x, p.y);
      emit("pointer", { type: "dblclick", world: w && snapWorld(w, e), hit: hitAt(p.x, p.y), native: e });
    });
    el.addEventListener("wheel", (e) => {
      e.preventDefault();
      zoomBy(Math.exp(-e.deltaY * 0.0012), local(e));
    }, { passive: false });
    el.addEventListener("pointerleave", () => emit("pointer", { type: "leave" }));
  }

  let spaceDown = false;
  window.addEventListener("keydown", (e) => { if (e.code === "Space" && !isTyping(e)) { spaceDown = true; } });
  window.addEventListener("keyup", (e) => { if (e.code === "Space") spaceDown = false; });
  function isTyping(e) { const t = e.target; return t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT" || t.isContentEditable); }

  return {
    mount, load, refresh, setBuild, setSelection, setDraft, setMode, fit, focus, zoomBy, worldAt, screenOf,
    on(name, fn) { (listeners[name] = listeners[name] || []).push(fn); },
    get mode() { return mode; },
    get pxPerM() { return pxPerM; },
    get spaceDown() { return spaceDown; },
    requestRender() { needsRender = true; },
    pointsOf,
    hitAt, routeOffset,
  };
})();
