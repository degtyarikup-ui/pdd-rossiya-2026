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

  // --- Переменные сцены ---
  let scene, camera, renderer;
  let container;
  let inspectorGroup, headMesh, leftArmPivot, rightArmPivot, batonMesh, vestMesh;
  let carMesh, tramMesh;
  let activeVehicleMesh;
  let arrowsGroup;
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
  let camDistance = 30;
  let camHeight = 22;
  let clock = new THREE.Clock();

  function init() {
    container = document.getElementById('canvas-container');
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x3B485A);
    scene.fog = new THREE.Fog(0x3B485A, 38, 115);

    camera = new THREE.PerspectiveCamera(42, width / height, 0.5, 300);
    updateCameraPosition();

    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: 'high-performance' });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    container.appendChild(renderer.domElement);

    setupLighting();
    buildEnvironment();
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
    // Мягкий полусферический свет неба и земли
    const hemiLight = new THREE.HemisphereLight(0xDFE9F8, 0x2A3546, 0.75);
    scene.add(hemiLight);

    // Основной солнечный направленный свет с мягкими тенями
    const sunLight = new THREE.DirectionalLight(0xFFF7E6, 1.25);
    sunLight.position.set(28, 48, 24);
    sunLight.castShadow = true;
    sunLight.shadow.mapSize.width = 2048;
    sunLight.shadow.mapSize.height = 2048;
    sunLight.shadow.camera.near = 5;
    sunLight.shadow.camera.far = 130;
    sunLight.shadow.bias = -0.0004;

    const d = 34;
    sunLight.shadow.camera.left = -d;
    sunLight.shadow.camera.right = d;
    sunLight.shadow.camera.top = d;
    sunLight.shadow.camera.bottom = -d;
    scene.add(sunLight);

    // Заполняющий холодный свет с противоположной стороны
    const fillLight = new THREE.DirectionalLight(0x769ECC, 0.45);
    fillLight.position.set(-26, 22, -26);
    scene.add(fillLight);
  }

  // --- Перекрёсток: дороги, тротуары, разметка, рельсы, здания ---
  function buildEnvironment() {
    const envGroup = new THREE.Group();
    scene.add(envGroup);

    // Основание / трава вокруг города
    const groundGeo = new THREE.PlaneGeometry(240, 240);
    const groundMat = new THREE.MeshStandardMaterial({
      color: 0x3E543B,
      roughness: 0.95,
      metalness: 0.05,
    });
    const ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    envGroup.add(ground);

    // Асфальтовое покрытие дорог (проезжая часть 13.6м)
    const roadMat = new THREE.MeshStandardMaterial({
      color: 0x272B33,
      roughness: 0.88,
      metalness: 0.1,
    });
    const roadWidth = 13.6;
    const roadLen = 140;

    const roadNS = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth, roadLen), roadMat);
    roadNS.rotation.x = -Math.PI / 2;
    roadNS.position.y = 0.02;
    roadNS.receiveShadow = true;
    envGroup.add(roadNS);

    const roadEW = new THREE.Mesh(new THREE.PlaneGeometry(roadLen, roadWidth), roadMat);
    roadEW.rotation.x = -Math.PI / 2;
    roadEW.position.y = 0.02;
    roadEW.receiveShadow = true;
    envGroup.add(roadEW);

    // Центр перекрестка
    const centerMesh = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth, roadWidth), roadMat);
    centerMesh.rotation.x = -Math.PI / 2;
    centerMesh.position.y = 0.025;
    centerMesh.receiveShadow = true;
    envGroup.add(centerMesh);

    // Дорожная разметка (белая термопластичная краска)
    const markMat = new THREE.MeshStandardMaterial({
      color: 0xFDFDFD,
      roughness: 0.5,
      metalness: 0.05,
    });

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

    // Стрелки направлений по полосам на асфальте
    buildLaneArrows(parent, markMat);
  }

  // Стрелки полос движения перед перекрестком
  function buildLaneArrows(parent, markMat) {
    const arrowShaft = new THREE.PlaneGeometry(0.35, 2.4);
    const arrowHead = new THREE.ConeGeometry(0.45, 0.9, 3);

    // Стрелка «Прямо и Направо» на правой полосе южного въезда
    const rightLaneArrow = new THREE.Mesh(arrowShaft, markMat);
    rightLaneArrow.rotation.x = -Math.PI / 2;
    rightLaneArrow.position.set(4.6, 0.036, 17);
    parent.add(rightLaneArrow);

    const headR = new THREE.Mesh(arrowHead, markMat);
    headR.rotation.x = -Math.PI / 2;
    headR.position.set(4.6, 0.036, 15.4);
    parent.add(headR);

    // Стрелка «Прямо и Налево» на средней полосе южного въезда
    const midLaneArrow = new THREE.Mesh(arrowShaft, markMat);
    midLaneArrow.rotation.x = -Math.PI / 2;
    midLaneArrow.position.set(1.8, 0.036, 17);
    parent.add(midLaneArrow);

    const headM = new THREE.Mesh(arrowHead, markMat);
    headM.rotation.x = -Math.PI / 2;
    headM.position.set(1.8, 0.036, 15.4);
    parent.add(headM);
  }

  // Приподнятые тротуары с гранитными бордюрами
  function buildSidewalks(parent, roadWidth) {
    const halfW = roadWidth / 2;
    const kerbMat = new THREE.MeshStandardMaterial({
      color: 0x7E8592,
      roughness: 0.65,
      metalness: 0.15,
    });
    const walkMat = new THREE.MeshStandardMaterial({
      color: 0x9FA6B2,
      roughness: 0.78,
      metalness: 0.08,
    });
    const lawnMat = new THREE.MeshStandardMaterial({
      color: 0x426E3B,
      roughness: 0.92,
      metalness: 0.05,
    });

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

      // Плита тротуара
      const walk = new THREE.Mesh(new THREE.BoxGeometry(walkSize, kerbH, walkSize), walkMat);
      walk.receiveShadow = true;
      g.add(walk);

      // Газон в глубине тротуара
      const lawn = new THREE.Mesh(new THREE.BoxGeometry(walkSize - 8, 0.02, walkSize - 8), lawnMat);
      lawn.position.set(q.sx * 4, kerbH / 2 + 0.01, q.sz * 4);
      lawn.receiveShadow = true;
      g.add(lawn);

      parent.add(g);

      // Гранитные бордюрные камни вдоль дороги
      const kerbEW = new THREE.Mesh(new THREE.BoxGeometry(walkSize, kerbH + 0.02, 0.35), kerbMat);
      kerbEW.position.set(q.sx * (halfW + walkSize / 2), kerbH / 2 + 0.01, q.sz * (halfW + 0.17));
      kerbEW.castShadow = true;
      parent.add(kerbEW);

      const kerbNS = new THREE.Mesh(new THREE.BoxGeometry(0.35, kerbH + 0.02, walkSize), kerbMat);
      kerbNS.position.set(q.sx * (halfW + 0.17), kerbH / 2 + 0.01, q.sz * (halfW + walkSize / 2));
      kerbNS.castShadow = true;
      parent.add(kerbNS);
    });
  }

  // Городские здания по углам перекрёстка (красивая архитектура с окнами и крышами)
  function buildCityBuildings(parent, roadWidth) {
    const halfW = roadWidth / 2;

    const buildingSpecs = [
      // Северо-Запад: 4-этажный классический дом с карнизом и окнами
      { x: -(halfW + 18), z: -(halfW + 18), w: 22, d: 24, h: 18, color: 0xC8B699, roofColor: 0x3D4350 },
      // Северо-Восток: 5-этажный современный кирпичный дом
      { x: (halfW + 18), z: -(halfW + 18), w: 24, d: 22, h: 22, color: 0x9E5848, roofColor: 0x2A2E38 },
      // Юго-Запад: 3-этажный дом с рустом и витринами
      { x: -(halfW + 18), z: (halfW + 18), w: 22, d: 22, h: 14, color: 0x768A7C, roofColor: 0x3F4652 },
      // Юго-Восток: 4-этажный светлый фасад
      { x: (halfW + 18), z: (halfW + 18), w: 24, d: 24, h: 17, color: 0xB5BAC4, roofColor: 0x323842 },
    ];

    buildingSpecs.forEach(b => {
      const bGroup = new THREE.Group();
      bGroup.position.set(b.x, 0, b.z);

      const facadeMat = new THREE.MeshStandardMaterial({
        color: b.color,
        roughness: 0.85,
        metalness: 0.1,
      });

      // Основной корпус
      const body = new THREE.Mesh(new THREE.BoxGeometry(b.w, b.h, b.d), facadeMat);
      body.position.y = b.h / 2;
      body.castShadow = true;
      body.receiveShadow = true;
      bGroup.add(body);

      // Карниз / крыша
      const roofMat = new THREE.MeshStandardMaterial({ color: b.roofColor, roughness: 0.7 });
      const roof = new THREE.Mesh(new THREE.BoxGeometry(b.w + 0.8, 1.2, b.d + 0.8), roofMat);
      roof.position.y = b.h + 0.6;
      roof.castShadow = true;
      bGroup.add(roof);

      // Сетка окон на фасадных сторонах
      const winMat = new THREE.MeshStandardMaterial({
        color: 0x3A4D62,
        roughness: 0.2,
        metalness: 0.85,
      });
      const winFrameMat = new THREE.MeshStandardMaterial({ color: 0xF5F6F8, roughness: 0.6 });

      const floors = Math.floor(b.h / 3.4);
      const cols = Math.floor(b.w / 3.8);

      for (let f = 1; f < floors; f++) {
        const y = f * 3.4 + 1.2;
        for (let c = -Math.floor(cols / 2); c <= Math.floor(cols / 2); c++) {
          const x = c * 3.2;

          // Окно на южном фасаде
          const winFrame = new THREE.Mesh(new THREE.BoxGeometry(1.5, 2.0, 0.15), winFrameMat);
          winFrame.position.set(x, y, b.d / 2 + 0.05);
          bGroup.add(winFrame);

          const winGlass = new THREE.Mesh(new THREE.PlaneGeometry(1.2, 1.7), winMat);
          winGlass.position.set(x, y, b.d / 2 + 0.14);
          bGroup.add(winGlass);

          // Окно на восточном/западном фасаде
          const winFrameSide = new THREE.Mesh(new THREE.BoxGeometry(0.15, 2.0, 1.5), winFrameMat);
          winFrameSide.position.set(b.w / 2 + 0.05, y, c * 3.2);
          bGroup.add(winFrameSide);

          const winGlassSide = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 1.7), winMat);
          winGlassSide.rotation.y = Math.PI / 2;
          winGlassSide.position.set(b.w / 2 + 0.14, y, c * 3.2);
          bGroup.add(winGlassSide);
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

    // Дорожные знаки: Знак 2.1 «Главная дорога» и Знак 5.19.1 «Пешеходный переход»
    buildRoadSigns(parent, halfW);
  }

  function buildStreetLamp() {
    const group = new THREE.Group();
    const poleMat = new THREE.MeshStandardMaterial({ color: 0x242830, metalness: 0.85, roughness: 0.3 });
    const glowMat = new THREE.MeshBasicMaterial({ color: 0xFFF4D4 });

    // Стойка
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.12, 6.5, 12), poleMat);
    pole.position.y = 3.25;
    pole.castShadow = true;
    group.add(pole);

    // Изогнутый кронштейн
    const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 1.6, 8), poleMat);
    arm.rotation.z = Math.PI / 3;
    arm.position.set(0.65, 6.7, 0);
    group.add(arm);

    // Светильник
    const head = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.2, 0.35), poleMat);
    head.position.set(1.4, 7.1, 0);
    group.add(head);

    const bulb = new THREE.Mesh(new THREE.PlaneGeometry(0.55, 0.25), glowMat);
    bulb.rotation.x = Math.PI / 2;
    bulb.position.set(1.4, 6.98, 0);
    group.add(bulb);

    return group;
  }

  function buildTree() {
    const group = new THREE.Group();
    const trunkMat = new THREE.MeshStandardMaterial({ color: 0x4A3525, roughness: 0.9 });
    const leafMat1 = new THREE.MeshStandardMaterial({ color: 0x3D6F36, roughness: 0.85 });
    const leafMat2 = new THREE.MeshStandardMaterial({ color: 0x4A8341, roughness: 0.85 });

    // Ствол
    const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.28, 3.2, 8), trunkMat);
    trunk.position.y = 1.6;
    trunk.castShadow = true;
    group.add(trunk);

    // Ярусы кроны (сочные зеленые сферы)
    const crown1 = new THREE.Mesh(new THREE.DodecahedronGeometry(1.6, 1), leafMat1);
    crown1.position.y = 3.8;
    crown1.castShadow = true;
    group.add(crown1);

    const crown2 = new THREE.Mesh(new THREE.DodecahedronGeometry(1.2, 1), leafMat2);
    crown2.position.set(0.3, 4.8, 0.2);
    crown2.castShadow = true;
    group.add(crown2);

    return group;
  }

  function buildRoadSigns(parent, halfW) {
    const postMat = new THREE.MeshStandardMaterial({ color: 0x8A929E, metalness: 0.8, roughness: 0.3 });

    // Стойка знака на южном въезде
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 3.5, 8), postMat);
    post.position.set(halfW + 0.6, 1.75, halfW + 4.5);
    post.castShadow = true;
    parent.add(post);

    // Знак «Пешеходный переход» (синий квадрат с белым треугольником)
    const signGeo = new THREE.BoxGeometry(0.8, 0.8, 0.04);
    const signMat = new THREE.MeshStandardMaterial({ color: 0x1E88E5, roughness: 0.4 });
    const sign = new THREE.Mesh(signGeo, signMat);
    sign.position.set(halfW + 0.6, 3.4, halfW + 4.5);
    parent.add(sign);

    const triangleGeo = new THREE.ConeGeometry(0.3, 0.55, 3);
    const whiteMat = new THREE.MeshBasicMaterial({ color: 0xFFFFFF });
    const triangle = new THREE.Mesh(triangleGeo, whiteMat);
    triangle.rotation.z = Math.PI;
    triangle.position.set(halfW + 0.6, 3.4, halfW + 4.47);
    parent.add(triangle);
  }

  // Трамвайные пути (аккуратные стальные рельсы с желобом)
  function buildTramTracks(parent) {
    const railMat = new THREE.MeshStandardMaterial({
      color: 0x949AA5,
      metalness: 0.88,
      roughness: 0.22,
    });
    const slabMat = new THREE.MeshStandardMaterial({
      color: 0x3E434D,
      roughness: 0.8,
    });

    // Бетонная плита под трамвайными путями
    const slab = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 140), slabMat);
    slab.rotation.x = -Math.PI / 2;
    slab.position.set(-2.2, 0.024, 0);
    slab.receiveShadow = true;
    parent.add(slab);

    // Две стальные колеи
    const railGeo = new THREE.BoxGeometry(0.1, 0.05, 140);
    [-0.76, 0.76].forEach(offset => {
      const rail = new THREE.Mesh(railGeo, railMat);
      rail.position.set(-2.2 + offset, 0.045, 0);
      rail.receiveShadow = true;
      parent.add(rail);
    });
  }

  // Центральный постамент регулировщика (круглый гранитный островок с диагональной полосатой разметкой)
  function buildCentralPedestal(parent) {
    const islandGeo = new THREE.CylinderGeometry(1.6, 1.7, 0.12, 36);
    const islandMat = new THREE.MeshStandardMaterial({
      color: 0x484E5B,
      roughness: 0.7,
      metalness: 0.1,
    });
    const island = new THREE.Mesh(islandGeo, islandMat);
    island.position.y = 0.06;
    island.receiveShadow = true;
    parent.add(island);

    // Окантовка островка со светоотражающей черно-белой разметкой (разметка 2.7)
    const ringGeo = new THREE.RingGeometry(1.5, 1.68, 36);
    const ringMat = new THREE.MeshBasicMaterial({ color: 0xFDFDFD });
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.122;
    parent.add(ring);
  }

  // --- 3D-модель инспектора ДПС (Регулировщик) ---
  function buildInspector() {
    inspectorGroup = new THREE.Group();
    inspectorGroup.position.set(0, 0.12, 0);

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

    // Очки / солнцезащитный козырек
    const glasses = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.07, 0.06), leatherMat);
    glasses.position.set(0, 2.16, 0.18);
    inspectorGroup.add(glasses);

    // Фуражка ДПС (тулья, околыш, козырек, золотая кокарда)
    const capCrown = new THREE.Mesh(new THREE.CylinderGeometry(0.32, 0.27, 0.15, 20), uniformMat);
    capCrown.position.set(0, 2.34, -0.02);
    capCrown.rotation.x = -0.05;
    inspectorGroup.add(capCrown);

    const capVisor = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.04, 18, 1, false, 0, Math.PI), leatherMat);
    capVisor.rotation.x = 0.25;
    capVisor.position.set(0, 2.27, 0.12);
    inspectorGroup.add(capVisor);

    const cockade = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.02, 10), goldMat);
    cockade.rotation.x = Math.PI / 2;
    cockade.position.set(0, 2.32, 0.26);
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

    return group;
  }

  // Детализированная 3D-модель классического городского трамвая
  function buildRussianTram() {
    const tram = new THREE.Group();

    const redMat = new THREE.MeshStandardMaterial({ color: 0xD32F2F, roughness: 0.4, metalness: 0.2 });
    const creamMat = new THREE.MeshStandardMaterial({ color: 0xF5F0E6, roughness: 0.45 });
    const glassMat = new THREE.MeshStandardMaterial({ color: 0x374A5E, metalness: 0.8, roughness: 0.15 });
    const metalMat = new THREE.MeshStandardMaterial({ color: 0x88929E, metalness: 0.85, roughness: 0.25 });
    const darkMat = new THREE.MeshStandardMaterial({ color: 0x212529, roughness: 0.7 });
    const lightGlowMat = new THREE.MeshBasicMaterial({ color: 0xFFF9E6 });

    // Нижняя красная часть кузова
    const lowerBody = new THREE.Mesh(new THREE.BoxGeometry(2.35, 1.1, 9.4), redMat);
    lowerBody.position.y = 0.95;
    lowerBody.castShadow = true;
    tram.add(lowerBody);

    // Остекление салона с черными стойками
    const cabinGlass = new THREE.Mesh(new THREE.BoxGeometry(2.28, 1.15, 9.2), glassMat);
    cabinGlass.position.y = 2.05;
    tram.add(cabinGlass);

    // Верхняя кремовая часть и скругленная крыша
    const upperBody = new THREE.Mesh(new THREE.BoxGeometry(2.35, 0.25, 9.4), creamMat);
    upperBody.position.y = 2.75;
    tram.add(upperBody);

    const roof = new THREE.Mesh(new THREE.CylinderGeometry(1.17, 1.17, 9.3, 16, 1, false, 0, Math.PI), creamMat);
    roof.rotation.z = Math.PI / 2;
    roof.rotation.y = Math.PI / 2;
    roof.position.set(0, 2.85, 0);
    roof.scale.set(0.3, 1.0, 1.0);
    tram.add(roof);

    // Табло маршрута над лобовым стеклом ("№ 3 Вокзал")
    const routeBoard = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.32, 0.1), darkMat);
    routeBoard.position.set(0, 2.75, 4.71);
    tram.add(routeBoard);

    // Круглые фары трамвая
    [-0.6, 0.6].forEach(x => {
      const lamp = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.14, 0.08, 14), lightGlowMat);
      lamp.rotation.x = Math.PI / 2;
      lamp.position.set(x, 0.75, 4.71);
      tram.add(lamp);
    });

    // Металлический пантограф (токоприёмник) на крыше
    const pantoGroup = new THREE.Group();
    pantoGroup.position.set(0, 3.2, 2.0);

    const baseFrame = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.08, 0.9), metalMat);
    pantoGroup.add(baseFrame);

    // Ромбовидные фермы пантографа
    const diamondArm1 = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 1.1, 8), metalMat);
    diamondArm1.rotation.x = 0.55;
    diamondArm1.position.set(0, 0.5, -0.3);
    pantoGroup.add(diamondArm1);

    const diamondArm2 = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 1.1, 8), metalMat);
    diamondArm2.rotation.x = -0.55;
    diamondArm2.position.set(0, 0.5, 0.3);
    pantoGroup.add(diamondArm2);

    const contactShoe = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.04, 0.15), metalMat);
    contactShoe.position.set(0, 1.0, 0);
    pantoGroup.add(contactShoe);

    tram.add(pantoGroup);

    // Две двухосные тележки с металлическими колесами
    [-2.6, 2.6].forEach(z => {
      const bogie = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.25, 1.6), darkMat);
      bogie.position.set(0, 0.28, z);
      tram.add(bogie);

      [-0.85, 0.85].forEach(x => {
        [-0.55, 0.55].forEach(wz => {
          const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.26, 0.12, 14), metalMat);
          wheel.rotation.z = Math.PI / 2;
          wheel.position.set(x, 0.26, z + wz);
          tram.add(wheel);
        });
      });
    });

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
      arrowsGroup.remove(arrowsGroup.children[0]);
    }

    const allowed = getAllowedMoves(currentGesture, currentApproach, currentVehicle);
    const originX = (currentVehicle === VEHICLES.CAR) ? 3.2 : -2.2;
    const originZ = 8.8;

    // Стрелка прямо
    const canStraight = allowed.includes(MOVES.STRAIGHT);
    addArrowCurve(
      originX, originZ,
      originX, -10,
      canStraight,
      MOVES.STRAIGHT
    );

    // Стрелка направо
    const canRight = allowed.includes(MOVES.RIGHT);
    if (currentVehicle === VEHICLES.CAR || canRight) {
      addArrowCurve(
        originX, originZ,
        originX + 12, originZ - 4,
        canRight,
        MOVES.RIGHT
      );
    }

    // Стрелка налево
    const canLeft = allowed.includes(MOVES.LEFT);
    if (canLeft) {
      addArrowCurve(
        originX, originZ,
        -12, 0,
        canLeft,
        MOVES.LEFT
      );
    }
  }

  function addArrowCurve(startX, startZ, endX, endZ, isAllowed, moveType) {
    if (currentMode === 'arcade' && !isMoving) return;

    const color = isAllowed ? 0x00E676 : 0x555A68;
    const arrowMat = new THREE.MeshBasicMaterial({
      color: color,
      transparent: true,
      opacity: isAllowed ? 0.9 : 0.25,
    });

    const curve = new THREE.QuadraticBezierCurve3(
      new THREE.Vector3(startX, 0.05, startZ),
      new THREE.Vector3((startX + endX) * 0.5, 0.05, (startZ + endZ) * 0.5),
      new THREE.Vector3(endX, 0.05, endZ)
    );

    const points = curve.getPoints(24);
    const geometry = new THREE.BufferGeometry().setFromPoints(points);
    const lineMat = new THREE.LineBasicMaterial({
      color: color,
      linewidth: 3,
      transparent: true,
      opacity: isAllowed ? 0.95 : 0.25,
    });
    const line = new THREE.Line(geometry, lineMat);
    arrowsGroup.add(line);

    // Наконечник стрелки
    const coneGeo = new THREE.ConeGeometry(0.4, 0.9, 12);
    const cone = new THREE.Mesh(coneGeo, arrowMat);
    cone.position.set(endX, 0.06, endZ);
    cone.rotation.x = Math.PI / 2;
    const dir = new THREE.Vector3(endX - startX, 0, endZ - startZ).normalize();
    cone.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);
    arrowsGroup.add(cone);
  }

  // --- Переключение сценария и поз регулировщика ---
  function setScenario(gesture, approach, vehicle) {
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
    if (carMesh) {
      carMesh.position.set(3.2, 0, 13.5);
      carMesh.rotation.y = Math.PI;
    }
    if (tramMesh) {
      tramMesh.position.set(-2.2, 0, 14.5);
      tramMesh.rotation.y = Math.PI;
    }
    isMoving = false;
    moveProgress = 0;
  }

  // --- Запуск анимации движения ТС при ответе игрока ---
  function makeMove(moveType) {
    if (isMoving) return;

    const allowed = getAllowedMoves(currentGesture, currentApproach, currentVehicle);
    const isCorrect = allowed.includes(moveType);

    if (moveType === MOVES.NONE) {
      // Если действие «Стоять»
      notifyFlutter({
        type: 'move_result',
        move: moveType,
        isCorrect: isCorrect,
      });
      return;
    }

    movingObject = (currentVehicle === VEHICLES.CAR) ? carMesh : tramMesh;
    const startX = movingObject.position.x;
    const startZ = movingObject.position.z;

    if (moveType === MOVES.STRAIGHT) {
      moveCurve = new THREE.LineCurve3(
        new THREE.Vector3(startX, 0, startZ),
        new THREE.Vector3(startX, 0, -16)
      );
    } else if (moveType === MOVES.RIGHT) {
      moveCurve = new THREE.QuadraticBezierCurve3(
        new THREE.Vector3(startX, 0, startZ),
        new THREE.Vector3(startX + 1.5, 0, 0.5),
        new THREE.Vector3(18, 0, 0.5)
      );
    } else if (moveType === MOVES.LEFT) {
      moveCurve = new THREE.QuadraticBezierCurve3(
        new THREE.Vector3(startX, 0, startZ),
        new THREE.Vector3(-1.0, 0, 0.5),
        new THREE.Vector3(-18, 0, -0.5)
      );
    } else if (moveType === MOVES.UTURN) {
      moveCurve = new THREE.QuadraticBezierCurve3(
        new THREE.Vector3(startX, 0, startZ),
        new THREE.Vector3(-1.5, 0, 2.0),
        new THREE.Vector3(startX - 2.5, 0, 18)
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
      // Вид из кабины водителя машины
      if (activeVehicleMesh) {
        camera.position.set(
          activeVehicleMesh.position.x,
          1.65,
          activeVehicleMesh.position.z + 0.4
        );
        camera.lookAt(0, 1.45, 0);
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

    // Анимация движения машины/трамвая
    if (isMoving && moveCurve && movingObject) {
      moveProgress += delta * 0.65;
      if (moveProgress >= 1) {
        isMoving = false;
        moveProgress = 1;
        setTimeout(resetVehiclePositions, 300);
      } else {
        const point = moveCurve.getPoint(moveProgress);
        movingObject.position.copy(point);

        const tangent = moveCurve.getTangent(moveProgress);
        movingObject.rotation.y = Math.atan2(-tangent.x, -tangent.z);
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
