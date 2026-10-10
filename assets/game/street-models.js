// Shared, texture-free street models from the main driving game.
// Five vertex-coloured meshes per walker; lamps can be batched by material.
(() => {
  'use strict';
  const sceneryMat = color => new THREE.MeshLambertMaterial({ color });
  // Procedural appearances: no texture downloads or extra image assets.
  const PEOPLE_COLORS = [0x3979A3, 0xB6654F, 0x66845A, 0xD5AA49, 0x865E94, 0xD4C8B3];
  function personLook(variant) {
    return {
      variant,
      skin: [0xE9AF83, 0xC58C65, 0xF2C9A5, 0x986647][variant % 4],
      hair: [0x49372B, 0xB68A4E, 0x392D2B, 0xB4ACA1][Math.floor(variant / 3) % 4],
      pants: [0x344759, 0x55544E, 0x37473B, 0x655066][variant % 4],
      top: PEOPLE_COLORS[variant % PEOPLE_COLORS.length],
    };
  }
  function modelPart(group, geometry, color, x, y, z, rx = 0, ry = 0, rz = 0) {
    const mesh = new THREE.Mesh(geometry, sceneryMat(color));
    mesh.position.set(x, y, z);
    if (rx || ry || rz) mesh.rotation.set(rx, ry, rz);
    mesh.castShadow = true; group.add(mesh);
    return mesh;
  }
  function modelBox(group, size, color, x, y, z, rx = 0, ry = 0, rz = 0) {
    return modelPart(group, new THREE.BoxGeometry(...size), color, x, y, z, rx, ry, rz);
  }
  function mergeModelParts(group, doubleSided = false) {
    // Bake colours into vertices: one draw call for each independently animated
    // part, even when it contains shoes, hands, a face, hair and accessories.
    const parts = group.children.filter(o => o.isMesh);
    if (!parts.length) return;
    const colors = [];
    parts.forEach(part => {
      const count = part.geometry.index?.count || part.geometry.attributes.position.count;
      const c = part.material.color;
      for (let i = 0; i < count; i++) colors.push(c.r, c.g, c.b);
    });
    const mesh = mergeStatic(parts, new THREE.MeshLambertMaterial({ vertexColors: true, side: doubleSided ? THREE.DoubleSide : THREE.FrontSide }));
    mesh.geometry.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    mesh.castShadow = true;
    parts.forEach(part => { group.remove(part); part.geometry.dispose(); part.material.dispose(); });
    group.add(mesh);
  }

  function mergeStatic(meshes, material) {
    const positions = [], normals = [], uvs = [], sides = [];
    const normalMatrix = new THREE.Matrix3();
    // Texture coordinates and face flags baked by road-materials.js survive
    // merging; parts without them get zeros so the arrays stay aligned.
    const withUv = meshes.some(m => m.geometry.attributes.uv), withSide = meshes.some(m => m.geometry.attributes.pddSide);
    meshes.forEach(mesh => {
      if (mesh.matrixAutoUpdate) mesh.updateMatrix();
      const geometry = mesh.geometry.index ? mesh.geometry.toNonIndexed() : mesh.geometry;
      const p = geometry.attributes.position, n = geometry.attributes.normal, uv = geometry.attributes.uv, side = geometry.attributes.pddSide;
      normalMatrix.getNormalMatrix(mesh.matrix);
      const v = new THREE.Vector3();
      for (let i = 0; i < p.count; i++) {
        v.fromBufferAttribute(p, i).applyMatrix4(mesh.matrix); positions.push(v.x, v.y, v.z);
        v.fromBufferAttribute(n, i).applyMatrix3(normalMatrix).normalize(); normals.push(v.x, v.y, v.z);
        if (withUv) uvs.push(uv ? uv.getX(i) : 0, uv ? uv.getY(i) : 0);
        if (withSide) sides.push(side ? side.getX(i) : 0);
      }
      if (geometry !== mesh.geometry) geometry.dispose();
    });
    const merged = new THREE.BufferGeometry();
    merged.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    merged.setAttribute('normal', new THREE.Float32BufferAttribute(normals, 3));
    if (uvs.length) merged.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
    if (sides.length) merged.setAttribute('pddSide', new THREE.Float32BufferAttribute(sides, 1));
    const mesh = new THREE.Mesh(merged, material);
    if (material?.userData?.pddKind) mesh.userData.pddSkinned = material.userData.pddKind;
    return mesh;
  }
  const CONE_MASCOT_CHANCE = 0.008;

  function shouldSpawnConeMascot() {
    if (typeof window !== 'undefined') {
      if (window.PDD_FORCE_CONE === true) return true;
      if (window.PDD_FORCE_CONE === false) return false;
      try {
        const search = window.location && window.location.search;
        if (search) {
          const params = new URLSearchParams(search);
          if (params.get('mascot') === '1' || params.get('cone') === '1') return true;
        }
      } catch (_) {}
    }
    return Math.random() < CONE_MASCOT_CHANCE;
  }

  function createConeMascotPedestrian() {
    const ped = new THREE.Group();
    ped.userData.isConeMascot = true;
    ped.userData.arms = [];
    ped.userData.legs = [];

    const ORANGE = 0xFF6E00;
    const DARK_ORANGE = 0xE65100;
    const WHITE = 0xFFFFFF;
    const BLACK = 0x1A1A1A;
    const BLUE = 0x1E88E5;
    const PINK = 0xFF4081;

    // 1. Legs with sneakers
    [-1, 1].forEach(side => {
      const hip = new THREE.Group();
      hip.position.set(side * 0.13, 0.28, 0);
      // Upper leg
      modelBox(hip, [0.10, 0.22, 0.10], ORANGE, 0, -0.09, 0);
      // Sneaker body
      modelBox(hip, [0.13, 0.09, 0.20], WHITE, 0, -0.21, 0.035);
      // Sole
      modelBox(hip, [0.14, 0.035, 0.21], DARK_ORANGE, 0, -0.25, 0.035);
      // Toe cap (rounded)
      modelPart(hip, new THREE.SphereGeometry(0.06, 12, 8), WHITE, 0, -0.21, 0.11);
      mergeModelParts(hip);
      ped.add(hip);
      ped.userData.legs.push(hip);
    });

    // 2. Right Arm (Thumbs up! 👍)
    const rightArm = new THREE.Group();
    rightArm.position.set(0.20, 0.80, 0.03);
    rightArm.rotation.set(-0.35, 0.25, 0.25);
    rightArm.userData.isThumbsUp = true;
    // Sleeve
    modelBox(rightArm, [0.09, 0.18, 0.09], ORANGE, 0.03, -0.06, 0.04, -0.4, 0, 0);
    // Glove cuff
    modelBox(rightArm, [0.13, 0.05, 0.13], WHITE, 0.06, -0.13, 0.10, -0.4, 0, 0);
    // Fist
    modelPart(rightArm, new THREE.SphereGeometry(0.068, 12, 8), WHITE, 0.07, -0.17, 0.14);
    // Finger ridges
    modelBox(rightArm, [0.07, 0.022, 0.025], 0xE5E5E5, 0.07, -0.155, 0.19);
    modelBox(rightArm, [0.07, 0.022, 0.025], 0xE5E5E5, 0.07, -0.185, 0.18);
    // Thumb pointing straight UP!
    modelPart(rightArm, new THREE.CylinderGeometry(0.024, 0.028, 0.085, 10), WHITE, 0.04, -0.095, 0.155, 0.2, 0, -0.1);
    modelPart(rightArm, new THREE.SphereGeometry(0.024, 8, 6), WHITE, 0.035, -0.052, 0.165);
    mergeModelParts(rightArm);
    ped.add(rightArm);
    ped.userData.arms.push(rightArm);

    // 3. Left Arm (Swinging cartoon arm)
    const leftArm = new THREE.Group();
    leftArm.position.set(-0.20, 0.80, 0.03);
    leftArm.rotation.set(0.25, -0.20, -0.25);
    // Sleeve
    modelBox(leftArm, [0.09, 0.18, 0.09], ORANGE, -0.03, -0.07, -0.03, 0.3, 0, 0);
    // Glove cuff
    modelBox(leftArm, [0.13, 0.05, 0.13], WHITE, -0.06, -0.15, -0.06, 0.3, 0, 0);
    // Glove palm
    modelPart(leftArm, new THREE.SphereGeometry(0.068, 12, 8), WHITE, -0.08, -0.20, -0.08);
    // Cartoon fingers
    modelBox(leftArm, [0.075, 0.065, 0.035], WHITE, -0.08, -0.255, -0.08);
    mergeModelParts(leftArm);
    ped.add(leftArm);
    ped.userData.arms.push(leftArm);

    // 4. Main Cone Body & Expressive Face
    const body = new THREE.Group();

    // Base plinth
    modelBox(body, [0.66, 0.065, 0.66], DARK_ORANGE, 0, 0.31, 0);
    modelBox(body, [0.56, 0.035, 0.56], ORANGE, 0, 0.355, 0);

    // Cone stacked segments
    // 1. Lower orange section (y=0.37 to 0.52, h=0.15)
    modelPart(body, new THREE.CylinderGeometry(0.245, 0.280, 0.15, 18), ORANGE, 0, 0.445, 0);
    // 2. Lower white reflective stripe (y=0.52 to 0.68, h=0.16)
    modelPart(body, new THREE.CylinderGeometry(0.205, 0.245, 0.16, 18), WHITE, 0, 0.60, 0);
    // 3. Middle orange face section (y=0.68 to 1.02, h=0.34)
    modelPart(body, new THREE.CylinderGeometry(0.130, 0.205, 0.34, 18), ORANGE, 0, 0.85, 0);
    // 4. Upper white reflective stripe (y=1.02 to 1.16, h=0.14)
    modelPart(body, new THREE.CylinderGeometry(0.098, 0.130, 0.14, 18), WHITE, 0, 1.09, 0);
    // 5. Top orange tip (y=1.16 to 1.30, h=0.14)
    modelPart(body, new THREE.CylinderGeometry(0.060, 0.098, 0.14, 18), ORANGE, 0, 1.23, 0);
    // 6. Rounded cone dome tip
    modelPart(body, new THREE.SphereGeometry(0.060, 12, 8), ORANGE, 0, 1.30, 0);

    // --- FACE FEATURES ---
    // Right Eye (Open, Big Cartoon Eye at y=0.88, z=0.17)
    modelPart(body, new THREE.SphereGeometry(0.065, 14, 8), WHITE, -0.065, 0.88, 0.168);
    // Eyelid / dark contour
    modelPart(body, new THREE.SphereGeometry(0.068, 14, 8), 0x221100, -0.065, 0.88, 0.164);
    // Blue Iris
    modelPart(body, new THREE.SphereGeometry(0.046, 12, 8), BLUE, -0.063, 0.875, 0.188);
    // Black Pupil
    modelPart(body, new THREE.SphereGeometry(0.030, 10, 8), BLACK, -0.062, 0.875, 0.198);
    // Sparkle highlights
    modelPart(body, new THREE.SphereGeometry(0.013, 8, 6), WHITE, -0.074, 0.893, 0.205);
    modelPart(body, new THREE.SphereGeometry(0.007, 8, 6), WHITE, -0.054, 0.860, 0.205);

    // Left Eye (Playfully Winking 😉 at y=0.88, z=0.17)
    modelPart(body, new THREE.TorusGeometry(0.038, 0.009, 8, 12, Math.PI * 0.95), BLACK, 0.065, 0.862, 0.182, 0, 0, -0.05);
    modelBox(body, [0.020, 0.012, 0.015], BLACK, 0.108, 0.868, 0.175, 0, 0, 0.45);

    // Eyebrows
    modelBox(body, [0.065, 0.018, 0.015], BLACK, -0.065, 0.965, 0.155, 0, 0, -0.15);
    modelBox(body, [0.065, 0.018, 0.015], BLACK, 0.065, 0.975, 0.155, 0, 0, 0.22);

    // Mouth (Curved Happy Open Smile)
    modelPart(body, new THREE.CylinderGeometry(0.075, 0.02, 0.055, 12), 0x1A0505, 0, 0.765, 0.190, Math.PI / 2, 0, 0);
    // Upper white teeth line
    modelBox(body, [0.095, 0.016, 0.022], WHITE, 0, 0.790, 0.198);
    // Cute pink tongue
    modelPart(body, new THREE.SphereGeometry(0.040, 10, 8), PINK, 0.006, 0.748, 0.202);
    // Rosy cheeks
    modelPart(body, new THREE.SphereGeometry(0.028, 8, 6), 0xFFA07A, -0.112, 0.795, 0.175);
    modelPart(body, new THREE.SphereGeometry(0.028, 8, 6), 0xFFA07A, 0.112, 0.795, 0.175);

    mergeModelParts(body);
    ped.add(body);
    ped.userData.body = body;

    ped.userData.appearance = 'cone_mascot';
    return ped;
  }

  function createPedestrian(color = 0x0574F8, variant = Math.floor(Math.random() * 12)) {
    if (variant === 'cone' || variant === 'mascot' || (variant !== 'no_mascot' && shouldSpawnConeMascot())) {
      return createConeMascotPedestrian();
    }
    const ped = new THREE.Group(), look = personLook(variant);
    ped.userData.arms = []; ped.userData.legs = [];
    [-1, 1].forEach(side => {
      const hip = new THREE.Group(); hip.position.set(side * 0.11, 0.65, 0);
      modelBox(hip, [0.15, 0.6, 0.16], look.pants, 0, -0.3, 0);
      modelBox(hip, [0.17, 0.09, 0.25], 0xECE5D6, 0, -0.61, 0.035);
      mergeModelParts(hip); ped.add(hip); ped.userData.legs.push(hip);
      const arm = new THREE.Group(); arm.position.set(side * 0.27, 1.12, 0);
      arm.rotation.z = side * 0.1;
      modelBox(arm, [0.13, 0.38, 0.14], color, 0, -0.16, 0);
      modelBox(arm, [0.12, 0.12, 0.13], look.skin, 0, -0.4, 0);
      mergeModelParts(arm); ped.add(arm); ped.userData.arms.push(arm);
    });
    modelBox(ped, [0.42, 0.58, 0.26], color, 0, 0.92, 0);
    // Clothing detail within the same outline: belt, collar, zip, neck, eyes.
    const shade = k => new THREE.Color(color).multiplyScalar(k).getHex();
    modelBox(ped, [0.43, 0.06, 0.27], 0x2B2F33, 0, 0.66, 0);
    modelBox(ped, [0.3, 0.06, 0.24], shade(0.75), 0, 1.19, 0.01);
    modelBox(ped, [0.025, 0.46, 0.01], shade(0.6), 0, 0.93, 0.131);
    modelPart(ped, new THREE.CylinderGeometry(0.07, 0.07, 0.08, 8), look.skin, 0, 1.23, 0);
    for (const ex of [-0.06, 0.06]) modelBox(ped, [0.035, 0.035, 0.02], 0x2B2F33, ex, 1.38, 0.178);
    modelPart(ped, new THREE.SphereGeometry(0.18, 8, 6), look.skin, 0, 1.36, 0);
    const hat = variant % 3;
    modelPart(ped, new THREE.SphereGeometry(0.185, 8, 4, 0, Math.PI * 2, 0, Math.PI / 2),
      hat === 0 ? look.top : look.hair, 0, 1.39, 0);
    if (hat === 0) modelBox(ped, [0.25, 0.04, 0.18], look.top, 0, 1.42, 0.14);
    if (hat === 2) modelBox(ped, [0.3, 0.25, 0.09], look.hair, 0, 1.28, -0.14);
    if (variant % 2) modelBox(ped, [0.3, 0.4, 0.16], look.top, 0, 0.95, -0.19);
    mergeModelParts(ped);
    const height = [0.94, 1.04, 1, 1.09][variant % 4];
    ped.scale.set(variant % 3 === 1 ? 1.08 : 1, height, 1);
    ped.userData.appearance = variant;
    return ped;
  }

  function createLampPost() {
    const lamp = new THREE.Group();
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.1, 5.2, 6), null);
    pole.position.y = 2.6;
    const arm = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.08, 0.08), null);
    arm.position.set(-0.6, 5.1, 0);
    // A cast foot and a collar where the arm joins (same mesh as the pole).
    const foot = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.17, 0.5, 8), null); foot.position.y = 0.25;
    const collar = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.1, 0.16, 8), null); collar.position.y = 5.1;
    const parts = [pole, arm, foot, collar];
    lamp.add(mergeStatic(parts, sceneryMat(0x5B646A))); parts.forEach(m => m.geometry.dispose());
    const head = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.16, 0.26), new THREE.MeshBasicMaterial({ color: 0xE6E9D8 }));
    head.position.set(-1.25, 5.05, 0); lamp.add(head);
    return lamp;
  }

  function animateWalk(mesh, time, legStride, armStride = legStride) {
    if (!mesh || !mesh.userData) return;
    if (mesh.userData.isConeMascot) {
      if (mesh.userData.legs) {
        mesh.userData.legs.forEach((leg, i) => {
          leg.rotation.x = Math.sin(time * 5 + i * Math.PI) * 0.35 * legStride;
        });
      }
      if (mesh.userData.arms) {
        mesh.userData.arms.forEach(arm => {
          if (arm.userData.isThumbsUp) {
            arm.rotation.x = -0.35 + Math.sin(time * 5) * 0.10 * armStride;
            arm.rotation.z = 0.25 + Math.cos(time * 5) * 0.05 * armStride;
          } else {
            arm.rotation.x = 0.25 + Math.sin(time * 5) * 0.35 * armStride;
          }
        });
      }
      if (mesh.userData.body) {
        mesh.userData.body.rotation.z = Math.sin(time * 5) * 0.04 * legStride;
        mesh.userData.body.position.y = Math.abs(Math.sin(time * 5)) * 0.02 * legStride;
      }
      return;
    }
    if (mesh.userData.legs) {
      mesh.userData.legs.forEach((leg, i) => { leg.rotation.x = Math.sin(time * 5 + i * Math.PI) * 0.32 * legStride; });
    }
    if (mesh.userData.arms) {
      mesh.userData.arms.forEach((arm, i) => { arm.rotation.x = Math.sin(time * 5 + i * Math.PI) * -0.2 * armStride; });
    }
  }
  window.PDD_STREET = {
    createPedestrian,
    createConeMascotPedestrian,
    CONE_MASCOT_CHANCE,
    createLampPost,
    animateWalk,
    personLook,
    peopleColors: PEOPLE_COLORS,
  };
})();
