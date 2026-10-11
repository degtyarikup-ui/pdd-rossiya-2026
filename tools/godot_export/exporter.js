// In-browser half of the model export (see export_models.cjs).
// Each model is rebuilt by the game's factory, then flattened: every mesh of
// the static body is baked into its root's space and meshes sharing a
// material are merged, so one car = one draw call per material, not ~80.
// Moving parts stay separate nodes with stable names Godot looks up:
//   axle_<i> / wheel_<i> (axle_front_* steer), brake_<i>, blink_L / blink_R
//   (+ _rear child), leg_<i>, arm_<i>.
(function () {
  const U = THREE.BufferGeometryUtils;

  function prepare(geometry, keepColor = false) {
    let g = geometry.index ? geometry.toNonIndexed() : geometry.clone();
    for (const name of Object.keys(g.attributes)) if (!['position', 'normal', 'uv', ...(keepColor ? ['color'] : [])].includes(name)) g.deleteAttribute(name);
    if (!g.attributes.normal) g.computeVertexNormals();
    if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
    g.clearGroups();
    return g;
  }

  function materialName(m) {
    return m.userData?.vehicleSurface || m.userData?.pddKind || m.name || ('c' + (m.color ? m.color.getHexString() : 'x'));
  }

  // Flattens `root` into a new Group. `dynamic(node)` tells which descendants
  // must stay separate (they are flattened on their own, recursively).
  function flatten(root, dynamic) {
    const out = new THREE.Group();
    out.name = root.name;
    const buckets = new Map();
    root.updateMatrixWorld(true);
    const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
    const visit = (node) => {
      for (const child of node.children) {
        if (child.isSprite) continue;
        if (dynamic(child)) {
          const sub = flatten(child, dynamic);
          new THREE.Matrix4().multiplyMatrices(inv, child.matrixWorld).decompose(sub.position, sub.quaternion, sub.scale);
          out.add(sub);
          continue;
        }
        if (child.visible === false) continue;
        if (child.isMesh) {
          const rel = new THREE.Matrix4().multiplyMatrices(inv, child.matrixWorld);
          if (Array.isArray(child.material)) {
            // Multi-material geometry (tyres): split by group.
            for (const group of child.geometry.groups) {
              const m = child.material[group.materialIndex];
              const part = child.geometry.index ? child.geometry.toNonIndexed() : child.geometry.clone();
              const keep = new THREE.BufferGeometry();
              for (const [name, attr] of Object.entries(part.attributes)) {
                keep.setAttribute(name, new THREE.BufferAttribute(attr.array.slice(group.start * attr.itemSize, (group.start + group.count) * attr.itemSize), attr.itemSize));
              }
              add(m, keep, rel);
            }
          } else add(child.material, child.geometry, rel);
        }
        visit(child);
      }
    };
    const add = (material, geometry, rel) => {
      const g = prepare(geometry); g.applyMatrix4(rel);
      if (!buckets.has(material.uuid)) buckets.set(material.uuid, { material, list: [] });
      buckets.get(material.uuid).list.push(g);
    };
    if (root.isMesh) add(root.material, root.geometry, new THREE.Matrix4());
    visit(root);
    for (const { material, list } of buckets.values()) {
      const merged = U.mergeBufferGeometries(list, false);
      const mat = material.clone();
      mat.name = materialName(material);
      if (mat.map) mat.map.name = mat.name;
      const mesh = new THREE.Mesh(merged, mat);
      mesh.name = out.name ? out.name + ':' + mat.name : mat.name;
      out.add(mesh);
    }
    return out;
  }

  function nameVehicleParts(car) {
    (car.userData.wheels || []).forEach((tyre, i) => {
      tyre.name = 'wheel_' + i;
      const front = (car.userData.frontAxles || []).includes(tyre.parent);
      tyre.parent.name = (front ? 'axle_front_' : 'axle_') + i;
    });
    (car.brakeLights || []).forEach((m, i) => { m.name = 'brake_' + i; });
    for (const side of ['L', 'R']) {
      const b = car['blinker' + side]; if (!b) continue;
      b.name = 'blink_' + side; b.visible = true;
      b.children.filter(c => c.isMesh).forEach(c => { c.name = 'blink_' + side + '_rear'; });
    }
  }
  const isDynamic = (n) => /^(axle_|wheel_|brake_|blink_|leg_|arm_)/.test(n.name);

  function toGlb(object) {
    return new Promise((resolve, reject) => new THREE.GLTFExporter().parse(object, (buf) => {
      const bytes = new Uint8Array(buf); let s = '';
      for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      resolve(btoa(s));
    }, { binary: true, embedImages: true, onlyVisible: false }));
  }

  function stats(object) {
    let meshes = 0, tris = 0;
    object.traverse(o => { if (o.isMesh) { meshes++; tris += (o.geometry.index ? o.geometry.index.count : o.geometry.attributes.position.count) / 3; } });
    return { meshes, tris: Math.round(tris) };
  }

  // Average colour of a material's texture (canvas), cached: baked into
  // vertex colours where a model is reduced to one material.
  const avgCache = new Map();
  function textureAverage(map) {
    if (!map || !map.image) return [1, 1, 1];
    if (avgCache.has(map.uuid)) return avgCache.get(map.uuid);
    const img = map.image, c = document.createElement('canvas');
    c.width = Math.min(64, img.width); c.height = Math.min(64, img.height);
    const ctx = c.getContext('2d'); ctx.drawImage(img, 0, 0, c.width, c.height);
    const d = ctx.getImageData(0, 0, c.width, c.height).data; let r = 0, g = 0, b = 0, n = 0;
    for (let i = 0; i < d.length; i += 4) { if (d[i + 3] < 8) continue; r += d[i]; g += d[i + 1]; b += d[i + 2]; n++; }
    const avg = n ? [r / n / 255, g / n / 255, b / n / 255] : [1, 1, 1];
    avgCache.set(map.uuid, avg); return avg;
  }

  // One mesh, one material: every part becomes vertex colours (RGB = colour,
  // A = 1 where the part takes the instance's paint, see tint()). `swing(node)`
  // may return [amplitude, pivotY, pivotZ] for limbs: written to uv2 so the
  // Godot shader can swing them (walk cycle without bones or extra nodes).
  function bakeColors(root, tint, swing) {
    root.updateMatrixWorld(true);
    const inv = new THREE.Matrix4().copy(root.matrixWorld).invert(), list = [];
    const visit = (node, limb) => {
      for (const child of node.children) {
        if (child.isSprite) continue;
        if (child.visible === false && !/^blink_/.test(child.name)) continue;
        if (/^blink_/.test(child.name)) continue;  // signals are drawn by Godot
        const own = swing ? swing(child) : null;
        if (own) {
          // Pivot in root space: the limb group's own origin.
          const pivot = new THREE.Vector3().setFromMatrixPosition(child.matrixWorld).applyMatrix4(inv);
          own.pivot = pivot;
        }
        const l = own || limb;
        if (child.isMesh) {
          const mats = Array.isArray(child.material) ? child.material : [child.material];
          const g = prepare(child.geometry, true);
          g.applyMatrix4(new THREE.Matrix4().multiplyMatrices(inv, child.matrixWorld));
          // Parts already merged by the game carry their colours per vertex.
          const own = g.attributes.color;
          if (own) g.deleteAttribute('color');
          const n = g.attributes.position.count, col = new Float32Array(n * 4), uv2 = new Float32Array(n * 2);
          const groups = child.geometry.groups.length && Array.isArray(child.material) ? child.geometry.groups : [{ start: 0, count: n, materialIndex: 0 }];
          for (const grp of groups) {
            const m = mats[grp.materialIndex] || mats[0];
            const t = textureAverage(m.map);
            for (let i = grp.start; i < Math.min(n, grp.start + grp.count); i++) {
              const c = own ? new THREE.Color(own.getX(i), own.getY(i), own.getZ(i)).multiply(m.color) : m.color;
              const [tinted, k] = tint({ color: c, userData: m.userData });
              const base = tinted ? [k, k, k] : [c.r, c.g, c.b];
              col.set([base[0] * t[0], base[1] * t[1], base[2] * t[2], tinted ? 1 : 0], i * 4);
              if (l) uv2.set([l.amp, l.pivot.y], i * 2);
            }
          }
          g.setAttribute('color', new THREE.BufferAttribute(col, 4));
          g.setAttribute('uv2', new THREE.BufferAttribute(uv2, 2));
          list.push(g);
        }
        visit(child, l);
      }
    };
    visit(root, null);
    const merged = U.mergeBufferGeometries(list, false);
    const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.8 });
    mat.name = 'baked';
    const mesh = new THREE.Mesh(merged, mat); mesh.name = root.name;
    const out = new THREE.Group(); out.name = root.name; out.add(mesh);
    out.scale.copy(root.scale); // people come in several heights
    return out;
  }

  window.__toGlb = toGlb;
  window.__exp = { flatten, bakeColors, toGlb, stats, isDynamic, prepare };
  window.exportModels = async function () {
    const result = {};
    // Cars: paint exported WHITE — Godot multiplies it by the per-car colour.
    for (const id of Object.keys(PDD_VEHICLES.specs)) {
      const car = PDD_VEHICLES.create(id, 0xFFFFFF);
      nameVehicleParts(car);
      const before = stats(car);
      car.name = id;
      const flat = flatten(car, isDynamic);
      flat.userData = { halfWidth: car.userData.halfWidth, halfLength: car.userData.halfLength, height: car.userData.height, defaultPaint: '#' + PDD_VEHICLES.specs[id].color.toString(16).padStart(6, '0') };
      result['vehicles/' + id] = { glb: await toGlb(flat), before, after: stats(flat), meta: flat.userData };
    }
    // Traffic: the same cars reduced to one material (vertex colours).
    for (const id of Object.keys(PDD_VEHICLES.specs)) {
      const car = PDD_VEHICLES.create(id, 0xFFFFFF);
      nameVehicleParts(car);
      car.name = id;
      const before = stats(car);
      const flat = bakeColors(car, m => [m.userData?.vehicleSurface === 'paint', m.color.r]);
      result['traffic/' + id] = { glb: await toGlb(flat), before, after: stats(flat) };
    }
    // People, baked: jacket (built in the sentinel colour #FF00FF and its
    // shades) takes the instance colour; legs/arms swing in the shader.
    for (let v = 0; v < 12; v++) {
      const ped = PDD_STREET.createPedestrian(0xFF00FF, v);
      ped.name = 'walker_' + v;
      const legs = ped.userData.legs || [], arms = ped.userData.arms || [];
      const before = stats(ped);
      const flat = bakeColors(ped, m => [m.color.g < 0.01 && Math.abs(m.color.r - m.color.b) < 0.01 && m.color.r > 0.05, m.color.r],
        n => legs.includes(n) ? { amp: legs.indexOf(n) ? -0.32 : 0.32 } : arms.includes(n) ? { amp: arms.indexOf(n) ? 0.2 : -0.2 } : null);
      result['walkers/walker_' + v] = { glb: await toGlb(flat), before, after: stats(flat) };
    }
    const lamp = PDD_STREET.createLampPost(); lamp.name = 'lamp';
    const flatLamp = flatten(lamp, () => false);
    result['street/lamp'] = { glb: await toGlb(flatLamp), before: stats(lamp), after: stats(flatLamp) };
    return result;
  };
})();

// ---------------------------------------------------------------------------
// Scenery (needs the full game page: factories live inside game.js; the
// export script exposes them as window.__pdd). Every prop is baked into one
// mesh for shaders/scenery.gdshader:
//   COLOR.rgb  colour; COLOR.a = 1: takes the instance tint (canopy season
//              colour, facade colour), 0.5: turns to snow in winter (roofs)
//   UV         the game's own detail-map coordinates (skinObject)
//   UV2        (layer + 1, side): detail texture layer in the Texture2DArray
//              (0 = none) and 1 on vertical faces (pddSide)
(function () {
  const U = THREE.BufferGeometryUtils;
  function seeded(seed) {
    let a = seed >>> 0;
    return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }
  function withSeed(seed, fn) {
    const real = Math.random; Math.random = seeded(seed);
    try { return fn(); } finally { Math.random = real; }
  }

  function bakeScenery(root, layers, tintOf) {
    root.updateMatrixWorld(true);
    const inv = new THREE.Matrix4().copy(root.matrixWorld).invert(), list = [];
    root.traverse(node => {
      if (!node.isMesh || node.visible === false) return;
      const m = node.material; if (!m || Array.isArray(m)) return;
      let g = node.geometry.index ? node.geometry.toNonIndexed() : node.geometry.clone();
      const own = g.attributes.color, side = g.attributes.pddSide;
      for (const name of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(name)) g.deleteAttribute(name);
      if (!g.attributes.normal) g.computeVertexNormals();
      const n = g.attributes.position.count;
      if (!g.attributes.uv) g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(n * 2), 2));
      g.applyMatrix4(new THREE.Matrix4().multiplyMatrices(inv, node.matrixWorld));
      const kind = m.userData.pddKind;
      const layer = kind && layers.includes(kind) ? layers.indexOf(kind) + 1 : 0;
      const tinted = tintOf(node, m);
      const col = new Float32Array(n * 4), uv2 = new Float32Array(n * 2);
      for (let i = 0; i < n; i++) {
        const c = own ? new THREE.Color(own.getX(i), own.getY(i), own.getZ(i)).multiply(m.color) : m.color;
        col.set(tinted === 1 ? [1, 1, 1, 1] : [c.r, c.g, c.b, tinted === 0.5 ? 0.5 : 0], i * 4);
        uv2.set([layer, side ? side.getX(i) : 0], i * 2);
      }
      g.setAttribute('color', new THREE.BufferAttribute(col, 4));
      g.setAttribute('uv2', new THREE.BufferAttribute(uv2, 2));
      g.clearGroups();
      list.push(g);
    });
    const mesh = new THREE.Mesh(U.mergeBufferGeometries(list, false), new THREE.MeshStandardMaterial({ vertexColors: true }));
    mesh.material.name = 'scenery'; mesh.name = root.name;
    const out = new THREE.Group(); out.name = root.name; out.add(mesh);
    const box = new THREE.Box3().setFromObject(mesh);
    return { object: out, size: [box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z] };
  }

  function detailTextures(kinds) {
    return kinds.map(kind => {
      // A 128 px tile is scaled to 256: drawn alone, the smoothing reads past its edges as if
      // they were empty and leaves a seam every period. Scaling the middle copy of a 3 x 3 grid
      // of the tile reads the neighbours instead, so the picture still repeats without a seam.
      const src = PDD_ROADS.texture(kind).image, S = src.width, c = document.createElement('canvas');
      const grid = document.createElement('canvas'); grid.width = grid.height = 3 * S;
      const gx = grid.getContext('2d');
      for (let i = 0; i < 3; i++) for (let j = 0; j < 3; j++) gx.drawImage(src, i * S, j * S);
      c.width = c.height = 256;
      const ctx = c.getContext('2d'); ctx.imageSmoothingEnabled = true;
      ctx.drawImage(grid, S, S, S, S, 0, 0, 256, 256);
      const k = PDD_ROADS.kinds[kind];
      return { kind, png: c.toDataURL('image/png').split(',')[1], macro: k.macro || 0, macroScale: k.macroScale || 1,
        period: k.period || 0, side: k.side || 0, u: k.u || 0, v: k.v || 0 };
    });
  }

  window.__exp.bakeScenery = bakeScenery;
  window.exportScenery = async function () {
    const F = window.__pdd, toGlb = window.__toGlb;
    const layers = Object.keys(PDD_ROADS.kinds);
    const out = { textures: detailTextures(layers), props: {} };
    const seasonal = (node, m) => m.userData.seasonal ? 1 : 0;
    const add = async (name, obj, tint = seasonal, meta = {}) => {
      obj.name = name.split('/').pop();
      const { object, size } = bakeScenery(obj, layers, tint);
      out.props[name] = { glb: await toGlb(object), size, ...meta };
    };
    // Buildings: the facade colour is the instance tint too (one mesh serves
    // every colour of its palette), so the body is marked as tinted.
    const ROOFS = [0x6B7480, 0x94A3B8];
    const facade = palette => (node, m) => palette.includes(m.color.getHex()) ? 1
      : m.userData.seasonal === 'roof' || ROOFS.includes(m.color.getHex()) ? 0.5 : 0;
    const HOME = [0xF3E3C3, 0xE8CFA8, 0xD9B99B, 0xC8D9C0, 0xE9D5CC];
    const BLOCK = [0xF5F6FA, 0xE9ECF2, 0xDDE1EA, 0xC6CCD8, 0xB5675A, 0xA9B4C2];
    const homes = [[6, 4.5, 6], [7, 4.5, 7], [8, 4.5, 6.5], [6.5, 7.5, 7], [7.5, 7.5, 7.5], [8, 7.5, 6]];
    for (let i = 0; i < homes.length; i++) await add('buildings/home_' + i, withSeed(100 + i, () => F.createBuilding(...homes[i], 1)), facade(HOME), { style: 1, footprint: homes[i] });
    const blocks = [[10, 10.5, 8], [11, 13.5, 9], [12, 16.5, 10], [13, 10.5, 9], [10.5, 16.5, 8.5], [12.5, 13.5, 10], [11.5, 19.5, 11], [13, 22.5, 10]];
    for (let i = 0; i < blocks.length; i++) await add('buildings/block_' + i, withSeed(200 + i, () => F.createBuilding(...blocks[i], 2)), facade(BLOCK), { style: 2, footprint: blocks[i] });
    const towers = [[14, 28.5, 11], [15, 34.5, 11], [16, 40.5, 11], [13.5, 46.5, 11]];
    for (let i = 0; i < towers.length; i++) await add('buildings/tower_' + i, withSeed(300 + i, () => F.createBuilding(...towers[i], 2)), facade(BLOCK), { style: 3, footprint: towers[i] });
    // Trees: the seasonal canopy takes the instance tint (season palette).
    for (const kind of ['pine', 'round', 'birch']) for (let i = 0; i < 1; i++) {
      await add(`trees/${kind}_${i}`, withSeed(400 + i * 7 + kind.length, () => { const t = F.createTree(kind); t.scale.set(1, 1, 1); t.rotation.y = 0; return t; }),
        (node, m) => m.userData.seasonal || m.userData.pddKind === 'leaves' ? 1 : 0, { kind });
    }
    await add('street/bush', withSeed(500, () => { const b = F.createBush(0xFFFFFF); b.scale.set(1, 0.6, 1.3); b.position.y = 0; return b; }), () => 1);
    for (const length of [12, 14]) await add('street/fence_' + length, F.createFence(length), () => 0);
    for (let i = 0; i < 3; i++) await add('street/kiosk_' + i, withSeed(600 + i * 13, () => F.createKiosk()), () => 0);
    await add('street/lamp', F.createLampPost(), () => 0);
    return out;
  };
})();
