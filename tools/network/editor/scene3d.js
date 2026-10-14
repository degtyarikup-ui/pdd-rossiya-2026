// The editor's view: the scene as the game draws it (road surfaces from the build, the baked scene's
// ground, props, participants and lights from their models), with the routes, the road plan's handles,
// the selection and the object being placed drawn over it. It moves the camera itself (orbit, pan, zoom)
// and reports the rest of the pointer to tools.js in metres; what a click means is decided there.
//
// Plan view: +z (the player's way) is up and +x (the driver's left) is on the left, the way a driver
// sees the road ahead. The 3D view starts behind the player.
const Scene3D = (() => {
  const ASPHALT = 0x2c2f36, GROUND = 0xc9d2a6;
  const ACCENT = 0x0574f8, HOVER = 0x5aa2ff;
  const TYPE_COLOUR = { car: 0x4a7fd6, truck: 0xd98b3a, bus: 0xe8c44a, tram: 0xc94a4a, pedestrian: 0x8e5fc9,
    cyclist: 0x3ea37a, motorcycle: 0x2b2f36, special: 0xf0f0f0, van: 0x7c8a99, tanker: 0x6a7c4a, cart: 0x9a7b4f };
  const LETTER_COLOUR = { "А": 0xe0533d, "Б": 0x8b5cf6, "В": 0x0891b2, "Г": 0xd98e04, "Д": 0x16a34a };
  const EXIT_COLOUR = 0x0574f8, APPROACH_COLOUR = 0x16a34a, ACTOR_COLOUR = 0xe09a2a;
  const ROUTE_Y = 0.12;

  let container, renderer, scene, camera, labelsEl;
  let mode = "3d";
  let pxPerM = 6, target = new THREE.Vector3(0, 0, 0), orbitYaw = Math.PI, orbitPitch = 0.95, orbitDist = 240;
  let width = 1, height = 1, needsRender = true;
  let model = null, build = null, sel = [], hover = null, draft = null, hidden = new Set(), planHandles = true;
  let groups = {}, labels = [], loadToken = 0, simMode = false, follow = null;
  const anchors = new Map();      // key "t:id" -> { group, sig }
  const gltfCache = new Map();
  const listeners = {};
  const emit = (name, data) => (listeners[name] || []).forEach((fn) => fn(data));
  const loader = new THREE.GLTFLoader();
  const tmp = new THREE.Vector3();
  const materials = new Map();
  const keyOf = (r) => r ? `${r.t}:${r.id ?? ""}${r.part !== undefined && r.part >= 0 ? ":" + r.part : ""}` : "";

  function mat(colour, opts = {}) {
    const key = colour + JSON.stringify(opts);
    if (!materials.has(key)) materials.set(key, new THREE.MeshLambertMaterial({ color: colour, ...opts }));
    return materials.get(key);
  }
  function basic(colour, opts = {}) {
    const key = "b" + colour + JSON.stringify(opts);
    if (!materials.has(key)) materials.set(key, new THREE.MeshBasicMaterial({ color: colour, side: THREE.DoubleSide, ...opts }));
    return materials.get(key);
  }

  function setGroup(name) {
    if (groups[name]) {
      scene.remove(groups[name]);
      groups[name].traverse((o) => { if (o.geometry && o.userData.own) o.geometry.dispose(); });
    }
    groups[name] = new THREE.Group();
    groups[name].visible = !hidden.has(GROUP_LAYER[name] || "");
    scene.add(groups[name]);
    return groups[name];
  }
  // Which layer of the layers panel a drawing group belongs to (its eye hides it).
  const GROUP_LAYER = { static: "roads", roads: "roads", marks: "marks", routes: "routes", plan: "roads" };

  function loadGltf(url) {
    if (!gltfCache.has(url)) {
      gltfCache.set(url, new Promise((resolve) => {
        loader.load(url, (g) => resolve(g.scene), undefined, () => resolve(null));
      }));
    }
    return gltfCache.get(url).then((root) => (root ? root.clone(true) : null));
  }

  // ---- textures: the game's detail shading (game_godot/shaders/scenery.gdshader) -------------
  const TEXTURE_KINDS = ["asphalt", "pavement", "grass", "dirt"];
  const GRASS_COLOUR = "#86a97a";
  const texParams = {}, texMaps = {}, texUniforms = {};
  const DETAIL_SHADE = `{
    float fine = 0.5 + (texture2D(map, vUv).r - 0.5) * uGain;
    float large = 0.5 + (texture2D(map, vUv * uMacroScale + vec2(0.31, 0.17)).g - 0.5) * uGain;
    diffuseColor.rgb *= fine * 2.0 * (1.0 + (large * 2.0 - 1.0) * uMacro);
  }`;
  function uniformsOf(kind) {
    if (!texUniforms[kind]) {
      const p = texParams[kind] || { gain: 1, macro: 0, macroScale: 1 };
      texUniforms[kind] = { uGain: { value: p.gain }, uMacro: { value: p.macro }, uMacroScale: { value: p.macroScale } };
    }
    return texUniforms[kind];
  }
  const periodOf = (kind) => (texParams[kind] && texParams[kind].period) || 1;
  function pictureFor(kind) {
    if (!texMaps[kind]) {
      const t = new THREE.Texture();
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      t.anisotropy = 8;
      texMaps[kind] = t;
      loadPicture(kind);
    }
    return texMaps[kind];
  }
  function loadPicture(kind, src) {
    const img = new Image();
    img.onload = () => { texMaps[kind].image = img; texMaps[kind].needsUpdate = true; needsRender = true; };
    img.src = src || `/asset/texture/${kind}.png?v=${Date.now()}`;
  }
  function detailMaterial(kind, colour) {
    const u = uniformsOf(kind);
    const m = new THREE.MeshLambertMaterial({ color: colour, map: pictureFor(kind), side: THREE.DoubleSide });
    m.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, u);
      shader.fragmentShader = shader.fragmentShader
        .replace("void main() {", "uniform float uGain;\nuniform float uMacro;\nuniform float uMacroScale;\nvoid main() {")
        .replace("#include <map_fragment>", DETAIL_SHADE);
    };
    return m;
  }
  function setTextures(params) {
    const before = TEXTURE_KINDS.map(periodOf);
    for (const kind of TEXTURE_KINDS) {
      if (!params[kind]) continue;
      texParams[kind] = { ...params[kind] };
      const u = uniformsOf(kind);
      u.uGain.value = params[kind].gain;
      u.uMacro.value = params[kind].macro;
      u.uMacroScale.value = params[kind].macroScale;
    }
    if (!scene) return;
    if (TEXTURE_KINDS.some((k, i) => periodOf(k) !== before[i])) { rebuildRoads(); rebuildGround(); }
    needsRender = true;
  }
  // A picture changed (a file, or a style tried out before it is applied): src is a data URL or nothing.
  function reloadPicture(kind, src) { if (texMaps[kind]) loadPicture(kind, src); }

  let ground = null;
  function rebuildGround() {
    if (!ground) return;
    ground.material = detailMaterial("grass", GRASS_COLOUR);
    const k = 4000 / periodOf("grass");
    ground.geometry.dispose();
    ground.geometry = new THREE.PlaneGeometry(4000, 4000);
    const uv = ground.geometry.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * k, uv.getY(i) * k);
  }

  const OFFSET = { polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 };
  function dirtColour(surface) {
    const soil = new THREE.Color("#6f5840");
    const band = /^sand_join_(\d+)$/.exec(surface.id || "");
    return band ? new THREE.Color("#2c2f36").lerp(soil, (Number(band[1]) + 0.5) / 12) : soil;
  }
  function layerMaterial(s) {
    if (s.layer === "") return new THREE.MeshLambertMaterial({ color: s.colour, side: THREE.DoubleSide, ...OFFSET });
    const kind = s.layer === "sand" ? "dirt" : s.layer === "grass" ? "grass" : s.id === "asphalt" ? "asphalt" : "pavement";
    const m = detailMaterial(kind, s.layer === "sand" ? dirtColour(s) : s.layer === "grass" ? GRASS_COLOUR : s.colour);
    Object.assign(m, OFFSET);
    return m;
  }

  function surfaceMesh(s) {
    const kind = s.layer === "" ? null : s.layer === "sand" ? "dirt" : s.layer === "grass" ? "grass" : s.id === "asphalt" ? "asphalt" : "pavement";
    const period = kind ? periodOf(kind) : 1;
    const pos = [], uv = [];
    for (let k = 0; k < s.idx.length; k++) {
      const i = s.idx[k] * 2;
      pos.push(s.verts[i], s.y, s.verts[i + 1]);
      uv.push(s.verts[i] / period, s.verts[i + 1] / period);
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    geo.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
    geo.computeVertexNormals();
    const m = new THREE.Mesh(geo, layerMaterial(s));
    m.userData.own = true;
    return m;
  }

  function rebuildRoads() {
    const g = setGroup("roads");
    const mk = setGroup("marks");
    if (!build) return;
    for (const s of build.surfaces) {
      if (!s.idx.length) continue;
      (s.layer === "" ? mk : g).add(surfaceMesh(s));
    }
    const kerbs = build.kerbs, segs = kerbs.segs, pos = [];
    for (let j = 0; j < segs.length; j += 4) {
      const ax = segs[j], az = segs[j + 1], bx = segs[j + 2], bz = segs[j + 3];
      pos.push(ax, kerbs.y0, az, bx, kerbs.y0, bz, bx, kerbs.y1, bz, ax, kerbs.y0, az, bx, kerbs.y1, bz, ax, kerbs.y1, az);
    }
    const kg = new THREE.BufferGeometry();
    kg.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
    kg.computeVertexNormals();
    const km = new THREE.Mesh(kg, new THREE.MeshLambertMaterial({ color: kerbs.colour, side: THREE.DoubleSide }));
    km.userData.own = true;
    g.add(km);
  }

  // The game's filter of the baked scene (situation.gd _without_baked_ground): the static mesh keeps only
  // the flat ground the network does not draw itself.
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
      if (!o.isMesh || !o.geometry) return;
      // tex_0: dirt strips the game does not draw (situation.gd).
      if (o.name === "tex_0" || (model && (model.bakedSigns || []).includes(o.name))) { o.visible = false; return; }
      const textureGround = o.name.startsWith("tex_");
      if (o.name !== "static" && !textureGround) return;
      const geo = o.geometry = o.geometry.clone(), pos = geo.attributes.position;
      o.userData.own = true;
      const index = geo.index?.array || Array.from({length:pos.count}, (_, i) => i);
      const keep = [];
      for (let k = 0; k < index.length; k += 3) {
        const a = index[k], b = index[k + 1], c = index[k + 2];
        const ya = pos.getY(a), yb = pos.getY(b), yc = pos.getY(c);
        const flat = Math.abs(ya - yb) < 0.001 && Math.abs(ya - yc) < 0.001;
        const lo = Math.min(ya, yb, yc), hi = Math.max(ya, yb, yc);
        let drop = false;
        if (textureGround) {
          const cx = (pos.getX(a) + pos.getX(b) + pos.getX(c)) / 3, cz = (pos.getZ(a) + pos.getZ(b) + pos.getZ(c)) / 3;
          drop = flat && ya >= -0.001 && ya < 0.035 && covered(cover, cx, cz);
        } else if (flat && ya < -0.001 && ya > -0.5) drop = true;
        else if (flat && ya > 0.17 && ya < 0.215) drop = true;
        else if (flat && ya >= -0.001 && ya < 0.035) {
          const cx = (pos.getX(a) + pos.getX(b) + pos.getX(c)) / 3, cz = (pos.getZ(a) + pos.getZ(b) + pos.getZ(c)) / 3;
          drop = covered(cover, cx, cz);
        } else if (!flat && lo > -0.02 && hi < 0.215) drop = true;
        else if (!flat && (hi >= 0.215 || lo <= -0.05)) drop = true;
        else if (flat && ya >= 0.215) drop = true;
        else if (ya < -0.05) drop = true;
        if (!drop) keep.push(a, b, c);
      }
      geo.setIndex(keep);
    });
  }
  function rebuildStatic() {
    const g = setGroup("static");
    if (!model) return;
    // A pending preview has no coverage map yet. Never show the raw legacy
    // scene: it includes terrain and furniture outside the editable layers.
    if (!build) return;
    const token = loadToken;
    if (model.id === "mini_regulator") return;
    loadGltf(`/asset/scene/${model.id}/scene.glb`).then((root) => {
      if (!root || token !== loadToken || groups.static !== g) return;
      if (build) filterBaked(root, build);
      g.add(root);
      needsRender = true;
    });
  }

  // ---- routes ----------------------------------------------------------------------------
  const lineMaterials = new Set();
  function lineMat(colour, px, opacity = 1, dashed = false) {
    const m = new THREE.LineMaterial({ color: colour, linewidth: px, transparent: opacity < 1, opacity, dashed,
      dashScale: 1, dashSize: 0.9, gapSize: 0.6, resolution: new THREE.Vector2(width, height) });
    lineMaterials.add(m);
    return m;
  }
  function polyline(points, y, colour, px, opacity = 1, dashed = false) {
    const geo = new THREE.LineGeometry();
    geo.setPositions(points.flatMap((p) => [p[0], y, p[1]]));
    const line = new THREE.Line2(geo, lineMat(colour, px, opacity, dashed));
    if (dashed) line.computeLineDistances();
    line.userData.own = true;
    line.renderOrder = 5;
    return line;
  }

  // Catmull-Rom through the points, as the game draws a route (situation.gd).
  function smooth(pts, step = 0.4) {
    if (!pts || pts.length < 3) return pts || [];
    const n = pts.length, out = [];
    for (let i = 0; i < n - 1; i++) {
      const p0 = pts[Math.max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(i + 2, n - 1)];
      const steps = Math.max(1, Math.ceil(Math.hypot(p2[0] - p1[0], p2[1] - p1[1]) / step));
      for (let s = 0; s < steps; s++) {
        const t = s / steps, t2 = t * t, t3 = t2 * t;
        out.push([0, 1].map((k) => 0.5 * (2 * p1[k] + (p2[k] - p0[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2 + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)));
      }
    }
    out.push(pts[n - 1]);
    return out;
  }

  function arrowhead(points, w, y, colour, opacity) {
    const n = points.length;
    if (n < 2) return null;
    const [ex, ez] = points[n - 1], [sx, sz] = points[Math.max(0, n - 4)];
    const dx = ex - sx, dz = ez - sz, l = Math.hypot(dx, dz) || 1, ux = dx / l, uz = dz / l;
    const back = 2.2, side = w;
    const bx = ex - ux * back, bz = ez - uz * back;
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute([ex, y, ez, bx - uz * side, y, bz + ux * side, bx + uz * side, y, bz - ux * side], 3));
    const m = new THREE.Mesh(g, basic(colour, { transparent: opacity < 1, opacity }));
    m.userData.own = true;
    m.renderOrder = 5;
    return m;
  }

  function routeStyle(r) {
    if (r.kind === "manoeuvre") return { colour: EXIT_COLOUR, px: r.exit === model?.question?.maneuver ? 4 : 2.5 };
    if (r.kind === "choice") return { colour: LETTER_COLOUR[r.label] || EXIT_COLOUR, px: 3.5 };
    if (r.kind === "approach") return { colour: APPROACH_COLOUR, px: 3 };
    return { colour: ACTOR_COLOUR, px: 2, dashed: true };
  }
  const isSel = (r) => sel.some((s) => keyOf(s) === keyOf(r));

  function rebuildRoutes() {
    const g = setGroup("routes");
    dropLabels("route");
    const selActor = sel.find((s) => s.t === "actor");
    const actorRouteId = selActor ? (model.actors.find((x) => x.id === selActor.id)?.route || `actor_${selActor.id}`) : null;
    const focusRoute = sel.find((s) => s.t === "route")?.id || actorRouteId || (hover && hover.t === "route" ? hover.id : null);
    const answers = model.routes.some((x) => x.kind === "choice");
    for (const r of model.routes) {
      if (r.points.length < 2) continue;
      if (r.kind === "actor" && model.actors.some(a => (a.route || `actor_${a.id}`) === r.id && a.behaviour?.staysPut)) continue;
      // With answer lines on the road the manoeuvres are only drawn when picked: they are how the car
      // drives, not what the question shows.
      // The exits are where the game continues the street after each way out (and its autopilot's path):
      // not something the player is told to drive. Drawn only when one is picked.
      if (r.kind === "manoeuvre" && focusRoute !== r.id) continue;
      // The question's way and the answers always show; the other exits only on focus or in the test.
      const st = routeStyle(r);
      const focused = focusRoute === r.id;
      const main = r.kind === "choice" || r.kind === "approach" || (r.kind === "manoeuvre" && r.exit === model.question?.maneuver) || r.kind === "actor";
      if (!main && !focused && !simMode) continue;
      const dim = focusRoute ? !focused : !main;
      const opacity = dim ? 0.28 : 1;
      const shown = smooth(r.points);
      g.add(polyline(shown, ROUTE_Y, st.colour, focused ? st.px + 1.5 : st.px, opacity, st.dashed));
      const head = arrowhead(shown, focused ? 1.1 : 0.8, ROUTE_Y, st.colour, opacity);
      if (head) g.add(head);
      // The approach ends underneath the player's car, hiding its final arrow. Show direction
      // along the green line as well, so a saved route around the ring is unambiguous.
      if (r.kind === "approach") {
        let travelled = 0;
        for (let i = 1; i < shown.length - 1; i++) {
          travelled += Math.hypot(shown[i][0] - shown[i - 1][0], shown[i][1] - shown[i - 1][1]);
          if (travelled < 12) continue;
          const direction = arrowhead(shown.slice(Math.max(0, i - 2), i + 1), 0.7, ROUTE_Y, st.colour, opacity);
          if (direction) g.add(direction);
          travelled = 0;
        }
      }
      if (r.kind === "choice" && (r.labelPosition || r.points.length)) {
        const at = r.labelPosition || r.points[Math.floor(r.points.length / 2)];
        if (at) labels.push({ text: r.label, cls: "letter", colour: st.colour, world: [at[0], 0.8, at[1]], ref: { t: "route", id: r.id } });
      }
      if (r.kind === "manoeuvre" && (focused || simMode)) {
        const end = r.points.at(-1);
        const text = { left: "налево", right: "направо", straight: "прямо", uturn: "разворот" }[r.exit] || r.exit;
        if (text && end) {
          labels.push({ text, cls: "exit", colour: st.colour, world: [end[0], 0.8, end[1]], ref: { t: "route", id: r.id } });
        }
      }
    }
  }

  // ---- participants, lights, props, the player ------------------------------------------
  function fallbackBox(colour, size, opacity = 1) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(size[0], size[1], size[2]), opacity < 1 ? new THREE.MeshLambertMaterial({ color: colour, transparent: true, opacity }) : mat(colour));
    m.position.y = size[1] / 2;
    return m;
  }

  function playerCar() {
    const car = new THREE.Group();
    const paint = new THREE.MeshLambertMaterial({ color: 0xf08a24 }), glass = new THREE.MeshLambertMaterial({ color: 0x1e2530 });
    const body = new THREE.Mesh(new THREE.BoxGeometry(1.9, 0.6, 4.2), paint);
    body.position.y = 0.55;
    const cabin = new THREE.Mesh(new THREE.BoxGeometry(1.62, 0.6, 2.3), glass);
    cabin.position.set(0, 1.12, -0.2);
    const roof = new THREE.Mesh(new THREE.BoxGeometry(1.58, 0.08, 2.1), paint);
    roof.position.set(0, 1.45, -0.2);
    car.add(body, cabin, roof);
    const wheel = new THREE.CylinderGeometry(0.35, 0.35, 0.22, 14);
    wheel.rotateZ(Math.PI / 2);
    for (const [x, z] of [[0.92, 1.3], [-0.92, 1.3], [0.92, -1.3], [-0.92, -1.3]]) {
      const w = new THREE.Mesh(wheel, mat(0x15171c));
      w.position.set(x, 0.35, z);
      car.add(w);
    }
    return car;
  }

  // Archived editor models have no animated indicator surfaces. A soft amber
  // preview marks the four lamps; Godot uses the vehicle's own authored lenses.
  let hazardMaterial = null;
  function hazardPreview(actor) {
    if (!ActorSignals.supports(actor.type)) return null;
    if (!hazardMaterial) {
      const canvas = document.createElement("canvas"); canvas.width = canvas.height = 64;
      const ctx = canvas.getContext("2d"), gradient = ctx.createRadialGradient(32,32,0,32,32,32);
      gradient.addColorStop(0,"#fff9d8"); gradient.addColorStop(.2,"#ffc14d"); gradient.addColorStop(1,"rgba(255,145,0,0)");
      ctx.fillStyle = gradient; ctx.fillRect(0,0,64,64);
      hazardMaterial = new THREE.SpriteMaterial({map:new THREE.CanvasTexture(canvas),transparent:true,depthWrite:false,depthTest:false,blending:THREE.AdditiveBlending});
    }
    const lights = new THREE.Group(), scale = actor.scale?.[0] || 1;
    lights.name = "editor_hazard_preview";
    const hw = (actor.halfWidth || .95)/scale, hl = (actor.halfLength || 2.1)/scale;
    for (const x of [-hw*.95,hw*.95]) for (const z of [-hl*.9,hl*.9]) {
      const lamp = new THREE.Sprite(hazardMaterial);
      lamp.position.set(x,.8,z); lamp.scale.setScalar(.65/scale); lights.add(lamp);
    }
    lights.visible = false;
    return lights;
  }

  function updateHazards(now) {
    for (const actor of model?.actors || []) {
      const g = anchors.get(`actor:${actor.id}`)?.group, lights = g?.getObjectByName("editor_hazard_preview");
      if (!lights) continue;
      const enabled = ActorSignals.hazards(actor);
      if (enabled !== g.userData.hazardsEnabled) {
        g.userData.hazardsEnabled = enabled; g.userData.hazardsSince = now;
      }
      const visible = enabled && ActorSignals.pulse((now-g.userData.hazardsSince)/1000);
      if (lights.visible !== visible) { lights.visible = visible; needsRender = true; }
    }
  }

  function updateSignalCycles(now) {
    const lit = Math.floor(now / 500) % 2 === 0;
    for (const light of model?.lights || []) {
      if (light.state !== "flashing_yellow") continue;
      const group = anchors.get(`light:${light.id}`)?.group;
      const section = group?.getObjectByName("lamp_yellow");
      if (!section || group.userData.yellowPhase === lit) continue;
      group.userData.yellowPhase = lit;
      section.traverse(m => { if (m.isMesh && m.material?.color) m.material.color.setHex(lit ? 0xffd52a : 0x352d14); });
      needsRender = true;
    }
  }

  // Each object of the scene is a group under "anchors", kept between redraws while its model is the
  // same (only moved): dragging 200 trees about does not reload them.
  function anchorSig(t, o) {
    if (t === "decor") return `${o.prop}|${o.tint}`;
    if (t === "actor") return `${o.asset}|${o.type}`;
    if (t === "light") return `${o.asset}|${o.state}|${o.arrow || ""}|${o.tram || ""}|${(o.mountedSigns || []).join(",")}|${(o.mountedMainRoad || []).join(",")}`;
    if (t === "officer") return `officer|${o.gesture}`;
    if (t === "sign") return `sign|${o.mount || "pole"}|${o.reach ?? 4.5}|${o.armSide || "left"}|${o.clearance ?? 5.5}|${JSON.stringify(SignMount.faces(o).map(SignMount.faceCopy))}`;
    return t;
  }

  function makeAnchor(t, o, key) {
    const g = new THREE.Group();
    g.userData.ref = t === "stop" || t === "player" ? { t } : { t, id: o.id };
    const token = loadToken;
    const attach = (url, fallback, tint, onLoaded) => {
      g.add(fallback);
      loadGltf(url).then((root) => {
        if (!root || anchors.get(key)?.group !== g || token !== loadToken) return;
        g.remove(fallback);
        if (tint) root.traverse((m) => { if (m.isMesh && m.material && m.material.color) { m.material = m.material.clone(); m.material.color.set(tint); } });
        if (onLoaded) onLoaded(root);
        g.add(root);
        needsRender = true;
      });
    };
    if (t === "decor") {
      const url = o.prop === "parked" ? "/asset/models/vehicles/sedan.glb" : `/asset/scenery/${o.prop}.glb`;
      attach(url, fallbackBox(0xb9b4ab, [2, 2, 2]), o.tint);
    } else if (t === "actor") {
      const ped = o.type === "pedestrian" || o.type === "cyclist";
      attach(`/asset/scene/${o.asset}`, fallbackBox(TYPE_COLOUR[o.type] || 0x888888, ped ? [0.6, 1.7, 0.6] : [1.9, 1.4, 4.2]));
      const lights = hazardPreview(o);
      if (lights) g.add(lights);
    } else if (t === "light") {
      const isTram = !!o.tram;
      const mounted = (o.mountedSigns || []).filter(Boolean);
      let lift = mounted.length * 2.4, lightRoot = null;
      const pole = fallbackBox(0x3a3f47, [0.3, isTram ? 5.4 : 3.4, 0.3]);
      pole.position.y += lift;
      const configureLight = (root) => {
        root.position.y += lift;
        lightRoot = root;
        root.traverse((m) => {
          const lampName = m.name?.startsWith("aperture_") ? m.parent?.name : m.name;
          if (m.name === "cffffff" || m.material?.name === "cffffff") {
            if (!o.arrow) {
              m.visible = false;
            } else if (o.arrow === "left") {
              m.visible = true;
              if (m.material) { m.material = m.material.clone(); m.material.side = THREE.DoubleSide; }
              m.scale.x = -1;
            } else {
              m.visible = true;
              m.scale.x = 1;
            }
          }
          if (lampName?.startsWith("lamp_red")) {
            const on = (o.state === "red");
            if (m.material) { m.material = m.material.clone(); m.material.color.setHex(on ? 0xFF3838 : 0x351719); }
          }
          if (lampName?.startsWith("lamp_yellow")) {
            const on = (o.state === "yellow" || o.state === "flashing_yellow");
            if (m.material) { m.material = m.material.clone(); m.material.color.setHex(on ? 0xFFD52A : 0x352D14); }
          }
          if (lampName?.startsWith("lamp_green")) {
            const on = (o.state === "green");
            if (m.material) { m.material = m.material.clone(); m.material.color.setHex(on ? 0x36FF88 : 0x123126); }
          }
          if (lampName === "lamp_arrow" && m.material) {
            m.material = m.material.clone(); m.material.color.setHex(o.arrowActive === false ? 0x123126 : 0x36ff88);
          }
          if (isTram && lampName?.startsWith("lamp_tram_")) {
            const tSig = o.tram || "straight";
            let on = false;
            if (tSig === "straight") on = lampName.includes("bottom") || lampName.includes("mid");
            else if (tSig === "left") on = lampName.includes("bottom") || lampName.includes("left");
            else if (tSig === "right") on = lampName.includes("bottom") || lampName.includes("right");
            else if (tSig === "stop") on = !lampName.includes("bottom");
            else if (tSig === "all") on = true;
            else if (tSig === "off") on = false;
            else on = lampName.includes("bottom") || lampName.includes("mid");
            if (m.material) { m.material = m.material.clone(); m.material.color.setHex(on ? 0xF0F6FF : 0x20252C); }
          }
        });
      };
      const asset = o.asset || (isTram ? (App.state.catalog?.lightTramAsset || App.state.catalog?.lightAssets?.tram) : null)
        || (App.state.catalog?.lightAssets?.[o.arrow || ""] || App.state.catalog?.lightAsset);
      const shared = App.state.catalog?.lightModelAssets?.[isTram ? "tram" : (o.arrow || "")];
      if (shared || asset) attach(shared || `/asset/scene/${asset}`, pole, null, configureLight);
      else g.add(pole);
      if (mounted.length) {
        const extension = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.07, lift, 12), mat(0x3a3f47));
        extension.position.y = lift / 2;
        g.add(extension);
        const heights = mounted.map(() => 2.4), signs = [];
        const arrange = () => {
          lift = heights.reduce((a, h) => a + h, 0) + 0.15 * (mounted.length - 1);
          if (lightRoot) lightRoot.position.y = lift;
          pole.position.y = (isTram ? 5.4 : 3.4) / 2 + lift;
          extension.geometry.dispose();
          extension.geometry = new THREE.CylinderGeometry(0.07, 0.07, lift, 12);
          extension.position.y = lift / 2;
          let offset = 0;
          for (let i = mounted.length - 1; i >= 0; i--) {
            signs[i].position.set(0, SIGN_BOTTOM * 0.2 + offset, 0.18);
            offset += heights[i] + 0.15;
          }
          needsRender = true;
        };
        mounted.forEach((code, i) => {
          const sign = signModel({ code, mainRoad: code === "8.13" ? (o.mountedMainRoad || []) : [] }, false, height => { heights[i] = height * 0.8; setTimeout(arrange, 0); });
          sign.scale.setScalar(0.8);
          signs.push(sign); g.add(sign);
        });
        arrange();
      }
    } else if (t === "officer") {
      g.add(officerModel(o.gesture));
    } else if (t === "sign") {
      g.add(signModel(o));
    } else if (t === "player") {
      g.add(playerCar());
    } else if (t === "stop") {
      const bar = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.04, 0.45), mat(0xf2f4f8));
      bar.position.y = 0.07;
      g.add(bar);
    }
    return g;
  }

  // RoadBuild.sign_node parity: a vertical board centred on its pole, using the picture's proportions.
  const SIGN_W = 3.0, SIGN_BOTTOM = 2.2, SIGN_LEAN = 0;
  const signTex = new Map(), signWaiters = new Map(), laneTex = new Map();
  function signTexture(code, ready = null) {
    if (!signTex.has(code)) {
      signWaiters.set(code, []);
      const texture = new THREE.TextureLoader().load(`/asset/sign/${code}.svg`, () => {
        // Rasterize SVG paths at the game's bounded resolution, not the catalogue's tiny canvas.
        const source = texture.image;
        texture.userData = { sourceSize: [source.width, source.height] };
        const scale = App.state.catalog?.signLayouts?.[code]?.scale || 1;
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(source.width * scale); canvas.height = Math.round(source.height * scale);
        canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height);
        texture.image = canvas; texture.needsUpdate = true;
        for (const callback of signWaiters.get(code) || []) callback();
        signWaiters.delete(code); needsRender = true;
      });
      signTex.set(code, texture);
    }
    const texture = signTex.get(code);
    if (ready && !texture.image?.width) signWaiters.get(code)?.push(ready);
    return texture;
  }
  function signOutlineShape(code) {
    if (['2.1', '2.2'].includes(code)) return 2;
    if (code === '2.4') return 5;
    if (code === '2.5') return 6;
    if (code.startsWith('3.') || code.startsWith('4.')) return 1;
    if (code.startsWith('1.3.')) return 0;
    if (code.startsWith('1.4.') || code === '1.34.3') return 3;
    if (code.startsWith('1.') || code.startsWith('2.3.')) return 4;
    return 3;
  }
  function laneTexture(lanes) {
    const key = JSON.stringify(LaneSign.normalize(lanes));
    if (!laneTex.has(key)) {
      if (laneTex.size >= 16) {
        const oldest = laneTex.keys().next().value;
        // The canvas remains on any live face; Three can upload it again if that face is visible.
        laneTex.get(oldest).dispose(); laneTex.delete(oldest);
      }
      const texture = new THREE.CanvasTexture(LaneSign.canvas(lanes));
      texture.userData = { cornerRadius: .1 };
      laneTex.set(key, texture);
    }
    return laneTex.get(key);
  }
  function mainRoadTexture(main, roads) {
    const c = document.createElement("canvas");
    c.width = 256; c.height = 256;
    const x = c.getContext("2d");
    x.fillStyle = "#fff"; x.fillRect(0, 0, 256, 256);
    x.strokeStyle = "#151515"; x.lineWidth = 10; x.strokeRect(5, 5, 246, 246);
    const ends = { north: [128, 28], south: [128, 228], east: [228, 128], west: [28, 128], ne: [199, 57], se: [199, 199], sw: [57, 199], nw: [57, 57] };
    const all = roads && roads.length ? roads : ["north", "south", "east", "west"];
    x.lineCap = "square";
    for (const [d, e] of Object.entries(ends)) {
      if (!all.includes(d) && !main.includes(d)) continue;
      x.lineWidth = main.includes(d) ? 18 : 6;
      x.beginPath(); x.moveTo(128, 128); x.lineTo(...e); x.stroke();
    }
    return new THREE.CanvasTexture(c);
  }
  function signModel(o, withPole = true, onHeight = null) {
    const g = new THREE.Group(), board = new THREE.Group(), support = new THREE.Group(), parts = [];
    g.add(board); g.add(support);
    const faceMat = tex => {
      const material = new THREE.ShaderMaterial({
        uniforms: { picture: { value: tex }, region: { value: new THREE.Vector4(0, 0, 1, 1) },
          outline: { value: new THREE.Vector4(0, 0, 1, 1) }, shape: { value: 3 },
          aspect: { value: tex.image?.width / tex.image?.height || 1 }, radius: { value: tex.userData?.cornerRadius || 0 } },
        vertexShader: "varying vec2 faceUV; void main(){faceUV=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}",
        fragmentShader: `uniform sampler2D picture; uniform vec4 region, outline;
          uniform int shape; uniform float aspect, radius; varying vec2 faceUV;
          float segmentDistance(vec2 p,vec2 a,vec2 b){vec2 v=p-a,e=b-a;return length(v-e*clamp(dot(v,e)/dot(e,e),0.,1.));}
          float triangleDistance(vec2 p){vec2 a=vec2(-.96,.96),b=vec2(.96,.96),c=vec2(0.,-.96);
            float e=min(segmentDistance(p,a,b),min(segmentDistance(p,b,c),segmentDistance(p,c,a)));
            bool inside=p.y<.96&&p.y>2.*p.x-.96&&p.y>-2.*p.x-.96;return (inside?-e:e)-.04;}
          void main(){vec4 image=texture2D(picture,region.xy+faceUV*region.zw);
            vec2 p=(faceUV-outline.xy)/outline.zw*2.-1.;p.y=-p.y;float d=0.;
            if(shape==1)d=length(p)-1.;
            else if(shape==2){vec2 q=abs(vec2(p.x+p.y,p.y-p.x))*.70710678-vec2((1.+radius*.41421356)*.70710678-radius);
              d=length(max(q,vec2(0.)))+min(max(q.x,q.y),0.)-radius;}
            else if(shape==3){vec2 q=abs(p*vec2(aspect,1.))-vec2(aspect,1.)+vec2(radius);
              d=length(max(q,vec2(0.)))+min(max(q.x,q.y),0.)-radius;}
            else if(shape==4||shape==5)d=triangleDistance(p*vec2(1.,shape==5?-1.:1.));
            else if(shape==6)d=max(max(abs(p.x),abs(p.y)),(abs(p.x)+abs(p.y))*.70710678)-1.;
            float e=max(fwidth(d),.0001);
            float coverage=shape==0?smoothstep(.5-fwidth(image.a),.5+fwidth(image.a)+.0001,image.a):1.-smoothstep(-e*.5,e*.5,d);
            if(coverage<=.001)discard;
            vec3 front=mix(vec3(1.),image.rgb,smoothstep(0.,.1,image.a));
            gl_FragColor=vec4(gl_FrontFacing?front:vec3(.43,.46,.49),coverage);}`,
        side: THREE.DoubleSide, transparent: true, depthWrite: true,
      });
      material.map = tex; // Retain the existing image-ready/layout path.
      return material;
    };
    const add = (tex, w, h, gap = 0.05) => {
      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, h), faceMat(tex));
      mesh.rotation.y = Math.PI; board.add(mesh);
      const part = { mesh, w, h, gap }; parts.push(part); return part;
    };
    let topFaceHeight = SIGN_W;
    const arrange = () => {
      let y = 0;
      for (const part of parts) { part.mesh.position.y = y + part.h / 2; y += part.h + part.gap; }
      const height = Math.max(0, y - (parts.at(-1)?.gap || 0));
      const spec = SignMount.layout(withPole ? o : {}, height, topFaceHeight);
      board.position.set(spec.x, spec.bottom, -0.16);
      while (support.children.length) { const m = support.children[0]; support.remove(m); m.geometry.dispose(); m.material.dispose(); }
      if (withPole) {
        const post = new THREE.Mesh(new THREE.CylinderGeometry(spec.overhead ? 0.16 : 0.05, spec.overhead ? 0.16 : 0.05, spec.postHeight, 12), mat(0x7a7f87));
        post.position.set(0, spec.postHeight / 2, 0.09); support.add(post);
        if (spec.overhead) {
          const part = (size, pos, colour = 0x7a7f87) => { const m = new THREE.Mesh(new THREE.BoxGeometry(...size), mat(colour)); m.position.set(...pos); support.add(m); return m; };
          part([0.7, 0.3, 0.7], [0, 0.15, 0.09], 0x62676d);
          part([spec.armLength, 0.22, 0.22], [spec.side * spec.armLength / 2, spec.postHeight, 0.09]);
          const start = new THREE.Vector3(0, spec.postHeight - 1.4, 0.24), end = new THREE.Vector3(spec.x, spec.postHeight, 0.24);
          const brace = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.07, start.distanceTo(end), 8), mat(0x7a7f87));
          brace.position.copy(start.clone().add(end).multiplyScalar(0.5));
          brace.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), end.clone().sub(start).normalize()); support.add(brace);
        }
      }
      if (onHeight) onHeight(height); needsRender = true;
    };
    const imagePart = (code, width, gap, top = false) => {
      let part;
      const fit = () => {
        if (!part || !part.mesh.material.map.image?.width) return;
        const im = part.mesh.material.map.image;
        const source = part.mesh.material.map.userData?.sourceSize || [im.width, im.height];
        part.h = width * source[1] / source[0];
        const crop = App.state.catalog?.signRegions?.[code];
        let w = width, h = part.h;
        if (crop) {
          const scale = Math.min(width / crop[2], part.h / crop[3]);
          w = crop[2] * scale; h = crop[3] * scale;
          part.mesh.material.uniforms.region.value.set(crop[0] / source[0], 1 - (crop[1] + crop[3]) / source[1], crop[2] / source[0], crop[3] / source[1]);
        }
        const layout = App.state.catalog?.signLayouts?.[code];
        const r = layout?.outline || [0, 0, 1, 1];
        const uniforms = part.mesh.material.uniforms;
        uniforms.outline.value.set(r[0], 1-r[1]-r[3], r[2], r[3]);
        uniforms.shape.value = signOutlineShape(code); uniforms.radius.value = .1;
        uniforms.aspect.value = (crop?.[2] || source[0]) * r[2] / ((crop?.[3] || source[1]) * r[3]);
        part.mesh.geometry.dispose(); part.mesh.geometry = new THREE.PlaneGeometry(w, h);
        if (top) topFaceHeight = part.h;
        arrange();
      };
      const texture = signTexture(code, fit);
      const im = texture.image;
      part = add(texture, width, im?.width ? width * im.height / im.width : width, gap);
      if (top) topFaceHeight = part.h;
      fit();
    };
    const faces = SignMount.faces(o);
    for (let i = faces.length - 1; i >= 0; i--) {
      const face = faces[i], gap = i ? 0.16 : 0.05;
      const width = face.code.startsWith('1.4.') ? SIGN_W * 0.25 : face.laneDirections?.length ? LaneSign.dimensions(face.laneDirections).width : SIGN_W;
      if (face.plate) {
        const c = document.createElement('canvas'); c.width = 512; c.height = 120;
        const ctx = c.getContext('2d'); ctx.fillStyle = 'white'; ctx.fillRect(0, 0, 512, 120);
        ctx.fillStyle = '#151515'; ctx.font = 'bold 60px sans-serif'; ctx.textAlign = 'center'; ctx.fillText(face.plate, 256, 82, 490);
        add(new THREE.CanvasTexture(c), width * 0.8, 0.28 * SIGN_W / 0.8);
      }
      if (face.plateSign) imagePart(face.plateSign, face.plateSign.startsWith('1.4.') ? SIGN_W * 0.25 : width * 0.8, 0.05);
      if (face.code === '8.13') { add(mainRoadTexture(face.mainRoad || [], face.roads), SIGN_W * 0.75, SIGN_W * 0.75, gap); if (!i) topFaceHeight = SIGN_W * 0.75; }
      else {
        if (face.mainRoad?.length) add(mainRoadTexture(face.mainRoad, face.roads), SIGN_W * 0.6, SIGN_W * 0.6);
        if (face.laneDirections?.length) {
          const size = LaneSign.dimensions(face.laneDirections); add(laneTexture(face.laneDirections), size.width, size.height, gap);
          if (!i) topFaceHeight = size.height;
        } else imagePart(face.code, width, gap, !i);
      }
    }
    arrange(); g.rotation.y = -Math.PI;
    return g;
  }

  // A traffic controller as the game draws him (scripts/regulator_officer.gd, simplified): a white
  // helmet, a dark blue uniform, the arms in the chosen signal, a striped baton.
  function officerModel(gesture) {
    const g = new THREE.Group();
    const add = (size, colour, x, y, z) => { const m = new THREE.Mesh(new THREE.BoxGeometry(...size), mat(colour)); m.position.set(x, y, z); g.add(m); return m; };
    add([0.32, 0.85, 0.24], 0x1f2a44, 0.12, 0.43, 0); add([0.32, 0.85, 0.24], 0x1f2a44, -0.12, 0.43, 0);
    add([0.62, 0.75, 0.34], 0x253858, 0, 1.25, 0);
    add([0.64, 0.12, 0.36], 0xd9ff3d, 0, 1.45, 0);
    add([0.26, 0.28, 0.26], 0xe8c4a0, 0, 1.78, 0);
    add([0.3, 0.14, 0.3], 0xf4f6f8, 0, 1.97, 0);
    const arm = (side, rx, rz) => {
      const pivot = new THREE.Group();
      pivot.position.set(side * 0.38, 1.55, 0);
      pivot.rotation.set(rx, 0, rz);
      const a = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.7, 0.16), mat(0x253858));
      a.position.y = -0.35;
      pivot.add(a);
      g.add(pivot);
      return pivot;
    };
    const R = { down: [0, 0, 0, 0], sides: [0, -Math.PI / 2, 0, Math.PI / 2], forward: [0, 0, -Math.PI / 2, 0], up: [0, 0, 0, Math.PI] }[gesture] || [0, -Math.PI / 2, 0, Math.PI / 2];
    arm(1, R[0], -R[1]);
    const right = arm(-1, R[2], -R[3]);
    const baton = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.5, 0.07), mat(0xffffff));
    baton.position.y = -0.85;
    right.add(baton);
    return g;
  }

  function lampColour(state) {
    return { red: 0xff3b30, yellow: 0xffcc00, green: 0x34c759, flashing_yellow: 0xffcc00 }[state] || 0x555555;
  }

  function placeAnchor(g, t, o) {
    if (t === "stop" || t === "player") {
      g.position.set(model.stop.x, 0, model.stop.z);
      g.rotation.y = model.stop.yaw || 0;
      return;
    }
    g.position.set(o.pos[0], o.y || 0, o.pos[1]);
    g.rotation.y = o.yaw || 0;
    if (t === "light") g.scale.setScalar(o.scale || 1);
    else if (o.scale) g.scale.set(o.scale[0], o.scale[1], o.scale[2]);
  }

  function syncAnchors() {
    if (!groups.anchors) groups.anchors = new THREE.Group(), scene.add(groups.anchors);
    const want = new Map();
    if (model) {
      want.set("player:", ["player", model.stop]);
      for (const d of model.decor) want.set(`decor:${d.id}`, ["decor", d]);
      for (const a of model.actors) want.set(`actor:${a.id}`, ["actor", a]);
      for (const l of model.lights) want.set(`light:${l.id}`, ["light", l]);
      for (const o of model.officers || []) want.set(`officer:${o.id}`, ["officer", o]);
      for (const o of model.signs || []) want.set(`sign:${o.id}`, ["sign", o]);
    }
    for (const [key, entry] of anchors) {
      const w = want.get(key);
      if (!w || anchorSig(w[0], w[1]) !== entry.sig) {
        groups.anchors.remove(entry.group);
        anchors.delete(key);
      }
    }
    for (const [key, [t, o]] of want) {
      let entry = anchors.get(key);
      if (!entry) {
        entry = { group: makeAnchor(t, o, key), sig: anchorSig(t, o), t };
        anchors.set(key, entry);
        groups.anchors.add(entry.group);
      }
      if (!(simMode && (t === "player" || t === "actor"))) placeAnchor(entry.group, t, o);
      const layer = t === "decor" ? "decor" : t === "light" ? "lights" : t === "sign" ? "signs" : "actors";
      if (t === "officer") entry.group.userData.ref = { t: "officer", id: o.id };
      entry.group.visible = !hidden.has(layer);
    }
    dropLabels("anchor");
    if (!model) return;
    for (const a of model.actors) {
      if (!a.name || hidden.has("actors")) continue;
      labels.push({ text: a.name, cls: "anchor actor", world: [a.pos[0], 3.4, a.pos[1]], ref: { t: "actor", id: a.id }, follow: `actor:${a.id}` });
    }
  }

  // Moves an object's model without touching the data (the test drive).
  function setPose(key, x, z, yaw) {
    const e = anchors.get(key);
    if (!e) return;
    e.group.position.set(x, 0, z);
    e.group.rotation.y = yaw;
    needsRender = true;
  }

  // ---- the road plan: streets and their nodes --------------------------------------------
  function rebuildPlan() {
    const g = setGroup("plan");
    // Tram tracks: their centre line with an arrow the way they run (the rails come from the build).
    for (const t of (model && model.tracks) || []) {
      if (t.points.length < 2) continue;
      const on = sel.some((x) => x.t === "track" && x.id === t.id), hov = hover && hover.t === "track" && hover.id === t.id;
      const colour = on ? ACCENT : hov ? HOVER : t.depot ? 0xd98e04 : 0x8b5cf6;
      g.add(polyline(t.points, 0.18, colour, on ? 3 : 2, on || hov ? 1 : 0.7, !on));
      const head = arrowhead(t.points, 0.9, 0.18, colour, 1);
      if (head) g.add(head);
    }
    if (!model || !model.layout || simMode) return;
    const L = model.layout;
    const crop = model.crop || 90;
    const selStreets = new Set(sel.filter((s) => s.t === "street").map((s) => s.id));
    const selNodes = new Set(sel.filter((s) => s.t === "node").map((s) => s.id));
    for (const st of L.streets) {
      const pts = Layout.centreline(L, st);
      const on = selStreets.has(st.id), hov = hover && hover.t === "street" && hover.id === st.id;
      if (on || hov) {
        const w = Layout.widthOf(st);
        const outline = [...Layout.offsetRight(pts, -w / 2), ...Layout.offsetRight(pts, w / 2).reverse()];
        outline.push(outline[0]);
        g.add(polyline(outline, 0.16, on ? ACCENT : HOVER, on ? 3 : 2));
      }
      if (planHandles || on) g.add(polyline(pts, 0.15, on ? ACCENT : 0xffffff, 1.5, on ? 1 : 0.55, !on));
      if (on) {
        const mid = Layout.along(pts, Layout.polyLen(pts) / 2).p;
        g.add(handle(mid, "diamond", 0xffffff, ACCENT));
      }
    }
    if (!planHandles && !selNodes.size && !selStreets.size) return;
    for (const n of L.nodes) {
      const kind = Layout.nodeKind(L, n, crop);
      const on = selNodes.has(n.id);
      if (!planHandles && !on && !L.streets.some((s) => selStreets.has(s.id) && (s.a === n.id || s.b === n.id))) continue;
      g.add(handle([n.x, n.z], kind === "border" ? "square" : "circle", on ? ACCENT : 0xffffff, ACCENT, kind === "junction" || kind === "ring" ? 1.25 : 1));
    }
  }

  // A handle drawn the same size on screen at any zoom (rescaled in the render loop).
  function handle(p, shape, fill, stroke, size = 1) {
    const g = new THREE.Group();
    const geo = shape === "square" ? new THREE.PlaneGeometry(1.6, 1.6) : shape === "diamond" ? new THREE.PlaneGeometry(1.4, 1.4) : new THREE.CircleGeometry(0.9, 24);
    const ring = shape === "square" ? new THREE.PlaneGeometry(2.1, 2.1) : shape === "diamond" ? new THREE.PlaneGeometry(1.9, 1.9) : new THREE.CircleGeometry(1.2, 24);
    const a = new THREE.Mesh(ring, basic(stroke, { depthTest: false }));
    const b = new THREE.Mesh(geo, basic(fill, { depthTest: false }));
    for (const m of [a, b]) { m.rotation.x = -Math.PI / 2; m.renderOrder = 20; m.userData.own = true; }
    if (shape === "diamond") { a.rotation.z = b.rotation.z = Math.PI / 4; }
    b.position.y = 0.01;
    g.add(a, b);
    g.position.set(p[0], 0.4, p[1]);
    g.userData.screenSize = size;
    handles.push(g);
    return g;
  }
  let handles = [];

  // ---- selection: outlines, points, the turn handle -------------------------------------
  function footprintOf(ref) {
    if (!model) return null;
    if (ref.t === "decor") {
      const d = model.decor.find((x) => x.id === ref.id);
      if (!d) return null;
      const size = (App.catalogSize(d.prop) || [2, 2, 2]);
      return { x: d.pos[0], z: d.pos[1], yaw: d.yaw || 0, hx: size[0] * d.scale[0] / 2, hz: size[2] * d.scale[2] / 2 };
    }
    if (ref.t === "actor") {
      const a = model.actors.find((x) => x.id === ref.id);
      if (!a) return null;
      const ped = a.type === "pedestrian" || a.type === "cyclist";
      return { x: a.pos[0], z: a.pos[1], yaw: a.yaw || 0, hx: ped ? 0.6 : (a.halfWidth || 0.9) + 0.2, hz: ped ? 0.6 : (a.halfLength || 2.1) + 0.2 };
    }
    if (ref.t === "sign") {
      const o = (model.signs || []).find((x) => x.id === ref.id);
      return o ? { x: o.pos[0], z: o.pos[1], yaw: o.yaw || 0, hx: 1.6, hz: 0.6 } : null;
    }
    if (ref.t === "officer") {
      const o = (model.officers || []).find((x) => x.id === ref.id);
      return o ? { x: o.pos[0], z: o.pos[1], yaw: o.yaw || 0, hx: 0.6, hz: 0.6 } : null;
    }
    if (ref.t === "light") {
      const l = model.lights.find((x) => x.id === ref.id);
      return l ? { x: l.pos[0], z: l.pos[1], yaw: l.yaw || 0, hx: 0.9, hz: 0.9 } : null;
    }
    if (ref.t === "player" || ref.t === "stop") return { x: model.stop.x, z: model.stop.z, yaw: model.stop.yaw || 0, hx: 1.2, hz: 2.4 };
    return null;
  }

  function rect(f, pad) {
    const c = Math.cos(f.yaw), s = Math.sin(f.yaw);
    const corner = (u, v) => [f.x + u * c + v * s, f.z - u * s + v * c];
    const hx = f.hx + pad, hz = f.hz + pad;
    return [corner(-hx, -hz), corner(hx, -hz), corner(hx, hz), corner(-hx, hz), corner(-hx, -hz)];
  }

  let turnHandle = null;
  function rebuildSelection() {
    const g = setGroup("selection");
    turnHandle = null;
    if (!model || simMode) return;
    const draw = (ref, colour, px) => {
      const f = footprintOf(ref);
      if (f) { g.add(polyline(rect(f, 0.35), 0.2, colour, px)); return f; }
      const pts = App.pointsOfRef(ref);
      if (pts && pts.length > 1) {
        const closed = ref.t === "road" || ref.t === "lawn" || (ref.t === "marking" && App.isPaint(ref));
        g.add(polyline(closed ? [...pts, pts[0]] : pts, 0.2, colour, px));
      }
      return null;
    };
    if (hover && !isSel(hover)) draw(hover, HOVER, 2);
    let one = null;
    for (const ref of sel) one = draw(ref, ACCENT, 2.5) || one;
    // One object with a heading: a handle in front of it turns it.
    if (sel.length === 1 && one && (sel[0].t !== "stop" || model.layout?.player?.mode === "free")) {
      const reach = one.hz + 2.4;
      const p = [one.x + Math.sin(one.yaw) * reach, one.z + Math.cos(one.yaw) * reach];
      g.add(polyline([[one.x + Math.sin(one.yaw) * (one.hz + 0.35), one.z + Math.cos(one.yaw) * (one.hz + 0.35)], p], 0.2, ACCENT, 2));
      g.add(handle(p, "circle", 0xffffff, ACCENT, 1.1));
      turnHandle = { x: p[0], z: p[1], cx: one.x, cz: one.z };
    }
    // The points of a drawn shape or route, when it is the one selected, or an actor with a route.
    let pointRef = (sel.length === 1 && ["route", "road", "lawn", "marking", "track"].includes(sel[0].t)) ? sel[0] : null;
    if (!pointRef && sel.length === 1 && sel[0].t === "actor") {
      const a = model.actors.find((x) => x.id === sel[0].id);
      const r = a && model.routes.find((x) => x.id === (a.route || `actor_${a.id}`));
      if (r) pointRef = { t: "route", id: r.id, v: sel[0].v };
    }
    if (pointRef) {
      const pts = App.pointsOfRef(pointRef);
      if (pts && !(pointRef.t === "marking" && App.isPaint(pointRef))) {
        pts.forEach((p, i) => g.add(handle(p, "circle", i === pointRef.v ? ACCENT : 0xffffff, ACCENT, 0.8)));
      }
    }
  }

  // ---- draft (a road or a line being drawn) and ghost (an object being placed) -----------
  function rebuildDraft() {
    const g = setGroup("draft");
    if (!draft) return;
    const pts = draft.cursor ? [...draft.points, draft.cursor] : draft.points;
    if (draft.kind === "road" && pts.length >= 2) {
      const w = draft.width || 8.4;
      const ribbon = [...Layout.offsetRight(pts, -w / 2), ...Layout.offsetRight(pts, w / 2).reverse()];
      const shape = new THREE.Shape(ribbon.map((p) => new THREE.Vector2(p[0], p[1])));
      const geo = new THREE.ShapeGeometry(shape);
      geo.rotateX(Math.PI / 2);
      const m = new THREE.Mesh(geo, basic(ACCENT, { transparent: true, opacity: 0.35, depthWrite: false }));
      m.position.y = 0.25;
      m.userData.own = true;
      g.add(m);
      g.add(polyline(pts, 0.3, ACCENT, 2, 1, true));
    } else if (pts.length >= 2) {
      g.add(polyline(draft.closed ? [...pts, pts[0]] : pts, 0.3, draft.colour || ACCENT, 2.5, 1, !draft.bare));
    }
    if (!draft.bare) for (const p of draft.points) g.add(handle(p, "circle", 0xffffff, ACCENT, 0.7));
    if (draft.snap) g.add(handle(draft.snap, draft.snapKind === "port" ? "square" : "circle", ACCENT, 0xffffff, 1.2));
  }

  let ghostObj = null, ghostKey = "";
  function setGhost(gh) {
    const key = gh ? `${gh.url}|${gh.tint}` : "";
    if (key !== ghostKey) {
      if (ghostObj) { scene.remove(ghostObj); ghostObj = null; }
      ghostKey = key;
      if (gh) {
        const g = new THREE.Group();
        const body = new THREE.MeshLambertMaterial({ color: ACCENT, transparent: true, opacity: 0.5, depthWrite: false });
        const box = new THREE.Mesh(new THREE.BoxGeometry(gh.half[1] * 2, 1, gh.half[0] * 2), body);
        box.position.y = 0.5;
        g.add(box);
        if (gh.url) {
          loadGltf(gh.url).then((root) => {
            if (!root || ghostObj !== g) return;
            g.remove(box);
            root.traverse((o) => { if (o.isMesh) { o.material = o.material.clone(); o.material.transparent = true; o.material.opacity = 0.6; o.material.depthWrite = false; } });
            g.add(root);
            needsRender = true;
          });
        }
        const arrow = new THREE.Mesh(new THREE.ConeGeometry(0.6, 1.4, 12), basic(ACCENT, { transparent: true, opacity: 0.8 }));
        arrow.rotation.x = Math.PI / 2;
        arrow.position.set(0, 0.3, gh.half[0] + 1.4);
        g.add(arrow);
        scene.add(g);
        ghostObj = g;
      }
    }
    if (ghostObj && gh) {
      ghostObj.position.set(gh.x, 0, gh.z);
      ghostObj.rotation.y = gh.yaw || 0;
      ghostObj.scale.setScalar(gh.scale || 1);
    }
    needsRender = true;
  }

  // ---- labels (HTML over the view) -----------------------------------------------------
  function dropLabels(kind) {
    labels = labels.filter((l) => {
      const match = (l.ref && l.ref.t === kind) || l.cls.split(/\s+/).includes(kind) || l.cls.startsWith(kind);
      if (!match) return true;
      if (l.el) l.el.remove();
      return false;
    });
  }
  function placeLabels() {
    if (!labelsEl) return;
    const placed = [];
    for (const l of labels) {
      if (!l.el) {
        l.el = document.createElement("div");
        l.el.className = "tag " + l.cls;
        l.el.textContent = l.text;
        if (l.colour) l.el.style.setProperty("--c", "#" + new THREE.Color(l.colour).getHexString());
        labelsEl.appendChild(l.el);
      }
      const at = l.follow && anchors.get(l.follow) ? anchors.get(l.follow).group.position : null;
      tmp.set(at ? at.x : l.world[0], l.world[1], at ? at.z : l.world[2]).project(camera);
      const x = (tmp.x + 1) / 2 * width, y = (1 - tmp.y) / 2 * height;
      const w = l.text.length * 7 + 16, h = 22;
      const box = { x0: x - w / 2, y0: y - h, x1: x + w / 2, y1: y };
      const clash = placed.some((b) => box.x0 < b.x1 && box.x1 > b.x0 && box.y0 < b.y1 && box.y1 > b.y0);
      const visible = tmp.z < 1 && x > -40 && x < width + 40 && y > -20 && y < height + 20 && !clash && (mode === "3d" || pxPerM > 1.6 || l.cls === "letter");
      if (visible) placed.push(box);
      l.el.style.display = visible ? "" : "none";
      l.el.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`;
      l.el.classList.toggle("sel", !!(l.ref && isSel(l.ref)));
    }
  }
  function clearLabels() {
    labels.forEach((l) => l.el && l.el.remove());
    labels = [];
    if (labelsEl) labelsEl.innerHTML = "";
  }

  // ---- camera ---------------------------------------------------------------------------
  let planCam, perspCam;
  function mount(el) {
    container = el;
    renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: false });
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
    ground.position.y = -0.15;
    scene.add(ground);
    rebuildGround();
    planCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 5000);
    perspCam = new THREE.PerspectiveCamera(40, 1, 0.5, 5000);
    camera = perspCam;
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
  }

  // The question's camera of the game (world.gd): orthographic, pitched atan2(42, 44), looking along +z,
  // framed on a phone held upright. phone: { centre: [x, z], height (m above the card), card (px of 844) }.
  const PHONE_W = 390, PHONE_H = 844, TILT = Math.sin(Math.atan2(42, 44));
  let phone = null;
  function phoneRect() {
    const ph = Math.min(height - 40, (width - 40) * PHONE_H / PHONE_W), pw = ph * PHONE_W / PHONE_H;
    return { x: (width - pw) / 2, y: (height - ph) / 2, w: pw, h: ph };
  }
  function applyPhoneCamera() {
    const rc = phoneRect();
    const free = Math.max(0.3, 1 - phone.card / PHONE_H);
    const size = phone.height / free;
    const up = (1 - free) * size * 0.5 / TILT;
    const look = new THREE.Vector3(phone.centre[0], 0, phone.centre[1] - up);
    const V = size * height / rc.h;
    camera = planCam;
    Object.assign(camera, { left: -V / 2 * width / height, right: V / 2 * width / height, top: V / 2, bottom: -V / 2 });
    camera.updateProjectionMatrix();
    camera.position.set(look.x, 42, look.z - 44);
    camera.up.set(0, 1, 0);
    camera.lookAt(look);
    camera.updateMatrixWorld();
    needsRender = true;
  }
  function setPhone(p) {
    phone = p ? { ...p } : null;
    applyCamera();
  }

  function applyCamera() {
    if (phone) return applyPhoneCamera();
    if (follow) {
      target.set(follow.x, 0, follow.z);
      orbitYaw = follow.yaw + Math.PI;
      if (follow.dist) orbitDist = follow.dist;
      if (follow.pitch) orbitPitch = follow.pitch;
      if (mode !== "3d") mode = "3d";
    }
    if (mode === "plan") {
      camera = planCam;
      const hw = width / 2 / pxPerM, hh = height / 2 / pxPerM;
      Object.assign(camera, { left: -hw, right: hw, top: hh, bottom: -hh });
      camera.updateProjectionMatrix();
      camera.position.set(target.x, 1000, target.z);
      camera.up.set(0, 0, 1);
      camera.lookAt(target.x, 0, target.z);
    } else {
      camera = perspCam;
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      const cp = Math.cos(orbitPitch), sp = Math.sin(orbitPitch);
      camera.position.set(target.x + Math.sin(orbitYaw) * cp * orbitDist, sp * orbitDist + (follow ? 1.5 : 0), target.z + Math.cos(orbitYaw) * cp * orbitDist);
      camera.up.set(0, 1, 0);
      camera.lookAt(target.x, follow ? 1.5 : 0, target.z);
    }
    camera.updateMatrixWorld();
    needsRender = true;
    emit("camera", { mode, pxPerM });
  }

  // Metres per screen pixel at a point of the ground.
  function worldPerPixel(x, z) {
    if (mode === "plan") return 1 / pxPerM;
    const d = camera.position.distanceTo(new THREE.Vector3(x, 0, z));
    return (2 * d * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2))) / height;
  }

  function loop() {
    requestAnimationFrame(loop);
    const now = performance.now();
    emit("frame", now);
    updateHazards(now);
    updateSignalCycles(now);
    if (!needsRender) return;
    needsRender = false;
    for (const h of handles) {
      if (!h.parent) continue;
      const k = worldPerPixel(h.position.x, h.position.z) * 7 * h.userData.screenSize;
      h.scale.set(k, 1, k);
    }
    handles = handles.filter((h) => h.parent);
    renderer.render(scene, camera);
    placeLabels();
  }

  // ---- public: content -------------------------------------------------------------------
  function load(S, B) {
    loadToken++;
    model = S; build = B;
    for (const [, e] of anchors) groups.anchors.remove(e.group);
    anchors.clear();
    sel = []; hover = null; draft = null;
    clearLabels();
    rebuildStatic();
    rebuildRoads();
    refresh(S);
    fit(S.id === "mini_regulator" ? [-55, -50, 55, 60] : undefined);
  }
  function refresh(S) {
    if (S) model = S;
    if (!model) return;
    syncAnchors();
    rebuildRoutes();
    rebuildPlan();
    rebuildSelection();
    needsRender = true;
  }
  function setBuild(B) {
    build = B;
    rebuildRoads();
    // Refilter a fresh cached GLB copy against the latest coverage, including
    // the first preview after loading a regenerated highway without a build.
    rebuildStatic();
    needsRender = true;
  }
  function setSelection(list) {
    sel = list || [];
    rebuildRoutes();
    rebuildPlan();
    rebuildSelection();
    needsRender = true;
  }
  function setHover(ref) {
    if (keyOf(ref) === keyOf(hover)) return;
    hover = ref;
    rebuildRoutes();
    rebuildPlan();
    rebuildSelection();
    needsRender = true;
  }
  function setDraft(d) {
    draft = d;
    rebuildDraft();
    needsRender = true;
  }
  function setHidden(set) {
    hidden = new Set(set);
    for (const [name, g] of Object.entries(groups)) if (GROUP_LAYER[name]) g.visible = !hidden.has(GROUP_LAYER[name]);
    refresh();
  }
  function setPlanHandles(on) {
    planHandles = !!on;
    rebuildPlan();
    needsRender = true;
  }
  function setSimMode(on) {
    simMode = !!on;
    if (!on) follow = null;
    refresh();
    applyCamera();
  }
  function setFollow(f) {
    follow = f;
    applyCamera();
  }
  // The camera as it is, to come back to (after the test drive).
  const getView = () => ({ mode, pxPerM, orbitYaw, orbitPitch, orbitDist, x: target.x, z: target.z });
  function setView(v) {
    ({ mode, pxPerM, orbitYaw, orbitPitch, orbitDist } = v);
    target.set(v.x, 0, v.z);
    applyCamera();
  }

  // ---- public: camera ----------------------------------------------------------------------
  function setMode(m) {
    mode = m;
    applyCamera();
  }
  // Shows the box [x0, z0, x1, z1] (the whole scene by default).
  function fit(box) {
    const crop = (model && model.crop) || 90;
    const b = box || [-crop, -crop, crop, crop];
    const cx = (b[0] + b[2]) / 2, cz = (b[1] + b[3]) / 2, span = Math.max(b[2] - b[0], b[3] - b[1], 12);
    target.set(cx, 0, cz);
    pxPerM = Math.min(width, height) / (span * 1.08);
    orbitDist = span * 1.25 + 20;
    if (!box) { orbitYaw = Math.PI; orbitPitch = 0.95; }
    applyCamera();
  }
  function focus(x, z) {
    target.set(x, 0, z);
    applyCamera();
  }
  function zoomBy(f, at) {
    const before = at ? worldAt(at.x, at.y) : null;
    if (mode === "plan") pxPerM = Math.max(0.8, Math.min(80, pxPerM * f));
    else orbitDist = Math.max(8, Math.min(900, orbitDist / f));
    applyCamera();
    if (before) {
      const after = worldAt(at.x, at.y);
      if (after) { target.x += before.x - after.x; target.z += before.z - after.z; applyCamera(); }
    }
  }
  function panBy(dx, dy) {
    const w0 = worldAt(width / 2, height / 2), w1 = worldAt(width / 2 + dx, height / 2 + dy);
    if (!w0 || !w1) return;
    target.x -= w1.x - w0.x;
    target.z -= w1.z - w0.z;
    applyCamera();
  }

  function worldAt(sx, sy) {
    const ndc = new THREE.Vector2((sx / width) * 2 - 1, -(sy / height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, camera);
    const hit = new THREE.Vector3();
    if (!ray.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), hit)) return null;
    return { x: hit.x, z: hit.z };
  }
  function screenOf(x, z, y = 0) {
    tmp.set(x, y, z).project(camera);
    return { x: (tmp.x + 1) / 2 * width, y: (1 - tmp.y) / 2 * height };
  }

  // ---- picking -----------------------------------------------------------------------------
  // What is under the pointer: the turn handle, points of the selection, plan handles, the models
  // (by their meshes), routes, then the ground: markings, streets, roads and lawns.
  function hitAt(sx, sy, skip = () => false) {
    if (!model) return null;
    const near = (p, r = 12, y = 0.4) => { const s = screenOf(p[0], p[1], y); return Math.hypot(s.x - sx, s.y - sy) < r; };
    if (turnHandle && near([turnHandle.x, turnHandle.z], 14)) return { t: "turn", ...sel[0] };
    if (!hidden.has("routes")) {
      for (const r of model.routes) {
        if (r.kind !== "choice") continue;
        const at = r.labelPosition || r.points[Math.floor(r.points.length / 2)];
        if (at && near(at, 15, 0.8) && !skip({ t: "route", id: r.id })) return { t: "letter", id: r.id };
      }
    }
    let pointRef = (sel.length === 1 && ["route", "road", "lawn", "marking", "track"].includes(sel[0].t)) ? sel[0] : null;
    if (!pointRef && sel.length === 1 && sel[0].t === "actor") {
      const a = model.actors.find((x) => x.id === sel[0].id);
      const r = a && model.routes.find((x) => x.id === (a.route || `actor_${a.id}`));
      if (r) pointRef = { t: "route", id: r.id };
    }
    if (pointRef) {
      const pts = App.pointsOfRef(pointRef) || [];
      for (let i = 0; i < pts.length; i++) if (near(pts[i], 14)) return { ...pointRef, v: i, point: true };
    }
    const L = model.layout;
    if (L && !skip({ t: "street" })) {
      const selStreet = sel.find((s) => s.t === "street");
      if (selStreet) {
        const st = Layout.streetOf(L, selStreet.id);
        if (st) {
          const pts = Layout.centreline(L, st);
          if (near(Layout.along(pts, Layout.polyLen(pts) / 2).p, 12)) return { t: "bend", id: st.id };
        }
      }
      if (planHandles || sel.some((s) => s.t === "street" || s.t === "node")) {
        for (const n of L.nodes) if (near([n.x, n.z], 11)) return { t: "node", id: n.id };
      }
    }
    // Models: a ray against their meshes (a building is picked by its roof as well as its foot).
    const ndc = new THREE.Vector2((sx / width) * 2 - 1, -(sy / height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, camera);
    if (groups.anchors) {
      const hits = ray.intersectObjects(groups.anchors.children.filter((g) => g.visible), true);
      for (const h of hits) {
        let o = h.object;
        while (o && !o.userData.ref) o = o.parent;
        if (o && !skip(o.userData.ref)) return o.userData.ref.t === "player" ? { t: "stop" } : { ...o.userData.ref };
      }
    }
    // Small things seen from far away: the nearest anchor point within a few pixels.
    let best = null, bd = 10;
    const anchorsList = [];
    model.actors.forEach((a) => anchorsList.push([{ t: "actor", id: a.id }, a.pos, "actors"]));
    model.lights.forEach((l) => anchorsList.push([{ t: "light", id: l.id }, l.pos, "lights"]));
    model.decor.forEach((d) => anchorsList.push([{ t: "decor", id: d.id }, d.pos, "decor"]));
    for (const [ref, p, layer] of anchorsList) {
      if (hidden.has(layer) || skip(ref)) continue;
      const s = screenOf(p[0], p[1], 0.5), d = Math.hypot(s.x - sx, s.y - sy);
      if (d < bd) { bd = d; best = ref; }
    }
    if (best) return best;
    const w = worldAt(sx, sy);
    const wpp = w ? worldPerPixel(w.x, w.z) : 0.2;
    const lineHit = (pts, tol) => {
      if (!w) return false;
      for (let k = 0; k + 1 < pts.length; k++) if (segDist(w, pts[k], pts[k + 1]) < tol) return true;
      return false;
    };
    if (!hidden.has("routes")) {
      for (const r of model.routes) {
        const isMain = r.kind === "choice" || r.kind === "approach" || (r.kind === "manoeuvre" && r.exit === model.question?.maneuver) || r.kind === "actor";
        if (!isMain && !simMode && !sel.some((s) => s.t === "route" && s.id === r.id)) continue;
        const ref = { t: "route", id: r.id };
        if (!skip(ref) && lineHit(smooth(r.points), wpp * 8)) return ref;
      }
    }
    if (!w) return null;
    if (!hidden.has("roads")) {
      for (const t of model.tracks || []) {
        const ref = { t: "track", id: t.id };
        if (!skip(ref) && lineHit(t.points, Math.max(wpp * 8, 1.0))) return ref;
      }
    }
    if (!hidden.has("marks")) {
      for (const m of model.markings || []) {
        if (m.auto) continue;
        const ref = { t: "marking", id: m.id };
        if (skip(ref)) continue;
        if (m.points && lineHit(m.points, Math.max(wpp * 6, (m.type === "zebra" ? (m.length || 4) / 2 : 0.4)))) return ref;
      }
    }
    if (hidden.has("roads")) return null;
    if (L) {
      let bestSt = null, bestD = Infinity;
      for (const st of L.streets) {
        const pts = Layout.centreline(L, st);
        for (let k = 0; k + 1 < pts.length; k++) {
          const d = segDist(w, pts[k], pts[k + 1]);
          if (d < Layout.widthOf(st) / 2 + 0.5 && d < bestD) { bestD = d; bestSt = st; }
        }
      }
      if (bestSt && !skip({ t: "street", id: bestSt.id })) return { t: "street", id: bestSt.id };
      for (const n of L.nodes) {
        if (n.ring && Math.hypot(w.x - n.x, w.z - n.z) < n.ring.r && !skip({ t: "node", id: n.id })) return { t: "node", id: n.id };
      }
    }
    for (const l of model.lawns || []) {
      if (l.auto) continue;
      const ref = { t: "lawn", id: l.id };
      if (!skip(ref) && inside(w, l.outer)) return ref;
    }
    for (const r of model.roads) {
      if (r.auto) continue;
      for (let k = 0; k < (r.holes || []).length; k++) {
        const ref = { t: "road", id: r.id, part: k };
        if (!skip(ref) && inside(w, r.holes[k])) return ref;
      }
      const ref = { t: "road", id: r.id, part: -1 };
      if (!skip(ref) && inside(w, r.outer)) return ref;
    }
    for (const m of model.markings || []) {
      if (m.auto || m.points) continue;
      const ref = { t: "marking", id: m.id };
      if (!skip(ref) && (m.polygons || []).some((p) => inside(w, p.outer))) return ref;
    }
    return null;
  }

  function segDist(p, a, b) {
    const dx = b[0] - a[0], dz = b[1] - a[1], l2 = dx * dx + dz * dz || 1;
    const t = Math.max(0, Math.min(1, ((p.x - a[0]) * dx + (p.z - a[1]) * dz) / l2));
    return Math.hypot(p.x - (a[0] + t * dx), p.z - (a[1] + t * dz));
  }
  function inside(p, poly) {
    let c = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const [xi, zi] = poly[i], [xj, zj] = poly[j];
      if ((zi > p.z) !== (zj > p.z) && p.x < ((xj - xi) * (p.z - zi)) / (zj - zi) + xi) c = !c;
    }
    return c;
  }

  // Everything whose anchor lies in the screen rectangle (the marquee).
  function inRect(x0, y0, x1, y1, skip) {
    if (!model) return [];
    const out = [];
    const take = (ref, p, layer) => {
      if (hidden.has(layer) || skip(ref)) return;
      const s = screenOf(p[0], p[1], 0.3);
      if (s.x >= x0 && s.x <= x1 && s.y >= y0 && s.y <= y1) out.push(ref);
    };
    model.decor.forEach((d) => take({ t: "decor", id: d.id }, d.pos, "decor"));
    model.actors.forEach((a) => take({ t: "actor", id: a.id }, a.pos, "actors"));
    model.lights.forEach((l) => take({ t: "light", id: l.id }, l.pos, "lights"));
    return out;
  }

  // ---- the pointer: camera moves here, the rest goes to the tools ------------------------------
  let panTool = false, spaceDown = false;
  function bindPointer() {
    const el = renderer.domElement;
    let nav = null;
    const local = (e) => { const r = el.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
    const pack = (type, e, p) => ({ type, sx: p.x, sy: p.y, world: worldAt(p.x, p.y), shift: e.shiftKey, alt: e.altKey, meta: e.metaKey || e.ctrlKey, button: e.button, detail: e.detail });
    el.addEventListener("contextmenu", (e) => e.preventDefault());
    el.addEventListener("pointerdown", (e) => {
      const p = local(e);
      el.focus();
      const panning = e.button === 1 || (e.button === 0 && (spaceDown || panTool));
      const orbit = e.button === 2;
      if (panning || orbit) {
        nav = { kind: orbit && mode === "3d" && !e.shiftKey ? "orbit" : "pan", last: p };
        el.setPointerCapture(e.pointerId);
        el.classList.add("grabbing");
        return;
      }
      if (e.button !== 0) return;
      el.setPointerCapture(e.pointerId);
      if (phone) { nav = { kind: "phone", last: p }; return; }
      emit("pointer", pack("down", e, p));
    });
    el.addEventListener("pointermove", (e) => {
      const p = local(e);
      if (nav) {
        const dx = p.x - nav.last.x, dy = p.y - nav.last.y;
        if (nav.kind === "phone") {
          // Dragging the picture: the scene follows the finger (screen right is -x, up is +z).
          const rc = phoneRect(), V = phone.height / Math.max(0.3, 1 - phone.card / PHONE_H) * height / rc.h, k = V / height;
          phone.centre = [phone.centre[0] + dx * k, phone.centre[1] + dy * k / TILT];
          applyCamera();
          emit("phone", phone);
        } else if (nav.kind === "orbit") {
          follow = null;
          orbitYaw -= dx * 0.008;
          orbitPitch = Math.max(0.12, Math.min(1.52, orbitPitch + dy * 0.008));
          applyCamera();
        } else panBy(dx, dy);
        nav.last = p;
        return;
      }
      emit("pointer", pack("move", e, p));
    });
    el.addEventListener("pointerup", (e) => {
      const p = local(e);
      if (nav) { nav = null; el.classList.remove("grabbing"); return; }
      emit("pointer", pack("up", e, p));
    });
    el.addEventListener("dblclick", (e) => emit("pointer", pack("dblclick", e, local(e))));
    el.addEventListener("pointerleave", () => emit("pointer", { type: "leave" }));
    // A trackpad scrolls to pan and pinches to zoom (as in Figma); a mouse wheel zooms.
    el.addEventListener("wheel", (e) => {
      e.preventDefault();
      const p = local(e);
      if (phone) {
        phone.height = Math.max(8, Math.min(140, phone.height * Math.exp(e.deltaY * (e.ctrlKey ? 0.01 : 0.0015))));
        applyCamera();
        emit("phone", phone);
        return;
      }
      const wheel = e.deltaMode !== 0 || (e.deltaX === 0 && Math.abs(e.deltaY) >= 40 && Number.isInteger(e.deltaY));
      if (e.ctrlKey || e.metaKey || wheel) zoomBy(Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0015)), p);
      else panBy(-e.deltaX, -e.deltaY);
    }, { passive: false });
    window.addEventListener("keydown", (e) => { if (e.code === "Space" && !typing(e)) { spaceDown = true; el.classList.add("grab"); } });
    window.addEventListener("keyup", (e) => { if (e.code === "Space") { spaceDown = false; el.classList.remove("grab"); } });
  }
  const typing = (e) => { const t = e.target; return t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable); };

  // A square picture of the whole scene from above (the scene list's card).
  function capture(size = 360) {
    const keep = { mode, pxPerM, tx: target.x, tz: target.z };
    const keepSel = sel, keepHover = hover, keepHandles = planHandles;
    sel = []; hover = null; planHandles = false;
    rebuildPlan(); rebuildSelection();
    groups.routes && (groups.routes.visible = false);
    mode = "plan";
    const crop = (model && model.crop) || 90;
    target.set(0, 0, 0);
    pxPerM = Math.min(width, height) / (crop * 2);
    applyCamera();
    renderer.render(scene, camera);
    const c = document.createElement("canvas");
    c.width = c.height = size;
    const side = Math.min(width, height) * renderer.getPixelRatio();
    const src = renderer.domElement;
    c.getContext("2d").drawImage(src, (src.width - side) / 2, (src.height - side) / 2, side, side, 0, 0, size, size);
    mode = keep.mode; pxPerM = keep.pxPerM; target.set(keep.tx, 0, keep.tz);
    sel = keepSel; hover = keepHover; planHandles = keepHandles;
    groups.routes && (groups.routes.visible = !hidden.has("routes"));
    rebuildPlan(); rebuildSelection();
    applyCamera();
    return c;
  }

  return {
    mount, load, refresh, setBuild, setSelection, setHover, setDraft, setGhost, setHidden, setPlanHandles,
    setSimMode, setFollow, setPhone, phoneRect, getView, setView, setPose, setMode, fit, focus, zoomBy, panBy, worldAt, screenOf, worldPerPixel, hitAt, inRect,
    setTextures, reloadPicture, capture, smooth,
    on(name, fn) { (listeners[name] = listeners[name] || []).push(fn); },
    setPanTool(on) { panTool = !!on; renderer && renderer.domElement.classList.toggle("grab", panTool); },
    requestRender() { needsRender = true; },
    get mode() { return mode; },
    get pxPerM() { return pxPerM; },
    get spaceDown() { return spaceDown; },
    get turnHandle() { return turnHandle; },
    get anchors() { return anchors; },
  };
})();
