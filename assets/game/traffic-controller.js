// 3D-симулятор и игра «Регулировщик 3D» на Three.js
// Реализует сигналы регулировщика по п. 6.10 ПДД РФ для авто и трамваев.

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
      return [MOVES.NONE]; // RIGHT или BACK
    }
    return [MOVES.NONE];
  }

  // --- Three.js сцена ---
  let scene, camera, renderer, container;
  let inspectorGroup, leftArmPivot, rightArmPivot, headMesh, batonMesh;
  let carMesh, tramMesh;
  let arrowsGroup;
  let currentGesture = GESTURES.HANDS_DOWN;
  let currentApproach = APPROACHES.LEFT;
  let currentVehicle = VEHICLES.CAR;
  let currentMode = 'training'; // 'training' | 'arcade'
  let cameraMode = 'overview';   // 'overview' | 'driver'

  // Целевые углы для плавной интерполяции
  const targetInspectorRotY = 0;
  let curInspectorRotY = 0;
  let targetLeftArm = { x: 0, y: 0, z: 0 };
  let targetRightArm = { x: 0, y: 0, z: 0 };
  let curLeftArm = { x: 0, y: 0, z: 0 };
  let curRightArm = { x: 0, y: 0, z: 0 };

  // Анимация движения машины/трамвая
  let isMoving = false;
  let moveProgress = 0;
  let moveCurve = null;
  let movingObject = null;
  let initialObjectPos = new THREE.Vector3();
  let initialObjectRot = 0;

  // Инициализация
  function init() {
    container = document.getElementById('canvas-container');
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x131722);
    scene.fog = new THREE.FogExp2(0x131722, 0.015);

    camera = new THREE.PerspectiveCamera(45, width / height, 0.5, 200);
    updateCameraPosition();

    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    container.appendChild(renderer.domElement);

    setupLighting();
    buildEnvironment();
    buildInspector();
    buildVehicles();
    buildTrajectoryArrows();

    setupTouchControls();
    window.addEventListener('resize', onWindowResize);

    // Первоначальное состояние
    setScenario(GESTURES.RIGHT_ARM_FORWARD, APPROACHES.LEFT, VEHICLES.CAR);

    // Сообщаем Flutter о готовности
    notifyFlutter({ type: 'ready' });

    animate();
  }

  function setupLighting() {
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.65);
    scene.add(ambientLight);

    const dirLight = new THREE.DirectionalLight(0xfff5e6, 0.95);
    dirLight.position.set(25, 45, 20);
    dirLight.castShadow = true;
    dirLight.shadow.mapSize.width = 1024;
    dirLight.shadow.mapSize.height = 1024;
    dirLight.shadow.camera.near = 5;
    dirLight.shadow.camera.far = 100;
    const d = 28;
    dirLight.shadow.camera.left = -d;
    dirLight.shadow.camera.right = d;
    dirLight.shadow.camera.top = d;
    dirLight.shadow.camera.bottom = -d;
    scene.add(dirLight);

    const blueFill = new THREE.DirectionalLight(0x4285F4, 0.35);
    blueFill.position.set(-20, 20, -20);
    scene.add(blueFill);
  }

  // --- Перекрёсток: дороги, разметка, рельсы ---
  function buildEnvironment() {
    const groundGeo = new THREE.PlaneGeometry(160, 160);
    const groundMat = new THREE.MeshLambertMaterial({ color: 0x1A202C });
    const ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    scene.add(ground);

    // Асфальтовый перекресток (крест)
    const roadMat = new THREE.MeshLambertMaterial({ color: 0x222630 });
    const roadWidth = 14;
    const roadLen = 120;

    const roadNS = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth, roadLen), roadMat);
    roadNS.rotation.x = -Math.PI / 2;
    roadNS.position.y = 0.02;
    roadNS.receiveShadow = true;
    scene.add(roadNS);

    const roadEW = new THREE.Mesh(new THREE.PlaneGeometry(roadLen, roadWidth), roadMat);
    roadEW.rotation.x = -Math.PI / 2;
    roadEW.position.y = 0.02;
    roadEW.receiveShadow = true;
    scene.add(roadEW);

    // Центр перекрестка
    const centerMat = new THREE.MeshLambertMaterial({ color: 0x272B36 });
    const centerMesh = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth, roadWidth), centerMat);
    centerMesh.rotation.x = -Math.PI / 2;
    centerMesh.position.y = 0.025;
    centerMesh.receiveShadow = true;
    scene.add(centerMesh);

    // Дорожная разметка (белая)
    const markMat = new THREE.MeshBasicMaterial({ color: 0xEAEAEA });

    // Стоп-линии перед перекрестком на 4 сторонах
    const stopLineGeo = new THREE.PlaneGeometry(6, 0.45);
    const stopOffsets = [
      { x: 3.2, z: 8.5, rot: 0 },         // Юг (наша сторона)
      { x: -3.2, z: -8.5, rot: 0 },       // Север
      { x: 8.5, z: -3.2, rot: Math.PI/2 },// Восток
      { x: -8.5, z: 3.2, rot: Math.PI/2 },// Запад
    ];
    stopOffsets.forEach(pos => {
      const sl = new THREE.Mesh(stopLineGeo, markMat);
      sl.rotation.x = -Math.PI / 2;
      sl.rotation.z = pos.rot;
      sl.position.set(pos.x, 0.035, pos.z);
      scene.add(sl);
    });

    // Зебра пешеходных переходов
    buildCrosswalks(markMat);

    // Трамвайные пути (две рельсы вдоль улицы с Севера на Юг на левой полосе)
    buildTramTracks();

    // Островок регулировщика в центре (небольшой круглый подиум)
    const islandGeo = new THREE.CylinderGeometry(1.4, 1.5, 0.08, 32);
    const islandMat = new THREE.MeshLambertMaterial({ color: 0x393F4D });
    const island = new THREE.Mesh(islandGeo, islandMat);
    island.position.y = 0.04;
    island.receiveShadow = true;
    scene.add(island);

    // Белая круглая окантовка островка
    const ringGeo = new THREE.RingGeometry(1.35, 1.48, 32);
    const ringMat = new THREE.MeshBasicMaterial({ color: 0xFFFFFF });
    const ring = new THREE.Mesh(ringGeo, ringMat);
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.082;
    scene.add(ring);
  }

  function buildCrosswalks(markMat) {
    const stripeGeo = new THREE.PlaneGeometry(0.5, 3.5);
    const stripeCount = 6;
    const stripeDist = 0.95;

    // Зебра на юге
    for (let i = 0; i < stripeCount; i++) {
      const s = new THREE.Mesh(stripeGeo, markMat);
      s.rotation.x = -Math.PI / 2;
      s.position.set(-2.5 + i * stripeDist, 0.032, 10.5);
      scene.add(s);
    }
  }

  function buildTramTracks() {
    const railMat = new THREE.MeshStandardMaterial({
      color: 0x8C92A0,
      metalness: 0.8,
      roughness: 0.3,
    });
    const railGeo = new THREE.BoxGeometry(0.08, 0.04, 120);

    // Левая колея
    const railL = new THREE.Mesh(railGeo, railMat);
    railL.position.set(-2.2 - 0.75, 0.04, 0);
    scene.add(railL);

    // Правая колея
    const railR = new THREE.Mesh(railGeo, railMat);
    railR.position.set(-2.2 + 0.75, 0.04, 0);
    scene.add(railR);
  }

  // --- 3D-модель инспектора ДПС (Регулировщик) ---
  function buildInspector() {
    inspectorGroup = new THREE.Group();
    inspectorGroup.position.set(0, 0.08, 0);

    const uniformMat = new THREE.MeshLambertMaterial({ color: 0x1A2536 }); // Темно-синяя форма
    const vestMat = new THREE.MeshLambertMaterial({ color: 0xC8E800 });    // Салатовый жилет ДПС
    const stripeMat = new THREE.MeshBasicMaterial({ color: 0xEAEAEA });   // Светоотражающая полоса
    const skinMat = new THREE.MeshLambertMaterial({ color: 0xF3C29E });     // Кожа
    const bootMat = new THREE.MeshLambertMaterial({ color: 0x111111 });     // Ботинки

    // Ботинки
    const bootL = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.16, 0.42), bootMat);
    bootL.position.set(-0.2, 0.08, 0.05);
    inspectorGroup.add(bootL);

    const bootR = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.16, 0.42), bootMat);
    bootR.position.set(0.2, 0.08, 0.05);
    inspectorGroup.add(bootR);

    // Ноги / Брюки
    const legL = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.9, 0.24), uniformMat);
    legL.position.set(-0.2, 0.55, 0);
    legL.castShadow = true;
    inspectorGroup.add(legL);

    const legR = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.9, 0.24), uniformMat);
    legR.position.set(0.2, 0.55, 0);
    legR.castShadow = true;
    inspectorGroup.add(legR);

    // Туловище (в жилете)
    const torso = new THREE.Mesh(new THREE.BoxGeometry(0.68, 0.85, 0.38), vestMat);
    torso.position.set(0, 1.4, 0);
    torso.castShadow = true;
    inspectorGroup.add(torso);

    // Светоотражающие полосы на жилете
    const vestStripe1 = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.08, 0.39), stripeMat);
    vestStripe1.position.set(0, 1.3, 0);
    inspectorGroup.add(vestStripe1);

    const vestStripe2 = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.08, 0.39), stripeMat);
    vestStripe2.position.set(0, 1.55, 0);
    inspectorGroup.add(vestStripe2);

    // Голова и шея
    const neck = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.14, 0.15, 12), skinMat);
    neck.position.set(0, 1.88, 0);
    inspectorGroup.add(neck);

    headMesh = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.4, 0.36), skinMat);
    headMesh.position.set(0, 2.12, 0);
    headMesh.castShadow = true;
    inspectorGroup.add(headMesh);

    // Фуражка ДПС
    const capCrown = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.24, 0.16, 16), uniformMat);
    capCrown.position.set(0, 2.36, -0.02);
    inspectorGroup.add(capCrown);

    const capVisor = new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.04, 0.22), bootMat);
    capVisor.position.set(0, 2.3, 0.16);
    capVisor.rotation.x = 0.15;
    inspectorGroup.add(capVisor);

    // Левая рука (плечевой шарнир)
    leftArmPivot = new THREE.Group();
    leftArmPivot.position.set(-0.44, 1.75, 0);

    const leftArmMesh = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.75, 0.18), uniformMat);
    leftArmMesh.position.set(0, -0.35, 0);
    leftArmMesh.castShadow = true;
    leftArmPivot.add(leftArmMesh);

    const handL = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.16, 0.14), skinMat);
    handL.position.set(0, -0.75, 0);
    leftArmPivot.add(handL);

    inspectorGroup.add(leftArmPivot);

    // Правая рука с жезлом (плечевой шарнир)
    rightArmPivot = new THREE.Group();
    rightArmPivot.position.set(0.44, 1.75, 0);

    const rightArmMesh = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.75, 0.18), uniformMat);
    rightArmMesh.position.set(0, -0.35, 0);
    rightArmMesh.castShadow = true;
    rightArmPivot.add(rightArmMesh);

    const handR = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.16, 0.14), skinMat);
    handR.position.set(0, -0.75, 0);
    rightArmPivot.add(handR);

    // Жезл регулировщика (черно-белый)
    batonMesh = buildBaton();
    batonMesh.position.set(0, -0.75, 0.18);
    rightArmPivot.add(batonMesh);

    inspectorGroup.add(rightArmPivot);

    scene.add(inspectorGroup);
  }

  function buildBaton() {
    const batonGroup = new THREE.Group();
    const handleMat = new THREE.MeshBasicMaterial({ color: 0x111111 });
    const whiteMat = new THREE.MeshBasicMaterial({ color: 0xFFFFFF });
    const redTipMat = new THREE.MeshBasicMaterial({ color: 0xFF1744 });

    // Рукоятка
    const handle = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.16, 12), handleMat);
    handle.rotation.x = Math.PI / 2;
    batonGroup.add(handle);

    // Чередующиеся полосы (4 секции)
    for (let i = 0; i < 4; i++) {
      const mat = (i % 2 === 0) ? whiteMat : handleMat;
      const stripe = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.12, 12), mat);
      stripe.position.z = 0.12 + i * 0.11;
      stripe.rotation.x = Math.PI / 2;
      batonGroup.add(stripe);
    }

    // Красный наконечник
    const tip = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.06, 12), redTipMat);
    tip.position.z = 0.58;
    tip.rotation.x = Math.PI / 2;
    batonGroup.add(tip);

    return batonGroup;
  }

  // --- Автомобиль игрока и трамвай ---
  function buildVehicles() {
    // 1. Автомобиль (седан на правой полосе, x = 3.2, z = 13.5)
    carMesh = new THREE.Group();
    carMesh.position.set(3.2, 0, 13.5);

    const carBodyMat = new THREE.MeshLambertMaterial({ color: 0x0574F8 }); // Синий брендовый
    const carGlassMat = new THREE.MeshLambertMaterial({ color: 0x22304A });
    const carWheelMat = new THREE.MeshLambertMaterial({ color: 0x151515 });

    // Кузов
    const base = new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.7, 4.4), carBodyMat);
    base.position.y = 0.55;
    base.castShadow = true;
    carMesh.add(base);

    const cabin = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.65, 2.4), carGlassMat);
    cabin.position.set(0, 1.15, -0.2);
    cabin.castShadow = true;
    carMesh.add(cabin);

    // Фары
    const headlightMat = new THREE.MeshBasicMaterial({ color: 0xFFF3B0 });
    const hlL = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.15, 0.05), headlightMat);
    hlL.position.set(-0.65, 0.6, -2.22);
    carMesh.add(hlL);
    const hlR = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.15, 0.05), headlightMat);
    hlR.position.set(0.65, 0.6, -2.22);
    carMesh.add(hlR);

    // Колеса
    const wheelGeo = new THREE.CylinderGeometry(0.36, 0.36, 0.28, 16);
    [-0.95, 0.95].forEach(x => {
      [-1.3, 1.3].forEach(z => {
        const wheel = new THREE.Mesh(wheelGeo, carWheelMat);
        wheel.rotation.z = Math.PI / 2;
        wheel.position.set(x, 0.36, z);
        wheel.castShadow = true;
        carMesh.add(wheel);
      });
    });

    scene.add(carMesh);

    // 2. Трамвай (на рельсах, x = -2.2, z = 14.5)
    tramMesh = new THREE.Group();
    tramMesh.position.set(-2.2, 0, 14.5);

    const tramBodyMat = new THREE.MeshLambertMaterial({ color: 0xE53935 }); // Красный трамвай
    const tramTopMat = new THREE.MeshLambertMaterial({ color: 0xF5F5F5 });  // Белый верх
    const tramGlassMat = new THREE.MeshLambertMaterial({ color: 0x37474F });

    const tramBody = new THREE.Mesh(new THREE.BoxGeometry(2.4, 1.3, 8.5), tramBodyMat);
    tramBody.position.y = 1.0;
    tramBody.castShadow = true;
    tramMesh.add(tramBody);

    const tramCabin = new THREE.Mesh(new THREE.BoxGeometry(2.35, 1.1, 8.2), tramGlassMat);
    tramCabin.position.y = 2.15;
    tramMesh.add(tramCabin);

    const tramRoof = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.3, 8.4), tramTopMat);
    tramRoof.position.y = 2.8;
    tramMesh.add(tramRoof);

    // Пантограф
    const pantoMat = new THREE.MeshBasicMaterial({ color: 0x90A4AE });
    const panto = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.8, 1.2), pantoMat);
    panto.position.set(0, 3.25, 0);
    tramMesh.add(panto);

    scene.add(tramMesh);

    // Запоминаем исходные координаты
    initialObjectPos.copy(carMesh.position);
  }

  // --- Стрелки траекторий на асфальте ---
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

    // Стрелка направо (только если не запрещено и разрешено)
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
    // В режиме блиц-аркады стрелки показываем только после хода
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
    // Направление
    const dir = new THREE.Vector3(endX - startX, 0, endZ - startZ).normalize();
    cone.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);
    arrowsGroup.add(cone);
  }

  // --- Переключение сценария и поз ---
  function setScenario(gesture, approach, vehicle) {
    currentGesture = gesture;
    currentApproach = approach;
    currentVehicle = vehicle || currentVehicle;

    // Вращение регулировщика в зависимости от ракурса
    // 0 = лицом к югу (front)
    // Math.PI = спиной к югу (back)
    // Math.PI / 2 = левым боком к югу (left)
    // -Math.PI / 2 = правым боком к югу (right)
    switch (approach) {
      case APPROACHES.FRONT:
        curInspectorRotY = 0;
        break;
      case APPROACHES.BACK:
        curInspectorRotY = Math.PI;
        break;
      case APPROACHES.LEFT:
        curInspectorRotY = -Math.PI / 2; // левый бок смотрит на нас (к югу)
        break;
      case APPROACHES.RIGHT:
        curInspectorRotY = Math.PI / 2;  // правый бок смотрит на нас (к югу)
        break;
    }

    if (inspectorGroup) {
      inspectorGroup.rotation.y = curInspectorRotY;
    }

    // Конфигурация рук
    if (gesture === GESTURES.ARM_UP) {
      // Правая рука вертикально вверх
      targetRightArm = { x: 0, y: 0, z: Math.PI - 0.2 };
      targetLeftArm = { x: 0, y: 0, z: 0 };
    } else if (gesture === GESTURES.RIGHT_ARM_FORWARD) {
      // Правая рука вытянута вперед (по направлению груди)
      targetRightArm = { x: -Math.PI / 2, y: 0, z: 0 };
      targetLeftArm = { x: 0, y: 0, z: 0 };
    } else {
      // Руки опущены вдоль тела
      targetRightArm = { x: 0, y: 0, z: 0 };
      targetLeftArm = { x: 0, y: 0, z: 0 };
    }

    // Подсветка активного транспорта (авто или трамвай)
    if (carMesh && tramMesh) {
      carMesh.visible = (currentVehicle === VEHICLES.CAR);
      tramMesh.visible = (currentVehicle === VEHICLES.TRAM);
    }

    resetVehiclePositions();
    updateTrajectoryArrows();

    notifyFlutter({
      type: 'scenario_changed',
      gesture: currentGesture,
      approach: currentApproach,
      vehicle: currentVehicle,
      allowedMoves: getAllowedMoves(currentGesture, currentApproach, currentVehicle),
    });
  }

  function resetVehiclePositions() {
    isMoving = false;
    moveProgress = 0;
    if (carMesh) {
      carMesh.position.set(3.2, 0, 13.5);
      carMesh.rotation.y = 0;
    }
    if (tramMesh) {
      tramMesh.position.set(-2.2, 0, 14.5);
      tramMesh.rotation.y = 0;
    }
  }

  // --- Совершение хода игроком ---
  function makeMove(selectedMove) {
    const allowed = getAllowedMoves(currentGesture, currentApproach, currentVehicle);
    const isCorrect = (selectedMove === MOVES.NONE)
      ? allowed.includes(MOVES.NONE)
      : allowed.includes(selectedMove);

    movingObject = (currentVehicle === VEHICLES.CAR) ? carMesh : tramMesh;
    const startPos = movingObject.position.clone();

    if (isCorrect && selectedMove !== MOVES.NONE) {
      // Создаем траекторию Безье для проезда
      let endPos, controlPos;
      if (selectedMove === MOVES.STRAIGHT) {
        endPos = new THREE.Vector3(startPos.x, 0, -18);
        controlPos = new THREE.Vector3(startPos.x, 0, 0);
      } else if (selectedMove === MOVES.RIGHT) {
        endPos = new THREE.Vector3(startPos.x + 18, 0, 3.2);
        controlPos = new THREE.Vector3(startPos.x, 0, 3.2);
      } else if (selectedMove === MOVES.LEFT) {
        endPos = new THREE.Vector3(-18, 0, -3.2);
        controlPos = new THREE.Vector3(startPos.x, 0, -3.2);
      } else if (selectedMove === MOVES.UTURN) {
        endPos = new THREE.Vector3(-startPos.x, 0, 18);
        controlPos = new THREE.Vector3(0, 0, 0);
      }

      moveCurve = new THREE.QuadraticBezierCurve3(startPos, controlPos, endPos);
      isMoving = true;
      moveProgress = 0;
    } else if (!isCorrect) {
      // Анимация нарушения: тряска и вспышка стоп-сигнала
      triggerViolationEffect();
    }

    updateTrajectoryArrows();

    notifyFlutter({
      type: 'move_result',
      isCorrect: isCorrect,
      selectedMove: selectedMove,
      allowedMoves: allowed,
    });

    return isCorrect;
  }

  function triggerViolationEffect() {
    // Вспышка красного света вокруг регулировщика
    const flashLight = new THREE.PointLight(0xFF1744, 4, 15);
    flashLight.position.set(0, 2, 0);
    scene.add(flashLight);

    let frames = 0;
    const interval = setInterval(() => {
      frames++;
      flashLight.intensity = (frames % 2 === 0) ? 4 : 0;
      if (frames > 6) {
        clearInterval(interval);
        scene.remove(flashLight);
      }
    }, 60);
  }

  function setCameraView(mode) {
    cameraMode = mode;
    updateCameraPosition();
  }

  function updateCameraPosition() {
    if (cameraMode === 'driver') {
      // Ракурс из-за руля
      const posX = (currentVehicle === VEHICLES.CAR) ? 3.2 : -2.2;
      camera.position.set(posX, 1.6, 12.8);
      camera.lookAt(0, 1.4, 0);
    } else {
      // Обзорный ракурс (Isometric Top-45)
      camera.position.set(0, 18.5, 22.0);
      camera.lookAt(0, 1.0, 1.5);
    }
  }

  function setupTouchControls() {
    let isDragging = false;
    let prevX = 0;

    container.addEventListener('pointerdown', e => {
      if (currentMode !== 'training') return;
      isDragging = true;
      prevX = e.clientX;
    });

    window.addEventListener('pointermove', e => {
      if (!isDragging || currentMode !== 'training') return;
      const dx = e.clientX - prevX;
      prevX = e.clientX;
      // Вращение камеры вокруг центра в режиме обучения
      const radius = 28;
      const angle = Math.atan2(camera.position.x, camera.position.z) + dx * 0.008;
      camera.position.x = radius * Math.sin(angle);
      camera.position.z = radius * Math.cos(angle);
      camera.lookAt(0, 1.2, 0);
    });

    window.addEventListener('pointerup', () => {
      isDragging = false;
    });
  }

  function onWindowResize() {
    if (!renderer || !camera || !container) return;
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
  }

  // --- Игровой цикл ---
  function animate() {
    requestAnimationFrame(animate);

    // Плавная интерполяция рук регулировщика
    curLeftArm.x += (targetLeftArm.x - curLeftArm.x) * 0.15;
    curLeftArm.y += (targetLeftArm.y - curLeftArm.y) * 0.15;
    curLeftArm.z += (targetLeftArm.z - curLeftArm.z) * 0.15;
    if (leftArmPivot) {
      leftArmPivot.rotation.set(curLeftArm.x, curLeftArm.y, curLeftArm.z);
    }

    curRightArm.x += (targetRightArm.x - curRightArm.x) * 0.15;
    curRightArm.y += (targetRightArm.y - curRightArm.y) * 0.15;
    curRightArm.z += (targetRightArm.z - curRightArm.z) * 0.15;
    if (rightArmPivot) {
      rightArmPivot.rotation.set(curRightArm.x, curRightArm.y, curRightArm.z);
    }

    // Анимация движения машины при правильном ответе
    if (isMoving && moveCurve && movingObject) {
      moveProgress += 0.02;
      if (moveProgress >= 1) {
        isMoving = false;
        moveProgress = 1;
        // Задержка перед сбросом позиции
        setTimeout(resetVehiclePositions, 350);
      } else {
        const point = moveCurve.getPoint(moveProgress);
        movingObject.position.copy(point);

        // Поворот машины по ходу движения
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

  // Экспорт API для вызова из Flutter через evaluateJavascript
  window.TrafficControllerGame = {
    setScenario,
    makeMove,
    setMode(mode) {
      currentMode = mode;
      updateTrajectoryArrows();
    },
    setCameraView,
    reset() {
      resetVehiclePositions();
      updateTrajectoryArrows();
    },
  };

  window.addEventListener('DOMContentLoaded', init);
})();
