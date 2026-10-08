// 3D-симулятор и игра «Регулировщик 3D» на Three.js
// Реализует сигналы регулировщика по п. 6.10 ПДД РФ для авто и трамваев.
// Высокодетализированная городская сцена перекрёстка с аутентичными моделями.

(() => {
  'use strict';

  // --- Константы правил п. 6.10 ПДД ---
  const GESTURES = {
    HANDS_DOWN: 'handsDownOrSides',
    RIGHT_ARM_FORWARD: 'rightArmForward',
    ARM_UP: 'armUp',
  };

  const APPROACHES = {
    FRONT: 'front', // Лицом / грудь
    BACK: 'back',   // Спиной
    LEFT: 'left',   // Левым боком
    RIGHT: 'right', // Правым боком
  };

  const VEHICLES = {
    CAR: 'car',
    TRAM: 'tram',
  };

  const MOVES = {
    STRAIGHT: 'straight',
    RIGHT: 'right',
    LEFT: 'left',
    UTURN: 'uTurn',
    NONE: 'none',
  };

  // Вычисление разрешенных ходов по ПДД РФ
  function getAllowedMoves(gesture, approach, vehicle) {
    if (gesture === GESTURES.ARM_UP) {
      return [MOVES.NONE];
    }
    if (gesture === GESTURES.HANDS_DOWN) {
      if (approach === APPROACHES.LEFT || approach === APPROACHES.RIGHT) {
        return vehicle === VEHICLES.TRAM ? [MOVES.STRAIGHT] : [MOVES.STRAIGHT, MOVES.RIGHT];
      }
      return [MOVES.NONE];
    }
    if (gesture === GESTURES.RIGHT_ARM_FORWARD) {
      if (approach === APPROACHES.LEFT) {
        return vehicle === VEHICLES.TRAM
          ? [MOVES.LEFT]
          : [MOVES.STRAIGHT, MOVES.RIGHT, MOVES.LEFT, MOVES.UTURN];
      }
      if (approach === APPROACHES.FRONT) {
        return [MOVES.RIGHT];
      }
      return [MOVES.NONE];
    }
    return [MOVES.NONE];
  }

  // Фирменная палитра флагманской игры (BRAND)
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
    grass: 0x86A97A,
    grassDark: 0x496D42,
    sidewalk: 0x747970,
    curb: 0x737870,
    buildingColors: [0xF5F6FA, 0xE9ECF2, 0xDDE1EA, 0xC6CCD8, 0xB5675A, 0xA9B4C2],
    windowColor: 0x64748B,
    playerCar: 0x0574F8,
    tramRed: 0xD32F2F,
    tramWhite: 0xF5F5F5
  };

  // --- Переменные сцены ---
  let scene, camera, renderer;
  let container;
  let inspectorGroup, headMesh, leftArmPivot, rightArmPivot, batonMesh, vestMesh;
  let carMesh, tramMesh;
  let activeVehicleMesh;
  let arrowsGroup;
  let envGroup;
  let skyDome;
  let streetLights = [];
  let isMoving = false;
  let moveProgress = 0;
  let moveCurve = null;
  let movingObject = null;
  const initialObjectPos = new THREE.Vector3();
  let initialObjectRotY = Math.PI;

  // Состояние
  let currentGesture = GESTURES.RIGHT_ARM_FORWARD;
  let currentApproach = APPROACHES.LEFT;
  let currentVehicle = VEHICLES.CAR;
  let currentCameraMode = 'overview'; // 'overview' | 'driver'
  let currentMode = 'training';       // 'training' | 'arcade'
  let activeBlinkerSide = null;       // 'left' | 'right' | null
  let resetTimer = null;

  // Анимация рук регулировщика (целевые и текущие углы)
  const targetLeftArm = new THREE.Vector3();
  const targetRightArm = new THREE.Vector3();
  const curLeftArm = new THREE.Vector3();
  const curRightArm = new THREE.Vector3();
  let targetInspectorRotY = 0;
  let curInspectorRotY = 0;

  // Камера: плавное вращение и обзор
  let camAngle = 0;
  let targetAngle = 0;
  let camDistance = 23;
  let camHeight = 18;
  let clock = new THREE.Clock();

  function init() {
    container = document.getElementById('canvas-container');
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(0xDEE4E5);
    scene.fog = null;

    // Процедурный градиентный купол неба с облаками (как во флагманской игре)
    skyDome = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 16), new THREE.ShaderMaterial({
      uniforms: { horizon: { value: new THREE.Color(0xB9D6EE) }, zenith: { value: new THREE.Color(0x6FA8DC) }, cloud: { value: 0.55 } },
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
      side: THREE.BackSide, depthWrite: false
    }));
    skyDome.frustumCulled = false; skyDome.renderOrder = -1; skyDome.userData.sky = true;
    scene.add(skyDome);

    camera = new THREE.PerspectiveCamera(42, width / height, 0.5, 400);
    updateCameraPosition();

    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: 'high-performance' });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    container.appendChild(renderer.domElement);

    setupLighting();
    buildEnvironment();

    // Подключаем процедурные шейдерные материалы дорог и окружения
    if (window.PDD_ROADS) {
      window.PDD_ROADS.attach(renderer, { roots: () => [envGroup], lineage: () => null });
    }

    buildInspector();
    buildVehicles();
    buildTrajectoryArrows();

    window.addEventListener('resize', onWindowResize);

    // Первоначальное состояние
    setScenario(GESTURES.RIGHT_ARM_FORWARD, APPROACHES.LEFT, VEHICLES.CAR);

    // Сообщаем Flutter о готовности
    notifyFlutter({ type: 'ready' });

    animate();
  }

  function setupLighting() {
    // Рассеянный дневной свет (как во флагманской игре)
    const ambientLight = new THREE.AmbientLight(0xFFFFFF, 0.75);
    scene.add(ambientLight);

    // Верхнее солнце с естественными мягкими тенями
    const sunLight = new THREE.DirectionalLight(0xFFF9EE, 0.85);
    sunLight.position.set(16, 68, 14);
    sunLight.castShadow = true;
    sunLight.shadow.mapSize.width = 1024;
    sunLight.shadow.mapSize.height = 1024;
    sunLight.shadow.camera.near = 10;
    sunLight.shadow.camera.far = 180;
    const d = 36;
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

  // --- Перекрёсток: дороги, тротуары, разметка, рельсы, здания ---
  function buildEnvironment() {
    envGroup = new THREE.Group();
    scene.add(envGroup);

    // Ландшафт / трава вокруг города (с процедурной фактурой grass)
    const groundGeo = new THREE.PlaneGeometry(320, 320);
    const groundMat = new THREE.MeshLambertMaterial({ color: BRAND.grass });
    groundMat.userData.pddKind = 'grass';
    const ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -0.01;
    ground.receiveShadow = true;
    envGroup.add(ground);

    // Проезжая часть с фактурой асфальта (микропоры и каменная крошка)
    const roadMat = new THREE.MeshLambertMaterial({ color: BRAND.asphalt });
    roadMat.userData.pddKind = 'asphalt';
    const roadWidth = 13.6;
    const roadLen = 140;

    const roadNS = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth, roadLen), roadMat);
    roadNS.rotation.x = -Math.PI / 2;
    roadNS.position.y = 0.02;
    roadNS.userData.surface = 'road';
    roadNS.receiveShadow = true;
    envGroup.add(roadNS);

    const roadEW = new THREE.Mesh(new THREE.PlaneGeometry(roadLen, roadWidth), roadMat);
    roadEW.rotation.x = -Math.PI / 2;
    roadEW.position.y = 0.02;
    roadEW.userData.surface = 'road';
    roadEW.receiveShadow = true;
    envGroup.add(roadEW);

    // Центр перекрестка
    const centerMesh = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth, roadWidth), roadMat);
    centerMesh.rotation.x = -Math.PI / 2;
    centerMesh.position.y = 0.025;
    centerMesh.userData.surface = 'road';
    centerMesh.receiveShadow = true;
    envGroup.add(centerMesh);

    // Дорожная разметка (чистый белый базовый термопластик как во флагмане)
    const markMat = new THREE.MeshBasicMaterial({ color: BRAND.asphaltMarking });

    buildRoadMarkings(envGroup, markMat, roadWidth);
    buildSidewalks(envGroup, roadWidth);
    buildCityBuildings(envGroup, roadWidth);
    buildStreetFurniture(envGroup, roadWidth);
    buildTramTracks(envGroup);
    buildCentralPedestal(envGroup);
  }

  // Разметка перекрёстка: стоп-линии, зебры, разделительные линии, стрелки полос
  function buildRoadMarkings(parent, markMat, roadWidth) {
    const halfW = roadWidth / 2;

    // Стоп-линии перед каждым направлением
    const stopLineGeo = new THREE.PlaneGeometry(5.8, 0.5);
    const stopPositions = [
      { x: 3.2, z: halfW + 1.2, rot: 0 },          // Юг
      { x: -3.2, z: -(halfW + 1.2), rot: 0 },      // Север
      { x: halfW + 1.2, z: -3.2, rot: Math.PI/2 }, // Восток
      { x: -(halfW + 1.2), z: 3.2, rot: Math.PI/2 },// Запад
    ];

    stopPositions.forEach(p => {
      const sl = new THREE.Mesh(stopLineGeo, markMat);
      sl.rotation.x = -Math.PI / 2;
      sl.rotation.z = p.rot;
      sl.position.set(p.x, 0.035, p.z);
      parent.add(sl);
    });

    // Зебры пешеходных переходов (на всех 4 сторонах)
    const stripeGeo = new THREE.PlaneGeometry(0.5, 3.6);
    const stripeCount = 12;
    const stripeDist = 1.0;

    // Зебра на юге и севере
    [-1, 1].forEach(side => {
      const zPos = side * (halfW + 3.8);
      for (let i = 0; i < stripeCount; i++) {
        const s = new THREE.Mesh(stripeGeo, markMat);
        s.rotation.x = -Math.PI / 2;
        s.position.set(-5.5 + i * stripeDist, 0.033, zPos);
        parent.add(s);
      }
    });

    // Зебра на западе и востоке
    [-1, 1].forEach(side => {
      const xPos = side * (halfW + 3.8);
      for (let i = 0; i < stripeCount; i++) {
        const s = new THREE.Mesh(stripeGeo, markMat);
        s.rotation.x = -Math.PI / 2;
        s.rotation.z = Math.PI / 2;
        s.position.set(xPos, 0.033, -5.5 + i * stripeDist);
        parent.add(s);
      }
    });

    // Двойная сплошная линия (разметка 1.3) вдоль южного и северного направлений
    const doubleLineGeo = new THREE.PlaneGeometry(0.14, 50);
    [-0.14, 0.14].forEach(off => {
      // Южная ветка
      const lineS = new THREE.Mesh(doubleLineGeo, markMat);
      lineS.rotation.x = -Math.PI / 2;
      lineS.position.set(off, 0.034, 32);
      parent.add(lineS);
      // Северная ветка
      const lineN = new THREE.Mesh(doubleLineGeo, markMat);
      lineN.rotation.x = -Math.PI / 2;
      lineN.position.set(off, 0.034, -32);
      parent.add(lineN);
    });
  }

  // Приподнятые тротуары с гранитными бордюрами и фактурными материалами
  function buildSidewalks(parent, roadWidth) {
    const halfW = roadWidth / 2;
    const kerbMat = new THREE.MeshLambertMaterial({
      color: BRAND.curb,
    });
    kerbMat.userData.pddKind = 'pavement';
    const walkMat = new THREE.MeshLambertMaterial({
      color: BRAND.sidewalk,
    });
    walkMat.userData.pddKind = 'pavement';
    const lawnMat = new THREE.MeshLambertMaterial({
      color: BRAND.grassDark,
    });
    lawnMat.userData.pddKind = 'grass';

    const walkSize = 50;
    const kerbH = 0.18;

    // 4 квартала перекрестка: Юго-Запад, Юго-Восток, Северо-Запад, Северо-Восток
    const quadrants = [
      { sx: 1, sz: 1 },   // Юго-Восток
      { sx: -1, sz: 1 },  // Юго-Запад
      { sx: 1, sz: -1 },  // Северо-Восток
      { sx: -1, sz: -1 }, // Северо-Запад
    ];

    quadrants.forEach(q => {
      const g = new THREE.Group();
      g.position.set(q.sx * (halfW + walkSize / 2), kerbH / 2, q.sz * (halfW + walkSize / 2));

      // Плита тротуара (процедурная плитка)
      const walk = new THREE.Mesh(new THREE.BoxGeometry(walkSize, kerbH, walkSize), walkMat);
      walk.userData.surface = 'sidewalk';
      walk.receiveShadow = true;
      g.add(walk);

      // Газон в глубине тротуара
      const lawn = new THREE.Mesh(new THREE.BoxGeometry(walkSize - 8, 0.02, walkSize - 8), lawnMat);
      lawn.userData.surface = 'lawn';
      lawn.receiveShadow = true;
      g.add(lawn);

      parent.add(g);

      // Гранитные бордюрные камни вдоль дороги
      const kerbEW = new THREE.Mesh(new THREE.BoxGeometry(walkSize, kerbH + 0.02, 0.35), kerbMat);
      kerbEW.position.set(q.sx * (halfW + walkSize / 2), kerbH / 2 + 0.01, q.sz * (halfW + 0.17));
      kerbEW.userData.surface = 'sidewalk';
      kerbEW.castShadow = true;
      parent.add(kerbEW);

      const kerbNS = new THREE.Mesh(new THREE.BoxGeometry(0.35, kerbH + 0.02, walkSize), kerbMat);
      kerbNS.position.set(q.sx * (halfW + 0.17), kerbH / 2 + 0.01, q.sz * (halfW + walkSize / 2));
      kerbNS.userData.surface = 'sidewalk';
      kerbNS.castShadow = true;
      parent.add(kerbNS);
    });
  }

  // Городские здания по углам перекрёстка (архитектура с шейдерными фасадами и окнами)
  function buildCityBuildings(parent, roadWidth) {
    const halfW = roadWidth / 2;

    const buildingSpecs = [
      // Северо-Запад: штукатурный светлый фасад
      { x: -(halfW + 30), z: -(halfW + 30), w: 20, d: 20, h: 14, color: 0xF5F6FA, style: 'plaster' },
      // Северо-Восток: кирпичный классический дом
      { x: (halfW + 30), z: -(halfW + 30), w: 20, d: 20, h: 16, color: 0xB5675A, style: 'brick' },
      // Юго-Запад: панельный городской дом
      { x: -(halfW + 30), z: (halfW + 30), w: 20, d: 20, h: 13, color: 0xDDE1EA, style: 'panel' },
      // Юго-Восток: панельный современный фасад
      { x: (halfW + 30), z: (halfW + 30), w: 20, d: 20, h: 15, color: 0xE9ECF2, style: 'panel' },
    ];

    buildingSpecs.forEach(b => {
      const bGroup = new THREE.Group();
      bGroup.position.set(b.x, 0, b.z);

      const facadeMat = new THREE.MeshLambertMaterial({ color: b.color });
      const body = new THREE.Mesh(new THREE.BoxGeometry(b.w, b.h, b.d), facadeMat);
      body.position.y = b.h / 2;
      body.receiveShadow = true;
      if (window.PDD_ROADS) {
        if (b.style === 'plaster') window.PDD_ROADS.skinObject(body, 'plaster', { v0: -0.2 });
        else if (b.style === 'brick') window.PDD_ROADS.skinObject(body, 'brick');
        else window.PDD_ROADS.skinObject(body, 'panel', { u0: -0.4, v0: -0.45 });
      }
      bGroup.add(body);

      // Плоская кровля (гудрон / рубероид) с парапетом
      const slabMat = new THREE.MeshLambertMaterial({ color: 0x6B7480 });
      const slab = new THREE.Mesh(new THREE.BoxGeometry(b.w - 0.2, 0.08, b.d - 0.2), slabMat);
      slab.position.y = b.h + 0.04;
      if (window.PDD_ROADS) window.PDD_ROADS.skinObject(slab, 'roofFlat');
      bGroup.add(slab);

      const borderMat = new THREE.MeshLambertMaterial({ color: 0x94A3B8 });
      const roofBorder = new THREE.Mesh(new THREE.BoxGeometry(b.w + 0.4, 0.4, b.d + 0.4), borderMat);
      roofBorder.position.y = b.h + 0.2;
      if (window.PDD_ROADS) window.PDD_ROADS.skinObject(roofBorder, 'roofFlat');
      bGroup.add(roofBorder);

      // Окна на фасадах
      const winGeo = new THREE.PlaneGeometry(1.2, 1.4);
      const winMat = new THREE.MeshBasicMaterial({ color: 0x647D87 });

      const floors = Math.floor(b.h / 3.4);
      const cols = Math.floor(b.w / 3.8);

      for (let f = 1; f < floors; f++) {
        const y = f * 3.4 + 0.8;
        for (let c = -Math.floor(cols / 2); c <= Math.floor(cols / 2); c++) {
          const x = c * 3.2;

          // Окно на южном фасаде
          const winS = new THREE.Mesh(winGeo, winMat);
          winS.position.set(x, y, b.d / 2 + 0.02);
          if (window.PDD_ROADS) window.PDD_ROADS.skinObject(winS, 'window');
          bGroup.add(winS);

          // Окно на боковом фасаде
          const winSide = new THREE.Mesh(winGeo, winMat);
          winSide.rotation.y = Math.PI / 2;
          winSide.position.set(b.w / 2 + 0.02, y, c * 3.2);
          if (window.PDD_ROADS) window.PDD_ROADS.skinObject(winSide, 'window');
          bGroup.add(winSide);
        }
      }

      parent.add(bGroup);
    });
  }

  // Уличная мебель: фонарные столбы, деревья, дорожные знаки
  function buildStreetFurniture(parent, roadWidth) {
    const halfW = roadWidth / 2;

    // 4 угловых фонарных столба с теплыми светящимися лампами
    const lampPositions = [
      { x: halfW + 1.2, z: halfW + 1.2, rot: Math.PI * 0.75 },
      { x: -(halfW + 1.2), z: halfW + 1.2, rot: Math.PI * 0.25 },
      { x: halfW + 1.2, z: -(halfW + 1.2), rot: -Math.PI * 0.75 },
      { x: -(halfW + 1.2), z: -(halfW + 1.2), rot: -Math.PI * 0.25 },
    ];

    lampPositions.forEach(p => {
      const lamp = buildStreetLamp();
      lamp.position.set(p.x, 0.18, p.z);
      lamp.rotation.y = p.rot;
      parent.add(lamp);
    });

    // Дорожные деревья с красивой объемной листвой
    const treePositions = [
      { x: halfW + 4.5, z: halfW + 12 },
      { x: halfW + 12, z: halfW + 4.5 },
      { x: -(halfW + 4.5), z: halfW + 12 },
      { x: -(halfW + 12), z: halfW + 4.5 },
      { x: halfW + 4.5, z: -(halfW + 12) },
      { x: -(halfW + 4.5), z: -(halfW + 12) },
    ];

    treePositions.forEach(p => {
      const tree = buildTree();
      tree.position.set(p.x, 0.18, p.z);
      parent.add(tree);
    });

  }

  function buildStreetLamp() {
    const group = new THREE.Group();
    const poleMat = new THREE.MeshStandardMaterial({
      color: 0x242830,
      metalness: 0.75,
      roughness: 0.35,
    });
    const glowMat = new THREE.MeshBasicMaterial({
      color: 0xFFF7D6,
    });

    // 1. Основание столба
    const base = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.22, 0.5, 12), poleMat);
    base.position.y = 0.25;
    base.castShadow = true;
    group.add(base);

    // 2. Вертикальная мачта
    const poleH = 5.8;
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.14, poleH, 12), poleMat);
    pole.position.y = 0.5 + poleH / 2;
    pole.castShadow = true;
    group.add(pole);

    // 3. Верхушка мачты (шарнир)
    const cap = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 10), poleMat);
    cap.position.set(0, 6.3, 0);
    group.add(cap);

    // 4. Изогнутый кронштейн к проезжей части
    const armLength = 1.34;
    const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, armLength, 10), poleMat);
    const armAngle = Math.atan2(1.2, 0.6);
    arm.rotation.z = -armAngle;
    arm.position.set(0.6, 6.6, 0);
    group.add(arm);

    // 5. Корпус светильника (строго смонтирован на кончике кронштейна в 1.2, 6.9, 0)
    const headGroup = new THREE.Group();
    headGroup.position.set(1.2, 6.9, 0);
    headGroup.rotation.z = -0.18;

    const head = new THREE.Mesh(new THREE.BoxGeometry(0.65, 0.12, 0.28), poleMat);
    head.position.set(0.28, 0, 0);
    headGroup.add(head);

    const bulb = new THREE.Mesh(new THREE.PlaneGeometry(0.52, 0.22), glowMat);
    bulb.rotation.x = Math.PI / 2;
    bulb.position.set(0.28, -0.062, 0);
    headGroup.add(bulb);

    group.add(headGroup);

    return group;
  }

  function buildTree() {
    const group = new THREE.Group();
    const trunkMat = new THREE.MeshLambertMaterial({ color: 0x5D4534 });
    const leafMat1 = new THREE.MeshLambertMaterial({ color: 0x48793C });
    const leafMat2 = new THREE.MeshLambertMaterial({ color: 0x568F48 });

    // Ствол дерева с фактурой коры
    const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.28, 3.2, 8), trunkMat);
    trunk.position.y = 1.6;
    trunk.castShadow = true;
    if (window.PDD_ROADS) {
      window.PDD_ROADS.skinObject(trunk, 'bark');
    }
    group.add(trunk);

    // Ярусы кроны с процедурными листьями
    const crown1 = new THREE.Mesh(new THREE.DodecahedronGeometry(1.6, 1), leafMat1);
    crown1.position.y = 3.8;
    crown1.castShadow = true;
    if (window.PDD_ROADS) {
      window.PDD_ROADS.skinObject(crown1, 'leaves');
    }
    group.add(crown1);

    const crown2 = new THREE.Mesh(new THREE.DodecahedronGeometry(1.2, 1), leafMat2);
    crown2.position.set(0.3, 4.8, 0.2);
    crown2.castShadow = true;
    if (window.PDD_ROADS) {
      window.PDD_ROADS.skinObject(crown2, 'leaves');
    }
    group.add(crown2);

    return group;
  }

  // Трамвайные пути (аккуратные стальные рельсы, утопленные в асфальт)
  function buildTramTracks(parent) {
    const railMat = new THREE.MeshStandardMaterial({
      color: 0x949AA5,
      metalness: 0.88,
      roughness: 0.22,
    });

    // Две стальные колеи
    const railGeo = new THREE.BoxGeometry(0.1, 0.05, 140);
    [-0.76, 0.76].forEach(offset => {
      const rail = new THREE.Mesh(railGeo, railMat);
      rail.position.set(-2.2 + offset, 0.045, 0);
      rail.receiveShadow = true;
      parent.add(rail);
    });
  }

  // Центральный постамент регулировщика (аккуратный компактный островок под ногами)
  function buildCentralPedestal(parent) {
    const islandGeo = new THREE.CylinderGeometry(0.55, 0.60, 0.05, 32);
    const islandMat = new THREE.MeshLambertMaterial({
      color: 0x747970,
    });
    islandMat.userData.pddKind = 'pavement';
    const island = new THREE.Mesh(islandGeo, islandMat);
    island.position.y = 0.025;
    island.userData.surface = 'sidewalk';
    island.receiveShadow = true;
    parent.add(island);

    // Белая окантовка островка
    const ringGeo = new THREE.RingGeometry(0.52, 0.60, 32);
    const ringMat = new THREE.MeshBasicMaterial({ color: BRAND.asphaltMarking });
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.051;
    parent.add(ring);
  }

  // --- 3D-модель инспектора ДПС (Регулировщик) ---
  function buildInspector() {
    inspectorGroup = new THREE.Group();
    inspectorGroup.position.set(0, 0.05, 0);

    const uniformMat = new THREE.MeshStandardMaterial({ color: 0x1B263B, roughness: 0.75 }); // Форма ДПС
    const stripePantsMat = new THREE.MeshStandardMaterial({ color: 0xD32F2F, roughness: 0.6 });// Красный кант на брюках
    const vestMat = new THREE.MeshStandardMaterial({ color: 0xD4E119, roughness: 0.65 });     // Кислотно-салатовый жилет
    const scotchliteMat = new THREE.MeshStandardMaterial({ color: 0xF0F4F8, roughness: 0.15, metalness: 0.6 });// Светоотражающие полосы
    const skinMat = new THREE.MeshStandardMaterial({ color: 0xF0C09A, roughness: 0.85 });     // Кожа лица и рук
    const leatherMat = new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.35, metalness: 0.2 });// Ботинки, козырек, ремень
    const goldMat = new THREE.MeshStandardMaterial({ color: 0xD4AF37, metalness: 0.8, roughness: 0.3 });// Кокарда и пряжка

    // Ботинки
    [-0.19, 0.19].forEach(x => {
      const boot = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.18, 0.44), leatherMat);
      boot.position.set(x, 0.09, 0.06);
      boot.castShadow = true;
      inspectorGroup.add(boot);
    });

    // Брюки с кантом
    [-0.19, 0.19].forEach(x => {
      const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.13, 0.92, 14), uniformMat);
      leg.position.set(x, 0.58, 0);
      leg.castShadow = true;
      inspectorGroup.add(leg);

      const stripe = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.92, 0.04), stripePantsMat);
      stripe.position.set(x + (x > 0 ? 0.135 : -0.135), 0.58, 0);
      inspectorGroup.add(stripe);
    });

    // Ремень с кобурой и пряжкой
    const belt = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.34, 0.1, 18), leatherMat);
    belt.position.set(0, 1.05, 0);
    inspectorGroup.add(belt);

    const buckle = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.08, 0.04), goldMat);
    buckle.position.set(0, 1.05, 0.34);
    inspectorGroup.add(buckle);

    // Кобура на правом бедре
    const holster = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.22, 0.12), leatherMat);
    holster.position.set(0.35, 0.96, 0.04);
    inspectorGroup.add(holster);

    // Рация на левом плече
    const radio = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.16, 0.08), leatherMat);
    radio.position.set(-0.25, 1.72, 0.12);
    inspectorGroup.add(radio);

    // Туловище (в жилете ДПС)
    vestMesh = new THREE.Mesh(new THREE.CylinderGeometry(0.36, 0.33, 0.78, 16), vestMat);
    vestMesh.position.set(0, 1.45, 0);
    vestMesh.castShadow = true;
    inspectorGroup.add(vestMesh);

    // Светоотражающие полосы на жилете (две горизонтальные)
    [1.32, 1.55].forEach(y => {
      const stripeH = new THREE.Mesh(new THREE.CylinderGeometry(0.365, 0.365, 0.07, 18), scotchliteMat);
      stripeH.position.set(0, y, 0);
      inspectorGroup.add(stripeH);
    });

    // Шеврон / надпись ДПС (синяя плашка)
    const dpsBadge = new THREE.Mesh(new THREE.PlaneGeometry(0.24, 0.12), uniformMat);
    dpsBadge.position.set(0, 1.68, 0.365);
    inspectorGroup.add(dpsBadge);

    // Шея и голова
    const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.15, 0.18, 14), skinMat);
    neck.position.set(0, 1.92, 0);
    inspectorGroup.add(neck);

    headMesh = new THREE.Mesh(new THREE.SphereGeometry(0.22, 16, 14), skinMat);
    headMesh.position.set(0, 2.14, 0);
    headMesh.scale.set(0.9, 1.1, 0.95);
    headMesh.castShadow = true;
    inspectorGroup.add(headMesh);

    // Глаза, брови, нос регулировщика
    const eyeL = new THREE.Mesh(new THREE.SphereGeometry(0.024, 8, 8), leatherMat);
    eyeL.position.set(-0.075, 2.14, 0.202);
    inspectorGroup.add(eyeL);

    const eyeR = new THREE.Mesh(new THREE.SphereGeometry(0.024, 8, 8), leatherMat);
    eyeR.position.set(0.075, 2.14, 0.202);
    inspectorGroup.add(eyeR);

    const browL = new THREE.Mesh(new THREE.BoxGeometry(0.048, 0.012, 0.015), leatherMat);
    browL.position.set(-0.075, 2.18, 0.204);
    browL.rotation.z = -0.05;
    inspectorGroup.add(browL);

    const browR = new THREE.Mesh(new THREE.BoxGeometry(0.048, 0.012, 0.015), leatherMat);
    browR.position.set(0.075, 2.18, 0.204);
    browR.rotation.z = 0.05;
    inspectorGroup.add(browR);

    const nose = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.05, 0.035), skinMat);
    nose.position.set(0, 2.12, 0.215);
    inspectorGroup.add(nose);

    // Фуражка ДПС (тулья, околыш, аккуратный козырек, золотая кокарда)
    const capCrown = new THREE.Mesh(new THREE.CylinderGeometry(0.31, 0.25, 0.14, 20), uniformMat);
    capCrown.position.set(0, 2.34, -0.02);
    capCrown.rotation.x = -0.05;
    inspectorGroup.add(capCrown);

    const capBand = new THREE.Mesh(new THREE.CylinderGeometry(0.245, 0.245, 0.06, 20), leatherMat);
    capBand.position.set(0, 2.25, 0.01);
    inspectorGroup.add(capBand);

    const capVisor = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.018, 0.11), leatherMat);
    capVisor.position.set(0, 2.23, 0.21);
    capVisor.rotation.x = 0.22;
    inspectorGroup.add(capVisor);

    const cockade = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.02, 12), goldMat);
    cockade.rotation.x = Math.PI / 2;
    cockade.position.set(0, 2.30, 0.245);
    inspectorGroup.add(cockade);

    // Левая рука (плечо + предплечье + кисть)
    leftArmPivot = new THREE.Group();
    leftArmPivot.position.set(-0.42, 1.76, 0);

    const leftArmMesh = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.1, 0.72, 12), uniformMat);
    leftArmMesh.position.set(0, -0.34, 0);
    leftArmMesh.castShadow = true;
    leftArmPivot.add(leftArmMesh);

    const handL = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 10), skinMat);
    handL.position.set(0, -0.72, 0);
    leftArmPivot.add(handL);

    inspectorGroup.add(leftArmPivot);

    // Правая рука с жезлом регулировщика
    rightArmPivot = new THREE.Group();
    rightArmPivot.position.set(0.42, 1.76, 0);

    const rightArmMesh = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.1, 0.72, 12), uniformMat);
    rightArmMesh.position.set(0, -0.34, 0);
    rightArmMesh.castShadow = true;
    rightArmPivot.add(rightArmMesh);

    const handR = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 10), skinMat);
    handR.position.set(0, -0.72, 0);
    rightArmPivot.add(handR);

    // Жезл регулировщика (высококонтрастные черно-белые полосы + красный светодиод)
    batonMesh = buildBaton();
    batonMesh.position.set(0, -0.72, 0);
    rightArmPivot.add(batonMesh);

    inspectorGroup.add(rightArmPivot);

    scene.add(inspectorGroup);
  }

  function buildBaton() {
    const batonGroup = new THREE.Group();
    const handleMat = new THREE.MeshStandardMaterial({ color: 0x111111, roughness: 0.3 });
    const whiteMat = new THREE.MeshStandardMaterial({ color: 0xFFFFFF, roughness: 0.2 });
    const redTipMat = new THREE.MeshBasicMaterial({ color: 0xFF1744 });

    // Рукоятка жезла сидит прямо в ладони инспектора
    const handle = new THREE.Mesh(new THREE.CylinderGeometry(0.026, 0.028, 0.16, 14), handleMat);
    handle.position.set(0, 0, 0);
    batonGroup.add(handle);

    // Темляк (ремешок на запястье у верхнего торца рукоятки)
    const strap = new THREE.Mesh(new THREE.TorusGeometry(0.032, 0.006, 8, 16), handleMat);
    strap.rotation.x = Math.PI / 2;
    strap.position.set(0, 0.07, 0);
    batonGroup.add(strap);

    // 4 чередующиеся полосы (ГОСТ) вдоль оси жезла (-Y)
    for (let i = 0; i < 4; i++) {
      const mat = (i % 2 === 0) ? whiteMat : handleMat;
      const stripe = new THREE.Mesh(new THREE.CylinderGeometry(0.029, 0.029, 0.095, 14), mat);
      stripe.position.set(0, -0.125 - i * 0.095, 0);
      batonGroup.add(stripe);
    }

    // Красный светящийся торец на конце жезла
    const tip = new THREE.Mesh(new THREE.SphereGeometry(0.03, 12, 12), redTipMat);
    tip.position.set(0, -0.51, 0);
    batonGroup.add(tip);

    // Легкая подсветка кончика жезла
    const tipLight = new THREE.PointLight(0xFF1744, 0.6, 1.2);
    tipLight.position.set(0, -0.51, 0);
    batonGroup.add(tipLight);

    return batonGroup;
  }

  // --- Автомобиль игрока (модель из игры) и трамвай ---
  function buildVehicles() {
    // 1. Легковой автомобиль (использует официальную систему моделей PDD_VEHICLES)
    if (window.PDD_VEHICLES && typeof window.PDD_VEHICLES.create === 'function') {
      carMesh = window.PDD_VEHICLES.create('sedan', 'blue');
    } else {
      carMesh = buildFallbackCar();
    }

    // Располагаем машину на правой полосе южного въезда лицом к перекрестку
    carMesh.position.set(3.2, 0, 13.5);
    carMesh.rotation.y = Math.PI; // Лицом к перекрёстку (на север)
    scene.add(carMesh);

    // 2. Аутентичный российский трамвай (КТМ-5 / Татра красно-бежевый)
    tramMesh = buildRussianTram();
    tramMesh.position.set(-2.2, 0, 14.5);
    tramMesh.rotation.y = Math.PI;
    scene.add(tramMesh);

    // Запоминаем исходные координаты
    initialObjectPos.copy(carMesh.position);
    initialObjectRotY = carMesh.rotation.y;
    activeVehicleMesh = carMesh;
  }

  function buildFallbackCar() {
    const group = new THREE.Group();
    const bodyMat = new THREE.MeshStandardMaterial({ color: 0x1E88E5, metalness: 0.6, roughness: 0.3 });
    const glassMat = new THREE.MeshStandardMaterial({ color: 0x334E68, metalness: 0.9, roughness: 0.1 });
    const wheelMat = new THREE.MeshStandardMaterial({ color: 0x1A1D20, roughness: 0.8 });

    const body = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.7, 4.2), bodyMat);
    body.position.y = 0.55;
    group.add(body);

    const cabin = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.6, 2.1), glassMat);
    cabin.position.set(0, 1.15, -0.2);
    group.add(cabin);

    [-0.92, 0.92].forEach(x => {
      [-1.2, 1.2].forEach(z => {
        const w = new THREE.Mesh(new THREE.CylinderGeometry(0.34, 0.34, 0.24, 16), wheelMat);
        w.rotation.z = Math.PI / 2;
        w.position.set(x, 0.34, z);
        group.add(w);
      });
    });

    const blinkerMat = new THREE.MeshBasicMaterial({ color: 0xFFAE25 });
    const bL = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.09, 0.05), blinkerMat);
    bL.position.set(0.82, 0.61, 2.12);
    group.add(bL);
    group.blinkerL = bL;
    bL.visible = false;

    const bR = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.09, 0.05), blinkerMat);
    bR.position.set(-0.82, 0.61, 2.12);
    group.add(bR);
    group.blinkerR = bR;
    bR.visible = false;

    return group;
  }

  function transportMaterial(kind, color) {
    const surfaces = window.PDD_VEHICLE_MATERIALS;
    if (!surfaces) return new THREE.MeshLambertMaterial({ color });
    return surfaces.material('paint', color, surfaces.transportMap(kind));
  }

  function transportMesh(geometry, material) {
    const surfaces = window.PDD_VEHICLE_MATERIALS;
    if (surfaces) {
      geometry.userData = geometry.userData || {};
      if (!geometry.userData.vehicleUV) {
        if (material.map && material.map.name && material.map.name.startsWith('vehicle:transport:') && geometry.type === 'BoxGeometry') {
          surfaces.transportBoxUV(geometry); geometry.userData.vehicleUV = true;
        } else if (material.userData && ['rubber', 'rubberFarm'].includes(material.userData.vehicleSurface) && geometry.type === 'CylinderGeometry') {
          surfaces.tyreUV(geometry); geometry.userData.vehicleUV = true;
        }
      }
    }
    return new THREE.Mesh(geometry, material);
  }

  function buildFallbackTram(color = BRAND.tramRed) {
    const tram = new THREE.Group();
    const redMat = new THREE.MeshLambertMaterial({ color });
    const creamMat = new THREE.MeshLambertMaterial({ color: BRAND.tramWhite });
    const glassMat = new THREE.MeshLambertMaterial({ color: 0x374A5E });
    const metalMat = new THREE.MeshLambertMaterial({ color: 0x88929E });

    const L = 9.5;
    const W = 2.2;

    const lower = new THREE.Mesh(new THREE.BoxGeometry(W, 1.0, L), redMat);
    lower.position.y = 0.7;
    tram.add(lower);

    const upper = new THREE.Mesh(new THREE.BoxGeometry(W - 0.05, 1.1, L - 0.1), creamMat);
    upper.position.y = 1.7;
    tram.add(upper);

    const glass = new THREE.Mesh(new THREE.BoxGeometry(W + 0.04, 0.65, L - 0.7), glassMat);
    glass.position.y = 1.75;
    tram.add(glass);

    const panto = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.8, 0.8), metalMat);
    panto.position.set(0, 2.7, 1.5);
    tram.add(panto);

    return tram;
  }

  // Аутентичный российский трамвай на материалах PDD_VEHICLE_MATERIALS (как во флагманской игре)
  function buildRussianTram(color = BRAND.tramRed) {
    const tram = new THREE.Group(), V = window.PDD_VEHICLE_MATERIALS;
    if (!V) return buildFallbackTram(color);

    const bodyMat = transportMaterial('tram-body', color);
    const whiteMat = transportMaterial('roof', BRAND.tramWhite);
    const glassMat = V.material('glass', 0xffffff, V.transportMap('tram-windows'));
    const metalMat = V.material('metal', 0x71717A);
    const darkMat = V.material('metal', 0x23272C);

    // 1. Нижняя часть кузова (красный фирменный цвет)
    const lowerGeo = new THREE.BoxGeometry(2.2, 1.0, 9.5);
    const lower = transportMesh(lowerGeo, bodyMat);
    lower.position.y = 0.7;
    lower.castShadow = true;
    tram.add(lower);

    // 2. Верхняя часть кузова / крыша (белая)
    const upperGeo = new THREE.BoxGeometry(2.15, 1.1, 9.4);
    const upper = transportMesh(upperGeo, whiteMat);
    upper.position.y = 1.7;
    upper.castShadow = true;
    tram.add(upper);

    // 3. Оконный пояс с атласом окон трамвая
    const sideWindowsGeo = new THREE.BoxGeometry(2.24, 0.65, 8.8);
    const sideWindows = transportMesh(sideWindowsGeo, glassMat);
    sideWindows.position.y = 1.75;
    tram.add(sideWindows);

    // 4. Лобовое и заднее остекление
    const frontGlassGeo = new THREE.BoxGeometry(1.9, 0.8, 0.1);
    const fg = transportMesh(frontGlassGeo, glassMat);
    fg.position.set(0, 1.65, 4.76);
    tram.add(fg);

    const bg = transportMesh(frontGlassGeo.clone(), glassMat);
    bg.position.set(0, 1.65, -4.76);
    tram.add(bg);

    // 5. Пантограф (токоприёмник) на крыше
    const pantoBase = transportMesh(new THREE.BoxGeometry(0.8, 0.15, 0.8), metalMat);
    pantoBase.position.set(0, 2.35, 1.5);
    tram.add(pantoBase);

    const barGeo = new THREE.CylinderGeometry(0.04, 0.04, 1.1);
    const bar1 = transportMesh(barGeo, metalMat);
    bar1.position.set(0, 2.85, 1.5);
    bar1.rotation.x = 0.35;
    tram.add(bar1);

    const headGeo = new THREE.BoxGeometry(1.6, 0.06, 0.2);
    const head = transportMesh(headGeo, metalMat);
    head.position.set(0, 3.3, 1.7);
    tram.add(head);

    // 6. Тележки под вагоном
    [-2.6, 2.6].forEach(z => {
      const bogie = transportMesh(new THREE.BoxGeometry(1.8, 0.25, 1.6), darkMat);
      bogie.position.set(0, 0.25, z);
      tram.add(bogie);
    });

    // 7. Оптика
    const headMat = V.material('lens', 0xFFF3CC);
    const tailMat = V.material('lens', 0xD33D38);
    const hl = transportMesh(new THREE.CylinderGeometry(0.18, 0.18, 0.1, 16).rotateX(Math.PI / 2), headMat);
    hl.position.set(0, 0.75, 4.76);
    tram.add(hl);

    [-0.7, 0.7].forEach(sx => {
      const tl = transportMesh(new THREE.CylinderGeometry(0.1, 0.1, 0.08, 12).rotateX(Math.PI / 2), tailMat);
      tl.position.set(sx, 0.75, -4.76);
      tram.add(tl);
    });

    if (window.PDD_VEHICLES && typeof window.PDD_VEHICLES.applyModelEdits === 'function') {
      window.PDD_VEHICLES.applyModelEdits('tram', tram);
    }

    return tram;
  }

  // --- Стрелки разрешенных траекторий на асфальте ---
  function buildTrajectoryArrows() {
    arrowsGroup = new THREE.Group();
    scene.add(arrowsGroup);
    updateTrajectoryArrows();
  }

  function updateTrajectoryArrows() {
    while (arrowsGroup.children.length > 0) {
      const child = arrowsGroup.children[0];
      if (child.geometry) child.geometry.dispose();
      if (child.material) child.material.dispose();
      arrowsGroup.remove(child);
    }

    if (currentMode === 'arcade' && !isMoving) return;

    const allowed = getAllowedMoves(currentGesture, currentApproach, currentVehicle);
    const originX = (currentVehicle === VEHICLES.CAR) ? 3.2 : -2.2;
    const originZ = 8.8;

    const canStraight = allowed.includes(MOVES.STRAIGHT);
    const canRight = allowed.includes(MOVES.RIGHT);
    const canLeft = allowed.includes(MOVES.LEFT);
    const canUturn = allowed.includes(MOVES.UTURN);

    // Стрелка прямо (только если разрешено)
    if (canStraight) {
      addRoadRibbonArrow(
        new THREE.LineCurve3(
          new THREE.Vector3(originX, 0.052, originZ),
          new THREE.Vector3(originX, 0.052, -11.0)
        )
      );
    }

    // Стрелка направо (только если разрешено)
    if (canRight) {
      addRoadRibbonArrow(
        new THREE.QuadraticBezierCurve3(
          new THREE.Vector3(originX, 0.052, originZ),
          new THREE.Vector3(originX, 0.052, 2.4),
          new THREE.Vector3(12.0, 0.052, 2.4)
        )
      );
    }

    // Стрелка налево (только если разрешено)
    if (canLeft) {
      addRoadRibbonArrow(
        new THREE.CubicBezierCurve3(
          new THREE.Vector3(originX, 0.052, originZ),
          new THREE.Vector3(originX, 0.052, 2.0),
          new THREE.Vector3(0.0, 0.052, -2.4),
          new THREE.Vector3(-12.0, 0.052, -2.4)
        )
      );
    }

    // Разворот (если разрешено для автомобиля)
    if (canUturn && currentVehicle === VEHICLES.CAR) {
      addRoadRibbonArrow(
        new THREE.CubicBezierCurve3(
          new THREE.Vector3(originX, 0.052, originZ),
          new THREE.Vector3(originX, 0.052, 2.0),
          new THREE.Vector3(-2.8, 0.052, 2.0),
          new THREE.Vector3(-2.8, 0.052, 12.0)
        )
      );
    }

    // Если движение запрещено (например, грудь/спина или поднятая рука)
    if (allowed.length === 1 && allowed[0] === MOVES.NONE) {
      addStopProhibitionMarker(originX, originZ);
    }
  }

  function addRoadRibbonArrow(curve, width = 0.55) {
    const numPoints = 32;
    const points = curve.getPoints(numPoints);
    const ribbonPointCount = numPoints - 1;

    // Одиночная сплошная яркая неоново-зеленая лента
    createStripMesh(points, ribbonPointCount, width, 0.052, 0x00E676);

    // Большой плоский стрелочный наконечник на асфальте
    const lastP = points[ribbonPointCount];
    const tipP = points[numPoints];
    const atx = tipP.x - lastP.x;
    const atz = tipP.z - lastP.z;
    const alen = Math.hypot(atx, atz) || 1;
    const dirX = atx / alen;
    const dirZ = atz / alen;

    const headW = width * 2.2;
    const anx = -dirZ * (headW / 2);
    const anz = dirX * (headW / 2);

    const tipExtX = tipP.x + dirX * 0.6;
    const tipExtZ = tipP.z + dirZ * 0.6;

    createTriangleMesh(
      [lastP.x + anx, 0.053, lastP.z + anz],
      [lastP.x - anx, 0.053, lastP.z - anz],
      [tipExtX, 0.053, tipExtZ],
      0x00E676
    );
  }

  function createStripMesh(points, count, stripWidth, yElev, color) {
    const halfW = stripWidth / 2;
    const vertices = [];
    const indices = [];

    for (let i = 0; i <= count; i++) {
      const p = points[i];
      let tx, tz;
      if (i === 0) {
        tx = points[1].x - points[0].x;
        tz = points[1].z - points[0].z;
      } else if (i === count) {
        tx = points[i].x - points[i - 1].x;
        tz = points[i].z - points[i - 1].z;
      } else {
        tx = points[i + 1].x - points[i - 1].x;
        tz = points[i + 1].z - points[i - 1].z;
      }
      const len = Math.hypot(tx, tz) || 1;
      const nx = (-tz / len) * halfW;
      const nz = (tx / len) * halfW;

      vertices.push(p.x + nx, yElev, p.z + nz);
      vertices.push(p.x - nx, yElev, p.z - nz);

      if (i < count) {
        const v0 = i * 2;
        const v1 = i * 2 + 1;
        const v2 = (i + 1) * 2;
        const v3 = (i + 1) * 2 + 1;
        indices.push(v0, v1, v2);
        indices.push(v2, v1, v3);
      }
    }

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(vertices, 3));
    geo.setIndex(indices);
    geo.computeVertexNormals();

    const mat = new THREE.MeshBasicMaterial({
      color: color,
      side: THREE.DoubleSide,
      depthWrite: false,
    });

    const mesh = new THREE.Mesh(geo, mat);
    arrowsGroup.add(mesh);
  }

  function createTriangleMesh(p1, p2, p3, color) {
    const vertices = [
      p1[0], p1[1], p1[2],
      p2[0], p2[1], p2[2],
      p3[0], p3[1], p3[2],
    ];
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(vertices, 3));
    geo.setIndex([0, 1, 2]);
    geo.computeVertexNormals();

    const mat = new THREE.MeshBasicMaterial({
      color: color,
      side: THREE.DoubleSide,
      depthWrite: false,
    });
    arrowsGroup.add(new THREE.Mesh(geo, mat));
  }

  function addStopProhibitionMarker(x, z) {
    // Яркая запрещающая стоп-полоса перед стоп-линией
    const barGeo = new THREE.BoxGeometry(2.6, 0.05, 0.45);
    const barMat = new THREE.MeshBasicMaterial({ color: 0xFF1744 });
    const bar = new THREE.Mesh(barGeo, barMat);
    bar.position.set(x, 0.052, z - 0.4);
    arrowsGroup.add(bar);
  }

  // --- Переключение сценария и поз регулировщика ---
  function setScenario(gesture, approach, vehicle) {
    if (resetTimer) {
      clearTimeout(resetTimer);
      resetTimer = null;
    }

    currentGesture = gesture;
    currentApproach = approach;
    currentVehicle = vehicle || currentVehicle;

    // Вращение регулировщика в зависимости от ракурса
    switch (approach) {
      case APPROACHES.FRONT:
        targetInspectorRotY = 0;           // Лицом к югу
        break;
      case APPROACHES.BACK:
        targetInspectorRotY = Math.PI;     // Спиной к югу
        break;
      case APPROACHES.LEFT:
        targetInspectorRotY = -Math.PI / 2;// Левым боком к югу
        break;
      case APPROACHES.RIGHT:
        targetInspectorRotY = Math.PI / 2; // Правым боком к югу
        break;
    }

    // Положение рук инспектора
    if (gesture === GESTURES.ARM_UP) {
      // 1. Рука поднята вверх: правая вверх (жезл строго вертикально), левая опущена
      targetRightArm.set(0, 0, Math.PI);
      targetLeftArm.set(0, 0, 0);
    } else if (gesture === GESTURES.HANDS_DOWN) {
      // 2. Руки опущены или вытянуты в стороны
      targetLeftArm.set(0, 0, -Math.PI / 2);
      targetRightArm.set(0, 0, Math.PI / 2);
    } else if (gesture === GESTURES.RIGHT_ARM_FORWARD) {
      // 3. Правая рука вытянута вперед, левая опущена
      targetRightArm.set(-Math.PI / 2, 0, 0);
      targetLeftArm.set(0, 0, 0);
    }

    // Переключение видимости авто/трамвая
    if (carMesh && tramMesh) {
      if (currentVehicle === VEHICLES.CAR) {
        carMesh.visible = true;
        tramMesh.visible = false;
        activeVehicleMesh = carMesh;
      } else {
        carMesh.visible = false;
        tramMesh.visible = true;
        activeVehicleMesh = tramMesh;
      }
    }

    resetVehiclePositions();
    updateTrajectoryArrows();
  }

  function resetVehiclePositions() {
    if (resetTimer) {
      clearTimeout(resetTimer);
      resetTimer = null;
    }
    if (carMesh) {
      carMesh.position.set(3.2, 0, 13.5);
      carMesh.rotation.y = Math.PI;
      if (carMesh.blinkerL) carMesh.blinkerL.visible = false;
      if (carMesh.blinkerR) carMesh.blinkerR.visible = false;
    }
    if (tramMesh) {
      tramMesh.position.set(-2.2, 0, 14.5);
      tramMesh.rotation.y = Math.PI;
    }
    activeBlinkerSide = null;
    isMoving = false;
    moveProgress = 0;
  }

  // --- Запуск анимации движения ТС при ответе игрока ---
  function makeMove(moveType) {
    if (isMoving) return;
    if (resetTimer) {
      clearTimeout(resetTimer);
      resetTimer = null;
    }
    // Если машина осталась в конце предыдущего манёвра, возвращаем её на старт
    if (moveProgress >= 1) {
      resetVehiclePositions();
    }

    const allowed = getAllowedMoves(currentGesture, currentApproach, currentVehicle);
    const isCorrect = allowed.includes(moveType);

    if (moveType === MOVES.NONE) {
      activeBlinkerSide = null;
      if (carMesh) {
        if (carMesh.blinkerL) carMesh.blinkerL.visible = false;
        if (carMesh.blinkerR) carMesh.blinkerR.visible = false;
      }
      // Если действие «Стоять»
      notifyFlutter({
        type: 'move_result',
        move: moveType,
        isCorrect: isCorrect,
      });
      return;
    }

    if (moveType === MOVES.RIGHT) {
      activeBlinkerSide = 'right';
    } else if (moveType === MOVES.LEFT || moveType === MOVES.UTURN) {
      activeBlinkerSide = 'left';
    } else {
      activeBlinkerSide = null;
    }

    movingObject = (currentVehicle === VEHICLES.CAR) ? carMesh : tramMesh;
    const startX = movingObject.position.x;
    const startZ = movingObject.position.z;

    // Все манёвры завершаются за перекрёстком и пешеходным переходом (на отметке ±13.5)
    if (moveType === MOVES.STRAIGHT) {
      moveCurve = new THREE.LineCurve3(
        new THREE.Vector3(startX, 0, startZ),
        new THREE.Vector3(startX, 0, -13.5)
      );
    } else if (moveType === MOVES.RIGHT) {
      moveCurve = new THREE.QuadraticBezierCurve3(
        new THREE.Vector3(startX, 0, startZ),
        new THREE.Vector3(startX, 0, 2.4),
        new THREE.Vector3(13.5, 0, 2.4)
      );
    } else if (moveType === MOVES.LEFT) {
      moveCurve = new THREE.CubicBezierCurve3(
        new THREE.Vector3(startX, 0, startZ),
        new THREE.Vector3(startX, 0, 2.0),
        new THREE.Vector3(0.0, 0, -2.4),
        new THREE.Vector3(-13.5, 0, -2.4)
      );
    } else if (moveType === MOVES.UTURN) {
      moveCurve = new THREE.CubicBezierCurve3(
        new THREE.Vector3(startX, 0, startZ),
        new THREE.Vector3(startX, 0, 2.0),
        new THREE.Vector3(-2.8, 0, 2.0),
        new THREE.Vector3(-2.8, 0, 13.5)
      );
    }

    isMoving = true;
    moveProgress = 0;

    notifyFlutter({
      type: 'move_result',
      move: moveType,
      isCorrect: isCorrect,
    });
  }

  // --- Камера: переключение ракурса и горизонтальное вращение ---
  function setCameraView(view) {
    currentCameraMode = view;
    if (view === 'driver') {
      targetAngle = 0;
    }
  }

  function rotateCamera(deltaX) {
    if (currentCameraMode === 'overview') {
      targetAngle += deltaX * 0.007;
    }
  }

  function updateCameraPosition() {
    if (currentCameraMode === 'overview') {
      const radius = camDistance;
      camera.position.x = Math.sin(camAngle) * radius;
      camera.position.y = camHeight;
      camera.position.z = Math.cos(camAngle) * radius;
      camera.lookAt(0, 1.2, 0);
    } else {
      // Вид из кабины водителя машины / трамвая
      if (currentVehicle === VEHICLES.TRAM && tramMesh) {
        camera.position.set(-2.2, 1.9, 10.4);
        camera.lookAt(-2.2, 1.6, 0);
      } else if (carMesh) {
        camera.position.set(3.2, 1.45, 12.8);
        camera.lookAt(3.2, 1.35, 0);
      }
    }
  }

  function onWindowResize() {
    if (!container) return;
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
  }

  // --- Главный цикл анимации ---
  function animate() {
    requestAnimationFrame(animate);

    const delta = clock.getDelta();
    const time = clock.getElapsedTime();

    // Плавное вращение камеры
    camAngle += (targetAngle - camAngle) * 0.08;
    updateCameraPosition();

    // Плавный поворот регулировщика к целевому направлению
    curInspectorRotY += (targetInspectorRotY - curInspectorRotY) * 0.12;
    if (inspectorGroup) {
      inspectorGroup.rotation.y = curInspectorRotY;
    }

    // Дыхание регулировщика и легкое покачивание жезла (живая анимация)
    if (vestMesh) {
      const breathe = Math.sin(time * 2.2) * 0.006;
      vestMesh.scale.set(1 + breathe, 1, 1 + breathe);
    }

    // Плавная интерполяция рук регулировщика
    curLeftArm.x += (targetLeftArm.x - curLeftArm.x) * 0.12;
    curLeftArm.y += (targetLeftArm.y - curLeftArm.y) * 0.12;
    curLeftArm.z += (targetLeftArm.z - curLeftArm.z) * 0.12;
    if (leftArmPivot) {
      leftArmPivot.rotation.set(curLeftArm.x, curLeftArm.y, curLeftArm.z);
    }

    curRightArm.x += (targetRightArm.x - curRightArm.x) * 0.12;
    curRightArm.y += (targetRightArm.y - curRightArm.y) * 0.12;
    curRightArm.z += (targetRightArm.z - curRightArm.z) * 0.12;
    if (rightArmPivot) {
      rightArmPivot.rotation.set(curRightArm.x, curRightArm.y, curRightArm.z);
    }

    // Анимация движения машины/трамвая (движение ВПЕРЕД по траектории с постоянной скоростью)
    if (isMoving && moveCurve && movingObject) {
      const curveLength = moveCurve.getLength();
      // Постоянная линейная скорость (м/с): строго одинаковая для всех направлений!
      const moveSpeed = (currentMode === 'arcade') ? 16.0 : 10.5;
      moveProgress += (delta * moveSpeed) / Math.max(curveLength, 1);

      if (moveProgress >= 1) {
        moveProgress = 1;
        isMoving = false;
        activeBlinkerSide = null;
        if (carMesh) {
          if (carMesh.blinkerL) carMesh.blinkerL.visible = false;
          if (carMesh.blinkerR) carMesh.blinkerR.visible = false;
        }
        // Даём спокойно рассмотреть завершение манёвра без мгновенного исчезновения
        const holdDuration = (currentMode === 'arcade') ? 700 : 2000;
        if (resetTimer) clearTimeout(resetTimer);
        resetTimer = setTimeout(resetVehiclePositions, holdDuration);
      }

      const u = Math.min(Math.max(moveProgress, 0), 1);
      const point = moveCurve.getPointAt(u);
      movingObject.position.copy(point);

      const tangent = moveCurve.getTangentAt(u);
      movingObject.rotation.y = Math.atan2(tangent.x, tangent.z);
    }

    // Мигание поворотников автомобиля при манёвре (~3.2 Гц)
    if (carMesh) {
      const blinkState = (activeBlinkerSide && isMoving) ? (Math.floor(time * 6.5) % 2 === 0) : false;
      if (carMesh.blinkerL) {
        carMesh.blinkerL.visible = (activeBlinkerSide === 'left') && blinkState;
      }
      if (carMesh.blinkerR) {
        carMesh.blinkerR.visible = (activeBlinkerSide === 'right') && blinkState;
      }
    }

    renderer.render(scene, camera);
  }

  // --- Связь с Flutter ---
  function notifyFlutter(payload) {
    const jsonStr = JSON.stringify(payload);
    if (window.FlutterChannel && typeof window.FlutterChannel.postMessage === 'function') {
      window.FlutterChannel.postMessage(jsonStr);
    } else if (window.parent && window.parent !== window) {
      window.parent.postMessage(jsonStr, '*');
    }
  }

  // Экспорт API для вызова из Flutter
  window.TrafficControllerGame = {
    setScenario,
    makeMove,
    setMode(mode) {
      currentMode = mode;
      updateTrajectoryArrows();
    },
    setCameraView,
    rotateCamera,
    reset() {
      resetVehiclePositions();
      updateTrajectoryArrows();
    },
  };

  window.addEventListener('DOMContentLoaded', init);
})();
