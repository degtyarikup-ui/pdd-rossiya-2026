// Shared procedural vehicle models: the garage thumbnails use these same meshes.
(function () {
  // Camera-facing halo: readable in daylight without expensive bloom/lights.
  function addGlow(lamp, color, size = 1.15) {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 64;
    const ctx = canvas.getContext('2d');
    const gradient = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
    gradient.addColorStop(0, 'rgba(255,255,255,1)');
    gradient.addColorStop(0.15, 'rgba(255,255,255,.9)');
    gradient.addColorStop(0.38, 'rgba(255,255,255,.35)');
    gradient.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = gradient; ctx.fillRect(0, 0, 64, 64);
    const glow = new THREE.Sprite(new THREE.SpriteMaterial({
      map: new THREE.CanvasTexture(canvas), color, transparent: true,
      blending: THREE.AdditiveBlending, depthWrite: false, fog: false,
    }));
    glow.scale.set(size, size, 1);
    glow.userData.signalGlow = true;
    lamp.add(glow);
    return glow;
  }
  // Indicators blink front AND rear: the rear lamp rides on the front one, so
  // every turn signal and the hazard lights show from behind too.
  function addRearBlinker(front, length) {
    const rear = new THREE.Mesh(front.geometry, front.material);
    rear.position.set(0, 0, -(length + 0.1));
    front.add(rear);
    addGlow(rear, 0xFFB329, 1.25);
  }
  // Six passenger cars (any paint colour) plus the premium-only gold wedge.
  const specs = {
    hatch: { color: 0xED4621, width: 1.72, length: 3.5, height: 1.4, cabin: 2.0, cabinZ: -0.3 },
    sedan: { color: 0x317ED4, width: 1.8, length: 4.2, height: 1.35, cabin: 2.05, cabinZ: -0.1 },
    coupe: { color: 0x2B2F36, width: 1.8, length: 4.3, height: 1.25, cabin: 1.7, cabinZ: -0.25 },
    wagon: { color: 0x6E8E6A, width: 1.8, length: 4.5, height: 1.45, cabin: 2.9, cabinZ: -0.45 },
    suv: { color: 0x4D7768, width: 1.9, length: 4.25, height: 1.85, cabin: 2.7, cabinZ: -0.35 },
    pickup: { color: 0xD7AA60, width: 1.9, length: 4.6, height: 1.65, cabin: 1.65, cabinZ: 0.55 },
    cyber: { color: 0xD4AF37, width: 2.0, length: 5.0, height: 1.75, cabin: 2.4, cabinZ: 0.1, premium: true },
  };
  // Paint colours a car can come in (hex). Names are shown in the garage.
  const paints = {
    red: 0xED4621, blue: 0x317ED4, green: 0x4D7768, sand: 0xD7AA60, white: 0xF2F3F5, black: 0x2B2F36,
    silver: 0xB9C0C7, orange: 0xF08A24, purple: 0x7A5BC6, teal: 0x2FA3A0, yellow: 0xE8C547, wine: 0x8B1E2D, gold: 0xD4AF37,
  };
  // Hand edits from the game lab's model workshop (model-edits.js):
  // PDD_MODEL_EDITS[modelId] = { spec, scale: [x, y, z], colors: { 'hex': 'hex' },
  // parts: { meshIndex: { color, hidden } } }. Mesh indices follow the build order.
  function hex(value) { return parseInt(String(value).replace('#', ''), 16); }
  function applyModelEdits(modelId, root) {
    const e = (window.PDD_MODEL_EDITS || {})[modelId];
    if (!e || !root) return root;
    const remap = Object.fromEntries(Object.entries(e.colors || {}).map(([a, b]) => [hex(a), hex(b)]));
    const meshes = [];
    root.traverse(o => { if (o.isMesh) meshes.push(o); });
    meshes.forEach((m, i) => {
      const part = (e.parts || {})[i];
      const own = () => { if (!m.userData.ownMaterial) { m.material = m.material.clone(); m.userData.ownMaterial = true; } return m.material; };
      if (m.material?.color && remap[m.material.color.getHex()] !== undefined) own().color.setHex(remap[m.material.color.getHex()]);
      const attr = m.geometry?.attributes?.color;
      if (attr && Object.keys(remap).length) {
        const c = new THREE.Color();
        for (let k = 0; k < attr.count; k++) {
          c.setRGB(attr.getX(k), attr.getY(k), attr.getZ(k));
          const to = remap[c.getHex()];
          if (to !== undefined) { c.setHex(to); attr.setXYZ(k, c.r, c.g, c.b); }
        }
        attr.needsUpdate = true;
      }
      if (part?.color && m.material?.color) {
        own().color.setHex(hex(part.color));
        if (m.material.vertexColors) m.material.vertexColors = false, m.material.needsUpdate = true;
      }
      if (part?.hidden) m.visible = false;
    });
    if (e.scale) root.scale.multiply(new THREE.Vector3(...e.scale));
    return root;
  }
  function create(id = 'hatch', paint) {
    const edited = (window.PDD_MODEL_EDITS || {})['vehicle:' + id]?.spec;
    const s = { ...(specs[id] || specs.hatch), ...(edited || {}) }, car = new THREE.Group();
    return applyModelEdits('vehicle:' + (specs[id] ? id : 'hatch'), build(id, s, car, paint));
  }
  function build(id, s, car, paint) {
    const material = color => new THREE.MeshLambertMaterial({ color });
    const paintColor = paint === undefined || paint === null ? s.color : (typeof paint === 'string' ? (paints[paint] ?? parseInt(paint.replace('#', ''), 16)) : paint);
    const body = material(paintColor), glass = material(0x233542), dark = material(0x252C32), metal = material(0xBBC4C7);
    if (id === 'cyber') return createCyber(car, s, body, glass, dark, metal);
    function box(w, h, d, x, y, z, mat = body) {
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
      mesh.position.set(x, y, z); mesh.castShadow = true; mesh.receiveShadow = true; car.add(mesh); return mesh;
    }
    const lifted = id === 'suv' || id === 'pickup', wheelRadius = lifted ? 0.4 : 0.33;
    const baseY = lifted ? 0.66 : 0.52;
    box(s.width, 0.48, s.length, 0, baseY, 0);
    box(s.width * 0.85, s.height - baseY - 0.12, s.cabin, 0, (s.height + baseY) / 2, s.cabinZ, glass);
    box(s.width * 0.87, 0.13, s.cabin + 0.05, 0, s.height, s.cabinZ);
    // Pillars and beltline, not just a differently coloured sedan.
    [-1, 1].forEach(side => {
      [-1, 1].forEach(end => box(0.1, s.height - baseY, 0.1, side * s.width * 0.43,
        (s.height + baseY) / 2, s.cabinZ + end * s.cabin / 2));
      box(0.08, s.height - baseY, 0.09, side * s.width * 0.44, (s.height + baseY) / 2, s.cabinZ);
      box(0.17, 0.12, 0.26, side * (s.width / 2 + 0.06), baseY + 0.52, s.cabinZ + s.cabin / 2 - 0.25);
      box(0.18, 0.12, s.length * 0.8, side * s.width / 2, baseY - 0.15, 0, dark);
    });
    box(s.width * 0.75, 0.15, 0.05, 0, baseY, s.length / 2 + 0.02, dark);
    // Bumpers, door lines, licence plates and a rear window.
    [-1, 1].forEach(end => box(s.width + 0.04, 0.17, 0.2, 0, baseY - 0.17, end * (s.length / 2 - 0.02), dark));
    [-1, 1].forEach(end => box(0.5, 0.11, 0.02, 0, baseY - 0.02, end * (s.length / 2 + 0.11), metal));
    [-1, 1].forEach(side => box(0.02, 0.36, 0.03, side * (s.width / 2 + 0.005), baseY + 0.02, s.cabinZ, dark));
    box(s.width * 0.6, (s.height - baseY) * 0.5, 0.02, 0, (s.height + baseY) / 2 + 0.05, s.cabinZ - s.cabin / 2 - 0.01, glass);
    if (id === 'pickup') {
      box(s.width * 0.84, 0.09, 1.48, 0, baseY + 0.24, -1.42, dark);
      [-1, 1].forEach(side => box(0.13, 0.32, 1.55, side * (s.width / 2 - 0.06), baseY + 0.4, -1.43));
      box(s.width, 0.32, 0.12, 0, baseY + 0.4, -s.length / 2 + 0.06);
    }
    if (id === 'suv') {
      [-1, 1].forEach(side => box(0.07, 0.12, 2.2, side * 0.64, s.height + 0.1, -0.35, dark));
      box(1.45, 0.1, 0.45, 0, baseY - 0.18, s.length / 2, metal);
    }
    if (id === 'hatch') box(1.5, 0.08, 0.3, 0, s.height + 0.04, -1.32);
    if (id === 'coupe') { const rear = box(s.width * 0.8, 0.06, 0.9, 0, s.height - 0.22, -1.45, glass); rear.rotation.x = -0.5; }
    if (id === 'wagon') [-1, 1].forEach(side => box(0.07, 0.1, 2.6, side * 0.62, s.height + 0.1, -0.5, dark));
    car.brakeLights = [];
    [-1, 1].forEach(side => {
      box(0.34, 0.14, 0.06, side * s.width * 0.33, baseY + 0.08, s.length / 2 + 0.04,
        new THREE.MeshBasicMaterial({ color: 0xFFF3CC }));
      car.brakeLights.push(box(0.31, 0.13, 0.06, side * s.width * 0.33, baseY + 0.09, -s.length / 2 - 0.04,
        new THREE.MeshBasicMaterial({ color: 0xD33D38 })));
    });
    car.blinkerL = box(0.13, 0.12, 0.07, s.width / 2 - 0.1, baseY + 0.08, s.length / 2 + 0.05,
      new THREE.MeshBasicMaterial({ color: 0xFFAE25 }));
    addRearBlinker(car.blinkerL, s.length);
    car.blinkerR = car.blinkerL.clone(); car.blinkerR.position.x *= -1; car.add(car.blinkerR);
    car.blinkerL.visible = car.blinkerR.visible = false;
    addGlow(car.blinkerL, 0xFFB329, 1.25);
    addGlow(car.blinkerR, 0xFFB329, 1.25);
    car.userData.wheels = [];
    car.userData.frontAxles = [];
    [-1, 1].forEach(side => [-1, 1].forEach(end => {
      const axle = new THREE.Group(); axle.position.set(side * (s.width / 2), wheelRadius, end * s.length * 0.31); car.add(axle);
      const tire = new THREE.Mesh(new THREE.CylinderGeometry(wheelRadius, wheelRadius, 0.23, 16), dark);
      tire.geometry.rotateZ(Math.PI / 2); axle.add(tire); tire.castShadow = true;
      const rim = new THREE.Mesh(new THREE.CylinderGeometry(wheelRadius * 0.59, wheelRadius * 0.59, 0.24, 8), metal);
      rim.geometry.rotateZ(Math.PI / 2); tire.add(rim);
      car.userData.wheels.push(tire);
      if (end > 0) car.userData.frontAxles.push(axle);
    }));
    car.userData.vehicle = id;
    car.userData.halfWidth = s.width / 2;
    car.userData.halfLength = s.length / 2;
    car.userData.height = s.height;
    return car;
  }
  // Premium-only: a low, angular wedge with a single-piece glass canopy and
  // a light bar. Same hooks as the others (wheels, brake lights, blinkers).
  function createCyber(car, s, body, glass, dark, metal) {
    function box(w, h, d, x, y, z, mat = body) {
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
      mesh.position.set(x, y, z); mesh.castShadow = true; mesh.receiveShadow = true; car.add(mesh); return mesh;
    }
    const baseY = 0.62, wheelRadius = 0.42;
    box(s.width, 0.55, s.length, 0, baseY, 0);
    // Sloped nose and tail: thin slabs rotated about X.
    const nose = box(s.width * 0.98, 0.08, 1.9, 0, baseY + 0.62, 1.55); nose.rotation.x = 0.5;
    const tail = box(s.width * 0.98, 0.08, 2.4, 0, baseY + 0.72, -1.35); tail.rotation.x = -0.32;
    const canopy = box(s.width * 0.86, 0.9, s.cabin, 0, baseY + 0.72, s.cabinZ, glass);
    canopy.rotation.x = 0.12;
    box(s.width * 0.9, 0.06, 0.06, 0, baseY + 1.2, s.cabinZ + s.cabin / 2 - 0.1, metal); // roof edge
    box(s.width, 0.08, 0.08, 0, baseY + 0.3, s.length / 2 + 0.02, new THREE.MeshBasicMaterial({ color: 0xFFF3CC })); // light bar
    box(s.width, 0.08, 0.08, 0, baseY + 0.3, -s.length / 2 - 0.02, new THREE.MeshBasicMaterial({ color: 0xD33D38 }));
    [-1, 1].forEach(side => box(0.16, 0.14, 0.34, side * (s.width / 2 - 0.1), baseY - 0.2, s.length * 0.31, dark));
    car.brakeLights = [];
    [-1, 1].forEach(side => car.brakeLights.push(box(0.4, 0.1, 0.06, side * s.width * 0.3, baseY + 0.16, -s.length / 2 - 0.05,
      new THREE.MeshBasicMaterial({ color: 0xD33D38 }))));
    car.blinkerL = box(0.13, 0.12, 0.07, s.width / 2 - 0.1, baseY + 0.16, s.length / 2 + 0.05, new THREE.MeshBasicMaterial({ color: 0xFFAE25 }));
    addRearBlinker(car.blinkerL, s.length);
    car.blinkerR = car.blinkerL.clone(); car.blinkerR.position.x *= -1; car.add(car.blinkerR);
    car.blinkerL.visible = car.blinkerR.visible = false;
    addGlow(car.blinkerL, 0xFFB329, 1.25); addGlow(car.blinkerR, 0xFFB329, 1.25);
    car.userData.wheels = []; car.userData.frontAxles = [];
    [-1, 1].forEach(side => [-1, 1].forEach(end => {
      const axle = new THREE.Group(); axle.position.set(side * (s.width / 2), wheelRadius, end * s.length * 0.32); car.add(axle);
      const tire = new THREE.Mesh(new THREE.CylinderGeometry(wheelRadius, wheelRadius, 0.28, 16), dark);
      tire.geometry.rotateZ(Math.PI / 2); axle.add(tire); tire.castShadow = true;
      const rim = new THREE.Mesh(new THREE.CylinderGeometry(wheelRadius * 0.6, wheelRadius * 0.6, 0.29, 6), metal);
      rim.geometry.rotateZ(Math.PI / 2); tire.add(rim);
      car.userData.wheels.push(tire);
      if (end > 0) car.userData.frontAxles.push(axle);
    }));
    car.userData.vehicle = 'cyber';
    car.userData.halfWidth = s.width / 2; car.userData.halfLength = s.length / 2; car.userData.height = s.height;
    return car;
  }
  window.PDD_VEHICLES = { specs, paints, create, addGlow, applyModelEdits };
})();
