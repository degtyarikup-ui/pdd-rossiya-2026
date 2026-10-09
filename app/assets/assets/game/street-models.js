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
  function modelPart(group, geometry, color, x, y, z) {
    const mesh = new THREE.Mesh(geometry, sceneryMat(color));
    mesh.position.set(x, y, z); mesh.castShadow = true; group.add(mesh);
    return mesh;
  }
  function modelBox(group, size, color, x, y, z) {
    return modelPart(group, new THREE.BoxGeometry(...size), color, x, y, z);
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
  function createPedestrian(color = 0x0574F8, variant = Math.floor(Math.random() * 12)) {
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
    mesh.userData.legs.forEach((leg, i) => { leg.rotation.x = Math.sin(time * 5 + i * Math.PI) * 0.32 * legStride; });
    mesh.userData.arms.forEach((arm, i) => { arm.rotation.x = Math.sin(time * 5 + i * Math.PI) * -0.2 * armStride; });
  }
  window.PDD_STREET = { createPedestrian, createLampPost, animateWalk, personLook, peopleColors: PEOPLE_COLORS };
})();
