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
  let envGroup, vehiclesGroup, signsGroup, fxGroup, scenarioGroup, locationGroup;
  let curbMatShared = null;
  // Текстуры знаков и табличек 8.13 создаются один раз на всю игру.
  const signTextureCache = new Map(), plateTextureCache = new Map();
  let skyDome, sunLight, ambientLight;
  let cachedRoadMat = null, cachedWalkMat = null, lawnMatShared = null;
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
  // Игрок крутит камеру пальцем (yaw — вокруг перекрёстка, pitch — наклон)
  // и приближает щипком/колёсиком. Сильно отдалить нельзя: за кварталами
  // только фон.
  let camZoom = 1.0, camYaw = 0, camPitch = 0, badgeScale = 1;
  const ZOOM_MIN = 0.8, ZOOM_MAX = 2.4;
  let camShake = 0;
  const audio = window.PDD_AMBIENT ? window.PDD_AMBIENT.create() : null;
  let viewInsetBottom = 0, viewInsetTop = 0;
  const raycaster = new THREE.Raycaster();
  const mouse = new THREE.Vector2();

  // Состояние сценария
  let currentScenario = null;
  let activeActors = new Map(); // id -> { mesh, badge, data, state: 'waiting'|'driving'|'done'|'crashed' }
  let currentStep = 1;
  let isResolving = false;
  let drivingAnimations = []; // массив активных анимаций
  let activeCollision = null; // активная анимация ДТП
  let activeFx = []; // активные частицы и спецэффекты
  let activeSigns = [];

  // Сценарий для самостоятельного открытия страницы (стенд, браузер); в приложении
  // сценарии присылает Flutter (crossroads_priority_model.dart).
  const DEFAULT_SCENARIO = {
    "id": "cross_main_turns_left",
    "title": "Главная дорога поворачивает налево (знак 8.13)",
    "subtitle": "Сначала проезжают машины на главной, между собой — по помехе справа. Затем второстепенные.",
    "pddArticle": "Пункт 13.10 ПДД РФ",
    "isEqual": false,
    "signs": [
      {
        "code": "2.1",
        "side": "south",
        "table8_13": "bottom_left"
      },
      {
        "code": "2.1",
        "side": "west",
        "table8_13": "bottom_right"
      },
      {
        "code": "2.4",
        "side": "north",
        "table8_13": "top_right"
      },
      {
        "code": "2.4",
        "side": "east",
        "table8_13": "left_top"
      }
    ],
    "actors": [
      {
        "id": "car_south",
        "type": "car",
        "name": "Синий хэтчбек",
        "color": "#317ED4",
        "side": "south",
        "maneuver": "left",
        "order": 1,
        "explanation": "Синий на главной дороге. Для белого седана он помеха справа, поэтому проезжает первым.",
        "hasSiren": false,
        "model": "hatch"
      },
      {
        "id": "car_west",
        "type": "car",
        "name": "Белый седан",
        "color": "#F2F3F5",
        "side": "west",
        "maneuver": "straight",
        "order": 2,
        "explanation": "Белый тоже на главной, но справа от него синий хэтчбек. Уступает ему и проезжает вторым.",
        "hasSiren": false,
        "model": "sedan"
      },
      {
        "id": "car_north",
        "type": "car",
        "name": "Оранжевый седан",
        "color": "#F08A24",
        "side": "north",
        "maneuver": "straight",
        "order": 3,
        "explanation": "Оранжевый на второстепенной: пропускает главную. Справа от него никого — едет третьим.",
        "hasSiren": false,
        "model": "sedan"
      },
      {
        "id": "car_east",
        "type": "suv",
        "name": "Зеленый кроссовер",
        "color": "#4D7768",
        "side": "east",
        "maneuver": "straight",
        "order": 4,
        "explanation": "Зеленый на второстепенной, и справа от него оранжевый седан. Проезжает последним.",
        "hasSiren": false,
        "model": "suv"
      }
    ]
  };
  let walkers = [];

  function init() {
    container = document.getElementById('canvas-container');
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(season.sky);

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
    // Без киношной тональной кривой: цвета как в основной игре и «Регулировщике».
    renderer.toneMapping = THREE.NoToneMapping;
    renderer.toneMappingExposure = 1.05;
    container.appendChild(renderer.domElement);

    setupLighting();

    envGroup = new THREE.Group();
    vehiclesGroup = new THREE.Group();
    signsGroup = new THREE.Group();
    scenarioGroup = new THREE.Group();
    fxGroup = new THREE.Group();
    locationGroup = new THREE.Group();

    scene.add(envGroup);
    scene.add(vehiclesGroup);
    scene.add(signsGroup);
    scene.add(scenarioGroup);
    scene.add(fxGroup);
    scene.add(locationGroup);
    window._pddCrossroads = { scene, camera, renderer, envGroup, vehiclesGroup, scenarioGroup, signsGroup, locationGroup, location: () => currentLocation };

    buildEnvironment();

    // Подключаем процедурные шейдерные материалы дорог (асфальт с микропорами)
    if (window.PDD_ROADS) {
      window.PDD_ROADS.attach(renderer, { roots: () => [envGroup], lineage: () => null });
    }

    // Обработчики событий
    window.addEventListener('resize', onWindowResize);
    setupGestures(renderer.domElement);

    // Уведомление Flutter о готовности Three.js
    notifyFlutter({ type: 'ready' });

    // Демонстрационный сценарий по умолчанию при автономном открытии
    setTimeout(() => {
      if (!currentScenario) {
        loadScenario(DEFAULT_SCENARIO);
      }
    }, 120);

    animate();
  }

  function setupLighting() {
    ambientLight = new THREE.AmbientLight(0xFFFFFF, season.ambient);
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

  // Изометрический обзор с юго-востока. Кадр подбирается под сценарий:
  // все участники с метками помещаются в видимую часть экрана над нижней
  // карточкой Flutter (раньше крайние машины обрезались краем экрана).
  const CAMERA_DIR = new THREE.Vector3(44, 38, 31).normalize();
  const CAMERA_BASE = 66;
  let fitDistance = CAMERA_BASE;

  function frameProbe() {
    const points = [new THREE.Vector3(-HALF_ROAD, 0, -HALF_ROAD), new THREE.Vector3(HALF_ROAD, 0, HALF_ROAD)];
    // Полные габариты машины вместе с меткой над ней (трамвай — 14 м).
    const box = new THREE.Box3();
    activeActors.forEach(({ mesh }) => {
      box.setFromObject(mesh);
      for (const x of [box.min.x, box.max.x]) for (const y of [box.min.y, box.max.y]) for (const z of [box.min.z, box.max.z]) points.push(new THREE.Vector3(x, y, z));
    });
    return points;
  }

  const BASE_YAW = Math.atan2(CAMERA_DIR.x, CAMERA_DIR.z), BASE_PITCH = Math.asin(CAMERA_DIR.y);

  function cameraDir() {
    const yaw = BASE_YAW + camYaw, pitch = THREE.MathUtils.clamp(BASE_PITCH + camPitch, 0.5, 1.3);
    return new THREE.Vector3(Math.cos(pitch) * Math.sin(yaw), Math.sin(pitch), Math.cos(pitch) * Math.cos(yaw));
  }

  function placeCamera(distance) {
    const target = new THREE.Vector3(0, 1.2, 0);
    camera.position.copy(target).addScaledVector(cameraDir(), distance);
    badgeScale = THREE.MathUtils.clamp(Math.sqrt(distance / 70), 0.8, 1.25);
    camera.lookAt(target);
    const w = container.clientWidth || window.innerWidth, h = container.clientHeight || window.innerHeight;
    // Центр кадра — посередине свободной области над карточкой.
    camera.setViewOffset(w, h, 0, Math.max(-h * 0.3, Math.min(h * 0.45, ((viewInsetBottom || 0) - (viewInsetTop || 0)) / 2)), w, h);
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld(true);
  }

  function fitCameraToScenario() {
    if (!camera) return;
    const h = container.clientHeight || window.innerHeight;
    const bottom = -1 + 2 * Math.min(0.9, (viewInsetBottom || 0) / h) + 0.06;
    const top = 1 - 2 * Math.min(0.6, (viewInsetTop || 0) / h) - 0.12;
    const points = frameProbe();
    const fits = distance => {
      placeCamera(distance);
      return points.every(p => {
        const v = p.clone().project(camera);
        return Math.abs(v.x) < 0.9 && v.y > bottom && v.y < top;
      });
    };
    const yaw = camYaw, pitch = camPitch, zoom = camZoom;
    camYaw = 0; camPitch = 0;
    let lo = CAMERA_BASE * 0.55, hi = CAMERA_BASE * 2.2;
    if (fits(lo)) hi = lo;
    for (let i = 0; i < 18; i++) {
      const mid = (lo + hi) / 2;
      if (fits(mid)) hi = mid; else lo = mid;
    }
    fitDistance = hi;
    camYaw = yaw; camPitch = pitch; camZoom = zoom;
    updateCameraPosition();
  }

  function updateCameraPosition() {
    if (!camera) return;
    camera.fov = 48;
    placeCamera(fitDistance / camZoom);
    if (camShake > 0) {
      camera.position.x += (Math.random() - 0.5) * camShake * 2.0;
      camera.position.z += (Math.random() - 0.5) * camShake * 2.0;
    }
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
    cachedRoadMat = roadMat;

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


    // 3. Разметка перекрестка
    buildMarkings(envGroup);

    // 4. Тротуары и бордюры
    buildSidewalks(envGroup);

    // 5. Городское окружение: деревья, фонари, фоновые дома
    buildCityDecor(envGroup);
    buildPedestrians(envGroup);
  }

  // Трамвайные пути — только там, где в сценарии идёт трамвай: по оси
  // Север–Юг ('ns') или Восток–Запад ('ew'), по центру проезжей части.
  function buildTramRails(parent, axis) {
    const railMat = new THREE.MeshLambertMaterial({ color: 0x90949C });
    const gauge = 1.524; // ГОСТ колея трамвая в РФ
    const railLength = CITY_REACH * 2;
    [-gauge / 2, gauge / 2].forEach(offset => {
      const geo = axis === 'ns'
        ? new THREE.BoxGeometry(0.08, 0.03, railLength)
        : new THREE.BoxGeometry(railLength, 0.03, 0.08);
      const rail = new THREE.Mesh(geo, railMat);
      if (axis === 'ns') rail.position.set(offset, 0.035, 0);
      else rail.position.set(0, 0.035, offset);
      rail.receiveShadow = true;
      parent.add(rail);
    });
  }

  // Т-образный перекрёсток: на месте закрытой ветки — продолжение квартала:
  // тротуар 6 м вдоль поперечной улицы, дальше газон, как в соседних углах
  // (сплошная серая плита на всю длину выглядела как недостроенная дорога).
  function closeArm(parent, side) {
    const len = CITY_REACH - HALF_ROAD, width = ROAD_WIDTH + 0.4;
    const ns = side === 'north' || side === 'south';
    const sign = side === 'south' || side === 'east' ? 1 : -1;
    const box = (w, d, along, mat, y, h) => {
      const m = new THREE.Mesh(ns ? new THREE.BoxGeometry(w, h, d) : new THREE.BoxGeometry(d, h, w), mat);
      if (ns) m.position.set(0, y, sign * along); else m.position.set(sign * along, y, 0);
      m.receiveShadow = true;
      parent.add(m);
      return m;
    };
    box(width, len, HALF_ROAD + len / 2, cachedWalkMat, 0.08, 0.16);
    const curb = box(ROAD_WIDTH, 0.25, HALF_ROAD + 0.12, curbMatShared, 0.1, 0.2);
    curb.castShadow = true;
    const lawn = new THREE.Mesh(new THREE.PlaneGeometry(ns ? width : len - 6, ns ? len - 6 : width), lawnMatShared);
    lawn.rotation.x = -Math.PI / 2;
    const at = sign * (HALF_ROAD + 6 + (len - 6) / 2);
    if (ns) lawn.position.set(0, 0.168, at); else lawn.position.set(at, 0.168, 0);
    lawn.receiveShadow = true;
    parent.add(lawn);
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
    cachedWalkMat = swMat;
    const curbMat = new THREE.MeshLambertMaterial({ color: 0x8C9098 });
    curbMat.userData.pddKind = 'pavement';
    curbMatShared = curbMat;

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
    // 1. Фонарные столбы по 4 углам перекрестка и вдоль улиц
    if (window.PDD_STREET && window.PDD_STREET.createLampPost) {
      const corners = [[-1, -1], [1, -1], [-1, 1], [1, 1]];
      corners.forEach(([sx, sz]) => {
        const lamp = window.PDD_STREET.createLampPost();
        lamp.position.set(sx * (HALF_ROAD + 1.8), 0.16, sz * (HALF_ROAD + 1.8));
        lamp.rotation.y = Math.atan2(-sz, sx);
        parent.add(lamp);
      });

      // Фонари вдоль улиц
      for (const dist of [24, 48, 72]) {
        [-1, 1].forEach(sx => {
          const l = window.PDD_STREET.createLampPost();
          l.position.set(sx * (HALF_ROAD + 1.8), 0.16, -dist);
          l.rotation.y = sx > 0 ? -Math.PI / 2 : Math.PI / 2;
          parent.add(l);
        });
        [-1, 1].forEach(sz => {
          const l = window.PDD_STREET.createLampPost();
          l.position.set(-dist, 0.16, sz * (HALF_ROAD + 1.8));
          l.rotation.y = sz > 0 ? 0 : Math.PI;
          parent.add(l);
        });
        [-1, 1].forEach(sz => {
          const l = window.PDD_STREET.createLampPost();
          l.position.set(dist, 0.16, sz * (HALF_ROAD + 1.8));
          l.rotation.y = sz > 0 ? 0 : Math.PI;
          parent.add(l);
        });
      }
    }

    // 2. Деревья по тротуарам (двухуровневые пышные кроны с сезонными оттенками + кора)
    const trunkMat = new THREE.MeshLambertMaterial({ color: 0x5D4534 });
    const canopyColors = (season.canopy && season.canopy.length >= 2)
      ? [season.canopy[0], season.canopy[1]]
      : [0xDE9B26, 0xCA5E2A];
    const leafMats = [
      new THREE.MeshLambertMaterial({ color: canopyColors[0] }),
      new THREE.MeshLambertMaterial({ color: canopyColors[1] }),
    ];

    function createStreetTree(x, z, s = 1.0) {
      const tree = new THREE.Group();
      const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.16 * s, 0.25 * s, 2.6 * s, 8), trunkMat);
      trunk.position.y = 1.3 * s;
      trunk.castShadow = true;
      if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
        window.PDD_ROADS.skinObject(trunk, 'bark');
      }
      tree.add(trunk);

      // Нижняя пышная крона
      const crownBig = new THREE.Mesh(new THREE.DodecahedronGeometry(1.65 * s, 1), leafMats[0]);
      crownBig.position.y = 3.2 * s;
      crownBig.castShadow = true;
      if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
        window.PDD_ROADS.skinObject(crownBig, 'leaves');
      }
      tree.add(crownBig);

      // Верхняя крона со вторым оттенком
      const crownTop = new THREE.Mesh(new THREE.DodecahedronGeometry(1.2 * s, 1), leafMats[1]);
      crownTop.position.set(0.28 * s, 4.3 * s, 0.18 * s);
      crownTop.castShadow = true;
      if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
        window.PDD_ROADS.skinObject(crownTop, 'leaves');
      }
      tree.add(crownTop);

      tree.position.set(x, 0.16, z);
      parent.add(tree);
    }

    // Высаживаем деревья вдоль тротуаров
    const treeDists = [16, 28, 42, 56, 70, 84];
    treeDists.forEach((dist, idx) => {
      const scale = 0.95 + (idx % 3) * 0.12;
      // Вдоль северной улицы (видны в перспективе по центру экрана)
      [-1, 1].forEach(sx => createStreetTree(sx * (HALF_ROAD + 3.4), -dist, scale));
      // Вдоль западной улицы
      [-1, 1].forEach(sz => createStreetTree(-dist, sz * (HALF_ROAD + 3.4), scale));
      // Вдоль восточной улицы
      [-1, 1].forEach(sz => createStreetTree(dist, sz * (HALF_ROAD + 3.4), scale));
      // Вдоль южной улицы
      if (dist <= 42) {
        [-1, 1].forEach(sx => createStreetTree(sx * (HALF_ROAD + 3.4), dist, scale));
      }
    });

    // 3. Реалистичные городские здания на заднем плане (красный кирпич, панели, окна, маркизы)
    buildDetailedBuildings(parent);
  }

  // Сливает плоскости (окна) в одну сетку: один вызов отрисовки на дом вместо
  // сотни. Каждая часть уже стоит на месте (matrix применена к геометрии).
  function mergePlaneGeometries(parts) {
    let vertexCount = 0, indexCount = 0;
    parts.forEach(g => { vertexCount += g.attributes.position.count; indexCount += g.index.count; });
    const position = new Float32Array(vertexCount * 3), normal = new Float32Array(vertexCount * 3), uv = new Float32Array(vertexCount * 2);
    const index = new Uint32Array(indexCount);
    let v = 0, i = 0;
    parts.forEach(g => {
      position.set(g.attributes.position.array, v * 3);
      normal.set(g.attributes.normal.array, v * 3);
      uv.set(g.attributes.uv.array, v * 2);
      for (let k = 0; k < g.index.count; k++) index[i + k] = g.index.array[k] + v;
      v += g.attributes.position.count; i += g.index.count;
      g.dispose();
    });
    const merged = new THREE.BufferGeometry();
    merged.setAttribute('position', new THREE.BufferAttribute(position, 3));
    merged.setAttribute('normal', new THREE.BufferAttribute(normal, 3));
    merged.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
    merged.setIndex(new THREE.BufferAttribute(index, 1));
    return merged;
  }

  function buildDetailedBuildings(parent) {
    // Газоны во всех четырёх кварталах: вдоль дорог — тротуар 6 м, дальше
    // трава, как на улицах основной игры (сплошная плитка делала сцену серой).
    const lawnMat = lawnMatShared = new THREE.MeshLambertMaterial({ color: season.ground });
    lawnMat.userData.pddKind = 'grass';
    const lawnSize = CITY_REACH - HALF_ROAD - 6;
    const lawnCentre = HALF_ROAD + 6 + lawnSize / 2;
    [[1, 1], [-1, 1], [1, -1], [-1, -1]].forEach(([sx, sz]) => {
      const lawn = new THREE.Mesh(new THREE.PlaneGeometry(lawnSize, lawnSize), lawnMat);
      lawn.rotation.x = -Math.PI / 2;
      lawn.position.set(sx * lawnCentre, 0.165, sz * lawnCentre);
      lawn.receiveShadow = true;
      parent.add(lawn);
    });

    const roofMat = new THREE.MeshLambertMaterial({ color: season.roof ?? 0x94A3B8 });
    const winMat = new THREE.MeshBasicMaterial({ color: 0x708995 });
    const awningMats = [0xE0533F, 0x2F6F9F, 0x3E8E5E, 0xD9A441].map(
      c => new THREE.MeshLambertMaterial({ color: c })
    );

    const bodyMats = new Map();
    const pitchedRoofMat = new THREE.MeshLambertMaterial({ color: 0x9C4A3A });
    function createHouse(w, h, d, x, y, z, rotY = 0, forcedKind, forcedColor, opts = {}) {
      const group = new THREE.Group();
      group.position.set(x, y, z);
      group.rotation.y = rotY;

      const brickColor = 0xB5675A;
      // Палитра домов основной игры (BRAND.buildingColors и тёплые штукатурки).
      const palette = [0xF5F6FA, 0xE9ECF2, 0xDDE1EA, 0xF3E3C3, 0xE8CFA8, brickColor];
      const color = forcedColor ?? palette[Math.abs(Math.round(x * 3 + z * 5)) % palette.length];
      const kind = forcedKind ?? (color === brickColor ? 'brick' : (Math.abs(Math.round(x + z)) % 3 === 0 ? 'plaster' : 'panel'));

      const matKey = kind + color;
      if (!bodyMats.has(matKey)) bodyMats.set(matKey, new THREE.MeshLambertMaterial({ color }));
      const bodyMat = bodyMats.get(matKey);
      const body = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), bodyMat);
      body.position.y = h / 2;
      body.castShadow = true;
      body.receiveShadow = true;
      if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
        window.PDD_ROADS.skinObject(body, kind);
      }
      group.add(body);

      // Кровля / парапет
      const roof = new THREE.Mesh(new THREE.BoxGeometry(w + 0.4, 0.4, d + 0.4), roofMat);
      roof.position.y = h + 0.2;
      if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
        window.PDD_ROADS.skinObject(roof, 'roofFlat');
      }
      group.add(roof);

      // Окна всех фасадов — одной сеткой.
      const panes = [];
      const pane = (px, py, pz, ry) => {
        const g = new THREE.PlaneGeometry(1.15, 1.35);
        g.applyMatrix4(new THREE.Matrix4().makeRotationY(ry).setPosition(px, py, pz));
        panes.push(g);
      };
      for (let wy = 2.4; wy < h - 1.2; wy += 2.7) {
        for (let wx = -w / 2 + 1.4; wx <= w / 2 - 1.4; wx += 2.1) {
          pane(wx, wy, d / 2 + 0.02, 0);
          pane(wx, wy, -d / 2 - 0.02, Math.PI);
        }
        for (const side of [-1, 1]) {
          for (let wz = -d / 2 + 1.4; wz <= d / 2 - 1.4; wz += 2.1) pane(side * (w / 2 + 0.02), wy, wz, side * Math.PI / 2);
        }
      }
      if (panes.length) {
        const windows = new THREE.Mesh(mergePlaneGeometries(panes), winMat);
        if (window.PDD_ROADS && window.PDD_ROADS.skinObject) window.PDD_ROADS.skinObject(windows, 'window');
        group.add(windows);
      }

      // Магазинный козырек / маркиза на первом этаже
      if (kind !== 'plaster' && !opts.pitched && opts.awning !== false) {
        const awningMat = awningMats[Math.abs(Math.round(x + z)) % awningMats.length];
        const awning = new THREE.Mesh(new THREE.BoxGeometry(Math.min(w - 2, 7.5), 0.08, 1.1), awningMat);
        awning.position.set(0, 2.65, d / 2 + 0.55);
        awning.rotation.x = 0.28;
        group.add(awning);
      }

      if (opts.pitched) {
        // Двускатная крыша частного дома (треугольная призма).
        const half = d / 2 + 0.35, rise = d * 0.32;
        const shape = new THREE.Shape([new THREE.Vector2(-half, 0), new THREE.Vector2(half, 0), new THREE.Vector2(0, rise)]);
        const prism = new THREE.ExtrudeGeometry(shape, { depth: w + 0.5, bevelEnabled: false });
        prism.translate(0, 0, -(w + 0.5) / 2);
        prism.rotateY(Math.PI / 2);
        const ridge = new THREE.Mesh(prism, pitchedRoofMat);
        ridge.position.y = h;
        ridge.castShadow = true;
        group.add(ridge);
        roof.visible = false;
      }
      occupied.push({ x, z, r: Math.hypot(w, d) / 2 + 1.5 });
      houseTarget.add(group);
      return group;
    }
    houseFactory = createHouse;
  }

  // --- Районы: у каждого перекрёстка своя застройка ---
  // Дома — та же фабрика, деревья и дальний фон — по одному InstancedMesh
  // на вид (несколько вызовов отрисовки на всю округу), без теней вдали.
  let currentLocation = null;
  let houseFactory = null, houseTarget = null, occupied = [];
  let lastLocation = -1;
  const LOCATIONS = ['quarter', 'park', 'suburb', 'shops', 'newblocks'];
  const LIGHT = 0xF5F6FA, PALE = 0xE9ECF2, GREY = 0xDDE1EA, SAND = 0xF3E3C3, WARM = 0xE8CFA8, BRICK = 0xB5675A;
  const COTTAGE = [0xF3E3C3, 0xE8CFA8, 0xDCE6D2, 0xF5F6FA, 0xE6D3C2];

  function seededRandom(text) {
    let h = 2166136261;
    for (const ch of String(text)) h = Math.imul(h ^ ch.charCodeAt(0), 16777619);
    return () => {
      h = Math.imul(h ^ (h >>> 15), 2246822507);
      h = Math.imul(h ^ (h >>> 13), 3266489909);
      return ((h ^= h >>> 16) >>> 0) / 4294967296;
    };
  }

  function chooseLocation(scenario) {
    const rnd = seededRandom(scenario.id || scenario.title || 'x');
    let index = Math.floor(rnd() * LOCATIONS.length);
    // Стенд и тесты могут попросить конкретный район.
    const forced = LOCATIONS.indexOf(window.PDD_CROSSROADS_LOCATION);
    if (forced >= 0) { lastLocation = -1; index = forced; }
    else if (index === lastLocation) index = (index + 1) % LOCATIONS.length;
    lastLocation = index;
    return { name: LOCATIONS[index], rnd };
  }

  function buildLocation(scenario) {
    while (locationGroup.children.length) {
      const child = locationGroup.children[0];
      locationGroup.remove(child);
      child.traverse(o => { if (o.geometry && !o.geometry.userData.keep) o.geometry.dispose(); });
    }
    occupied = [];
    houseTarget = locationGroup;
    const { name, rnd } = chooseLocation(scenario);
    const closed = scenario.closedSide;
    const E = HALF_ROAD;
    const house = (w, h, d, x, z, rot, kind, color, opts) => houseFactory(w, h, d, x, 0, z, rot, kind, color, opts);
    const trees = [];
    // Не в домах, не на дорогах и тротуарах (кроме закрытой ветки).
    const free = (x, z, pad = 0) => {
      const onNS = Math.abs(x) < E + 7 && !(closed === 'north' && z < -(E + 7)) && !(closed === 'south' && z > E + 7);
      const onEW = Math.abs(z) < E + 7 && !(closed === 'west' && x < -(E + 7)) && !(closed === 'east' && x > E + 7);
      if (onNS || onEW) return false;
      return occupied.every(o => Math.hypot(o.x - x, o.z - z) > o.r + pad);
    };
    const scatter = (count, minR, maxR, scale = 1) => {
      for (let i = 0, tries = 0; i < count && tries < count * 8; tries++) {
        const r = minR + rnd() * (maxR - minR), a = rnd() * Math.PI * 2;
        const x = Math.cos(a) * r, z = Math.sin(a) * r;
        if (!free(x, z, 1)) continue;
        trees.push({ x, z, s: scale * (0.8 + rnd() * 0.5) });
        i++;
      }
    };

    if (name === 'quarter') {
      house(22, 14, 14, -(E + 16), -(E + 18), 0, 'plaster', SAND);
      house(20, 12, 14, -(E + 40), -(E + 18), 0, 'panel', PALE);
      house(18, 15, 16, -(E + 16), -(E + 42), -Math.PI / 2, 'brick', BRICK);
      house(20, 13, 14, E + 16, -(E + 18), 0, 'panel', GREY);
      house(18, 15, 16, E + 16, -(E + 42), Math.PI / 2, 'plaster', WARM);
      house(20, 12, 14, E + 40, -(E + 18), 0, 'plaster', SAND);
      house(20, 12, 14, -(E + 18), E + 18, Math.PI / 2, 'panel', PALE);
      house(20, 11, 14, -(E + 40), E + 18, 0, 'plaster', WARM);
      scatter(26, 24, 70);
    } else if (name === 'park') {
      // Сквер: аллеи деревьев, пара домов вдали.
      house(22, 12, 14, -(E + 46), -(E + 40), 0, 'plaster', SAND);
      house(20, 13, 14, E + 44, -(E + 46), 0, 'panel', PALE);
      for (const [sx, sz] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {
        for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) {
          const x = sx * (E + 12 + i * 8 + rnd() * 3), z = sz * (E + 12 + j * 8 + rnd() * 3);
          if (free(x, z)) trees.push({ x, z, s: 0.9 + rnd() * 0.45 });
        }
      }
      scatter(30, 40, 80);
    } else if (name === 'suburb') {
      // Частный сектор: одноэтажные дома с двускатными крышами.
      for (const [sx, sz] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {
        for (let i = 0; i < 3; i++) for (let j = 0; j < 2; j++) {
          // Угол со стороны камеры — без домов, чтобы не заслонять машины.
          if (sx > 0 && sz > 0) continue;
          const x = sx * (E + 14 + i * 15), z = sz * (E + 14 + j * 16);
          const w = 8 + rnd() * 3, d = 7.5 + rnd() * 2;
          house(w, 4.2 + rnd() * 1.6, d, x, z, sz > 0 ? Math.PI : 0, 'plaster', COTTAGE[Math.floor(rnd() * COTTAGE.length)], { pitched: true });
        }
      }
      scatter(40, 20, 75);
    } else if (name === 'shops') {
      // Торговая улица: низкие магазины с маркизами у угла, дома за ними.
      for (const [sx, sz] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {
        house(14, 4.8, 10, sx * (E + 13), sz * (E + 12), sz > 0 ? Math.PI : 0, 'brick', [BRICK, SAND, LIGHT, WARM][Math.floor(rnd() * 4)], { awning: true });
        if (!(sx > 0 && sz > 0)) house(20, 15, 14, sx * (E + 22), sz * (E + 36), sz > 0 ? Math.PI : 0, 'panel', [PALE, GREY, LIGHT][Math.floor(rnd() * 3)]);
      }
      scatter(18, 30, 75);
    } else {
      // Новый микрорайон: длинные светлые дома, отступ от дороги, много зелени.
      house(44, 20, 13, -(E + 30), -(E + 34), 0, 'panel', LIGHT);
      house(13, 20, 40, E + 30, -(E + 34), 0, 'panel', PALE);
      house(40, 17, 13, -(E + 30), E + 34, 0, 'panel', GREY);
      house(13, 9, 30, E + 52, E + 44, 0, 'panel', LIGHT);
      scatter(36, 18, 75);
    }
    // Дальний пояс: деревья, чтобы при отдалении не было пустых полей.
    scatter(weak ? 60 : 110, 75, 150, 1.2);
    // Закрытая ветка — аллея.
    if (closed) {
      for (let d = E + 12; d < 72; d += 9) for (const off of [-3.5, 3.5]) {
        const ns = closed === 'north' || closed === 'south', sign = closed === 'south' || closed === 'east' ? 1 : -1;
        trees.push({ x: ns ? off : sign * d, z: ns ? sign * d : off, s: 0.9 + rnd() * 0.3 });
      }
    }
    plantTrees(trees, rnd);
    buildBackdrop(rnd);
    return name;
  }

  let treeGeometry = null;
  function plantTrees(list, rnd) {
    if (!list.length) return;
    if (!treeGeometry) {
      treeGeometry = {
        trunk: new THREE.CylinderGeometry(0.16, 0.25, 2.6, 6).translate(0, 1.3, 0),
        crown: new THREE.DodecahedronGeometry(1.75, 1).translate(0, 3.5, 0),
        trunkMat: new THREE.MeshLambertMaterial({ color: 0x5D4534 }),
        crownMat: new THREE.MeshLambertMaterial({ color: 0xFFFFFF }),
      };
      treeGeometry.trunk.userData.keep = treeGeometry.crown.userData.keep = true;
    }
    const canopy = season.canopy && season.canopy.length ? season.canopy : [0x4F7942, 0x3E6334, 0x6B8E23];
    const trunks = new THREE.InstancedMesh(treeGeometry.trunk, treeGeometry.trunkMat, list.length);
    const crowns = new THREE.InstancedMesh(treeGeometry.crown, treeGeometry.crownMat, list.length);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), color = new THREE.Color();
    list.forEach((t, i) => {
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), rnd() * Math.PI * 2);
      m.compose(new THREE.Vector3(t.x, 0.16, t.z), q, new THREE.Vector3(t.s, t.s * (0.9 + rnd() * 0.3), t.s));
      trunks.setMatrixAt(i, m);
      crowns.setMatrixAt(i, m);
      crowns.setColorAt(i, color.setHex(canopy[i % canopy.length]));
    });
    // Ближние деревья с тенью, дальние — без (тени дорогие).
    trunks.castShadow = crowns.castShadow = !weak;
    for (const mesh of [trunks, crowns]) { mesh.userData.sharedGeometry = true; locationGroup.add(mesh); }
  }

  // Силуэты домов за деревьями по краю: один InstancedMesh из коробок.
  function buildBackdrop(rnd) {
    const count = weak ? 24 : 40;
    const blocks = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0), new THREE.MeshLambertMaterial({ color: 0xFFFFFF }), count);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), color = new THREE.Color();
    const palette = [LIGHT, PALE, GREY, SAND, WARM];
    for (let i = 0; i < count; i++) {
      let a = (i / count) * Math.PI * 2 + rnd() * 0.08;
      const r = 165 + rnd() * 30;
      // Не загораживать концы улиц.
      if (Math.min(Math.abs(Math.cos(a)), Math.abs(Math.sin(a))) * r < HALF_ROAD + 12) a += 0.12;
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), -a);
      m.compose(new THREE.Vector3(Math.cos(a) * r, 0, Math.sin(a) * r), q, new THREE.Vector3(10 + rnd() * 14, 10 + rnd() * 20, 12 + rnd() * 8));
      blocks.setMatrixAt(i, m);
      blocks.setColorAt(i, color.setHex(palette[i % palette.length]));
    }
    locationGroup.add(blocks);
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
  // Освобождает геометрию и собственные текстуры убранного объекта (метки,
  // таблички). Общие текстуры машин и кэш знаков не трогаются.
  function disposeObject(root) {
    const shared = new Set([...signTextureCache.values(), ...plateTextureCache.values()]);
    root.traverse(o => {
      if (o.geometry) o.geometry.dispose();
      [].concat(o.material || []).forEach(m => {
        if (m.map && !shared.has(m.map) && !(m.map.userData && (m.map.userData.pddVehicleShared || m.map.userData.pddRoadShared))) m.map.dispose();
      });
    });
  }

  function clearSigns() {
    activeSigns.forEach(s => { signsGroup.remove(s); disposeObject(s); });
    activeSigns = [];
  }

  function createSignMesh(code, sideName, table8_13, slot = 0) {
    const group = new THREE.Group();

    // Металлическая оцинкованная стойка знака (расположена сзади щита, не пересекая лицевую панель)
    const poleMat = new THREE.MeshLambertMaterial({ color: 0x9FA3A9 });
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.045, 0.045, 3.5, 12), poleMat);
    pole.position.set(0, 1.75, -0.06);
    pole.castShadow = true;
    group.add(pole);

    // Щит знака
    const signTexUrl = (window.PDD_SIGN_TEXTURES && window.PDD_SIGN_TEXTURES[code]);
    let signMat;
    if (signTexUrl) {
      let tex = signTextureCache.get(code);
      if (!tex) {
        tex = new THREE.TextureLoader().load(signTexUrl);
        tex.anisotropy = 4;
        signTextureCache.set(code, tex);
      }
      signMat = new THREE.MeshLambertMaterial({ map: tex, transparent: true, alphaTest: 0.12 });
    } else {
      signMat = new THREE.MeshLambertMaterial({ color: 0xFFCC00 });
    }

    // Лицевая панель знака (крупная, четкая, строго перед стойкой)
    const faceGeo = new THREE.PlaneGeometry(1.65, 1.45);
    const face = new THREE.Mesh(faceGeo, signMat);
    face.position.set(0, 2.85, 0.02);
    group.add(face);

    // Тыльная серая панель знака (строго по контуру знака через альфа-маску, без круглых блинов)
    const backMat = new THREE.MeshLambertMaterial({
      color: 0x7E858E,
      map: signMat.map,
      transparent: true,
      alphaTest: 0.12,
    });
    if (signMat.map) {
      backMat.onBeforeCompile = shader => {
        shader.fragmentShader = shader.fragmentShader.replace(
          '#include <map_fragment>',
          'diffuseColor.a *= texture2D( map, vUv ).a;'
        );
      };
    }
    const back = new THREE.Mesh(faceGeo, backMat);
    back.position.set(0, 2.85, 0.00);
    back.rotation.y = Math.PI;
    group.add(back);

    // Табличка 8.13 «Направление главной дороги» (если указана)
    if (table8_13) {
      let plateTex = plateTextureCache.get(table8_13);
      if (!plateTex) { plateTex = createTable8_13Texture(table8_13); plateTextureCache.set(table8_13, plateTex); }
      const plateMat = new THREE.MeshLambertMaterial({ map: plateTex });
      const plateGeo = new THREE.PlaneGeometry(1.25, 1.25);

      const plate = new THREE.Mesh(plateGeo, plateMat);
      plate.position.set(0, 1.95, 0.02);
      group.add(plate);

      const plateBackMat = new THREE.MeshLambertMaterial({ color: 0x7E858E });
      const plateBack = new THREE.Mesh(plateGeo, plateBackMat);
      plateBack.position.set(0, 1.95, 0.00);
      plateBack.rotation.y = Math.PI;
      group.add(plateBack);
    }

    // Знак стоит справа от своего подъезда перед стоп-линией и смотрит на
    // водителей этого подъезда (как в жизни и в основной игре). Второй знак
    // той же стороны (2.2 перед 2.4, 4.1.1 при 2.1) — на 4.5 м дальше.
    const curbX = HALF_ROAD + 1.2;
    const curbZ = 11.0 + slot * 4.5;
    if (sideName === 'south') {
      group.position.set(curbX, 0, curbZ);
      group.rotation.y = 0;
    } else if (sideName === 'north') {
      group.position.set(-curbX, 0, -curbZ);
      group.rotation.y = Math.PI;
    } else if (sideName === 'east') {
      group.position.set(curbZ, 0, -curbX);
      group.rotation.y = Math.PI / 2;
    } else if (sideName === 'west') {
      group.position.set(-curbZ, 0, curbX);
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

  // Динамическая генерация четкой векторной текстуры для таблички 8.13 по ГОСТ Р 52290
  function createTable8_13Texture(type) {
    const canvas = document.createElement('canvas');
    canvas.width = 256;
    canvas.height = 256;
    const ctx = canvas.getContext('2d');

    // Белый фон с черной каймой
    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, 256, 256);
    ctx.lineWidth = 12;
    ctx.strokeStyle = '#000000';
    ctx.strokeRect(6, 6, 244, 244);

    const c = 128;
    const pad = 24;
    const end = 256 - pad;

    // Тонкие черные линии второстепенных дорог (крест дорог)
    ctx.lineWidth = 10;
    ctx.strokeStyle = '#1A1A1A';
    ctx.beginPath();
    ctx.moveTo(c, pad); ctx.lineTo(c, end);
    ctx.moveTo(pad, c); ctx.lineTo(end, c);
    ctx.stroke();

    // Жирная черная линия главной дороги (поворот по ГОСТ)
    ctx.lineWidth = 36;
    ctx.strokeStyle = '#000000';
    ctx.lineCap = 'square';
    ctx.lineJoin = 'miter';
    ctx.beginPath();

    if (type === 'left' || type === 'bottom_left') {
      // Снизу налево (водитель на главной, поворот налево)
      ctx.moveTo(c, end);
      ctx.lineTo(c, c);
      ctx.lineTo(pad, c);
    } else if (type === 'right' || type === 'bottom_right') {
      // Снизу направо (водитель на главной, поворот направо)
      ctx.moveTo(c, end);
      ctx.lineTo(c, c);
      ctx.lineTo(end, c);
    } else if (type === 'top_right') {
      // Сверху направо (водитель на второстепенной, главная соединяет встречную и правую дороги)
      ctx.moveTo(c, pad);
      ctx.lineTo(c, c);
      ctx.lineTo(end, c);
    } else if (type === 'left_top') {
      // Слева наверх (водитель на второстепенной, главная соединяет левую и встречную дороги)
      ctx.moveTo(pad, c);
      ctx.lineTo(c, c);
      ctx.lineTo(c, pad);
    } else if (type === 'top_left') {
      // Сверху налево
      ctx.moveTo(c, pad);
      ctx.lineTo(c, c);
      ctx.lineTo(pad, c);
    } else if (type === 'right_top') {
      // Справа наверх
      ctx.moveTo(end, c);
      ctx.lineTo(c, c);
      ctx.lineTo(c, pad);
    } else {
      // Прямо
      ctx.moveTo(c, end);
      ctx.lineTo(c, pad);
    }
    ctx.stroke();

    const tex = new THREE.CanvasTexture(canvas);
    tex.anisotropy = 4;
    return tex;
  }

  // --- Создание участников движения (машины, трамвай, грузовик, автобус, мотоцикл, скорая, полиция) ---
  function createVehicleMesh(actorData) {
    let mesh;
    const color = actorData.color || '#317ED4';

    if (actorData.type === 'tram') {
      mesh = buildTramModel(color);
    } else if (actorData.type === 'truck') {
      mesh = buildTruckModel(color);
    } else if (actorData.type === 'bus') {
      mesh = buildBusModel(color);
    } else if (actorData.type === 'motorcycle') {
      mesh = buildMotorcycleModel(color);
    } else if (actorData.type === 'police') {
      mesh = buildPoliceModel();
    } else if (actorData.type === 'emergency') {
      mesh = buildAmbulanceModel();
    } else if (window.PDD_VEHICLES && window.PDD_VEHICLES.create) {
      const model = actorData.model || (actorData.type === 'suv' ? 'suv' : 'sedan');
      mesh = window.PDD_VEHICLES.create(model, color);
      if (actorData.hasSiren) {
        addEmergencyBeacons(mesh);
      }
    } else {
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

  function buildTruckModel(colorHex) {
    const truck = new THREE.Group();
    const c = parseInt(colorHex.replace('#', ''), 16) || 0x317ED4;
    const cabMat = new THREE.MeshLambertMaterial({ color: c });
    const boxMat = new THREE.MeshLambertMaterial({ color: 0xE8ECF0 });
    const darkMat = new THREE.MeshLambertMaterial({ color: 0x242830 });
    const metalMat = new THREE.MeshLambertMaterial({ color: 0x8C929A });
    const glassMat = new THREE.MeshLambertMaterial({ color: 0x2A3B4C, transparent: true, opacity: 0.88 });
    const headMat = new THREE.MeshLambertMaterial({ color: 0xFFF3CC });
    const tailMat = new THREE.MeshLambertMaterial({ color: 0xD33D38 });

    // Рама шасси
    const chassis = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.28, 6.4), darkMat);
    chassis.position.y = 0.58;
    chassis.castShadow = true;
    truck.add(chassis);

    // Кабина
    const cabLower = new THREE.Mesh(new THREE.BoxGeometry(2.1, 1.2, 1.9), cabMat);
    cabLower.position.set(0, 1.15, 2.1);
    cabLower.castShadow = true;
    truck.add(cabLower);

    const cabUpper = new THREE.Mesh(new THREE.BoxGeometry(2.0, 1.1, 1.7), cabMat);
    cabUpper.position.set(0, 2.2, 2.05);
    cabUpper.castShadow = true;
    truck.add(cabUpper);

    // Лобовое стекло
    const windshield = new THREE.Mesh(new THREE.BoxGeometry(1.85, 0.72, 0.08), glassMat);
    windshield.position.set(0, 2.3, 2.92);
    windshield.rotation.x = -0.12;
    truck.add(windshield);

    // Боковые стекла и зеркала
    for (const sx of [-1, 1]) {
      const sideGlass = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.65, 0.9), glassMat);
      sideGlass.position.set(sx * 1.02, 2.3, 2.1);
      truck.add(sideGlass);

      const mirror = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.35, 0.16), darkMat);
      mirror.position.set(sx * 1.16, 2.15, 2.6);
      truck.add(mirror);
    }

    // Решетка и фары
    const grille = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.55, 0.08), darkMat);
    grille.position.set(0, 1.05, 3.06);
    truck.add(grille);

    for (const sx of [-1, 1]) {
      const headlight = new THREE.Mesh(new THREE.BoxGeometry(0.28, 0.16, 0.06), headMat);
      headlight.position.set(sx * 0.82, 0.95, 3.06);
      truck.add(headlight);
    }

    // Кузов-фургон
    const cargoBox = new THREE.Mesh(new THREE.BoxGeometry(2.25, 2.2, 4.4), boxMat);
    cargoBox.position.set(0, 1.88, -0.95);
    cargoBox.castShadow = true;
    truck.add(cargoBox);

    const stripe = new THREE.Mesh(new THREE.BoxGeometry(2.28, 0.14, 4.3), cabMat);
    stripe.position.set(0, 1.88, -0.95);
    truck.add(stripe);

    // Колеса (6 шт)
    const r = 0.46;
    truck.userData.wheels = [];
    truck.userData.frontAxles = [];

    const addWheel = (x, z, isFront) => {
      const axle = new THREE.Group();
      axle.position.set(x, r, z);
      truck.add(axle);

      const tyre = new THREE.Mesh(new THREE.CylinderGeometry(r, r, 0.28, 18), darkMat);
      tyre.rotation.z = Math.PI / 2;
      tyre.castShadow = true;
      axle.add(tyre);

      const rim = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.6, r * 0.6, 0.29, 14), metalMat);
      rim.rotation.z = Math.PI / 2;
      axle.add(rim);

      truck.userData.wheels.push(tyre);
      if (isFront) truck.userData.frontAxles.push(axle);
    };

    addWheel(1.02, 2.1, true);
    addWheel(-1.02, 2.1, true);
    addWheel(1.02, -0.6, false);
    addWheel(-1.02, -0.6, false);
    addWheel(1.02, -1.9, false);
    addWheel(-1.02, -1.9, false);

    for (const sx of [-1, 1]) {
      const tail = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.12, 0.05), tailMat);
      tail.position.set(sx * 0.85, 0.75, -3.17);
      truck.add(tail);
    }

    truck.userData.height = 3.2;
    truck.userData.isTruck = true;
    return truck;
  }

  function buildBusModel(colorHex) {
    const bus = new THREE.Group();
    const c = parseInt(colorHex.replace('#', ''), 16) || 0xF08A24;
    const bodyMat = new THREE.MeshLambertMaterial({ color: c });
    const whiteMat = new THREE.MeshLambertMaterial({ color: 0xF5F6F8 });
    const darkMat = new THREE.MeshLambertMaterial({ color: 0x22262C });
    const metalMat = new THREE.MeshLambertMaterial({ color: 0x8C929A });
    const glassMat = new THREE.MeshLambertMaterial({ color: 0x273545, transparent: true, opacity: 0.88 });
    const headMat = new THREE.MeshLambertMaterial({ color: 0xFFF3CC });
    const tailMat = new THREE.MeshLambertMaterial({ color: 0xD33D38 });

    const lower = new THREE.Mesh(new THREE.BoxGeometry(2.35, 1.25, 9.2), bodyMat);
    lower.position.y = 0.95;
    lower.castShadow = true;
    bus.add(lower);

    const roof = new THREE.Mesh(new THREE.BoxGeometry(2.3, 0.55, 9.1), whiteMat);
    roof.position.y = 2.8;
    roof.castShadow = true;
    bus.add(roof);

    const acUnit = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.28, 2.2), whiteMat);
    acUnit.position.set(0, 3.2, 0.5);
    bus.add(acUnit);

    const sideGlass = new THREE.Mesh(new THREE.BoxGeometry(2.38, 1.1, 8.4), glassMat);
    sideGlass.position.y = 2.05;
    bus.add(sideGlass);

    const windshield = new THREE.Mesh(new THREE.BoxGeometry(2.2, 1.45, 0.08), glassMat);
    windshield.position.set(0, 2.05, 4.62);
    windshield.rotation.x = -0.08;
    bus.add(windshield);

    const routeDisplay = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.28, 0.08), darkMat);
    routeDisplay.position.set(0, 2.85, 4.58);
    bus.add(routeDisplay);

    for (const sx of [-1, 1]) {
      const hl = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.16, 0.06), headMat);
      hl.position.set(sx * 0.88, 0.72, 4.62);
      bus.add(hl);

      const tl = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.16, 0.06), tailMat);
      tl.position.set(sx * 0.88, 0.85, -4.62);
      bus.add(tl);
    }

    const r = 0.48;
    bus.userData.wheels = [];
    bus.userData.frontAxles = [];

    const addWheel = (x, z, isFront) => {
      const axle = new THREE.Group();
      axle.position.set(x, r, z);
      bus.add(axle);

      const tyre = new THREE.Mesh(new THREE.CylinderGeometry(r, r, 0.28, 18), darkMat);
      tyre.rotation.z = Math.PI / 2;
      tyre.castShadow = true;
      axle.add(tyre);

      const rim = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.58, r * 0.58, 0.29, 14), metalMat);
      rim.rotation.z = Math.PI / 2;
      axle.add(rim);

      bus.userData.wheels.push(tyre);
      if (isFront) bus.userData.frontAxles.push(axle);
    };

    addWheel(1.12, 3.1, true);
    addWheel(-1.12, 3.1, true);
    addWheel(1.12, -2.4, false);
    addWheel(-1.12, -2.4, false);
    addWheel(1.12, -3.6, false);
    addWheel(-1.12, -3.6, false);

    bus.userData.height = 3.3;
    bus.userData.isBus = true;
    return bus;
  }

  function buildMotorcycleModel(colorHex) {
    const moto = new THREE.Group();
    const c = parseInt(colorHex.replace('#', ''), 16) || 0xED4621;
    const bodyMat = new THREE.MeshLambertMaterial({ color: c });
    const darkMat = new THREE.MeshLambertMaterial({ color: 0x1E2126 });
    const metalMat = new THREE.MeshLambertMaterial({ color: 0xC8D0D8 });
    const headMat = new THREE.MeshLambertMaterial({ color: 0xFFF3CC });
    const tailMat = new THREE.MeshLambertMaterial({ color: 0xD33D38 });
    const riderSuitMat = new THREE.MeshLambertMaterial({ color: 0x2A303A });

    const engine = new THREE.Mesh(new THREE.BoxGeometry(0.45, 0.42, 0.65), metalMat);
    engine.position.set(0, 0.48, 0.05);
    engine.castShadow = true;
    moto.add(engine);

    const tank = new THREE.Mesh(new THREE.BoxGeometry(0.48, 0.32, 0.65), bodyMat);
    tank.position.set(0, 0.85, 0.25);
    tank.castShadow = true;
    moto.add(tank);

    const seat = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.16, 0.7), darkMat);
    seat.position.set(0, 0.8, -0.32);
    seat.castShadow = true;
    moto.add(seat);

    const tail = new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.18, 0.4), bodyMat);
    tail.position.set(0, 0.88, -0.75);
    tail.rotation.x = -0.2;
    moto.add(tail);

    const tailLight = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.08, 0.04), tailMat);
    tailLight.position.set(0, 0.88, -0.96);
    moto.add(tailLight);

    const forkGroup = new THREE.Group();
    forkGroup.position.set(0, 0.4, 0.85);
    moto.add(forkGroup);

    const forkTubeL = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.85), metalMat);
    forkTubeL.position.set(0.14, 0.3, -0.08);
    forkTubeL.rotation.x = 0.28;
    forkGroup.add(forkTubeL);

    const forkTubeR = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.85), metalMat);
    forkTubeR.position.set(-0.14, 0.3, -0.08);
    forkTubeR.rotation.x = 0.28;
    forkGroup.add(forkTubeR);

    const handlebar = new THREE.Mesh(new THREE.BoxGeometry(0.72, 0.05, 0.05), metalMat);
    handlebar.position.set(0, 0.68, -0.16);
    forkGroup.add(handlebar);

    const headlight = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, 0.08, 16), headMat);
    headlight.rotation.x = Math.PI / 2;
    headlight.position.set(0, 0.55, 0.04);
    forkGroup.add(headlight);

    const r = 0.38;
    moto.userData.wheels = [];
    moto.userData.frontAxles = [forkGroup];

    const fTyre = new THREE.Mesh(new THREE.CylinderGeometry(r, r, 0.12, 18), darkMat);
    fTyre.rotation.z = Math.PI / 2;
    fTyre.castShadow = true;
    forkGroup.add(fTyre);
    moto.userData.wheels.push(fTyre);

    const rAxle = new THREE.Group();
    rAxle.position.set(0, r, -0.75);
    moto.add(rAxle);
    const rTyre = new THREE.Mesh(new THREE.CylinderGeometry(r, r, 0.16, 18), darkMat);
    rTyre.rotation.z = Math.PI / 2;
    rTyre.castShadow = true;
    rAxle.add(rTyre);
    moto.userData.wheels.push(rTyre);

    const riderTorso = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.55, 0.32), riderSuitMat);
    riderTorso.position.set(0, 1.25, -0.15);
    riderTorso.rotation.x = 0.32;
    riderTorso.castShadow = true;
    moto.add(riderTorso);

    const riderHelmet = new THREE.Mesh(new THREE.SphereGeometry(0.19, 14, 14), bodyMat);
    riderHelmet.position.set(0, 1.62, 0.02);
    riderHelmet.castShadow = true;
    moto.add(riderHelmet);

    const visor = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.10, 0.12), darkMat);
    visor.position.set(0, 1.62, 0.14);
    moto.add(visor);

    moto.userData.height = 1.9;
    return moto;
  }

  function buildPoliceModel() {
    let mesh;
    if (window.PDD_VEHICLES && window.PDD_VEHICLES.create) {
      mesh = window.PDD_VEHICLES.create('sedan', '#F2F3F5');
    } else {
      mesh = buildFallbackCar('#F2F3F5');
    }

    for (const sx of [-1, 1]) {
      const stripe = new THREE.Mesh(
        new THREE.BoxGeometry(0.04, 0.18, 2.6),
        new THREE.MeshLambertMaterial({ color: 0x0574F8 })
      );
      stripe.position.set(sx * 0.92, 0.78, 0.0);
      mesh.add(stripe);
    }

    addEmergencyBeacons(mesh);
    return mesh;
  }

  function buildAmbulanceModel() {
    let mesh;
    if (window.PDD_VEHICLES && window.PDD_VEHICLES.create) {
      mesh = window.PDD_VEHICLES.create('suv', '#F2F3F5');
    } else {
      mesh = buildFallbackCar('#F2F3F5');
    }

    for (const sx of [-1, 1]) {
      const redStripe = new THREE.Mesh(
        new THREE.BoxGeometry(0.04, 0.18, 2.4),
        new THREE.MeshLambertMaterial({ color: 0xEF4444 })
      );
      redStripe.position.set(sx * 0.98, 1.05, 0.0);
      mesh.add(redStripe);
    }

    addEmergencyBeacons(mesh);
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
    tram.userData.isTram = true;
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
    if (carMesh.blinkerL) carMesh.userData.blinkerLeft = carMesh.blinkerL;
    if (carMesh.blinkerR) carMesh.userData.blinkerRight = carMesh.blinkerR;
    if (maneuver === 'left' && carMesh.blinkerL) {
      carMesh.blinkerL.visible = true;
      carMesh.userData.activeBlinker = carMesh.blinkerL;
    } else if (maneuver === 'right' && carMesh.blinkerR) {
      carMesh.blinkerR.visible = true;
      carMesh.userData.activeBlinker = carMesh.blinkerR;
    }
  }

  // --- Парящий интерактивный бейдж над машиной ---
  // Метка над машиной — «булавка» в стиле приложения: плоский круг без
  // теней и обводок, внутри стрелка манёвра, хвостик указывает на машину.
  // Нажатие на метку или машину = «эта машина едет».
  const BADGE_STYLE = {
    normal: { fill: '#FFFFFF', ink: '#101828' },
    correct: { fill: '#2BC280', ink: '#FFFFFF' },
    error: { fill: '#ED4621', ink: '#FFFFFF' },
    priority: { fill: '#FFA53C', ink: '#FFFFFF' },
  };

  function drawManeuver(ctx, maneuver, ink) {
    ctx.save();
    ctx.translate(128, 104);
    ctx.strokeStyle = ink; ctx.fillStyle = ink;
    ctx.lineWidth = 17; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const head = (x, y, angle) => {
      ctx.save(); ctx.translate(x, y); ctx.rotate(angle);
      ctx.beginPath(); ctx.moveTo(0, -24); ctx.lineTo(22, 6); ctx.lineTo(-22, 6); ctx.closePath(); ctx.fill();
      ctx.restore();
    };
    ctx.beginPath();
    if (maneuver === 'left' || maneuver === 'right') {
      const k = maneuver === 'left' ? -1 : 1;
      ctx.moveTo(-k * 14, 46); ctx.lineTo(-k * 14, -2); ctx.quadraticCurveTo(-k * 14, -22, k * 6, -22); ctx.lineTo(k * 20, -22);
      ctx.stroke(); head(k * 26, -22, k * Math.PI / 2);
    } else if (maneuver === 'uTurn') {
      ctx.moveTo(22, 46); ctx.lineTo(22, -8); ctx.arc(0, -8, 22, 0, Math.PI, true); ctx.lineTo(-22, 14);
      ctx.stroke(); head(-22, 22, Math.PI);
    } else {
      ctx.moveTo(0, 46); ctx.lineTo(0, -18); ctx.stroke(); head(0, -26, 0);
    }
    ctx.restore();
  }

  function paintBadge(u, status, label) {
    const { ctx } = u, style = BADGE_STYLE[status] || BADGE_STYLE.normal;
    ctx.clearRect(0, 0, 256, 256);
    // Круг и хвостик одной фигурой.
    ctx.beginPath();
    ctx.arc(128, 104, 92, Math.PI * 0.62, Math.PI * 2.38);
    ctx.lineTo(128, 240);
    ctx.closePath();
    ctx.fillStyle = style.fill;
    ctx.fill();
    if (status === 'normal') {
      // Цвет машины — полоской-дугой снизу круга: видно, чья метка.
      ctx.beginPath();
      ctx.arc(128, 104, 92, Math.PI * 0.25, Math.PI * 0.75);
      ctx.lineTo(128, 240);
      ctx.closePath();
      ctx.fillStyle = u.color;
      ctx.fill();
      drawManeuver(ctx, u.maneuver, style.ink);
      if (u.siren) {
        ctx.beginPath(); ctx.arc(196, 40, 22, 0, Math.PI * 2); ctx.fillStyle = '#ED4621'; ctx.fill();
      }
    } else {
      ctx.fillStyle = style.ink;
      ctx.font = '700 96px -apple-system, Roboto, "Segoe UI", sans-serif';
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(label, 128, 110);
    }
    u.tex.needsUpdate = true;
  }

  function createVehicleBadge(actorData) {
    const badgeGroup = new THREE.Group();
    let h = 1.75;
    if (actorData.type === 'tram') h = 3.9;
    else if (actorData.type === 'bus') h = 3.4;
    else if (actorData.type === 'truck') h = 3.3;
    else if (actorData.type === 'motorcycle') h = 1.9;
    h += 0.5;
    badgeGroup.position.set(0, h, 0);

    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = 256;
    const ctx = canvas.getContext('2d');
    const tex = new THREE.CanvasTexture(canvas);
    tex.anisotropy = 4;
    const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthTest: false }));
    sprite.center.set(0.5, 0.06); // кончик хвостика — над крышей
    sprite.scale.set(3.8, 3.8, 1);
    sprite.renderOrder = 10;
    badgeGroup.add(sprite);

    badgeGroup.userData = {
      canvas, ctx, sprite, tex,
      actorId: actorData.id,
      baseY: h,
      order: actorData.order,
      color: actorData.color || '#0574F8',
      maneuver: actorData.maneuver,
      siren: !!actorData.hasSiren,
      status: 'normal',
    };
    paintBadge(badgeGroup.userData, 'normal');
    return badgeGroup;
  }

  function updateBadgeText(badgeGroup, text, status = 'normal') {
    if (!badgeGroup || !badgeGroup.userData) return;
    const u = badgeGroup.userData;
    u.status = status === true ? 'correct' : status;
    u.pop = 0;
    paintBadge(u, u.status, text);
  }

  // Позиционирование машин перед перекрестком
  function placeActorAtStart(actorMesh, sideName) {
    const isTram = !!actorMesh.userData.isTram;
    const isBus = !!actorMesh.userData.isBus;
    const isTruck = !!actorMesh.userData.isTruck;
    let stopDist = 14.8;
    if (isTram) stopDist = 17.0;
    else if (isBus) stopDist = 17.2;
    else if (isTruck) stopDist = 15.8;
    const laneX = isTram ? 0 : LANE_OFFSET;

    if (sideName === 'south') {
      actorMesh.position.set(laneX, 0, stopDist);
      actorMesh.rotation.y = Math.PI; // смотрит на север
    } else if (sideName === 'north') {
      actorMesh.position.set(-laneX, 0, -stopDist);
      actorMesh.rotation.y = 0; // смотрит на юг
    } else if (sideName === 'east') {
      actorMesh.position.set(stopDist, 0, -laneX);
      actorMesh.rotation.y = -Math.PI / 2; // смотрит на запад
    } else if (sideName === 'west') {
      actorMesh.position.set(-stopDist, 0, laneX);
      actorMesh.rotation.y = Math.PI / 2; // смотрит на восток
    }
  }

  // --- Загрузка сценария перекрестка ---
  function loadScenario(scenarioData) {
    currentScenario = scenarioData;
    currentStep = 1;
    isResolving = false;
    drivingAnimations = [];
    activeCollision = null;
    if (activeFx) {
      activeFx.forEach(fx => fx.cleanup && fx.cleanup());
      activeFx = [];
    }
    while (fxGroup.children.length > 0) {
      fxGroup.remove(fxGroup.children[0]);
    }

    // Очищаем предыдущие машины и знаки
    activeActors.forEach(({ mesh }) => { vehiclesGroup.remove(mesh); disposeObject(mesh); });
    activeActors.clear();
    clearSigns();
    // Пути трамвая и закрытая ветка — свои у каждого сценария.
    while (scenarioGroup.children.length) {
      const child = scenarioGroup.children[0];
      scenarioGroup.remove(child);
      child.traverse(o => { if (o.geometry) o.geometry.dispose(); });
    }
    const trams = (scenarioData.actors || []).filter(a => a.type === 'tram');
    if (trams.some(a => a.side === 'north' || a.side === 'south')) buildTramRails(scenarioGroup, 'ns');
    if (trams.some(a => a.side === 'east' || a.side === 'west')) buildTramRails(scenarioGroup, 'ew');
    if (scenarioData.closedSide) closeArm(scenarioGroup, scenarioData.closedSide);
    if (houseFactory) currentLocation = buildLocation(scenarioData);

    // Создаем дорожные знаки
    if (scenarioData.signs && scenarioData.signs.length > 0) {
      const perSide = {};
      scenarioData.signs.forEach(s => {
        const slot = perSide[s.side] = (perSide[s.side] ?? -1) + 1;
        const signMesh = createSignMesh(s.code, s.side, s.table8_13, slot);
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

    // Кадр под этот сценарий
    fitCameraToScenario();
  }

  // --- Жесты: тап — выбрать машину, палец — крутить, щипок — приблизить ---
  function setupGestures(el) {
    el.style.touchAction = 'none';
    const pointers = new Map();
    let tap = null, pinch = null;
    el.addEventListener('pointerdown', e => {
      if (audio) audio.unlock();
      try { el.setPointerCapture(e.pointerId); } catch (_) {}
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pointers.size === 1) tap = { x: e.clientX, y: e.clientY, t: performance.now(), moved: false };
      else { tap = null; pinch = startPinch(); }
    });
    el.addEventListener('pointermove', e => {
      const p = pointers.get(e.pointerId);
      if (!p) return;
      const dx = e.clientX - p.x, dy = e.clientY - p.y;
      p.x = e.clientX; p.y = e.clientY;
      if (pointers.size >= 2 && pinch) {
        const d = pinchDistance();
        if (pinch.d > 0) setZoom(pinch.zoom * d / pinch.d);
        return;
      }
      if (!tap) return;
      if (!tap.moved && Math.hypot(e.clientX - tap.x, e.clientY - tap.y) < 9) return;
      tap.moved = true;
      camYaw -= dx * 0.0065;
      camPitch = THREE.MathUtils.clamp(camPitch + dy * 0.004, 0.5 - BASE_PITCH, 1.3 - BASE_PITCH);
      updateCameraPosition();
    });
    const end = e => {
      if (!pointers.delete(e.pointerId)) return;
      if (pointers.size < 2) pinch = null;
      if (pointers.size === 0 && tap && !tap.moved && performance.now() - tap.t < 700 && e.type === 'pointerup') onTap(e);
      if (pointers.size === 0) tap = null;
    };
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
    el.addEventListener('wheel', e => { e.preventDefault(); setZoom(camZoom * Math.exp(-e.deltaY * 0.0015)); }, { passive: false });
    el.addEventListener('dblclick', () => window.resetCamera());

    function pinchDistance() {
      const [a, b] = [...pointers.values()];
      return Math.hypot(a.x - b.x, a.y - b.y);
    }
    function startPinch() { return { d: pinchDistance(), zoom: camZoom }; }
  }

  function setZoom(zoom) {
    camZoom = THREE.MathUtils.clamp(zoom, ZOOM_MIN, ZOOM_MAX);
    updateCameraPosition();
  }

  // Тап по машине или метке. Если палец чуть промахнулся — берём ближайшую
  // ждущую машину в радиусе ~50 px от точки касания.
  function onTap(event) {
    if (isResolving || !currentScenario) return;
    const rect = renderer.domElement.getBoundingClientRect();
    const clientX = event.clientX - rect.left;
    const clientY = event.clientY - rect.top;

    // Клик по кнопке закрытия в левом верхнем углу (под оверлеем Flutter)
    if (clientX <= 72 && clientY <= 72) {
      notifyFlutter({ type: 'close' });
      return;
    }

    // Клик по кнопке сброса камеры в правом нижнем углу
    if (clientX >= rect.width - 72 && clientY >= rect.height - 72) {
      window.resetCamera();
      return;
    }

    mouse.x = (clientX / rect.width) * 2 - 1;
    mouse.y = -(clientY / rect.height) * 2 + 1;
    raycaster.setFromCamera(mouse, camera);

    const candidates = [];
    activeActors.forEach(({ mesh, badge, state }) => {
      if (state !== 'waiting') return;
      candidates.push(mesh);
      if (badge) candidates.push(badge.userData.sprite);
    });
    let actorId = null;
    const hit = raycaster.intersectObjects(candidates, true)[0];
    for (let o = hit && hit.object; o; o = o.parent) {
      if (o.userData && o.userData.actorId) { actorId = o.userData.actorId; break; }
    }
    if (!actorId) {
      let best = 50;
      const v = new THREE.Vector3();
      activeActors.forEach(({ mesh, badge, state, data }) => {
        if (state !== 'waiting') return;
        const points = [mesh.getWorldPosition(new THREE.Vector3())];
        if (badge) points.push(badge.userData.sprite.getWorldPosition(new THREE.Vector3()).add(new THREE.Vector3(0, 1.8 * badgeScale, 0)));
        points.forEach(p => {
          v.copy(p).project(camera);
          const d = Math.hypot((v.x + 1) / 2 * rect.width - (event.clientX - rect.left), (1 - v.y) / 2 * rect.height - (event.clientY - rect.top));
          if (d < best) { best = d; actorId = data.id; }
        });
      });
    }
    if (!actorId) return;

    notifyFlutter({ type: 'vehicle_tapped', actorId, step: currentStep });
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
      updateBadgeText(chosen.badge, `${currentStep}`, true);
      if (audio) audio.chime(currentStep);

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
    const isTram = data.type === 'tram';

    // Формируем контрольные точки траектории Безье строго от текущей позиции
    const path = generateTrajectory(mesh, side, maneuver, isTram);

    let steerAngle = 0;
    if (maneuver === 'left') steerAngle = -0.42;
    else if (maneuver === 'right') steerAngle = 0.42;

    isResolving = true;
    if (audio) {
      audio.engine(data.type, isTram ? 2.6 : 2.0);
      if (data.hasSiren) audio.siren(2.2);
    }
    drivingAnimations.push({
      mesh,
      path,
      progress: 0,
      speed: isTram ? 0.38 : 0.48,
      wheels: mesh.userData.wheels || [],
      frontAxles: mesh.userData.frontAxles || [],
      steerAngle,
      blinker: mesh.userData.activeBlinker,
      onComplete: () => {
        isResolving = false;
        onComplete && onComplete();
      },
    });
  }

  // Вычисление траектории движения через перекресток
  function generateTrajectory(mesh, side, maneuver, isTram) {
    const pStart = mesh.position.clone();
    const exitD = HALF_ROAD + 32.0;
    const laneX = isTram ? 0 : LANE_OFFSET;

    if (maneuver === 'uTurn') {
      let pEnd, pC1, pC2;
      if (side === 'south') {
        pEnd = new THREE.Vector3(-laneX, 0, exitD);
        pC1 = new THREE.Vector3(laneX, 0, -2.5);
        pC2 = new THREE.Vector3(-laneX, 0, -2.5);
      } else if (side === 'north') {
        pEnd = new THREE.Vector3(laneX, 0, -exitD);
        pC1 = new THREE.Vector3(-laneX, 0, 2.5);
        pC2 = new THREE.Vector3(laneX, 0, 2.5);
      } else if (side === 'east') {
        pEnd = new THREE.Vector3(exitD, 0, laneX);
        pC1 = new THREE.Vector3(-2.5, 0, -laneX);
        pC2 = new THREE.Vector3(-2.5, 0, laneX);
      } else { // west
        pEnd = new THREE.Vector3(-exitD, 0, -laneX);
        pC1 = new THREE.Vector3(2.5, 0, laneX);
        pC2 = new THREE.Vector3(2.5, 0, -laneX);
      }
      return new THREE.CubicBezierCurve3(pStart, pC1, pC2, pEnd);
    }

    let pEnd, pMid;
    if (maneuver === 'straight') {
      if (side === 'south') pEnd = new THREE.Vector3(laneX, 0, -exitD);
      else if (side === 'north') pEnd = new THREE.Vector3(-laneX, 0, exitD);
      else if (side === 'east') pEnd = new THREE.Vector3(-exitD, 0, -laneX);
      else pEnd = new THREE.Vector3(exitD, 0, laneX); // west

      pMid = new THREE.Vector3(
        (pStart.x + pEnd.x) * 0.5,
        0,
        (pStart.z + pEnd.z) * 0.5
      );
    } else if (maneuver === 'right') {
      if (side === 'south') {
        pEnd = new THREE.Vector3(exitD, 0, laneX);
        pMid = new THREE.Vector3(laneX + 2.0, 0, laneX + 2.0);
      } else if (side === 'north') {
        pEnd = new THREE.Vector3(-exitD, 0, -laneX);
        pMid = new THREE.Vector3(-laneX - 2.0, 0, -laneX - 2.0);
      } else if (side === 'east') {
        pEnd = new THREE.Vector3(laneX, 0, -exitD);
        pMid = new THREE.Vector3(laneX + 2.0, 0, -laneX - 2.0);
      } else { // west
        pEnd = new THREE.Vector3(-laneX, 0, exitD);
        pMid = new THREE.Vector3(-laneX - 2.0, 0, laneX + 2.0);
      }
    } else { // left
      if (side === 'south') {
        pEnd = new THREE.Vector3(-exitD, 0, -laneX);
        pMid = new THREE.Vector3(laneX * 0.6, 0, -laneX * 0.6);
      } else if (side === 'north') {
        pEnd = new THREE.Vector3(exitD, 0, laneX);
        pMid = new THREE.Vector3(-laneX * 0.6, 0, laneX * 0.6);
      } else if (side === 'east') {
        pEnd = new THREE.Vector3(-laneX, 0, exitD);
        pMid = new THREE.Vector3(-laneX * 0.6, 0, -laneX * 0.6);
      } else { // west
        pEnd = new THREE.Vector3(laneX, 0, -exitD);
        pMid = new THREE.Vector3(laneX * 0.6, 0, laneX * 0.6);
      }
    }

    return new THREE.QuadraticBezierCurve3(pStart, pMid, pEnd);
  }

  // Геометрическая точка пересечения траекторий участников при ДТП
  function calculateCrashPoint(wrongActor, priorityActor) {
    const pW = wrongActor.mesh.position;
    const pP = priorityActor.mesh.position;
    const sideW = wrongActor.data.side;
    const sideP = priorityActor.data.side;

    const isWNorthSouth = (sideW === 'north' || sideW === 'south');
    const isPNorthSouth = (sideP === 'north' || sideP === 'south');

    if (isWNorthSouth && !isPNorthSouth) {
      return new THREE.Vector3(pW.x, 0, pP.z);
    } else if (!isWNorthSouth && isPNorthSouth) {
      return new THREE.Vector3(pP.x, 0, pW.z);
    } else {
      return new THREE.Vector3(
        (pW.x + pP.x) * 0.5,
        0,
        (pW.z + pP.z) * 0.5
      );
    }
  }

  function getVehicleCollisionExtents(actor) {
    const type = actor && actor.data ? actor.data.type : '';
    if (type === 'tram') return { front: 4.8, side: 1.15, isTram: true };
    if (type === 'bus') return { front: 4.6, side: 1.18, isBus: true };
    if (type === 'truck') return { front: 3.1, side: 1.15, isTruck: true };
    if (type === 'motorcycle') return { front: 1.1, side: 0.45, isMoto: true };
    return { front: 2.25, side: 0.95 }; // car / police / emergency
  }

  // --- Кинематографичная авария (ДТП) при ошибке очередности ---
  function triggerCollision(wrongActor, priorityActor) {
    isResolving = true;
    wrongActor.state = 'crashed';
    priorityActor.state = 'crashed';

    // Точка столкновения (реальная геометрическая точка пересечения курсов)
    const crashPoint = calculateCrashPoint(wrongActor, priorityActor);

    // Начальные координаты участников
    const tStartWrong = wrongActor.mesh.position.clone();
    const tStartPriority = priorityActor.mesh.position.clone();

    // Векторы направлений движения от старта к точке пересечения
    const vW = new THREE.Vector3(crashPoint.x - tStartWrong.x, 0, crashPoint.z - tStartWrong.z);
    const distW = vW.length();
    const dirW = distW > 0.001 ? vW.clone().normalize() : new THREE.Vector3(0, 0, 1);

    const vP = new THREE.Vector3(crashPoint.x - tStartPriority.x, 0, crashPoint.z - tStartPriority.z);
    const distP = vP.length();
    const dirP = distP > 0.001 ? vP.clone().normalize() : new THREE.Vector3(0, 0, 1);

    const extW = getVehicleCollisionExtents(wrongActor);
    const extP = getVehicleCollisionExtents(priorityActor);

    const cosAngle = dirW.dot(dirP);
    let targetWrong, targetPriority, impactPoint;

    if (cosAngle < -0.6) {
      // Встречные курсы (лобовое столкновение):
      // Машины сходятся навстречу друг другу, бамперы встречаются у точки crashPoint
      const crumple = 0.2;
      const stopDistW = Math.max(0.2, extW.front - crumple * 0.5);
      const stopDistP = Math.max(0.2, extP.front - crumple * 0.5);

      targetWrong = crashPoint.clone().sub(dirW.clone().multiplyScalar(stopDistW));
      targetPriority = crashPoint.clone().sub(dirP.clone().multiplyScalar(stopDistP));
      impactPoint = crashPoint.clone().setY(0.6);
    } else if (cosAngle > 0.6) {
      // Попутные курсы (удар сзади):
      const crumple = 0.2;
      const stopDistW = Math.max(0.2, extW.front + extP.front - crumple);
      targetWrong = crashPoint.clone().sub(dirW.clone().multiplyScalar(stopDistW));
      targetPriority = crashPoint.clone();
      impactPoint = targetPriority.clone().sub(dirP.clone().multiplyScalar(extP.front)).setY(0.6);
    } else {
      // Пересекающиеся полосы (боковой T-образный удар на перекрестке):
      // Приоритетная машина выезжает на перекресток первой (ее борт пересекает путь нарушителя).
      // Нарушитель не уступил и передним бампером врезается в борт приоритетного участника.
      // Чтобы длинные трамваи/автобусы/машины НЕ въезжали друг в друга:
      // Передний бампер нарушителя упирается в борт приоритетного ТС (с реалистичной деформацией ~16 см).
      const crumple = 0.16;
      const stopDistW = extW.front + extP.side - crumple;
      targetWrong = crashPoint.clone().sub(dirW.clone().multiplyScalar(stopDistW));

      // Приоритетный участник продвигается вперед через crashPoint так, чтобы удар пришелся в переднюю часть борта:
      const advanceP = Math.min(extP.front * 0.35, 1.6);
      targetPriority = crashPoint.clone().add(dirP.clone().multiplyScalar(advanceP));

      // Точка контакта бампера с бортом:
      impactPoint = targetWrong.clone().add(dirW.clone().multiplyScalar(extW.front)).setY(0.7);
    }

    // Следы экстренного торможения ведут строго до колес точки остановки
    if (!extW.isTram) createSkidMarks(tStartWrong, targetWrong, wrongActor.data.side);
    if (!extP.isTram) createSkidMarks(tStartPriority, targetPriority, priorityActor.data.side);

    activeCollision = {
      wrongActor,
      priorityActor,
      tStartWrong,
      tStartPriority,
      targetWrong,
      targetPriority,
      dirW,
      dirP,
      impactPoint,
      extW,
      extP,
      elapsed: 0,
      duration: 0.85,
      impactHandled: false,
    };
  }

  // Следы протектора торможения на асфальте
  function createSkidMarks(pStart, pCrash, side) {
    const skidMat = new THREE.MeshBasicMaterial({
      color: 0x16181A,
      transparent: true,
      opacity: 0.65,
      depthWrite: false,
    });
    const isNS = (side === 'north' || side === 'south');
    const trackWidth = 0.68;

    for (let sign of [-1, 1]) {
      const p1 = pStart.clone().lerp(pCrash, 0.42);
      const p2 = pCrash.clone();
      if (isNS) {
        p1.x += sign * trackWidth;
        p2.x += sign * trackWidth;
      } else {
        p1.z += sign * trackWidth;
        p2.z += sign * trackWidth;
      }
      p1.y = 0.02;
      p2.y = 0.02;

      const len = p1.distanceTo(p2);
      if (len < 0.4) continue;
      const skidGeo = new THREE.PlaneGeometry(0.22, len);
      const skidMesh = new THREE.Mesh(skidGeo, skidMat);
      skidMesh.rotation.x = -Math.PI / 2;
      skidMesh.position.copy(p1.clone().add(p2).multiplyScalar(0.5));
      const angle = Math.atan2(p2.x - p1.x, p2.z - p1.z);
      skidMesh.rotation.z = angle;
      fxGroup.add(skidMesh);
    }
  }

  // Частицы искр и осколков при ударе
  function createCrashParticles(pos) {
    const count = 45;
    const geo = new THREE.BufferGeometry();
    const positions = new Float32Array(count * 3);
    const velocities = [];

    for (let i = 0; i < count; i++) {
      positions[i * 3] = pos.x;
      positions[i * 3 + 1] = pos.y + 0.6;
      positions[i * 3 + 2] = pos.z;

      velocities.push(new THREE.Vector3(
        (Math.random() - 0.5) * 9.0,
        Math.random() * 7.0 + 2.5,
        (Math.random() - 0.5) * 9.0
      ));
    }

    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const mat = new THREE.PointsMaterial({
      color: 0xFFB300,
      size: 0.4,
      transparent: true,
      opacity: 0.95
    });

    const particles = new THREE.Points(geo, mat);
    fxGroup.add(particles);

    let life = 0.75;
    activeFx.push({
      cleanup: () => fxGroup.remove(particles),
      update: (dt) => {
        life -= dt;
        const posArr = particles.geometry.attributes.position.array;
        for (let i = 0; i < count; i++) {
          posArr[i * 3] += velocities[i].x * dt;
          posArr[i * 3 + 1] += velocities[i].y * dt;
          posArr[i * 3 + 2] += velocities[i].z * dt;
          velocities[i].y -= 11.5 * dt; // гравитация
        }
        particles.geometry.attributes.position.needsUpdate = true;
        mat.opacity = Math.max(0, life / 0.75);

        if (life <= 0) {
          fxGroup.remove(particles);
          return false;
        }
        return true;
      }
    });
  }

  // Клубы дыма при аварии
  function createCrashSmoke(pos) {
    const smokeGroup = new THREE.Group();
    const smokeMat = new THREE.MeshBasicMaterial({
      color: 0xCCCCCC,
      transparent: true,
      opacity: 0.55,
      depthWrite: false,
    });
    const puffs = [];

    for (let i = 0; i < 6; i++) {
      const puff = new THREE.Mesh(new THREE.SphereGeometry(0.35 + Math.random() * 0.25, 8, 6), smokeMat.clone());
      puff.position.set(
        pos.x + (Math.random() - 0.5) * 0.8,
        pos.y + 0.4 + Math.random() * 0.3,
        pos.z + (Math.random() - 0.5) * 0.8
      );
      smokeGroup.add(puff);
      puffs.push({
        mesh: puff,
        vx: (Math.random() - 0.5) * 0.8,
        vy: 1.2 + Math.random() * 0.8,
        vz: (Math.random() - 0.5) * 0.8,
      });
    }

    fxGroup.add(smokeGroup);
    let smokeLife = 1.2;

    activeFx.push({
      cleanup: () => fxGroup.remove(smokeGroup),
      update: (dt) => {
        smokeLife -= dt;
        puffs.forEach(p => {
          p.mesh.position.x += p.vx * dt;
          p.mesh.position.y += p.vy * dt;
          p.mesh.position.z += p.vz * dt;
          p.mesh.scale.multiplyScalar(1.0 + dt * 1.2);
          p.mesh.material.opacity = Math.max(0, (smokeLife / 1.2) * 0.55);
        });

        if (smokeLife <= 0) {
          fxGroup.remove(smokeGroup);
          return false;
        }
        return true;
      }
    });
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
    activeActors.forEach(({ badge, state }) => {
      if (!badge) return;
      const u = badge.userData;
      badge.position.y = u.baseY + Math.sin(time * 2.6 + u.order) * 0.1;
      let k = state === 'waiting' && !isResolving ? 1 + Math.sin(time * 4 + u.order) * 0.035 : 1;
      if (u.pop !== undefined && u.pop < 1) { u.pop = Math.min(1, u.pop + dt * 4); k *= 1 + Math.sin(u.pop * Math.PI) * 0.25; }
      const size = 3.8 * k * badgeScale;
      u.sprite.scale.set(size, size, 1);
    });

    // Мигание спецмаячков и поворотников
    const blinkCycle = Math.floor(time * 4) % 2 === 0;
    const hazardCycle = Math.floor(time * 6) % 2 === 0;
    activeActors.forEach(({ mesh }) => {
      if (mesh.userData.beacons) {
        mesh.userData.beacons[0].visible = blinkCycle;
        mesh.userData.beacons[1].visible = !blinkCycle;
      }
      if (mesh.userData.hazardLights) {
        if (mesh.userData.blinkerLeft) mesh.userData.blinkerLeft.visible = hazardCycle;
        if (mesh.userData.blinkerRight) mesh.userData.blinkerRight.visible = hazardCycle;
      } else if (mesh.userData.activeBlinker) {
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
        // Плавный разгон и замедление
        const t = THREE.MathUtils.smootherstep(anim.progress, 0, 1);
        const point = anim.path.getPoint(t);
        anim.mesh.position.copy(point);

        // Вращение колес
        anim.wheels.forEach(w => {
          w.rotation.x += dt * 14.0;
        });

        // Направление кузова строго по касательной траектории Безье
        const tangent = anim.path.getTangent(Math.min(0.999, t));
        if (tangent.lengthSq() > 0.0001) {
          anim.mesh.rotation.y = Math.atan2(tangent.x, tangent.z);
        }

        // Поворот передних колес по углу поворота
        if (anim.frontAxles && anim.frontAxles.length > 0) {
          const steer = anim.steerAngle * Math.sin(t * Math.PI);
          anim.frontAxles.forEach(a => { a.rotation.y = steer; });
        }

        // Выключение поворотника после завершения маневра
        if (anim.blinker && t > 0.72) {
          anim.blinker.visible = false;
          anim.blinker = null;
        }
      }
    }

    // Обновление активной анимации ДТП
    if (activeCollision) {
      const c = activeCollision;
      c.elapsed += dt;
      const progress = Math.min(1.0, c.elapsed / c.duration);
      const ease = 1 - Math.pow(1 - progress, 2);

      c.wrongActor.mesh.position.lerpVectors(c.tStartWrong, c.targetWrong, ease);
      c.priorityActor.mesh.position.lerpVectors(c.tStartPriority, c.targetPriority, ease);

      const wheelsWrong = c.wrongActor.mesh.userData.wheels || [];
      const wheelsPriority = c.priorityActor.mesh.userData.wheels || [];
      wheelsWrong.forEach(w => { w.rotation.x += dt * 16.0; });
      wheelsPriority.forEach(w => { w.rotation.x += dt * 16.0; });

      if (progress >= 1.0 && !c.impactHandled) {
        c.impactHandled = true;
        camShake = 0.55;
        if (audio) audio.crash();
        createCrashParticles(c.impactPoint);
        createCrashSmoke(c.impactPoint);

        // Реалистичный отскок от удара назад по вектору своего движения
        const recoilW = c.extW.isTram ? 0.08 : 0.22;
        const recoilP = c.extP.isTram ? 0.06 : 0.16;
        c.wrongActor.mesh.position.sub(c.dirW.clone().multiplyScalar(recoilW));
        c.priorityActor.mesh.position.sub(c.dirP.clone().multiplyScalar(recoilP));

        // Небольшой крен/толчок кузова от удара (минимальный для трамвая, чтобы не перекашивать длинный корпус)
        const tiltW = c.extW.isTram ? 0.012 : 0.035;
        const tiltP = c.extP.isTram ? 0.010 : 0.030;

        c.wrongActor.mesh.rotation.z += (c.dirW.x !== 0 ? -c.dirW.x : 1) * tiltW;
        c.wrongActor.mesh.rotation.x += (c.dirW.z !== 0 ? c.dirW.z : 1) * tiltW * 0.5;

        c.priorityActor.mesh.rotation.z += (c.dirP.x !== 0 ? c.dirP.x : -1) * tiltP;
        c.priorityActor.mesh.rotation.x += (c.dirP.z !== 0 ? -c.dirP.z : 1) * tiltP * 0.5;

        c.wrongActor.mesh.userData.hazardLights = true;
        c.priorityActor.mesh.userData.hazardLights = true;

        updateBadgeText(c.wrongActor.badge, '✗', 'error');
        updateBadgeText(c.priorityActor.badge, '!', 'priority');

        notifyFlutter({
          type: 'collision',
          chosenId: c.wrongActor.data.id,
          priorityId: c.priorityActor.data.id,
          reason: c.priorityActor.data.explanation || c.priorityActor.data.ruleExplanation ||
            c.wrongActor.data.explanation || c.wrongActor.data.ruleExplanation || '',
          pddArticle: currentScenario.pddArticle,
        });

        activeCollision = null;
      }
    }

    // Обновление активных частиц и спецэффектов
    for (let i = activeFx.length - 1; i >= 0; i--) {
      if (!activeFx[i].update(dt)) {
        activeFx.splice(i, 1);
      }
    }

    // Обновление погодных эффектов

    renderer.render(scene, camera);
  }

  function onWindowResize() {
    if (!renderer || !camera || !container) return;
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;
    camera.aspect = width / height;
    renderer.setSize(width, height);
    fitCameraToScenario();
  }

  // --- API для Flutter моста ---
  window.getCamera = () => camera;
  window.setZoom = setZoom;
  window.resetCamera = () => {
    camYaw = 0; camPitch = 0; camZoom = 1;
    updateCameraPosition();
  };
  // Настройка «Звук» приложения.
  window.setSoundEnabled = on => { if (audio) audio.setEnabled(on); };

  // Flutter присылает высоту нижней панели в физических пикселях,
  // кадр считается в CSS-пикселях страницы.
  window.setViewInset = (bottomPixels, topPixels = 0) => {
    viewInsetBottom = bottomPixels / (window.devicePixelRatio || 1);
    viewInsetTop = topPixels / (window.devicePixelRatio || 1);
    fitCameraToScenario();
  };

  // Погоды в этой игре нет (всегда ясно); вызовы остаются безопасными.
  window.setWeather = () => {};
  window.getWeather = () => ({ current: 'clear', rain: 0, fog: 0 });
  window.randomizeWeather = () => {};

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

  window.selectVehicle = actorId => {
    if (isResolving || !currentScenario) return;
    handleVehicleChoice(actorId);
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
