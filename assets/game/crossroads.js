// 3D-симулятор и игра «Разрули перекресток» на Three.js
// Проверяет очередность проезда перекрестков по ПДД РФ (п. 13.1–13.12, п. 3.2).
// Графика стандарта флагманской игры: PDD_ROADS шейдерный асфальт, PCFSoftShadowMap,
// процедурный купол неба seasons.js, ГОСТ знаки приоритета, модели PDD_VEHICLES.

(() => {
  'use strict';

  // Фирменные цвета
  const BRAND = {
    accent: 0x0574F8,
    accentLight: 0xE8F2FE,
    green: 0x2BC280,
    greenLight: 0xE8F8F0,
    red: 0xED4621,
    redLight: 0xFFFFECE8,
    gold: 0xFFA53C,
    asphalt: 0x2C2F36,
    asphaltMarking: 0xF2F4F8,
    asphaltMarkingYellow: 0xF5B025,
    tramRed: 0xD32F2F,
    tramWhite: 0xF5F5F5,
  };

  const CITY_REACH = 160;
  const ROAD_WIDTH = 13.6;
  const HALF_ROAD = ROAD_WIDTH / 2;
  const LANE_OFFSET = 3.4; // центр полосы движения

  // --- Переменные сцены ---
  let scene, camera, renderer, container;
  let envGroup, vehiclesGroup, signsGroup, fxGroup;
  let skyDome, sunLight;
  let clock = new THREE.Clock();

  // Окружение по сезону
  const seasonName = (window.PDD_SEASONS && window.PDD_SEASONS.fromDate)
    ? window.PDD_SEASONS.fromDate()
    : 'summer';
  const season = (window.PDD_SEASONS && window.PDD_SEASONS.palettes && window.PDD_SEASONS.palettes[seasonName]) || {
    sky: 0x88B8E6,
    sun: 0xFFF5E6,
    sunIntensity: 1.15,
    ambient: 0.55,
    ground: 0x6E8A5A,
    canopy: [0x4F7942, 0x3E6334, 0x6B8E23],
  };

  const lowEnd = (navigator.hardwareConcurrency || 8) <= 2 || (navigator.deviceMemory || 8) <= 3;
  const weak = lowEnd || (navigator.hardwareConcurrency || 8) <= 4;

  // Камера и зум
  let camZoom = 1.0;
  let camShake = 0;
  let viewInsetBottom = 0;
  const raycaster = new THREE.Raycaster();
  const mouse = new THREE.Vector2();

  // Состояние сценария
  let currentScenario = null;
  let activeActors = new Map(); // id -> { mesh, badge, data, state: 'waiting'|'driving'|'done'|'crashed' }
  let currentStep = 1;
  let isResolving = false;
  let drivingAnimations = []; // массив активных анимаций
  let activeSigns = [];
  let walkers = [];

  // --- Инициализация Three.js ---
  function init() {
    container = document.getElementById('canvas-container');
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(season.sky);
    scene.fog = new THREE.Fog(season.sky, 110, 320);

    // Процедурный градиентный купол неба с облаками (как в флагмане)
    skyDome = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 16), new THREE.ShaderMaterial({
      uniforms: {
        horizon: { value: new THREE.Color(season.sky) },
        zenith: { value: new THREE.Color(season.sky) },
        cloud: { value: 0.55 }
      },
      vertexShader: 'varying vec3 vDir; void main(){ vDir = position; vec4 p = projectionMatrix * vec4((modelViewMatrix * vec4(position, 0.0)).xyz, 1.0); gl_Position = p.xyww; }',
      fragmentShader: [
        'uniform vec3 horizon; uniform vec3 zenith; uniform float cloud; varying vec3 vDir;',
        'float h(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }',
        'float n(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);',
        '  return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y); }',
        'void main(){ vec3 d = normalize(vDir); float up = clamp(d.y, 0.0, 1.0);',
        '  vec3 c = mix(horizon, zenith, pow(up, 0.35));',
        '  vec2 q = d.xz / (d.y + 0.25) * 2.2; float f = n(q) * 0.55 + n(q * 2.1) * 0.3 + n(q * 4.3) * 0.15;',
        '  float puffs = smoothstep(0.58, 0.8, f) * smoothstep(0.0, 0.06, d.y) * cloud;',
        '  gl_FragColor = vec4(mix(c, vec3(1.0), puffs * 0.85), 1.0); }'].join('\n'),
      side: THREE.BackSide,
      depthWrite: false
    }));
    skyDome.frustumCulled = false;
    skyDome.renderOrder = -1;
    scene.add(skyDome);

    // Перспективная камера: изометрический обзор под углом 46 градусов
    camera = new THREE.PerspectiveCamera(42, width / height, 0.5, 450);
    updateCameraPosition();

    renderer = new THREE.WebGLRenderer({ antialias: !lowEnd, alpha: false, powerPreference: 'high-performance' });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, lowEnd ? 1.25 : 1.75));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    container.appendChild(renderer.domElement);

    setupLighting();

    envGroup = new THREE.Group();
    vehiclesGroup = new THREE.Group();
    signsGroup = new THREE.Group();
    fxGroup = new THREE.Group();

    scene.add(envGroup);
    scene.add(vehiclesGroup);
    scene.add(signsGroup);
    scene.add(fxGroup);

    buildEnvironment();

    // Подключаем процедурные шейдерные материалы дорог (асфальт с микропорами)
    if (window.PDD_ROADS) {
      window.PDD_ROADS.attach(renderer, { roots: () => [envGroup], lineage: () => null });
    }

    // Обработчики событий
    window.addEventListener('resize', onWindowResize);
    renderer.domElement.addEventListener('pointerdown', onPointerDown);

    // Уведомление Flutter о готовности Three.js
    notifyFlutter({ type: 'ready' });

    animate();
  }

  function setupLighting() {
    const ambientLight = new THREE.AmbientLight(0xFFFFFF, season.ambient);
    scene.add(ambientLight);

    sunLight = new THREE.DirectionalLight(season.sun, season.sunIntensity);
    sunLight.position.set(22, 65, 18);
    sunLight.castShadow = true;
    sunLight.shadow.mapSize.width = lowEnd ? 512 : 1024;
    sunLight.shadow.mapSize.height = lowEnd ? 512 : 1024;
    sunLight.shadow.camera.near = 10;
    sunLight.shadow.camera.far = 180;
    const d = 34;
    sunLight.shadow.camera.left = -d;
    sunLight.shadow.camera.right = d;
    sunLight.shadow.camera.top = d;
    sunLight.shadow.camera.bottom = -d;
    sunLight.shadow.bias = -0.0005;
    sunLight.shadow.radius = 4;
    scene.add(sunLight);

    const sunTarget = new THREE.Object3D();
    sunTarget.position.set(0, 0, 0);
    scene.add(sunTarget);
    sunLight.target = sunTarget;
  }

  function updateCameraPosition() {
    if (!camera) return;
    // Базовая позиция для изометрического обзора перекрестка сверху-сбоку
    const baseDistance = 32 / camZoom;
    const baseHeight = 27 / camZoom;

    // Смещение центра кадра вверх относительно нижней панели Flutter
    const targetY = viewInsetBottom * 0.015;

    let shakeX = 0, shakeZ = 0;
    if (camShake > 0) {
      shakeX = (Math.random() - 0.5) * camShake * 2.0;
      shakeZ = (Math.random() - 0.5) * camShake * 2.0;
    }

    camera.position.set(18 + shakeX, baseHeight, baseDistance + shakeZ);
    camera.lookAt(0, targetY, 0);
  }

  // --- Построение перекрестка и окружения ---
  function buildEnvironment() {
    // 1. Земля / газон
    const groundGeo = new THREE.PlaneGeometry(800, 800);
    const groundMat = new THREE.MeshLambertMaterial({ color: season.ground });
    groundMat.userData.pddKind = 'grass';
    const ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -0.01;
    ground.receiveShadow = true;
    envGroup.add(ground);

    // 2. Асфальтовые дороги (Север-Юг и Восток-Запад)
    const roadMat = new THREE.MeshLambertMaterial({ color: BRAND.asphalt });
    roadMat.userData.pddKind = 'asphalt';

    const roadLen = CITY_REACH * 2;
    const roadNS = new THREE.Mesh(new THREE.PlaneGeometry(ROAD_WIDTH, roadLen), roadMat);
    roadNS.rotation.x = -Math.PI / 2;
    roadNS.position.y = 0.02;
    roadNS.receiveShadow = true;
    envGroup.add(roadNS);

    const roadEW = new THREE.Mesh(new THREE.PlaneGeometry(roadLen, ROAD_WIDTH), roadMat);
    roadEW.rotation.x = -Math.PI / 2;
    roadEW.position.y = 0.02;
    roadEW.receiveShadow = true;
    envGroup.add(roadEW);

    // Центральный квадрат
    const centerMesh = new THREE.Mesh(new THREE.PlaneGeometry(ROAD_WIDTH, ROAD_WIDTH), roadMat);
    centerMesh.rotation.x = -Math.PI / 2;
    centerMesh.position.y = 0.025;
    centerMesh.receiveShadow = true;
    envGroup.add(centerMesh);

    // Трамвайные пути (линия Север-Юг по центру)
    buildTramRails(envGroup);

    // 3. Разметка перекрестка
    buildMarkings(envGroup);

    // 4. Тротуары и бордюры
    buildSidewalks(envGroup);

    // 5. Городское окружение: деревья, фонари, фоновые дома
    buildCityDecor(envGroup);
    buildPedestrians(envGroup);
  }

  function buildTramRails(parent) {
    const railMat = new THREE.MeshLambertMaterial({ color: 0x90949C });
    railMat.userData.pddKind = 'metal';
    const gauge = 1.524; // ГОСТ колея трамвая в РФ
    const railWidth = 0.08;
    const railLength = CITY_REACH * 2;

    [-gauge / 2, gauge / 2].forEach(offset => {
      const rail = new THREE.Mesh(new THREE.BoxGeometry(railWidth, 0.03, railLength), railMat);
      rail.position.set(offset, 0.035, 0);
      rail.receiveShadow = true;
      parent.add(rail);
    });
  }

  function buildMarkings(parent) {
    const markMat = new THREE.MeshBasicMaterial({ color: BRAND.asphaltMarking });

    // Стоп-линии перед перекрестком
    const stopWidth = 5.6;
    const stopGeo = new THREE.PlaneGeometry(stopWidth, 0.5);
    const stopPositions = [
      { x: LANE_OFFSET, z: HALF_ROAD + 1.4, rot: 0 },          // Юг
      { x: -LANE_OFFSET, z: -(HALF_ROAD + 1.4), rot: 0 },      // Север
      { x: HALF_ROAD + 1.4, z: -LANE_OFFSET, rot: Math.PI / 2 },// Восток
      { x: -(HALF_ROAD + 1.4), z: LANE_OFFSET, rot: Math.PI / 2 },// Запад
    ];

    stopPositions.forEach(p => {
      const stop = new THREE.Mesh(stopGeo, markMat);
      stop.rotation.x = -Math.PI / 2;
      stop.rotation.z = p.rot;
      stop.position.set(p.x, 0.032, p.z);
      parent.add(stop);
    });

    // Пешеходные переходы (зебра) по 4 сторонам
    buildPedestrianCrossings(parent, markMat);

    // Прерывистые осевые линии
    buildDashedDividers(parent, markMat);
  }

  function buildPedestrianCrossings(parent, markMat) {
    const barGeo = new THREE.PlaneGeometry(0.45, 3.8);
    const barCount = 10;
    const step = 0.9;

    // 4 перехода перед стоп-линиями
    const crossingDist = HALF_ROAD + 3.8;
    const crossings = [
      { axis: 'x', z: crossingDist, rot: 0 },
      { axis: 'x', z: -crossingDist, rot: 0 },
      { axis: 'z', x: crossingDist, rot: Math.PI / 2 },
      { axis: 'z', x: -crossingDist, rot: Math.PI / 2 },
    ];

    crossings.forEach(c => {
      for (let i = 0; i < barCount; i++) {
        const offset = (i - (barCount - 1) / 2) * step;
        const bar = new THREE.Mesh(barGeo, markMat);
        bar.rotation.x = -Math.PI / 2;
        bar.rotation.z = c.rot;
        if (c.axis === 'x') {
          bar.position.set(offset, 0.031, c.z);
        } else {
          bar.position.set(c.x, 0.031, offset);
        }
        parent.add(bar);
      }
    });
  }

  function buildDashedDividers(parent, markMat) {
    const dashGeo = new THREE.PlaneGeometry(0.2, 1.8);
    for (let d = HALF_ROAD + 8; d < CITY_REACH; d += 4.5) {
      // Север - Юг
      [1, -1].forEach(dir => {
        const dash = new THREE.Mesh(dashGeo, markMat);
        dash.rotation.x = -Math.PI / 2;
        dash.position.set(0, 0.031, dir * d);
        parent.add(dash);

        // Восток - Запад
        const dashH = new THREE.Mesh(dashGeo, markMat);
        dashH.rotation.x = -Math.PI / 2;
        dashH.rotation.z = Math.PI / 2;
        dashH.position.set(dir * d, 0.031, 0);
        parent.add(dashH);
      });
    }
  }

  function buildSidewalks(parent) {
    const swMat = new THREE.MeshLambertMaterial({ color: 0x767B82 });
    swMat.userData.pddKind = 'pavement';
    const curbMat = new THREE.MeshLambertMaterial({ color: 0x8C9098 });
    curbMat.userData.pddKind = 'curb';

    const swWidth = 6.0;
    const corners = [
      { sx: 1, sz: 1 },
      { sx: -1, sz: 1 },
      { sx: 1, sz: -1 },
      { sx: -1, sz: -1 }
    ];

    corners.forEach(c => {
      // Угловой квадрат тротуара
      const swGeo = new THREE.BoxGeometry(CITY_REACH - HALF_ROAD, 0.16, CITY_REACH - HALF_ROAD);
      const sw = new THREE.Mesh(swGeo, swMat);
      sw.position.set(
        c.sx * (HALF_ROAD + (CITY_REACH - HALF_ROAD) / 2),
        0.08,
        c.sz * (HALF_ROAD + (CITY_REACH - HALF_ROAD) / 2)
      );
      sw.receiveShadow = true;
      parent.add(sw);

      // Бордюр по внутреннему углу
      const curbGeoH = new THREE.BoxGeometry(CITY_REACH, 0.20, 0.25);
      const curbH = new THREE.Mesh(curbGeoH, curbMat);
      curbH.position.set(
        c.sx * (HALF_ROAD + CITY_REACH / 2),
        0.10,
        c.sz * (HALF_ROAD + 0.12)
      );
      curbH.castShadow = true;
      curbH.receiveShadow = true;
      parent.add(curbH);

      const curbGeoV = new THREE.BoxGeometry(0.25, 0.20, CITY_REACH);
      const curbV = new THREE.Mesh(curbGeoV, curbMat);
      curbV.position.set(
        c.sx * (HALF_ROAD + 0.12),
        0.10,
        c.sz * (HALF_ROAD + CITY_REACH / 2)
      );
      curbV.castShadow = true;
      curbV.receiveShadow = true;
      parent.add(curbV);
    });
  }

  function buildCityDecor(parent) {
    // 1. Фонарные столбы по 4 углам перекрестка
    if (window.PDD_STREET && window.PDD_STREET.createLampPost) {
      const corners = [[-1, -1], [1, -1], [-1, 1], [1, 1]];
      corners.forEach(([sx, sz]) => {
        const lamp = window.PDD_STREET.createLampPost();
        lamp.position.set(sx * (HALF_ROAD + 1.8), 0.16, sz * (HALF_ROAD + 1.8));
        lamp.rotation.y = Math.atan2(-sz, sx);
        parent.add(lamp);
      });
    }

    // 2. Деревья по тротуарам
    const treeMat = new THREE.MeshLambertMaterial({ color: season.canopy[0] });
    const trunkMat = new THREE.MeshLambertMaterial({ color: 0x5D4534 });

    for (const dir of [-1, 1]) {
      for (const dist of [18, 30, 44]) {
        [[-1, 1], [1, 1], [-1, -1], [1, -1]].forEach(([sx, sz]) => {
          const tree = new THREE.Group();
          const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.24, 2.4, 8), trunkMat);
          trunk.position.y = 1.2;
          trunk.castShadow = true;
          tree.add(trunk);

          const crown = new THREE.Mesh(new THREE.DodecahedronGeometry(1.6, 1), treeMat);
          crown.position.y = 2.9;
          crown.castShadow = true;
          tree.add(crown);

          tree.position.set(sx * (HALF_ROAD + 3.8), 0.16, sz * (HALF_ROAD + dist));
          parent.add(tree);
        });
      }
    }

    // 3. Здания на заднем плане
    const buildingColors = [0xEAECEF, 0xDCE0E8, 0xC8D0DC, 0xB48270, 0x8FA4B8];
    const bldMatList = buildingColors.map(c => new THREE.MeshLambertMaterial({ color: c }));

    for (let along = HALF_ROAD + 16; along < 90; along += 22) {
      [-1, 1].forEach(side => {
        [-1, 1].forEach(dir => {
          const w = 16, d = 14, h = 16 + (along % 12);
          const mat = bldMatList[(along + side) % bldMatList.length];
          const bld = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
          bld.position.set(side * (HALF_ROAD + 14), h / 2, dir * along);
          bld.castShadow = true;
          bld.receiveShadow = true;
          parent.add(bld);
        });
      });
    }
  }

  function buildPedestrians(parent) {
    if (!window.PDD_STREET || !window.PDD_STREET.createPedestrian) return;
    const colours = window.PDD_STREET.peopleColors || [0x2E5B88, 0x8A3324, 0x336644, 0x775533];
    const corners = [[-1, -1], [1, 1], [1, -1], [-1, 1]];
    const count = weak ? 4 : 8;
    for (let i = 0; i < count; i++) {
      const [sx, sz] = corners[i % 4];
      const axis = i % 2 === Math.floor(i / 4) ? 'z' : 'x';
      let mesh = window.PDD_STREET.createPedestrian(colours[i % colours.length], (i * 3 + 1) % 12);
      if (window.PDD_VEHICLES && window.PDD_VEHICLES.applyModelEdits) {
        mesh = window.PDD_VEHICLES.applyModelEdits('pedestrian', mesh);
      }
      mesh.position.y = 0.18;
      mesh.traverse(node => { if (node.isMesh) node.castShadow = !weak; });
      parent.add(mesh);
      walkers.push({
        mesh, sx, sz, axis,
        curb: HALF_ROAD + 1.8,
        centre: HALF_ROAD + 17,
        distance: 11, time: 0,
        phase: i * 1.9,
        pace: 0.075 + (i % 3) * 0.008
      });
    }
  }

  function updatePedestrians(delta) {
    if (!window.PDD_STREET || !window.PDD_STREET.animateWalk) return;
    for (const walker of walkers) {
      walker.time += delta;
      const phase = walker.phase + walker.time * walker.pace;
      const along = walker.centre + Math.sin(phase) * walker.distance;
      const { mesh, sx, sz, axis, curb } = walker;
      mesh.position.x = sx * (axis === 'x' ? along : curb);
      mesh.position.z = sz * (axis === 'z' ? along : curb);
      const direction = Math.cos(phase);
      const target = axis === 'x' ? (sx * direction >= 0 ? Math.PI / 2 : -Math.PI / 2)
        : (sz * direction >= 0 ? 0 : Math.PI);
      const turn = Math.atan2(Math.sin(target - mesh.rotation.y), Math.cos(target - mesh.rotation.y));
      mesh.rotation.y += THREE.MathUtils.clamp(turn, -2.6 * delta, 2.6 * delta);
      const stride = Math.max(Math.abs(direction), Math.abs(turn) > 0.05 ? 0.35 : 0);
      window.PDD_STREET.animateWalk(mesh, walker.time + walker.phase, stride, Math.abs(direction));
    }
  }

  // --- Создание и позиционирование дорожных знаков ---
  function clearSigns() {
    activeSigns.forEach(s => signsGroup.remove(s));
    activeSigns = [];
  }

  function createSignMesh(code, sideName, table8_13) {
    const group = new THREE.Group();

    // Металлическая оцинкованная стойка знака
    const poleMat = new THREE.MeshLambertMaterial({ color: 0x9FA3A9 });
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.045, 3.4, 12), poleMat);
    pole.position.y = 1.7;
    pole.castShadow = true;
    group.add(pole);

    // Щит знака
    const signTexUrl = (window.PDD_SIGN_TEXTURES && window.PDD_SIGN_TEXTURES[code]);
    let signMat;
    if (signTexUrl) {
      const loader = new THREE.TextureLoader();
      const tex = loader.load(signTexUrl);
      tex.anisotropy = 4;
      signMat = new THREE.MeshLambertMaterial({ map: tex, transparent: true });
    } else {
      signMat = new THREE.MeshLambertMaterial({ color: 0xFFCC00 });
    }

    // Геометрия лицевой панели знака
    let faceGeo;
    if (code === '2.1') {
      // Ромб (квадрат повернуть на 45 градусов)
      faceGeo = new THREE.PlaneGeometry(1.0, 1.0);
      const face = new THREE.Mesh(faceGeo, signMat);
      face.rotation.z = Math.PI / 4;
      face.position.set(0, 2.9, 0.03);
      group.add(face);
    } else if (code === '2.4') {
      // Треугольник вершиной вниз
      faceGeo = new THREE.PlaneGeometry(1.05, 0.95);
      const face = new THREE.Mesh(faceGeo, signMat);
      face.position.set(0, 2.9, 0.03);
      group.add(face);
    } else if (code === '2.5') {
      // STOP восьмигранник
      faceGeo = new THREE.PlaneGeometry(0.95, 0.95);
      const face = new THREE.Mesh(faceGeo, signMat);
      face.position.set(0, 2.9, 0.03);
      group.add(face);
    }

    // Серая задняя крышка знака
    const backMat = new THREE.MeshLambertMaterial({ color: 0x5C6068 });
    const backGeo = new THREE.CylinderGeometry(0.55, 0.55, 0.02, 16);
    const back = new THREE.Mesh(backGeo, backMat);
    back.rotation.x = Math.PI / 2;
    back.position.set(0, 2.9, 0);
    group.add(back);

    // Табличка 8.13 «Направление главной дороги» (если указана)
    if (table8_13) {
      const plateTex = createTable8_13Texture(table8_13);
      const plateMat = new THREE.MeshLambertMaterial({ map: plateTex });
      const plate = new THREE.Mesh(new THREE.PlaneGeometry(0.85, 0.85), plateMat);
      plate.position.set(0, 2.1, 0.03);
      group.add(plate);

      const plateBack = new THREE.Mesh(new THREE.BoxGeometry(0.86, 0.86, 0.02), backMat);
      plateBack.position.set(0, 2.1, 0);
      group.add(plateBack);
    }

    // Позиционирование знака по сторонам перекрестка
    const signDist = HALF_ROAD + 2.2;
    const signZ = HALF_ROAD + 3.0;

    if (sideName === 'south') {
      group.position.set(signDist, 0, signZ);
      group.rotation.y = 0; // смотрит на юг (на приближающийся транспорт)
    } else if (sideName === 'north') {
      group.position.set(-signDist, 0, -signZ);
      group.rotation.y = Math.PI;
    } else if (sideName === 'east') {
      group.position.set(signZ, 0, -signDist);
      group.rotation.y = Math.PI / 2;
    } else if (sideName === 'west') {
      group.position.set(-signZ, 0, signDist);
      group.rotation.y = -Math.PI / 2;
    }

    group.traverse(child => {
      if (child.isMesh) {
        child.castShadow = true;
        child.receiveShadow = true;
      }
    });
    return group;
  }

  // Динамическая генерация четкой векторной текстуры для таблички 8.13
  function createTable8_13Texture(type) {
    const canvas = document.createElement('canvas');
    canvas.width = 256;
    canvas.height = 256;
    const ctx = canvas.getContext('2d');

    // Белый фон с черной каймой
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, 256, 256);
    ctx.lineWidth = 10;
    ctx.strokeStyle = '#000000';
    ctx.strokeRect(5, 5, 246, 246);

    const c = 128;
    // Тонкие линии второстепенных дорог
    ctx.lineWidth = 8;
    ctx.strokeStyle = '#222222';
    ctx.beginPath();
    // 4 луча креста
    ctx.moveTo(c, 24); ctx.lineTo(c, 232);
    ctx.moveTo(24, c); ctx.lineTo(232, c);
    ctx.stroke();

    // Жирная черная линия главной дороги (поворот)
    ctx.lineWidth = 32;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();

    if (type === 'left') {
      // Снизу налево (относительно водителя с юга)
      ctx.moveTo(c, 232);
      ctx.lineTo(c, c);
      ctx.lineTo(24, c);
    } else if (type === 'right') {
      // Снизу направо
      ctx.moveTo(c, 232);
      ctx.lineTo(c, c);
      ctx.lineTo(232, c);
    } else {
      // Прямо
      ctx.moveTo(c, 232);
      ctx.lineTo(c, 24);
    }
    ctx.stroke();

    return new THREE.CanvasTexture(canvas);
  }

  // --- Создание участников движения (машины, трамвай, скорая) ---
  function createVehicleMesh(actorData) {
    let mesh;
    const color = actorData.color || '#317ED4';

    if (actorData.type === 'tram') {
      // Трамвай с реалистичными деталями и пантографом
      mesh = buildTramModel(color);
    } else if (window.PDD_VEHICLES && window.PDD_VEHICLES.create) {
      // Используем сертифицированные модели PDD_VEHICLES
      const model = actorData.model || (actorData.type === 'emergency' ? 'suv' : 'hatch');
      mesh = window.PDD_VEHICLES.create(model, color);

      // Для спецтранспорта добавляем проблесковые маячки (синий/красный)
      if (actorData.hasSiren) {
        addEmergencyBeacons(mesh);
      }
    } else {
      // Запасной процедурный меш высокого качества
      mesh = buildFallbackCar(color);
    }

    // Создаем интерактивный парящий бейдж над автомобилем
    const badge = createVehicleBadge(actorData);
    mesh.add(badge);
    mesh.userData.badge = badge;
    mesh.userData.actorId = actorData.id;

    // Включаем указатели поворота в зависимости от маневра
    enableTurnSignals(mesh, actorData.maneuver);

    mesh.traverse(child => {
      if (child.isMesh) {
        child.castShadow = true;
        child.receiveShadow = true;
      }
    });

    return mesh;
  }

  function buildTramModel(colorHex) {
    const tram = new THREE.Group();
    const bodyColor = parseInt(colorHex.replace('#', ''), 16) || BRAND.tramRed;
    const bodyMat = new THREE.MeshLambertMaterial({ color: bodyColor });
    const whiteMat = new THREE.MeshLambertMaterial({ color: BRAND.tramWhite });
    const glassMat = new THREE.MeshLambertMaterial({ color: 0x334455, transparent: true, opacity: 0.85 });
    const metalMat = new THREE.MeshLambertMaterial({ color: 0x6E727A });

    // Нижняя часть кузова
    const lower = new THREE.Mesh(new THREE.BoxGeometry(2.3, 1.1, 9.6), bodyMat);
    lower.position.y = 0.75;
    lower.castShadow = true;
    tram.add(lower);

    // Верхняя белая часть
    const upper = new THREE.Mesh(new THREE.BoxGeometry(2.25, 1.2, 9.5), whiteMat);
    upper.position.y = 1.8;
    upper.castShadow = true;
    tram.add(upper);

    // Остекление
    const windows = new THREE.Mesh(new THREE.BoxGeometry(2.32, 0.7, 9.0), glassMat);
    windows.position.y = 1.85;
    tram.add(windows);

    // Пантограф на крыше
    const panto = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 1.2), metalMat);
    panto.position.set(0, 2.9, 1.2);
    panto.rotation.x = 0.35;
    tram.add(panto);

    const pantoHead = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.06, 0.25), metalMat);
    pantoHead.position.set(0, 3.4, 1.4);
    tram.add(pantoHead);

    tram.userData.height = 3.6;
    return tram;
  }

  function addEmergencyBeacons(carMesh) {
    const V = window.PDD_VEHICLE_MATERIALS;
    const bar = new THREE.Mesh(
      new THREE.BoxGeometry(0.85, 0.08, 0.2),
      new THREE.MeshLambertMaterial({ color: 0x222222 })
    );
    const carH = carMesh.userData.height || 1.6;
    bar.position.set(0, carH + 0.04, 0);
    carMesh.add(bar);

    const blueBeacon = new THREE.Mesh(
      new THREE.BoxGeometry(0.35, 0.16, 0.18),
      new THREE.MeshLambertMaterial({ color: 0x0574F8 })
    );
    blueBeacon.position.set(-0.22, 0.1, 0);
    bar.add(blueBeacon);

    const redBeacon = new THREE.Mesh(
      new THREE.BoxGeometry(0.35, 0.16, 0.18),
      new THREE.MeshLambertMaterial({ color: 0xEF4444 })
    );
    redBeacon.position.set(0.22, 0.1, 0);
    bar.add(redBeacon);

    if (window.PDD_VEHICLES && window.PDD_VEHICLES.addGlow) {
      window.PDD_VEHICLES.addGlow(blueBeacon, 0x208CFF, 1.8);
      window.PDD_VEHICLES.addGlow(redBeacon, 0xFF3434, 1.8);
    }

    carMesh.userData.beacons = [blueBeacon, redBeacon];
  }

  function buildFallbackCar(colorHex) {
    const car = new THREE.Group();
    const c = parseInt(colorHex.replace('#', ''), 16) || 0x317ED4;
    const body = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.8, 3.8), new THREE.MeshLambertMaterial({ color: c }));
    body.position.y = 0.6;
    body.castShadow = true;
    car.add(body);

    const cabin = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.7, 2.0), new THREE.MeshLambertMaterial({ color: 0x2A323D }));
    cabin.position.set(0, 1.25, -0.2);
    cabin.castShadow = true;
    car.add(cabin);

    car.userData.height = 1.6;
    return car;
  }

  function enableTurnSignals(carMesh, maneuver) {
    if (maneuver === 'left' && carMesh.blinkerL) {
      carMesh.blinkerL.visible = true;
      carMesh.userData.activeBlinker = carMesh.blinkerL;
    } else if (maneuver === 'right' && carMesh.blinkerR) {
      carMesh.blinkerR.visible = true;
      carMesh.userData.activeBlinker = carMesh.blinkerR;
    }
  }

  // --- Парящий интерактивный бейдж над машиной ---
  function createVehicleBadge(actorData) {
    const badgeGroup = new THREE.Group();
    const h = (actorData.type === 'tram' ? 3.6 : 1.7) + 1.1;
    badgeGroup.position.set(0, h, 0);

    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 128;
    const ctx = canvas.getContext('2d');

    // Круглая белая плашка с цветным кольцом
    ctx.clearRect(0, 0, 128, 128);
    ctx.beginPath();
    ctx.arc(64, 64, 56, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255, 255, 255, 0.95)';
    ctx.fill();
    ctx.lineWidth = 8;
    ctx.strokeStyle = actorData.color || '#0574F8';
    ctx.stroke();

    // Символ внутри
    ctx.fillStyle = '#101828';
    ctx.font = 'bold 54px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('?', 64, 66);

    const tex = new THREE.CanvasTexture(canvas);
    const spriteMat = new THREE.SpriteMaterial({ map: tex, transparent: true });
    const sprite = new THREE.Sprite(spriteMat);
    sprite.scale.set(1.6, 1.6, 1.0);
    badgeGroup.add(sprite);

    badgeGroup.userData = {
      canvas,
      ctx,
      sprite,
      tex,
      actorId: actorData.id,
      baseY: h,
      order: actorData.order,
      color: actorData.color || '#0574F8',
    };

    return badgeGroup;
  }

  function updateBadgeText(badgeGroup, text, isCorrect = false) {
    if (!badgeGroup || !badgeGroup.userData) return;
    const { canvas, ctx, tex, color } = badgeGroup.userData;
    ctx.clearRect(0, 0, 128, 128);
    ctx.beginPath();
    ctx.arc(64, 64, 56, 0, Math.PI * 2);
    ctx.fillStyle = isCorrect ? '#2BC280' : 'rgba(255, 255, 255, 0.96)';
    ctx.fill();
    ctx.lineWidth = 8;
    ctx.strokeStyle = isCorrect ? '#FFFFFF' : color;
    ctx.stroke();

    ctx.fillStyle = isCorrect ? '#FFFFFF' : '#101828';
    ctx.font = 'bold 54px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, 64, 66);
    tex.needsUpdate = true;
  }

  // Позиционирование машин перед перекрестком
  function placeActorAtStart(actorMesh, sideName) {
    const stopDist = HALF_ROAD + 4.5;

    if (sideName === 'south') {
      actorMesh.position.set(LANE_OFFSET, 0, stopDist);
      actorMesh.rotation.y = Math.PI; // смотрит на север
    } else if (sideName === 'north') {
      actorMesh.position.set(-LANE_OFFSET, 0, -stopDist);
      actorMesh.rotation.y = 0; // смотрит на юг
    } else if (sideName === 'east') {
      actorMesh.position.set(stopDist, 0, -LANE_OFFSET);
      actorMesh.rotation.y = -Math.PI / 2; // смотрит на запад
    } else if (sideName === 'west') {
      actorMesh.position.set(-stopDist, 0, LANE_OFFSET);
      actorMesh.rotation.y = Math.PI / 2; // смотрит на восток
    }
  }

  // --- Загрузка сценария перекрестка ---
  function loadScenario(scenarioData) {
    currentScenario = scenarioData;
    currentStep = 1;
    isResolving = false;
    drivingAnimations = [];

    // Очищаем предыдущие машины и знаки
    activeActors.forEach(({ mesh }) => vehiclesGroup.remove(mesh));
    activeActors.clear();
    clearSigns();

    // Создаем дорожные знаки
    if (scenarioData.signs && scenarioData.signs.length > 0) {
      scenarioData.signs.forEach(s => {
        const signMesh = createSignMesh(s.code, s.side, s.table8_13);
        signsGroup.add(signMesh);
        activeSigns.push(signMesh);
      });
    }

    // Создаем участников движения
    if (scenarioData.actors && scenarioData.actors.length > 0) {
      scenarioData.actors.forEach(a => {
        const mesh = createVehicleMesh(a);
        placeActorAtStart(mesh, a.side);
        vehiclesGroup.add(mesh);

        activeActors.set(a.id, {
          mesh,
          badge: mesh.userData.badge,
          data: a,
          state: 'waiting',
        });
      });
    }

    // Обновляем камеру
    updateCameraPosition();
  }

  // --- Обработка клика / тапа игрока ---
  function onPointerDown(event) {
    if (isResolving || !currentScenario) return;

    const rect = renderer.domElement.getBoundingClientRect();
    mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    raycaster.setFromCamera(mouse, camera);

    // Проверяем пересечение с машинами и их бейджами
    const candidateMeshes = [];
    activeActors.forEach(({ mesh, badge }) => {
      candidateMeshes.push(mesh);
      if (badge) candidateMeshes.push(badge.userData.sprite);
    });

    const intersects = raycaster.intersectObjects(candidateMeshes, true);
    if (intersects.length === 0) return;

    // Находим корневую машину
    let hitObject = intersects[0].object;
    let actorId = null;

    while (hitObject) {
      if (hitObject.userData && hitObject.userData.actorId) {
        actorId = hitObject.userData.actorId;
        break;
      }
      hitObject = hitObject.parent;
    }

    if (!actorId) return;
    const actorRecord = activeActors.get(actorId);
    if (!actorRecord || actorRecord.state !== 'waiting') return;

    // Уведомляем Flutter о тапе
    notifyFlutter({
      type: 'vehicle_tapped',
      actorId: actorId,
      step: currentStep,
    });

    handleVehicleChoice(actorId);
  }

  // --- Проверка правильности выбора очередности ---
  function handleVehicleChoice(chosenActorId) {
    const chosen = activeActors.get(chosenActorId);
    if (!chosen) return;

    // Ищем актора, который ОБЯЗАН ехать на текущем шаге
    let priorityActor = null;
    activeActors.forEach(rec => {
      if (rec.state === 'waiting') {
        if (!priorityActor || rec.data.order < priorityActor.data.order) {
          priorityActor = rec;
        }
      }
    });

    if (!priorityActor) return;

    if (chosen.data.order === priorityActor.data.order) {
      // ПРАВИЛЬНЫЙ ВЫБОР!
      chosen.state = 'driving';
      updateBadgeText(chosen.badge, `${currentStep} ✓`, true);

      // Анимируем плавный проезд перекрестка
      startDriveAnimation(chosen, () => {
        chosen.state = 'done';
        chosen.mesh.visible = false;

        // Проверяем, остались ли еще участники
        let remaining = false;
        activeActors.forEach(rec => {
          if (rec.state === 'waiting') remaining = true;
        });

        if (!remaining) {
          // ПЕРЕКРЕСТОК ПОЛНОСТЬЮ РАЗРУЛЕН!
          notifyFlutter({
            type: 'crossroad_complete',
            totalSteps: currentScenario.actors.length,
          });
        }
      });

      notifyFlutter({
        type: 'step_correct',
        actorId: chosenActorId,
        step: currentStep,
        totalSteps: currentScenario.actors.length,
      });

      currentStep++;
    } else {
      // ОШИБКА / ДТП!
      // Игрок выбрал машину без преимущества. Начинается кинематографичная авария!
      triggerCollision(chosen, priorityActor);
    }
  }

  // --- Кинематографичная анимация проезда ---
  function startDriveAnimation(actorRecord, onComplete) {
    const { mesh, data } = actorRecord;
    const side = data.side;
    const maneuver = data.maneuver;

    // Формируем контрольные точки траектории Безье
    const path = generateTrajectory(side, maneuver);

    drivingAnimations.push({
      mesh,
      path,
      progress: 0,
      speed: 0.55,
      wheels: mesh.userData.wheels || [],
      blinker: mesh.userData.activeBlinker,
      onComplete,
    });
  }

  // Вычисление траектории движения через перекресток
  function generateTrajectory(side, maneuver) {
    const pStart = getStartPoint(side);
    const pEnd = getEndPoint(side, maneuver);
    const pMid = getMidPoint(side, maneuver);

    return new THREE.QuadraticBezierCurve3(pStart, pMid, pEnd);
  }

  function getStartPoint(side) {
    const d = HALF_ROAD + 4.5;
    if (side === 'south') return new THREE.Vector3(LANE_OFFSET, 0, d);
    if (side === 'north') return new THREE.Vector3(-LANE_OFFSET, 0, -d);
    if (side === 'east') return new THREE.Vector3(d, 0, -LANE_OFFSET);
    return new THREE.Vector3(-d, 0, LANE_OFFSET); // west
  }

  function getEndPoint(side, maneuver) {
    const exitD = HALF_ROAD + 25.0;
    if (maneuver === 'straight') {
      if (side === 'south') return new THREE.Vector3(LANE_OFFSET, 0, -exitD);
      if (side === 'north') return new THREE.Vector3(-LANE_OFFSET, 0, exitD);
      if (side === 'east') return new THREE.Vector3(-exitD, 0, -LANE_OFFSET);
      return new THREE.Vector3(exitD, 0, LANE_OFFSET);
    }
    if (maneuver === 'right') {
      if (side === 'south') return new THREE.Vector3(exitD, 0, LANE_OFFSET);
      if (side === 'north') return new THREE.Vector3(-exitD, 0, -LANE_OFFSET);
      if (side === 'east') return new THREE.Vector3(LANE_OFFSET, 0, -exitD);
      return new THREE.Vector3(-LANE_OFFSET, 0, exitD);
    }
    // left
    if (side === 'south') return new THREE.Vector3(-exitD, 0, -LANE_OFFSET);
    if (side === 'north') return new THREE.Vector3(exitD, 0, LANE_OFFSET);
    if (side === 'east') return new THREE.Vector3(-LANE_OFFSET, 0, exitD);
    return new THREE.Vector3(LANE_OFFSET, 0, -exitD);
  }

  function getMidPoint(side, maneuver) {
    if (maneuver === 'straight') {
      return new THREE.Vector3(0, 0, 0);
    }
    if (maneuver === 'right') {
      if (side === 'south') return new THREE.Vector3(LANE_OFFSET + 1.2, 0, HALF_ROAD - 1.2);
      if (side === 'north') return new THREE.Vector3(-LANE_OFFSET - 1.2, 0, -HALF_ROAD + 1.2);
      if (side === 'east') return new THREE.Vector3(HALF_ROAD - 1.2, 0, -LANE_OFFSET - 1.2);
      return new THREE.Vector3(-HALF_ROAD + 1.2, 0, LANE_OFFSET + 1.2);
    }
    // left
    return new THREE.Vector3(0, 0, 0);
  }

  // --- Кинематографичная авария (ДТП) при ошибке очередности ---
  function triggerCollision(wrongActor, priorityActor) {
    isResolving = true;
    wrongActor.state = 'crashed';
    priorityActor.state = 'crashed';

    // Точка столкновения (центр перекрестка или точка пересечения курсов)
    const crashPoint = new THREE.Vector3(0, 0, 0);

    // Анимация выезда обеих машин навстречу друг другу
    const tStartWrong = wrongActor.mesh.position.clone();
    const tStartPriority = priorityActor.mesh.position.clone();

    let crashElapsed = 0;
    const crashDuration = 0.85;

    function stepCrash(dt) {
      crashElapsed += dt;
      const progress = Math.min(1.0, crashElapsed / crashDuration);
      const ease = 1 - Math.pow(1 - progress, 2);

      wrongActor.mesh.position.lerpVectors(tStartWrong, crashPoint, ease * 0.85);
      priorityActor.mesh.position.lerpVectors(tStartPriority, crashPoint, ease * 0.85);

      if (progress < 1.0) {
        requestAnimationFrame(() => stepCrash(clock.getDelta()));
      } else {
        // УДАР!
        camShake = 0.45; // сотрясение камеры
        createCrashParticles(crashPoint);

        // Отправляем событие во Flutter для звука визга тормозов, удара и открытия шторки с ПДД
        notifyFlutter({
          type: 'collision',
          chosenId: wrongActor.data.id,
          priorityId: priorityActor.data.id,
          reason: priorityActor.data.ruleExplanation,
          pddArticle: currentScenario.pddArticle,
        });
      }
    }

    stepCrash(0.016);
  }

  // Частицы удара и пыли при ДТП
  function createCrashParticles(pos) {
    const count = 35;
    const geo = new THREE.BufferGeometry();
    const positions = new Float32Array(count * 3);
    const velocities = [];

    for (let i = 0; i < count; i++) {
      positions[i * 3] = pos.x;
      positions[i * 3 + 1] = pos.y + 0.6;
      positions[i * 3 + 2] = pos.z;

      velocities.push(new THREE.Vector3(
        (Math.random() - 0.5) * 8.0,
        Math.random() * 6.0 + 2.0,
        (Math.random() - 0.5) * 8.0
      ));
    }

    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const mat = new THREE.PointsMaterial({
      color: 0xFFAA33,
      size: 0.35,
      transparent: true,
      opacity: 0.95
    });

    const particles = new THREE.Points(geo, mat);
    fxGroup.add(particles);

    let life = 0.65;
    function animateParticles(dt) {
      life -= dt;
      const posArr = particles.geometry.attributes.position.array;
      for (let i = 0; i < count; i++) {
        posArr[i * 3] += velocities[i].x * dt;
        posArr[i * 3 + 1] += velocities[i].y * dt;
        posArr[i * 3 + 2] += velocities[i].z * dt;
        velocities[i].y -= 9.8 * dt; // гравитация
      }
      particles.geometry.attributes.position.needsUpdate = true;
      mat.opacity = Math.max(0, life / 0.65);

      if (life > 0) {
        requestAnimationFrame(() => animateParticles(clock.getDelta()));
      } else {
        fxGroup.remove(particles);
      }
    }
    animateParticles(0.016);
  }

  // --- Основной цикл рендера и анимаций ---
  function animate() {
    requestAnimationFrame(animate);

    const dt = clock.getDelta();
    const time = clock.getElapsedTime();

    // Затухание сотрясения камеры
    if (camShake > 0) {
      camShake = Math.max(0, camShake - dt * 1.5);
      updateCameraPosition();
    }

    updatePedestrians(dt);

    // Анимация парящих бейджей (мягкое покачивание)
    activeActors.forEach(({ badge }) => {
      if (badge) {
        const u = badge.userData;
        badge.position.y = u.baseY + Math.sin(time * 3.5 + u.order) * 0.12;
      }
    });

    // Мигание спецмаячков и поворотников
    const blinkCycle = Math.floor(time * 4) % 2 === 0;
    activeActors.forEach(({ mesh }) => {
      if (mesh.userData.beacons) {
        mesh.userData.beacons[0].visible = blinkCycle;
        mesh.userData.beacons[1].visible = !blinkCycle;
      }
      if (mesh.userData.activeBlinker) {
        mesh.userData.activeBlinker.visible = blinkCycle;
      }
    });

    // Обновление активных анимаций проезда машин
    for (let i = drivingAnimations.length - 1; i >= 0; i--) {
      const anim = drivingAnimations[i];
      anim.progress += dt * anim.speed;

      if (anim.progress >= 1.0) {
        anim.onComplete && anim.onComplete();
        drivingAnimations.splice(i, 1);
      } else {
        const point = anim.path.getPoint(anim.progress);
        const nextPoint = anim.path.getPoint(Math.min(1.0, anim.progress + 0.05));
        anim.mesh.position.copy(point);

        // Вращение колес
        anim.wheels.forEach(w => {
          w.rotation.x += dt * 12.0;
        });

        // Плавный поворот кузова по ходу движения
        const dir = nextPoint.clone().sub(point).normalize();
        if (dir.lengthSq() > 0.0001) {
          anim.mesh.rotation.y = Math.atan2(dir.x, dir.z);
        }
      }
    }

    renderer.render(scene, camera);
  }

  function onWindowResize() {
    if (!renderer || !camera || !container) return;
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
  }

  // --- API для Flutter моста ---
  window.setZoom = zoom => {
    camZoom = THREE.MathUtils.clamp(zoom, 0.5, 2.5);
    updateCameraPosition();
  };

  window.setViewInset = bottomPixels => {
    viewInsetBottom = bottomPixels;
    updateCameraPosition();
  };

  window.loadScenarioData = rawJson => {
    try {
      const data = typeof rawJson === 'string' ? JSON.parse(rawJson) : rawJson;
      loadScenario(data);
    } catch (e) {
      console.error('Error loading scenario:', e);
    }
  };

  window.resetCurrentScenario = () => {
    if (currentScenario) loadScenario(currentScenario);
  };

  function notifyFlutter(payload) {
    if (window.PDD_BRIDGE && window.PDD_BRIDGE.send) {
      window.PDD_BRIDGE.send(payload);
    } else if (window.FlutterChannel && window.FlutterChannel.postMessage) {
      window.FlutterChannel.postMessage(JSON.stringify(payload));
    } else if (window.parent && window.parent.postMessage) {
      window.parent.postMessage(JSON.stringify(payload), '*');
    }
  }

  window.addEventListener('DOMContentLoaded', init);
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    init();
  }
})();
