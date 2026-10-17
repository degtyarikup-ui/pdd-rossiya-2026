// A brush stamp is a collection of ordinary decor objects. The preview and the actual stroke use
// the same plan, with real scenery sizes, so a house cannot appear across a road after a click.
const EnvironmentBrush = (() => {
  const MODES = [
    { id: "forest", title: "Лес", size: 24, compound: true },
    { id: "village", title: "Частный сектор", size: 36, compound: true },
    { id: "quarter", title: "Городской квартал", size: 44, compound: true },
    { id: "park", title: "Парк", size: 28, compound: true },
    { id: "trees", title: "Деревья", size: 9, prop: "trees/round_0" },
    { id: "bushes", title: "Кусты", size: 7, prop: "street/bush" },
    { id: "houses", title: "Дома", size: 14, prop: "buildings/home_0" },
    { id: "fences", title: "Заборы", size: 13, prop: "street/fence_12" },
    { id: "selected", title: "Из библиотеки", size: 8 },
  ];
  const TAU = Math.PI * 2, GAP = 0.18;
  const round = value => Math.round(value * 1000) / 1000;
  const mode = id => MODES.find(m => m.id === id) || MODES[0];
  const propsOf = catalog => Array.isArray(catalog?.props) ? Object.fromEntries(catalog.props.map(p => [p.id, p])) : (catalog?.props || {});
  const sizeOf = (prop, catalog) => prop === "parked" ? [1.9, 1.4, 4.2] : propsOf(catalog)[prop]?.size;
  const scaleOf = object => Array.isArray(object.scale) ? object.scale : [object.scale || 1, object.scale || 1, object.scale || 1];
  const rotated = (p, yaw) => [p[0] * Math.cos(yaw) + p[1] * Math.sin(yaw), p[1] * Math.cos(yaw) - p[0] * Math.sin(yaw)];
  const box = polygon => [Math.min(...polygon.map(p => p[0])), Math.min(...polygon.map(p => p[1])), Math.max(...polygon.map(p => p[0])), Math.max(...polygon.map(p => p[1]))];
  const boxesMeet = (a, b) => a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3];
  function rectangle(pos, half, yaw = 0) {
    return [[-half[0], -half[1]], [half[0], -half[1]], [half[0], half[1]], [-half[0], half[1]]].map(p => {
      const r = rotated(p, yaw); return [r[0] + pos[0], r[1] + pos[1]];
    });
  }
  function footprint(object, catalog, gap = GAP) {
    const size = sizeOf(object.prop, catalog) || [2, 2, 2], scale = scaleOf(object);
    return rectangle(object.pos, [Math.abs(size[0] * scale[0]) / 2 + gap, Math.abs(size[2] * scale[2]) / 2 + gap], object.yaw || 0);
  }
  // Separating axes work for both an oriented prop rectangle and a surface triangle.
  function overlaps(a, b) {
    if (!boxesMeet(box(a), box(b))) return false;
    for (const polygon of [a, b]) for (let i = 0; i < polygon.length; i++) {
      const p = polygon[i], q = polygon[(i + 1) % polygon.length], axis = [p[1] - q[1], q[0] - p[0]];
      const pa = a.map(v => v[0] * axis[0] + v[1] * axis[1]), pb = b.map(v => v[0] * axis[0] + v[1] * axis[1]);
      if (Math.max(...pa) < Math.min(...pb) - 1e-8 || Math.max(...pb) < Math.min(...pa) - 1e-8) return false;
    }
    return true;
  }
  function pointIn(p, polygon) {
    let hit = false;
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const a = polygon[i], b = polygon[j];
      if ((a[1] > p[1]) !== (b[1] > p[1]) && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]) hit = !hit;
    }
    return hit;
  }
  const distanceToSegment = (p, a, b) => {
    const x = b[0] - a[0], z = b[1] - a[1], len = x * x + z * z;
    const t = len ? Math.max(0, Math.min(1, ((p[0] - a[0]) * x + (p[1] - a[1]) * z) / len)) : 0;
    return Math.hypot(p[0] - a[0] - t * x, p[1] - a[1] - t * z);
  };
  function segmentCrosses(a, b, c, d) {
    const cross = (p, q, r) => (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]);
    const x = cross(a, b, c), y = cross(a, b, d), z = cross(c, d, a), w = cross(c, d, b);
    return x * y < 0 && z * w < 0;
  }
  function polygonMeetsRoad(polygon, road) {
    const outer = road.outer || [];
    if (outer.length < 3) return false;
    const bounds = box(outer), margin = road.walk !== false && road.surface !== "sand" ? 3.2 : 0;
    if (!boxesMeet(box(polygon), [bounds[0] - margin, bounds[1] - margin, bounds[2] + margin, bounds[3] + margin])) return false;
    // Roads in S are current even while the asynchronous server build is still pending.
    const inside = p => pointIn(p, outer) && !(road.holes || []).some(h => pointIn(p, h));
    if (polygon.some(inside) || outer.some(p => pointIn(p, polygon))) return true;
    for (let i = 0; i < polygon.length; i++) for (let j = 0; j < outer.length; j++) {
      const a = polygon[i], b = polygon[(i + 1) % polygon.length], c = outer[j], d = outer[(j + 1) % outer.length];
      if (segmentCrosses(a, b, c, d)) return true;
      if (road.walk !== false && road.surface !== "sand" && Math.min(distanceToSegment(a, c, d), distanceToSegment(b, c, d), distanceToSegment(c, a, b), distanceToSegment(d, a, b)) < 3.2) return true;
    }
    return false;
  }
  // A local spatial index avoids scanning every triangle / every tree on each pointer move.
  function spatial(cell = 12) {
    const cells = new Map();
    function keys(bounds) {
      const out = [];
      for (let x = Math.floor(bounds[0] / cell); x <= Math.floor(bounds[2] / cell); x++)
        for (let z = Math.floor(bounds[1] / cell); z <= Math.floor(bounds[3] / cell); z++) out.push(`${x}:${z}`);
      return out;
    }
    return {
      add(polygon, value = polygon) { const item = { polygon, value }; for (const key of keys(box(polygon))) { if (!cells.has(key)) cells.set(key, []); cells.get(key).push(item); } },
      near(polygon) { return [...new Set(keys(box(polygon)).flatMap(key => cells.get(key) || []))]; },
    };
  }
  const surfaceCache = new WeakMap();
  function surfaces(build) {
    if (!build) return null;
    if (surfaceCache.has(build)) return surfaceCache.get(build);
    const index = spatial();
    for (const surface of build.surfaces || []) {
      if (!["asphalt", "pavement", "island", "sand", "median", "dirt_field"].includes(surface.id) && !surface.id?.startsWith("sand_join_")) continue;
      const { verts = [], idx = [] } = surface;
      for (let i = 0; i + 2 < idx.length; i += 3) {
        const tri = idx.slice(i, i + 3).map(v => [verts[v * 2], verts[v * 2 + 1]]);
        index.add(tri);
      }
    }
    surfaceCache.set(build, index);
    return index;
  }
  function context(scene, build, catalog) {
    const occupied = spatial();
    for (const object of scene.decor || []) occupied.add(footprint(object, catalog), object);
    for (const actor of scene.actors || []) if (actor.pos) occupied.add(rectangle(actor.pos, [(actor.halfWidth || 1) + 0.5, (actor.halfLength || 2.2) + 0.5], actor.yaw || 0), actor);
    for (const object of [...(scene.signs || []), ...(scene.lights || []), ...(scene.officers || [])]) if (object.pos) occupied.add(rectangle(object.pos, [1.2, 1.2]), object);
    const stop = scene.stop && (scene.stop.pos || [scene.stop.x, scene.stop.z]);
    if (stop && stop.every(Number.isFinite)) occupied.add(rectangle(stop, [1.5, 3], scene.stop.yaw || 0), scene.stop);
    return { occupied, roads: scene.roads || [], surface: surfaces(build), crop: Number(scene.crop || 90), catalog };
  }
  function random(seed) {
    let value = 2166136261;
    for (const c of String(seed)) { value ^= c.charCodeAt(0); value = Math.imul(value, 16777619); }
    return () => { value += 0x6D2B79F5; let t = value; t = Math.imul(t ^ t >>> 15, t | 1); t ^= t + Math.imul(t ^ t >>> 7, t | 61); return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  }
  function diameter(config, catalog) {
    const m = mode(config.brushMode), scale = config.brushScale || 1;
    if (m.id === "selected") {
      const s = sizeOf(config.prop, catalog) || [4, 4, 4]; return Math.max(4, Math.hypot(s[0], s[2]) + 1) * scale;
    }
    return m.size * scale;
  }
  function interval(config, catalog) {
    const m = mode(config.brushMode), d = diameter(config, catalog);
    return d * (m.compound ? 0.9 : m.id === "fences" ? 0.96 : m.id === "houses" || m.id === "selected" ? 1.05 : 0.65) * (config.brushSpacing || 1);
  }
  // Relative coordinates deliberately keep each lot coherent, with fences outside its own house.
  function candidates(config, catalog, seed = "preview") {
    const available = propsOf(catalog), rnd = random(seed), list = [], m = mode(config.brushMode);
    const add = (prop, x, z, yaw = 0, scale = 1, group = null) => { if (available[prop] || prop === "parked") list.push({ prop, pos: [x, z], yaw, scale: [scale, scale, scale], tint: null, group }); };
    const treeIds = ["trees/round_0", "trees/pine_0", "trees/birch_0"].filter(p => available[p]);
    const tree = (x, z, scale = 1, group = null) => { if (treeIds.length) add(treeIds[Math.floor(rnd() * treeIds.length)], x, z, rnd() * TAU, scale * (0.88 + rnd() * 0.2), group); };
    const scatter = (radius, step, kind) => {
      for (let x = -radius + step / 2; x < radius; x += step) for (let z = -radius + step / 2; z < radius; z += step) {
        const p = [x + (rnd() - 0.5) * step * 0.3, z + (rnd() - 0.5) * step * 0.3];
        if (Math.hypot(...p) > radius - (kind === "tree" ? 1.5 : .8)) continue;
        if (kind === "tree") tree(...p); else add("street/bush", ...p, rnd() * TAU, 0.9 + rnd() * 0.2);
      }
    };
    if (m.id === "forest") scatter(11.5, 4.4, "tree");
    else if (m.id === "trees") scatter(4.5, 3.9, "tree");
    else if (m.id === "bushes") scatter(3.5, 2.7, "bush");
    else if (m.id === "village") {
      for (let i = 0; i < 2; i++) {
        const x = i ? 8.5 : -8.5, group = `lot_${i}`;
        add(`buildings/home_${i}`, x, 0, 0, 1, group);
        add("street/fence_14", x, -11.5, Math.PI / 2, 1, group);
        add("street/fence_12", i ? 16.5 : -16.5, 0, 0, 1, group);
        add("street/fence_12", x, 10.5, Math.PI / 2, 1, group);
        tree(x - 3.4, -7.8, 0.85, group); tree(x + 3.3, 6.9, 0.8, group);
        add("street/bush", x - 3.6, 7, 0, 1, group);
      }
    } else if (m.id === "quarter") {
      for (let i = 0; i < 4; i++) {
        const x = i % 2 ? 10.5 : -10.5, z = i < 2 ? -9 : 9;
        add(`buildings/block_${i}`, x, z, 0, 1, `block_${i}`);
        tree(x + (x > 0 ? 9 : -9), z, 0.85, `block_${i}`);
      }
      for (const z of [-11, -5.5, 0, 5.5, 11]) tree(0, z, 0.85);
      add("street/lamp", -4, 0); add("street/lamp", 4, 0, Math.PI);
      add("street/bush", -4.5, -17); add("street/bush", 4.5, 17);
    } else if (m.id === "park") {
      for (const x of [-9, 0, 9]) for (const z of [-9, 0, 9]) if (Math.abs(x) + Math.abs(z) > 0) tree(x, z, 0.9);
      for (const x of [-5, 5]) for (const z of [-4, 4]) add("street/bush", x, z);
      add("street/kiosk_0", 0, 0); add("street/lamp", -4, 0); add("street/lamp", 4, 0, Math.PI);
    } else if (m.id === "houses") add(/^buildings\//.test(config.prop || "") ? config.prop : "buildings/home_0", 0, 0);
    else if (m.id === "fences") add(/^street\/fence_/.test(config.prop || "") ? config.prop : "street/fence_12", 0, 0);
    else if (m.id === "selected") add(config.prop || "trees/round_0", 0, 0);
    return list;
  }
  function plan(scene, build, catalog, config, point, existingContext = null) {
    const ctx = existingContext || context(scene, build, catalog), accepted = [], rejected = [];
    const scale = config.brushScale || 1, yaw = config.brushYaw || 0;
    // Stable local arrangement while moving; preview, click and repeated runs are identical.
    const list = candidates(config, catalog, config.brushVariation || 0).map(local => {
      const offset = rotated(local.pos.map(v => v * scale), yaw);
      const object = { ...local, pos: [round(point[0] + offset[0]), round(point[1] + offset[1])], yaw: round(local.yaw + yaw), scale: local.scale.map(v => round(v * scale)) };
      return { ...object, polygon: footprint(object, catalog) };
    });
    const groups = new Map();
    list.forEach((object, index) => { const key = object.group || `single_${index}`; if (!groups.has(key)) groups.set(key, []); groups.get(key).push(object); });
    const added = spatial();
    const reason = object => {
      const poly = object.polygon;
      if (poly.some(p => Math.abs(p[0]) > ctx.crop || Math.abs(p[1]) > ctx.crop)) return "edge";
      if (ctx.roads.some(r => polygonMeetsRoad(poly, r)) || ctx.surface?.near(poly).some(t => overlaps(poly, t.polygon))) return "road";
      if (ctx.occupied.near(poly).some(p => overlaps(poly, p.polygon)) || added.near(poly).some(p => overlaps(poly, p.polygon))) return "object";
      return null;
    };
    for (const group of groups.values()) {
      // Fences and gardens belonging to an obstructed house are skipped with the whole lot.
      const blocked = group.map(object => reason(object)).find(Boolean);
      if (blocked) { group.forEach(o => rejected.push({ ...o, reason: blocked })); continue; }
      for (const object of group) {
        const blockedBySibling = added.near(object.polygon).some(p => overlaps(object.polygon, p.polygon));
        if (blockedBySibling) { rejected.push({ ...object, reason: "object" }); continue; }
        accepted.push(object); added.add(object.polygon);
      }
    }
    return { accepted, rejected, center: [...point], diameter: diameter(config, catalog), yaw };
  }
  function append(scene, planned) {
    if (!planned.accepted.length) return [];
    scene.decor = scene.decor || [];
    const used = new Set(scene.decor.map(d => d.id)), ids = [];
    let n = 1;
    for (const object of planned.accepted) {
      while (used.has(`decor_${n}`)) n++;
      const id = `decor_${n++}`; used.add(id); ids.push(id);
      const { prop, pos, yaw, scale, tint } = object;
      scene.decor.push({ id, prop, pos: [...pos], yaw, scale: [...scale], tint });
    }
    return ids;
  }
  function matches(config, object) {
    switch (mode(config.brushMode).id) {
      case "forest": case "trees": return object.prop.startsWith("trees/");
      case "bushes": return object.prop === "street/bush";
      case "houses": return object.prop.startsWith("buildings/");
      case "fences": return object.prop.startsWith("street/fence_");
      case "selected": return object.prop === config.prop;
      default: return object.prop.startsWith("trees/") || object.prop.startsWith("buildings/") || object.prop.startsWith("street/");
    }
  }
  function erase(scene, catalog, config, point) {
    const radius = diameter(config, catalog) / 2, old = scene.decor || [];
    scene.decor = old.filter(object => !matches(config, object) || Math.hypot(object.pos[0] - point[0], object.pos[1] - point[1]) > radius);
    return old.length - scene.decor.length;
  }
  function illustration(id) {
    const tree = (x, y, s = 1) => `<g transform="translate(${x} ${y}) scale(${s})"><path d="M0 4v9" stroke="#7e6249" stroke-width="3"/><path d="M0-11 10 7H-10Z" fill="#4d8c61"/><path d="M0-17 8-1H-8Z" fill="#66a676"/></g>`;
    const home = (x, y, s = 1) => `<g transform="translate(${x} ${y}) scale(${s})"><path d="M-11 0H11V17H-11Z" fill="#e9d6b3"/><path d="M-14 1 0-10 14 1Z" fill="#b76e4d"/><path d="M-7 6h5v5h-5m9-5h5v5h-5" fill="#607887"/><path d="M-2 10h5v7h-5" fill="#8e7963"/></g>`;
    const block = (x, y) => `<g transform="translate(${x} ${y})"><path d="M-10-15H10V19H-10Z" fill="#c3cbd2"/><path d="M-12-17H12V-13H-12Z" fill="#677885"/>${[-8, 0, 8].flatMap(z => [-6, 2].map(a => `<path d="M${a} ${z}h4v5h-4Z" fill="#6c8c9e"/>`)).join("")}</g>`;
    let body = "";
    if (id === "forest") body = tree(35, 35, .9) + tree(65, 36, .85) + tree(50, 47, 1.15) + tree(25, 48, .7) + tree(78, 49, .7);
    else if (id === "village") body = home(30, 30, .9) + home(70, 31, .9) + tree(51, 43, .65) + `<path d="M13 50H86M17 45v11m8-11v11m8-11v11m8-11v11m18-11v11m8-11v11m8-11v11m8-11v11" stroke="#9c8c6b" stroke-width="2"/>`;
    else if (id === "quarter") body = block(30, 33) + block(70, 33) + tree(50, 46, .75);
    else if (id === "park") body = `<path d="M15 52 85 17M20 16 80 55" stroke="#d8cdb0" stroke-width="7"/>` + tree(28, 30, .8) + tree(73, 45, .9) + `<ellipse cx="40" cy="51" rx="10" ry="6" fill="#8ebd7d"/><ellipse cx="72" cy="18" rx="10" ry="6" fill="#8ebd7d"/>`;
    else if (id === "fences") body = `<path d="M13 38H87M13 49H87" stroke="#9b805d" stroke-width="5"/>${[18,31,44,57,70,83].map(x => `<path d="M${x-3} 55V29l3-4 3 4v26Z" fill="#c4a273" stroke="#9b805d" stroke-width="1"/>`).join("")}<path d="M12 58H88" stroke="#98ae81" stroke-width="3"/>`;
    return `<svg class="brush-illustration" viewBox="0 0 100 70" role="img" aria-label="${mode(id).title}"><rect x="2" y="2" width="96" height="66" rx="12" fill="#e8f0df"/>${body}</svg>`;
  }
  return { MODES, mode, diameter, interval, candidates, context, plan, append, erase, matches, illustration, footprint, overlaps, sizeOf };
})();
if (typeof module !== "undefined") module.exports = EnvironmentBrush;
