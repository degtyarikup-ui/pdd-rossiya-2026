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
  const CONE_MASCOT_CHANCE = 0.003;

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
    ped.userData.legs = [];
    ped.userData.arms = [];

    const ORANGE = 0xFF6E00;
    const DARK_ORANGE = 0xE65100;
    const WHITE = 0xFFFFFF;
    const BLACK = 0x1A1A1A;
    const BLUE = 0x0288D1;
    const CYAN = 0x4FC3F7;
    const MOUTH_DARK = 0x240606;
    const PINK = 0xFF4081;
    const CHEEK_PINK = 0xFFA07A;

    // 1. SHORT CUTE SNEAKER LEGS (sitting snugly under base plate)
    [-1, 1].forEach(side => {
      const hip = new THREE.Group();
      hip.position.set(side * 0.12, 0.12, 0);
      // Short leg link
      modelBox(hip, [0.08, 0.07, 0.08], ORANGE, 0, -0.035, 0);
      // White sneaker body
      modelBox(hip, [0.12, 0.050, 0.17], WHITE, 0, -0.080, 0.025);
      // Round sneaker toe cap
      modelPart(hip, new THREE.SphereGeometry(0.046, 12, 8), WHITE, 0, -0.080, 0.095);
      // Dark orange sole touching the ground at y=0
      modelBox(hip, [0.13, 0.022, 0.18], DARK_ORANGE, 0, -0.110, 0.025);
      mergeModelParts(hip);
      ped.add(hip);
      ped.userData.legs.push(hip);
    });

    // 2. CONE BODY
    const body = new THREE.Group();

    // Plinth base (lowered)
    modelBox(body, [0.68, 0.045, 0.68], DARK_ORANGE, 0, 0.155, 0);
    modelBox(body, [0.58, 0.025, 0.58], ORANGE, 0, 0.19, 0);

    // Cone stacked segments
    // 1. Lower orange (h=0.12, y=0.20 to 0.32)
    modelPart(body, new THREE.CylinderGeometry(0.245, 0.280, 0.12, 20), ORANGE, 0, 0.26, 0);
    // 2. Lower white stripe (h=0.15, y=0.32 to 0.47)
    modelPart(body, new THREE.CylinderGeometry(0.205, 0.245, 0.15, 20), WHITE, 0, 0.395, 0);
    // 3. Middle orange FACE (h=0.34, y=0.47 to 0.81)
    modelPart(body, new THREE.CylinderGeometry(0.130, 0.205, 0.34, 20), ORANGE, 0, 0.64, 0);
    // 4. Upper white stripe (h=0.13, y=0.81 to 0.94)
    modelPart(body, new THREE.CylinderGeometry(0.098, 0.130, 0.13, 20), WHITE, 0, 0.875, 0);
    // 5. Top orange (h=0.13, y=0.94 to 1.07)
    modelPart(body, new THREE.CylinderGeometry(0.060, 0.098, 0.13, 20), ORANGE, 0, 1.005, 0);
    // 6. Rounded cone dome tip
    modelPart(body, new THREE.SphereGeometry(0.060, 14, 10), ORANGE, 0, 1.07, 0);

    // --- FACE (Tilted flush with cone slope) ---
    const SLOPE = -0.217;

    // --- A. HAPPY PIXAR-STYLE SMILE ---
    const mouthShape = new THREE.Shape();
    mouthShape.moveTo(-0.084, 0.024);
    mouthShape.quadraticCurveTo(0, 0.040, 0.084, 0.024);
    mouthShape.quadraticCurveTo(0.092, -0.010, 0.070, -0.044);
    mouthShape.quadraticCurveTo(0, -0.078, -0.070, -0.044);
    mouthShape.quadraticCurveTo(-0.092, -0.010, -0.084, 0.024);

    const mouthGeo = new THREE.ShapeGeometry(mouthShape, 16);
    modelPart(body, mouthGeo, MOUTH_DARK, 0, 0.585, 0.190, SLOPE, 0, 0);

    // Upper teeth (clean white band along top of smile)
    const teethShape = new THREE.Shape();
    teethShape.moveTo(-0.076, 0.024);
    teethShape.quadraticCurveTo(0, 0.038, 0.076, 0.024);
    teethShape.lineTo(0.066, 0.006);
    teethShape.quadraticCurveTo(0, 0.018, -0.066, 0.006);
    teethShape.closePath();

    const teethGeo = new THREE.ShapeGeometry(teethShape, 16);
    modelPart(body, teethGeo, WHITE, 0, 0.585, 0.192, SLOPE, 0, 0);

    // Pink tongue at the bottom of the smile
    const tongueShape = new THREE.Shape();
    tongueShape.moveTo(-0.048, -0.030);
    tongueShape.quadraticCurveTo(0, -0.002, 0.048, -0.030);
    tongueShape.quadraticCurveTo(0.038, -0.066, 0, -0.074);
    tongueShape.quadraticCurveTo(-0.038, -0.066, -0.048, -0.030);

    const tongueGeo = new THREE.ShapeGeometry(tongueShape, 16);
    modelPart(body, tongueGeo, PINK, 0, 0.585, 0.192, SLOPE, 0, 0);

    // Smile corner creases
    modelBox(body, [0.018, 0.008, 0.005], MOUTH_DARK, 0.090, 0.608, 0.183, SLOPE, 0.35, 0.5);
    modelBox(body, [0.018, 0.008, 0.005], MOUTH_DARK, -0.090, 0.608, 0.183, SLOPE, -0.35, -0.5);

    // --- B. OPEN RIGHT EYE (Mascot's right eye, viewer's LEFT) ---
    const eyeRotY = -0.40;
    // Dark outline
    modelPart(body, new THREE.CylinderGeometry(0.048, 0.048, 0.008, 24), BLACK, -0.064, 0.698, 0.165, Math.PI/2 + SLOPE, eyeRotY, 0, 0.86, 1.0, 1.25);
    // White sclera
    modelPart(body, new THREE.CylinderGeometry(0.044, 0.044, 0.010, 24), WHITE, -0.064, 0.698, 0.167, Math.PI/2 + SLOPE, eyeRotY, 0, 0.86, 1.0, 1.25);
    // Large Deep Blue Iris
    modelPart(body, new THREE.CylinderGeometry(0.033, 0.033, 0.012, 22), BLUE, -0.064, 0.698, 0.169, Math.PI/2 + SLOPE, eyeRotY, 0, 0.86, 1.0, 1.15);
    // Soft light cyan shine at bottom of iris
    modelPart(body, new THREE.CylinderGeometry(0.024, 0.024, 0.013, 16), CYAN, -0.064, 0.684, 0.170, Math.PI/2 + SLOPE, eyeRotY, 0, 0.82, 1.0, 0.55);
    // Black Pupil
    modelPart(body, new THREE.CylinderGeometry(0.020, 0.020, 0.014, 20), BLACK, -0.064, 0.699, 0.171, Math.PI/2 + SLOPE, eyeRotY, 0, 0.86, 1.0, 1.05);
    // Primary big shine dot (top-left)
    modelPart(body, new THREE.CylinderGeometry(0.009, 0.009, 0.015, 12), WHITE, -0.073, 0.713, 0.173, Math.PI/2 + SLOPE, eyeRotY, 0);
    // Secondary small shine dot (bottom-right)
    modelPart(body, new THREE.CylinderGeometry(0.005, 0.005, 0.015, 10), WHITE, -0.056, 0.685, 0.173, Math.PI/2 + SLOPE, eyeRotY, 0);

    // --- C. WINKING LEFT EYE (Mascot's left eye, viewer's RIGHT) ---
    const winkRotY = 0.40;
    modelPart(body, new THREE.TorusGeometry(0.036, 0.008, 8, 16, Math.PI * 0.88), BLACK, 0.064, 0.682, 0.168, SLOPE, winkRotY, 0.18);
    // Eyelashes at outer corner: angled upwards-right
    modelBox(body, [0.018, 0.007, 0.005], BLACK, 0.098, 0.698, 0.155, SLOPE, winkRotY, 0.45);
    modelBox(body, [0.014, 0.006, 0.005], BLACK, 0.100, 0.686, 0.155, SLOPE, winkRotY, 0.15);

    // --- D. EYEBROWS ---
    // Right eyebrow: arched in a friendly high curve
    modelPart(body, new THREE.TorusGeometry(0.048, 0.008, 6, 12, Math.PI * 0.45), BLACK, -0.064, 0.765, 0.146, SLOPE, eyeRotY, 0.35);
    // Left eyebrow: confident cheerful wink tilt
    modelBox(body, [0.064, 0.015, 0.008], BLACK, 0.064, 0.762, 0.146, SLOPE, winkRotY, 0.22);

    // --- E. ROSY CHEEKS ---
    modelPart(body, new THREE.CylinderGeometry(0.026, 0.026, 0.008, 16), CHEEK_PINK, -0.100, 0.628, 0.158, Math.PI/2 + SLOPE, -0.55, 0, 0.9, 1.0, 0.7);
    modelPart(body, new THREE.CylinderGeometry(0.026, 0.026, 0.008, 16), CHEEK_PINK, 0.100, 0.628, 0.158, Math.PI/2 + SLOPE, 0.55, 0, 0.9, 1.0, 0.7);

    mergeModelParts(body);
    ped.add(body);
    ped.userData.body = body;

    // 3. MASCOT RIGHT ARM (Viewer's LEFT) -> THE PROUD THUMBS-UP 👍 IN FOREGROUND!
    const rightArm = new THREE.Group();
    rightArm.position.set(-0.16, 0.60, 0.06);
    rightArm.userData.isThumbsUp = true;

    // Rounded shoulder sphere
    modelPart(rightArm, new THREE.SphereGeometry(0.048, 12, 10), ORANGE, 0, 0, 0);
    // Sleeve extending forward
    modelPart(rightArm, new THREE.CylinderGeometry(0.044, 0.040, 0.11, 12), ORANGE, -0.02, -0.035, 0.05, 0.55, -0.25, -0.20);
    // Thick puffy white glove cuff ring
    modelPart(rightArm, new THREE.CylinderGeometry(0.062, 0.058, 0.045, 16), WHITE, -0.040, -0.075, 0.115, 0.55, -0.25, -0.20);
    // Big puffy white glove palm / fist
    modelPart(rightArm, new THREE.SphereGeometry(0.064, 16, 12), WHITE, -0.050, -0.105, 0.160);
    // Curled fingers along front of palm
    modelPart(rightArm, new THREE.CylinderGeometry(0.016, 0.016, 0.065, 10), 0xF5F5F5, -0.050, -0.090, 0.210, 0, 0, Math.PI/2);
    modelPart(rightArm, new THREE.CylinderGeometry(0.016, 0.016, 0.065, 10), 0xF0F0F0, -0.050, -0.112, 0.208, 0, 0, Math.PI/2);
    modelPart(rightArm, new THREE.CylinderGeometry(0.015, 0.015, 0.060, 10), 0xE8E8E8, -0.050, -0.132, 0.200, 0, 0, Math.PI/2);

    // BIG PROUD THUMB UP (👍):
    modelPart(rightArm, new THREE.CylinderGeometry(0.026, 0.029, 0.100, 14), WHITE, -0.028, -0.035, 0.170, -0.15, 0.05, 0.05);
    modelPart(rightArm, new THREE.SphereGeometry(0.027, 14, 10), WHITE, -0.024, 0.016, 0.172);

    mergeModelParts(rightArm);
    ped.add(rightArm);
    ped.userData.arms.push(rightArm);

    // 4. MASCOT LEFT ARM (Viewer's RIGHT) -> Confident arm resting by side
    const leftArm = new THREE.Group();
    leftArm.position.set(0.16, 0.60, 0.04);

    // Shoulder sphere
    modelPart(leftArm, new THREE.SphereGeometry(0.048, 12, 10), ORANGE, 0, 0, 0);
    // Sleeve connecting smoothly
    modelPart(leftArm, new THREE.CylinderGeometry(0.044, 0.038, 0.10, 12), ORANGE, 0.015, -0.040, -0.015, -0.25, 0.15, 0.20);
    // White cuff ring enclosing sleeve end
    modelPart(leftArm, new THREE.CylinderGeometry(0.058, 0.054, 0.042, 14), WHITE, 0.030, -0.085, -0.030, -0.25, 0.15, 0.20);
    // White glove palm
    modelPart(leftArm, new THREE.SphereGeometry(0.058, 14, 10), WHITE, 0.040, -0.125, -0.045);
    // Curled fingers
    modelPart(leftArm, new THREE.SphereGeometry(0.044, 12, 8), 0xF0F0F0, 0.042, -0.160, -0.050);

    mergeModelParts(leftArm);
    ped.add(leftArm);
    ped.userData.arms.push(leftArm);

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
            arm.rotation.x = Math.sin(time * 5) * 0.12 * armStride;
            arm.rotation.z = Math.cos(time * 5) * 0.06 * armStride;
          } else {
            arm.rotation.x = Math.sin(time * 5) * -0.32 * armStride;
          }
        });
      }
      if (mesh.userData.body) {
        mesh.userData.body.rotation.z = Math.sin(time * 5) * 0.04 * legStride;
        mesh.userData.body.position.y = Math.abs(Math.sin(time * 5)) * 0.015 * legStride;
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
