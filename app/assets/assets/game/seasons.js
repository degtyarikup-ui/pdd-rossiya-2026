// Calendar, palettes and one instanced leaf effect shared by both 3D games.
(() => {
  'use strict';
  const SEASONS = {
    summer: { ground: 0x86A97A, verge: [0x86A97A, 0x86A97A, 0x86A97A], sky: 0xDEE4E5, skyDark: 0x252B30,
      sun: 0xFFF9EE, sunIntensity: 0.6, ambient: 0.72, canopy: [0x4C9A4F, 0x3F8A46, 0x7FB069, 0x5FA85A],
      birch: 0x7FB069, pine: [0x388E3C, 0x43A047], roof: null, sidewalk: 0x747970, precipitation: 'rain', hillColor: 0x6E8F63 },
    autumn: { ground: 0x9CA56A, verge: [0x9CA56A, 0x9CA56A, 0x9CA56A], sky: 0xE8E1D1, skyDark: 0x2A2823,
      sun: 0xFFE3B8, sunIntensity: 0.56, ambient: 0.7, canopy: [0xD98A2B, 0xC94F2B, 0xE0B33C, 0xB86A2A, 0xC7A24A],
      birch: 0xE0B33C, pine: [0x3E7C42, 0x467E3C], roof: null, sidewalk: 0x7A776F, precipitation: 'rain', hillColor: 0x8E8A55 },
    winter: { ground: 0xE4E8EC, verge: [0xE4E8EC, 0xE4E8EC, 0xE4E8EC], sky: 0xE1E6EB, skyDark: 0x20262C,
      sun: 0xEAF1FA, sunIntensity: 0.5, ambient: 0.82, canopy: [0x8A7A66, 0x9C8B78, 0xBDC6CC, 0x8C8578],
      birch: 0xB9C4CC, pine: [0x3A6B45, 0x40704A], roof: 0xC7D0D8, sidewalk: 0xB9C0C6, precipitation: 'snow', hillColor: 0xD8DEE3 },
  };
  function seasonFromDate(date = new Date()) {
    const m = date.getMonth() + 1;
    return m >= 9 && m <= 11 ? 'autumn' : (m === 12 || m <= 2) ? 'winter' : 'summer';
  }
  function createLeaves(scene, {lowEnd = false, palette, spanX = 56, spanZ = 70, height = 16,
    count = lowEnd ? 18 : 36, scaleMin = 1.3, scaleMax = 2, spreadEvenly = false} = {}) {
  let leafFx = null;
  function ensureLeafFx() {
    if (leafFx) return leafFx;
    const shape = new THREE.Shape();
    shape.moveTo(0, -0.17);
    shape.quadraticCurveTo(0.13, -0.05, 0.02, 0.17);
    shape.lineTo(0, 0.2);
    shape.quadraticCurveTo(-0.13, -0.05, 0, -0.17);
    const geometry = new THREE.ShapeGeometry(shape, 3);
    geometry.rotateX(-Math.PI / 2);
    const mesh = new THREE.InstancedMesh(geometry, new THREE.MeshLambertMaterial({ side: THREE.DoubleSide }), count);
    mesh.frustumCulled = false; mesh.castShadow = false;
    const leaves = [];
    for (let i = 0; i < count; i++) leaves.push({ born: false });
    scene.add(mesh);
    leafFx = { mesh, leaves, count, dummy: new THREE.Object3D(), colour: new THREE.Color() };
    return leafFx;
  }
  function spawnLeaf(leaf, centre, anywhereHigh, index) {
    const colours = palette();
    // Sparse effects use one random position per cell, avoiding a clump of
    // leaves in front of the officer. Main-game defaults remain unchanged.
    const columns = Math.ceil(Math.sqrt(count));
    const rows = Math.ceil(count / columns);
    const x = spreadEvenly ? ((index % columns) + Math.random()) / columns : Math.random();
    const z = spreadEvenly ? (Math.floor(index / columns) + Math.random()) / rows : Math.random();
    leaf.x = centre.x + (x - 0.5) * spanX;
    leaf.z = centre.z + (z - (spreadEvenly ? 0.5 : 0.4)) * spanZ;
    leaf.y = anywhereHigh ? 0.5 + Math.random() * (height - 0.5) : height * (0.75 + Math.random() * 0.25);
    leaf.fall = 0.55 + Math.random() * 0.5;
    leaf.sway = 0.6 + Math.random() * 0.9; leaf.swayRate = 1.1 + Math.random() * 1.3; leaf.phase = Math.random() * 6.3;
    leaf.spin = (Math.random() - 0.5) * 5; leaf.tumble = 2 + Math.random() * 3;
    leaf.rot = Math.random() * 6.3; leaf.rest = 0; leaf.scale = scaleMin + Math.random() * (scaleMax - scaleMin); leaf.time = 0;
    leaf.colour = colours[Math.floor(Math.random() * colours.length)];
    leaf.born = true;
  }
  function update(dt, {enabled, centre, rain = 0}) {
    const autumn = enabled;
    if (!autumn) { if (leafFx) leafFx.mesh.visible = false; return; }
    const fx = ensureLeafFx();
    fx.mesh.visible = true;
    // Rain knocks most of them down: fewer leaves in the air.
    const active = Math.round(fx.count * (1 - 0.6 * rain));
    fx.leaves.forEach((leaf, i) => {
      const d = fx.dummy;
      if (!leaf.born || (i >= active && leaf.y > 0.05 && !leaf.rest)) {
        if (!leaf.born) spawnLeaf(leaf, centre, true, i);
        if (i >= active) { d.scale.setScalar(0.0001); d.updateMatrix(); fx.mesh.setMatrixAt(i, d.matrix); leaf.born = false; return; }
      }
      leaf.time += dt;
      let fade = 1;
      if (leaf.y > 0.03) {
        // A light breeze towards the camera; the sway is the leaf rocking.
        leaf.y = Math.max(0.03, leaf.y - leaf.fall * dt * (1 + 0.35 * Math.sin(leaf.time * leaf.swayRate * 2 + leaf.phase)));
        leaf.x += (Math.cos(leaf.time * leaf.swayRate + leaf.phase) * leaf.sway + 0.25) * dt;
        leaf.z += (-0.6 + Math.sin(leaf.time * leaf.swayRate * 0.7 + leaf.phase) * 0.3) * dt;
        leaf.rot += leaf.spin * dt;
        d.rotation.set(Math.sin(leaf.time * leaf.tumble + leaf.phase) * 0.9, leaf.rot, Math.cos(leaf.time * leaf.tumble * 0.8) * 0.7);
      } else {
        leaf.rest += dt;
        d.rotation.set(0, leaf.rot, 0);
        fade = 1 - THREE.MathUtils.smoothstep(leaf.rest, 2.5, 4);
        if (leaf.rest > 4) spawnLeaf(leaf, centre, false, i);
      }
      // Leaves left far behind the moving view start again above it.
      if (Math.abs(leaf.x - centre.x) > spanX * 0.72 || Math.abs(leaf.z - centre.z) > spanZ * 0.72) spawnLeaf(leaf, centre, false, i);
      d.position.set(leaf.x, leaf.y, leaf.z);
      d.scale.setScalar(leaf.scale * Math.max(0.0001, fade));
      d.updateMatrix();
      fx.mesh.setMatrixAt(i, d.matrix);
      fx.mesh.setColorAt(i, fx.colour.setHex(leaf.colour));
    });
    fx.mesh.instanceMatrix.needsUpdate = true;
    if (fx.mesh.instanceColor) fx.mesh.instanceColor.needsUpdate = true;
  }

  return {update, get mesh() { return leafFx?.mesh; }};
  }
  window.PDD_SEASONS = { palettes: SEASONS, fromDate: seasonFromDate, createLeaves };
})();
