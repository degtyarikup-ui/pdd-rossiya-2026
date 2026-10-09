// Shared officer model for the driving game and signal mini-game.
(() => {
  'use strict';
  function create(pose = 'arms_down') {
    const group = new THREE.Group();
    group.userData.isRegulator = true;
    group.userData.pose = pose;

    const darkUniform = new THREE.MeshLambertMaterial({ color: 0x1E293B });
    const vestLime = new THREE.MeshLambertMaterial({ color: 0x84CC16 });
    const stripeSilver = new THREE.MeshLambertMaterial({ color: 0xF1F5F9 });
    const skinMat = new THREE.MeshLambertMaterial({ color: 0xE2A76F, emissive: 0x241408 });
    const capMat = new THREE.MeshLambertMaterial({ color: 0x0F172A });
    const whiteMat = new THREE.MeshLambertMaterial({ color: 0xFFFFFF });
    const blackMat = new THREE.MeshLambertMaterial({ color: 0x111827 });

    const hairMat = new THREE.MeshLambertMaterial({ color: 0x2E1B14 });
    const noseMat = new THREE.MeshLambertMaterial({ color: 0xC88652, emissive: 0x1A0E06 });
    const lipMat = new THREE.MeshLambertMaterial({ color: 0x9B4D3C });
    const eyeWhiteMat = new THREE.MeshLambertMaterial({ color: 0xFFFFFF, emissive: 0x444444 });
    const eyeIrisMat = new THREE.MeshLambertMaterial({ color: 0x102A45, emissive: 0x081525 });
    const eyeGlintMat = new THREE.MeshBasicMaterial({ color: 0xFFFFFF });
    const cockadeMat = new THREE.MeshLambertMaterial({ color: 0xF59E0B, emissive: 0x553300 });

    // Boots
    [-0.14, 0.14].forEach(x => {
      const boot = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.16, 0.32), blackMat);
      boot.position.set(x, 0.08, 0.04);
      group.add(boot);
    });

    // Legs
    [-0.14, 0.14].forEach(x => {
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.11, 0.85, 8), darkUniform);
      leg.position.set(x, 0.58, 0);
      group.add(leg);
    });

    // Torso with vest
    const torso = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.65, 0.3), vestLime);
    torso.position.set(0, 1.28, 0);
    group.add(torso);

    // Reflective stripes on vest
    const hStripe = new THREE.Mesh(new THREE.BoxGeometry(0.52, 0.08, 0.32), stripeSilver);
    hStripe.position.set(0, 1.18, 0);
    group.add(hStripe);

    [-0.15, 0.15].forEach(x => {
      const vStripe = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.45, 0.32), stripeSilver);
      vStripe.position.set(x, 1.38, 0);
      group.add(vStripe);
    });



    // Neck & Shirt Collar (воротничок форменной рубашки и галстук ДПС)
    const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.075, 0.085, 0.12, 8), skinMat);
    neck.position.set(0, 1.62, 0);
    group.add(neck);

    [-0.055, 0.055].forEach(x => {
      const collar = new THREE.Mesh(new THREE.BoxGeometry(0.065, 0.042, 0.024), whiteMat);
      collar.position.set(x, 1.58, 0.148);
      collar.rotation.z = (x < 0 ? 0.38 : -0.38);
      group.add(collar);
    });
    const tie = new THREE.Mesh(new THREE.BoxGeometry(0.045, 0.13, 0.018), darkUniform);
    tie.position.set(0, 1.52, 0.152);
    group.add(tie);

    // Head base
    const head = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.26, 0.24), skinMat);
    head.position.set(0, 1.73, 0);
    group.add(head);

    // Eyes: Sclera (белки глаз), Iris (радужка) & Catchlight (блик)
    [-0.056, 0.056].forEach(x => {
      const eyeLid = new THREE.Mesh(new THREE.BoxGeometry(0.062, 0.038, 0.010), noseMat);
      eyeLid.position.set(x, 1.745, 0.120);
      group.add(eyeLid);

      const eyeWhite = new THREE.Mesh(new THREE.BoxGeometry(0.052, 0.030, 0.012), eyeWhiteMat);
      eyeWhite.position.set(x, 1.745, 0.124);
      group.add(eyeWhite);

      const pupil = new THREE.Mesh(new THREE.BoxGeometry(0.028, 0.028, 0.010), eyeIrisMat);
      pupil.position.set(x, 1.745, 0.129);
      group.add(pupil);

      const glint = new THREE.Mesh(new THREE.BoxGeometry(0.010, 0.010, 0.008), eyeGlintMat);
      glint.position.set(x + 0.007, 1.753, 0.133);
      group.add(glint);

      // Eyebrows (выразительные мужские брови)
      const brow = new THREE.Mesh(new THREE.BoxGeometry(0.060, 0.016, 0.018), hairMat);
      brow.position.set(x, 1.776, 0.127);
      brow.rotation.z = (x < 0 ? -0.08 : 0.08);
      group.add(brow);
    });

    // Nose (прямой выразительный нос со светотенью)
    const noseBridge = new THREE.Mesh(new THREE.BoxGeometry(0.038, 0.056, 0.042), noseMat);
    noseBridge.position.set(0, 1.705, 0.138);
    group.add(noseBridge);

    const noseTip = new THREE.Mesh(new THREE.BoxGeometry(0.042, 0.026, 0.028), noseMat);
    noseTip.position.set(0, 1.682, 0.150);
    group.add(noseTip);

    // Mouth (губы и четкая линия рта)
    const lips = new THREE.Mesh(new THREE.BoxGeometry(0.070, 0.018, 0.016), lipMat);
    lips.position.set(0, 1.644, 0.125);
    group.add(lips);

    const mouthLine = new THREE.Mesh(new THREE.BoxGeometry(0.056, 0.005, 0.008), new THREE.MeshLambertMaterial({ color: 0x6E291C }));
    mouthLine.position.set(0, 1.644, 0.131);
    group.add(mouthLine);

    // Chin (подбородок)
    const chin = new THREE.Mesh(new THREE.BoxGeometry(0.090, 0.032, 0.024), skinMat);
    chin.position.set(0, 1.612, 0.125);
    group.add(chin);

    // Ears (ушные раковины)
    [-0.124, 0.124].forEach(x => {
      const ear = new THREE.Mesh(new THREE.BoxGeometry(0.016, 0.052, 0.032), skinMat);
      ear.position.set(x, 1.722, -0.015);
      group.add(ear);
    });

    // Hair & Sideburns (виски и чёлка из-под фуражки; затылок чистый без пятен)
    [-0.122, 0.122].forEach(x => {
      const sideburn = new THREE.Mesh(new THREE.BoxGeometry(0.012, 0.055, 0.032), hairMat);
      sideburn.position.set(x, 1.762, 0.030);
      group.add(sideburn);
    });
    const hairFringe = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.018, 0.012), hairMat);
    hairFringe.position.set(0, 1.822, 0.122);
    group.add(hairFringe);

    // Police Cap
    const capBand = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.15, 0.08, 12), capMat);
    capBand.position.set(0, 1.86, 0);
    group.add(capBand);
    const capCrown = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.15, 0.06, 12), capMat);
    capCrown.position.set(0, 1.92, 0);
    group.add(capCrown);
    const visor = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.02, 0.14), blackMat);
    visor.position.set(0, 1.84, 0.18);
    visor.rotation.x = 0.2;
    group.add(visor);
    const cockade = new THREE.Mesh(new THREE.BoxGeometry(0.055, 0.065, 0.025), cockadeMat);
    cockade.position.set(0, 1.88, 0.155);
    group.add(cockade);

    // The model faces +Z: anatomical RIGHT is -X, LEFT is +X.
    function arm(x) {
      const pivot = new THREE.Group();
      pivot.position.set(x, 1.5, 0);
      const sleeve = new THREE.Mesh(new THREE.CylinderGeometry(0.065, 0.055, 0.5, 8), darkUniform);
      sleeve.position.y = -0.25; pivot.add(sleeve);
      const cuff = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.055, 8), stripeSilver);
      cuff.position.y = -0.44; pivot.add(cuff);
      const hand = new THREE.Mesh(new THREE.BoxGeometry(0.085, 0.1, 0.085), whiteMat);
      hand.position.y = -0.54; pivot.add(hand);
      group.add(pivot); return pivot;
    }
    const right = arm(-0.32), left = arm(0.32);
    const baton = new THREE.Group();
    // Extends from the fist away from the shoulder in every pose.
    const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 0.44, 8), whiteMat);
    shaft.position.y = -0.8; baton.add(shaft);
    for (let i = 0; i < 3; i++) {
      const stripe = new THREE.Mesh(new THREE.CylinderGeometry(0.026, 0.026, 0.07, 8), blackMat);
      stripe.position.y = -0.65 - i * 0.12; baton.add(stripe);
    }
    right.add(baton);
    group.controllerRig = { left, right, vest: torso };
    setPose(group, pose);
    group.traverse(o => { if (o.isMesh) o.castShadow = true; });
    return group;
  }
  const poses = {
    arms_down: { left: [0, 0, 0], right: [0, 0, 0] },
    arms_sides: { left: [0, 0, Math.PI / 2], right: [0, 0, -Math.PI / 2] },
    right_arm_forward: { left: [0, 0, 0], right: [-Math.PI / 2, 0, 0] },
    arm_up: { left: [0, 0, 0], right: [0, 0, Math.PI] },
  };
  function setPose(group, pose) {
    const angles = poses[pose] || poses.arms_down;
    group.userData.pose = pose;
    group.controllerRig.left.rotation.set(...angles.left);
    group.controllerRig.right.rotation.set(...angles.right);
  }
  window.PDD_CONTROLLER = { create, poses, setPose };
})();
