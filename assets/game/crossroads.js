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
  let skyDome, sunLight, ambientLight;
  let cachedRoadMat = null, cachedWalkMat = null;
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
  let activeCollision = null; // активная анимация ДТП
  let activeFx = []; // активные частицы и спецэффекты
  let activeSigns = [];

  // --- Погодная система (процедурная симуляция: ясно, дождь, туман) ---
  const WEATHERS = ['clear', 'rain', 'fog'];
  let currentTargetWeather = 'clear';
  let curRain = 0, curFog = 0, curOvercast = 0;
  let weatherAutoTimer = 45 + Math.random() * 30;
  let weatherFx = null;

  function pickNextWeather() {
    const pool = WEATHERS.filter(w => w !== currentTargetWeather);
    return pool[Math.floor(Math.random() * pool.length)];
  }

  function setWeather(kind, immediate) {
    if (!WEATHERS.includes(kind)) return;
    currentTargetWeather = kind;
    if (immediate) {
      curRain = kind === 'rain' ? 1 : 0;
      curFog = kind === 'fog' ? 1 : 0;
      curOvercast = kind === 'clear' ? 0 : (kind === 'rain' ? 1 : 0.85);
      applyWeather(0);
    }
    notifyFlutter({ type: 'weather_changed', weather: currentTargetWeather });
  }

  function ensureWeatherFx() {
    if (weatherFx) return weatherFx;

    const isWeak = !!weak;
    const dropCount = isWeak ? 1000 : 2100;
    const dropPositions = new Float32Array(dropCount * 2 * 3);
    const drops = [];

    const nearCount = Math.floor(dropCount * 0.22);
    const midCount = Math.floor(dropCount * 0.42);
    const farCount = dropCount - nearCount - midCount;

    // 1. Ближний план: капли перед камерой с параллаксом
    for (let i = 0; i < nearCount; i++) {
      drops.push({
        x: (Math.random() - 0.5) * 26,
        y: Math.random() * 26,
        z: 4 + Math.random() * 24,
        speed: 15.0 + Math.random() * 3.5,
        len: 1.2 + Math.random() * 0.6,
        layer: 'near',
      });
    }

    // 2. Средний план: капли над перекрёстком и автомобилями
    for (let i = 0; i < midCount; i++) {
      drops.push({
        x: (Math.random() - 0.5) * 52,
        y: Math.random() * 28,
        z: (Math.random() - 0.5) * 44,
        speed: 14.0 + Math.random() * 3.0,
        len: 0.75 + Math.random() * 0.35,
        layer: 'mid',
      });
    }

    // 3. Дальний план: мягкая плотная сетка дождя на фоне зданий
    for (let i = 0; i < farCount; i++) {
      drops.push({
        x: (Math.random() - 0.5) * 88,
        y: Math.random() * 30,
        z: -12 - Math.random() * 45,
        speed: 12.8 + Math.random() * 2.8,
        len: 0.45 + Math.random() * 0.25,
        layer: 'far',
      });
    }

    const rainGeo = new THREE.BufferGeometry();
    rainGeo.setAttribute('position', new THREE.BufferAttribute(dropPositions, 3));
    const rainMat = new THREE.LineBasicMaterial({
      color: 0xB2C6D8,
      transparent: true,
      opacity: 0,
    });
    const rainLines = new THREE.LineSegments(rainGeo, rainMat);
    rainLines.frustumCulled = false;
    scene.add(rainLines);

    weatherFx = {
      rainLines,
      drops,
      dropCount,
      headlights: [],
    };
    return weatherFx;
  }

  function attachCarHeadlights(carMesh) {
    if (!carMesh) return;
    ensureWeatherFx();
    if (carMesh.userData.headlightsAttached) return;
    carMesh.userData.headlightsAttached = true;

    // 1. Светящиеся линзы фар на переднем бампере
    const lensMat = new THREE.MeshBasicMaterial({ color: 0xFFFEE8, transparent: true, opacity: 0 });
    const lensL = new THREE.Mesh(new THREE.BoxGeometry(0.30, 0.12, 0.04), lensMat);
    lensL.position.set(0.55, 0.65, 2.15);
    carMesh.add(lensL);

    const lensR = new THREE.Mesh(new THREE.BoxGeometry(0.30, 0.12, 0.04), lensMat);
    lensR.position.set(-0.55, 0.65, 2.15);
    carMesh.add(lensR);

    // 2. Мягкий рассеянный свет фар
    const spot = new THREE.SpotLight(0xFFF5DD, 0, 30, Math.PI / 4.0, 0.95, 1.2);
    spot.position.set(0, 0.70, 2.10);
    const spotTarget = new THREE.Object3D();
    spotTarget.position.set(0, 0, 16.0);
    spot.target = spotTarget;
    carMesh.add(spot);
    carMesh.add(spotTarget);

    weatherFx.headlights.push({ car: carMesh, lensMat, spot });
  }

  function applyWeather(dt) {
    if (!weatherFx) return;

    const targetRain = currentTargetWeather === 'rain' ? 1 : 0;
    const targetFog = currentTargetWeather === 'fog' ? 1 : 0;
    const targetOvercast = currentTargetWeather === 'clear' ? 0 : (currentTargetWeather === 'rain' ? 1 : 0.85);

    const k = Math.min(1, dt * 0.22);
    curRain += (targetRain - curRain) * k;
    curFog += (targetFog - curFog) * k;
    curOvercast += (targetOvercast - curOvercast) * k;

    // 1. Цвет неба и атмосфера
    const clearSky = new THREE.Color(season.sky);
    const rainSky = new THREE.Color(0x8E9CA8);
    const fogSky = new THREE.Color(0xC2CCD5);

    scene.background.copy(clearSky).lerp(rainSky, curRain).lerp(fogSky, curFog);

    if (skyDome && skyDome.material && skyDome.material.uniforms) {
      skyDome.material.uniforms.horizon.value.copy(scene.background);
      skyDome.material.uniforms.zenith.value.copy(scene.background).lerp(new THREE.Color(0x76A3D4), 0.45 * (1 - curOvercast));
      const cloudVisibility = Math.max(0, 1.0 - curRain * 1.6 - curFog * 1.6);
      skyDome.material.uniforms.cloud.value = 0.45 * cloudVisibility;
    }

    if (scene.fog) {
      scene.fog.color.copy(scene.background);
      const targetNear = THREE.MathUtils.lerp(120, THREE.MathUtils.lerp(45, 26, curFog), Math.max(curRain, curFog));
      const targetFar = THREE.MathUtils.lerp(330, THREE.MathUtils.lerp(180, 110, curFog), Math.max(curRain, curFog));
      scene.fog.near = targetNear;
      scene.fog.far = targetFar;
    }

    // 2. Освещение
    if (ambientLight) {
      ambientLight.intensity = THREE.MathUtils.lerp(season.ambient, 0.62, curRain * 0.85 + curFog * 0.45);
    }
    if (sunLight) {
      const sunInt = THREE.MathUtils.lerp(season.sunIntensity, THREE.MathUtils.lerp(0.20, 0.08, curFog), Math.max(curRain, curFog));
      sunLight.intensity = sunInt;
      sunLight.color.setHex(season.sun).lerp(new THREE.Color(0xCCD8E4), Math.max(curRain, curFog));
    }

    // 3. Потемнение мокрого асфальта и тротуаров
    if (cachedRoadMat) {
      const dryAsphalt = new THREE.Color(BRAND.asphalt);
      const wetAsphalt = new THREE.Color(0x181A20);
      cachedRoadMat.color.copy(dryAsphalt).lerp(wetAsphalt, curRain * 0.90 + curFog * 0.25);
    }
    if (cachedWalkMat) {
      const dryWalk = new THREE.Color(season.sidewalk);
      const wetWalk = new THREE.Color(season.sidewalk).multiplyScalar(0.72);
      cachedWalkMat.color.copy(dryWalk).lerp(wetWalk, curRain * 0.35 + curFog * 0.15);
    }

    // 4. Дождь
    if (curRain > 0.01) {
      weatherFx.rainLines.visible = true;
      weatherFx.rainLines.material.opacity = curRain * 0.62;
      const pos = weatherFx.rainLines.geometry.attributes.position.array;
      let ptr = 0;
      const windX = 1.1;
      const windZ = -1.5;
      weatherFx.drops.forEach(d => {
        d.y -= d.speed * dt;
        d.x += windX * dt;
        d.z += windZ * dt;
        if (d.y < 0) {
          d.y = 22 + Math.random() * 4;
          if (d.layer === 'near') {
            d.x = (Math.random() - 0.5) * 26;
            d.z = 4 + Math.random() * 24;
          } else if (d.layer === 'mid') {
            d.x = (Math.random() - 0.5) * 52;
            d.z = (Math.random() - 0.5) * 44;
          } else {
            d.x = (Math.random() - 0.5) * 88;
            d.z = -12 - Math.random() * 45;
          }
        }
        pos[ptr++] = d.x;
        pos[ptr++] = d.y;
        pos[ptr++] = d.z;
        pos[ptr++] = d.x - 0.06 * d.len;
        pos[ptr++] = d.y - 1.15 * d.len;
        pos[ptr++] = d.z + 0.08 * d.len;
      });
      weatherFx.rainLines.geometry.attributes.position.needsUpdate = true;
    } else {
      weatherFx.rainLines.visible = false;
    }

    // 5. Фары автомобилей
    const targetHeadlight = Math.max(curRain * 0.85, curFog * 0.95);
    weatherFx.headlights = weatherFx.headlights.filter(h => h.car.parent);
    weatherFx.headlights.forEach(h => {
      h.lensMat.opacity = targetHeadlight;
      h.spot.intensity = targetHeadlight * 3.6;
    });
  }

  function updateWeather(dt) {
    if (!weatherFx) return;

    weatherAutoTimer -= dt;
    if (weatherAutoTimer <= 0) {
      weatherAutoTimer = 55 + Math.random() * 30;
      setWeather(pickNextWeather());
    }

    applyWeather(dt);
  }

  const DEFAULT_SCENARIO = {
    id: 'cross_main_turns_left',
    title: 'Главная дорога поворачивает налево (знак 8.13)',
    subtitle: 'Водители на главной разъезжаются по помехе справа.',
    pddArticle: 'Пункт 13.10 ПДД РФ',
    isEqual: false,
    signs: [
      { code: '2.1', side: 'south', table8_13: 'left' },
      { code: '2.1', side: 'west', table8_13: 'right' },
      { code: '2.4', side: 'north', table8_13: 'left' },
      { code: '2.4', side: 'east', table8_13: 'left' }
    ],
    actors: [
      {
        id: 'car_west',
        type: 'car',
        name: 'Белый седан',
        color: '#F2F3F5',
        side: 'west',
        maneuver: 'straight',
        order: 1,
        ruleExplanation: 'Белый седан на главной дороге и для южного автомобиля является помехой справа. Проезжает первым.',
        model: 'sedan'
      },
      {
        id: 'car_south',
        type: 'car',
        name: 'Синий хэтчбек',
        color: '#317ED4',
        side: 'south',
        maneuver: 'left',
        order: 2,
        ruleExplanation: 'Синий автомобиль на главной дороге, уступает белому справа и проезжает вторым.',
        model: 'hatch'
      },
      {
        id: 'car_east',
        type: 'suv',
        name: 'Зеленый кроссовер',
        color: '#4D7768',
        side: 'east',
        maneuver: 'straight',
        order: 3,
        ruleExplanation: 'Зеленый на второстепенной дороге. Среди второстепенных у него нет помехи справа от северного.',
        model: 'suv'
      },
      {
        id: 'car_north',
        type: 'car',
        name: 'Оранжевый седан',
        color: '#F08A24',
        side: 'north',
        maneuver: 'straight',
        order: 4,
        ruleExplanation: 'Оранжевый на второстепенной дороге, уступает зеленому кроссоверу справа и проезжает последним.',
        model: 'sedan'
      }
    ]
  };
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
    window._pddCrossroads = { scene, camera, renderer, envGroup, vehiclesGroup };

    buildEnvironment();

    // Подключаем процедурные шейдерные материалы дорог (асфальт с микропорами)
    if (window.PDD_ROADS) {
      window.PDD_ROADS.attach(renderer, { roots: () => [envGroup], lineage: () => null });
    }

    // Инициализация погодных эффектов и случайный стартовый выбор погоды
    ensureWeatherFx();
    setWeather(pickNextWeather(), true);

    // Обработчики событий
    window.addEventListener('resize', onWindowResize);
    renderer.domElement.addEventListener('pointerdown', onPointerDown);

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

  function updateCameraPosition() {
    if (!camera) return;
    // Оптимальная приближенная изометрическая перспектива (угол ~55°), идеально кадрирующая все 4 подъезда
    // перекрестка крупным планом над нижней шторкой Flutter на мобильных экранах
    camera.fov = 48;
    const baseHeight = 38 / camZoom;
    const baseDistanceX = 44 / camZoom;
    const baseDistanceZ = 31 / camZoom;

    // Смещение центра кадра вверх для учёта нижней шторки Flutter
    const targetY = 1.6 + (viewInsetBottom || 0) * 0.008;

    let shakeX = 0, shakeZ = 0;
    if (camShake > 0) {
      shakeX = (Math.random() - 0.5) * camShake * 2.0;
      shakeZ = (Math.random() - 0.5) * camShake * 2.0;
    }

    camera.position.set(baseDistanceX + shakeX, baseHeight, baseDistanceZ + shakeZ);
    camera.lookAt(0, targetY, 0);
    camera.updateProjectionMatrix();
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
    cachedWalkMat = swMat;
    const curbMat = new THREE.MeshLambertMaterial({ color: 0x8C9098 });
    curbMat.userData.pddKind = 'pavement';

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

    // 3. Реалистичные городские здания на заднем плане (только в безопасных для обзора секторах)
    buildDetailedBuildings(parent);
  }

  function buildDetailedBuildings(parent) {
    const buildingColors = [0xF2F4F8, 0xE5E9F0, 0xD8DEE9, 0xB48270, 0xA9B4C2];
    const roofMat = new THREE.MeshLambertMaterial({ color: season.roof ?? 0x94A3B8 });
    const winMat = new THREE.MeshBasicMaterial({ color: 0x64748B });

    function createHouse(w, h, d, x, y, z, rotY = 0) {
      const group = new THREE.Group();
      group.position.set(x, y, z);
      group.rotation.y = rotY;

      // Корпус здания
      const color = buildingColors[Math.abs(Math.round(x + z)) % buildingColors.length];
      const kind = color === 0xB48270 ? 'brick' : (Math.random() < 0.5 ? 'plaster' : 'panel');
      const bodyMat = new THREE.MeshLambertMaterial({ color });
      const body = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), bodyMat);
      body.position.y = h / 2;
      body.castShadow = true;
      body.receiveShadow = true;
      if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
        window.PDD_ROADS.skinObject(body, kind);
      }
      group.add(body);

      // Парапет / кровля
      const roof = new THREE.Mesh(new THREE.BoxGeometry(w + 0.3, 0.4, d + 0.3), roofMat);
      roof.position.y = h + 0.2;
      if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
        window.PDD_ROADS.skinObject(roof, 'roofFlat');
      }
      group.add(roof);

      // Ряды окон на главном фасаде (к улице)
      const winGeo = new THREE.PlaneGeometry(1.1, 1.3);
      for (let wy = 2.4; wy < h - 1.2; wy += 2.6) {
        for (let wx = -w / 2 + 1.4; wx <= w / 2 - 1.4; wx += 2.1) {
          const win = new THREE.Mesh(winGeo, winMat);
          win.position.set(wx, wy, d / 2 + 0.02);
          if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
            window.PDD_ROADS.skinObject(win, 'window');
          }
          group.add(win);
        }
      }
      parent.add(group);
    }

    // Дома на севере (вдоль северного проспекта): NW и NE квадранты
    [-1, 1].forEach(side => {
      for (let along = HALF_ROAD + 18; along < 95; along += 22) {
        const w = 18, d = 14, h = 18 + (along % 14);
        createHouse(w, h, d, side * (HALF_ROAD + 15), 0, -along, side > 0 ? -Math.PI / 2 : Math.PI / 2);
      }
    });

    // Дома вдоль поперечной улицы (Запад и Восток)
    [-1, 1].forEach(side => {
      for (let along = HALF_ROAD + 18; along < 80; along += 24) {
        const w = 20, d = 14, h = 16 + (along % 10);
        // Задняя линия (северная сторона улицы)
        createHouse(w, h, d, side * along, 0, -(HALF_ROAD + 15), 0);
      }
    });

    // В дальнем юге (позади камеры, z > 68): фоновые высотки
    [-1, 1].forEach(side => {
      createHouse(20, 24, 16, side * (HALF_ROAD + 18), 0, 75, side > 0 ? -Math.PI / 2 : Math.PI / 2);
    });

    // В ближнем правом секторе (SE перед камерой) — аккуратный зеленый сквер/газон:
    const parkLawn = new THREE.Mesh(
      new THREE.PlaneGeometry(32, 32),
      new THREE.MeshLambertMaterial({ color: season.ground })
    );
    parkLawn.rotation.x = -Math.PI / 2;
    parkLawn.position.set(HALF_ROAD + 18, 0.04, HALF_ROAD + 18);
    parkLawn.receiveShadow = true;
    if (window.PDD_ROADS && window.PDD_ROADS.skinObject) {
      window.PDD_ROADS.skinObject(parkLawn, 'grass');
    }
    parent.add(parkLawn);
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
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 3.5, 12), poleMat);
    pole.position.y = 1.75;
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

    // Лицевая панель знака (крупная, четкая)
    const faceGeo = new THREE.PlaneGeometry(1.65, 1.45);
    const face = new THREE.Mesh(faceGeo, signMat);
    face.position.set(0, 2.85, 0.035);
    group.add(face);

    // Задняя панель знака (дублирует знак для отличной читаемости со всех сторон в изометрии)
    const backFace = new THREE.Mesh(faceGeo, signMat);
    backFace.position.set(0, 2.85, -0.035);
    backFace.rotation.y = Math.PI;
    group.add(backFace);

    // Серая металлическая основа знака
    const backMat = new THREE.MeshLambertMaterial({ color: 0x5C6068 });
    const backGeo = new THREE.CylinderGeometry(0.85, 0.85, 0.05, 20);
    const back = new THREE.Mesh(backGeo, backMat);
    back.rotation.x = Math.PI / 2;
    back.position.set(0, 2.85, 0);
    group.add(back);

    // Табличка 8.13 «Направление главной дороги» (если указана)
    if (table8_13) {
      const plateTex = createTable8_13Texture(table8_13);
      const plateMat = new THREE.MeshLambertMaterial({ map: plateTex });
      const plateGeo = new THREE.PlaneGeometry(1.2, 1.2);

      const plate = new THREE.Mesh(plateGeo, plateMat);
      plate.position.set(0, 1.95, 0.035);
      group.add(plate);

      const plateBackFace = new THREE.Mesh(plateGeo, plateMat);
      plateBackFace.position.set(0, 1.95, -0.035);
      plateBackFace.rotation.y = Math.PI;
      group.add(plateBackFace);

      const plateBack = new THREE.Mesh(new THREE.BoxGeometry(1.22, 1.22, 0.05), backMat);
      plateBack.position.set(0, 1.95, 0);
      group.add(plateBack);
    }

    // Позиционирование знака: у правого угла тротуара перед стоп-линией, без перекрытия фонарей
    const curbX = HALF_ROAD + 1.2;
    const curbZ = 11.0;

    if (sideName === 'south') {
      group.position.set(curbX, 0, curbZ);
      group.rotation.y = 0.35;
    } else if (sideName === 'north') {
      group.position.set(-curbX, 0, -curbZ);
      group.rotation.y = Math.PI + 0.35;
    } else if (sideName === 'east') {
      group.position.set(curbZ, 0, -curbX);
      group.rotation.y = Math.PI / 2 - 0.35;
    } else if (sideName === 'west') {
      group.position.set(-curbZ, 0, curbX);
      group.rotation.y = -Math.PI / 2 - 0.35;
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
  // --- Парящий интерактивный бейдж над машиной ---
  function createVehicleBadge(actorData) {
    const badgeGroup = new THREE.Group();
    const h = (actorData.type === 'tram' ? 3.8 : 1.7) + 1.6;
    badgeGroup.position.set(0, h, 0);

    const canvas = document.createElement('canvas');
    canvas.width = 256;
    canvas.height = 256;
    const ctx = canvas.getContext('2d');

    // Отрисовка четкого бейджа в 256×256
    ctx.clearRect(0, 0, 256, 256);

    // Внешнее мягкое свечение
    ctx.shadowColor = 'rgba(0, 0, 0, 0.4)';
    ctx.shadowBlur = 16;
    ctx.shadowOffsetY = 6;

    // Круглая белая плашка
    ctx.beginPath();
    ctx.arc(128, 128, 102, 0, Math.PI * 2);
    ctx.fillStyle = '#FFFFFF';
    ctx.fill();

    // Сбрасываем тень для четкого контура
    ctx.shadowColor = 'transparent';

    // Цветное кольцо фирменного цвета машины
    ctx.lineWidth = 14;
    ctx.strokeStyle = actorData.color || '#0574F8';
    ctx.stroke();

    // Символ направления маневра
    ctx.fillStyle = '#101828';
    ctx.font = 'bold 92px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    let icon = '↑';
    if (actorData.type === 'tram') icon = '🚋';
    else if (actorData.hasSiren) icon = '🚨';
    else if (actorData.maneuver === 'left') icon = '↰';
    else if (actorData.maneuver === 'right') icon = '↱';

    ctx.fillText(icon, 128, 134);

    const tex = new THREE.CanvasTexture(canvas);
    tex.anisotropy = 4;
    const spriteMat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthTest: false });
    const sprite = new THREE.Sprite(spriteMat);
    sprite.scale.set(2.8, 2.8, 1.0);
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
      defaultIcon: icon,
    };

    return badgeGroup;
  }

  function updateBadgeText(badgeGroup, text, status = 'normal') {
    if (!badgeGroup || !badgeGroup.userData) return;
    const { canvas, ctx, tex, color } = badgeGroup.userData;
    ctx.clearRect(0, 0, 256, 256);

    const isCorrect = (status === true || status === 'correct');
    const isError = (status === 'error');
    const isPriority = (status === 'priority');

    let bgFill = '#FFFFFF';
    let borderStroke = color;
    let textColor = '#101828';
    let shadowColor = 'rgba(0, 0, 0, 0.3)';

    if (isCorrect) {
      bgFill = '#2BC280';
      borderStroke = '#FFFFFF';
      textColor = '#FFFFFF';
      shadowColor = 'rgba(43, 194, 128, 0.55)';
    } else if (isError) {
      bgFill = '#EF4444';
      borderStroke = '#FFFFFF';
      textColor = '#FFFFFF';
      shadowColor = 'rgba(239, 68, 68, 0.6)';
    } else if (isPriority) {
      bgFill = '#F59E0B';
      borderStroke = '#FFFFFF';
      textColor = '#FFFFFF';
      shadowColor = 'rgba(245, 158, 11, 0.6)';
    }

    ctx.shadowColor = shadowColor;
    ctx.shadowBlur = 18;
    ctx.shadowOffsetY = 6;

    ctx.beginPath();
    ctx.arc(128, 128, 102, 0, Math.PI * 2);
    ctx.fillStyle = bgFill;
    ctx.fill();

    ctx.shadowColor = 'transparent';
    ctx.lineWidth = 14;
    ctx.strokeStyle = borderStroke;
    ctx.stroke();

    ctx.fillStyle = textColor;
    ctx.font = 'bold 84px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, 128, 134);
    tex.needsUpdate = true;
  }

  // Позиционирование машин перед перекрестком
  function placeActorAtStart(actorMesh, sideName) {
    const isTram = actorMesh.userData.isTram;
    const stopDist = isTram ? 17.0 : 14.8;
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
    activeActors.forEach(({ mesh }) => vehiclesGroup.remove(mesh));
    activeActors.clear();
    clearSigns();
    if (weatherFx) {
      weatherFx.headlights = weatherFx.headlights.filter(h => h.car && h.car.parent);
    }

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
        attachCarHeadlights(mesh);

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
    const isTram = data.type === 'tram';

    // Формируем контрольные точки траектории Безье строго от текущей позиции
    const path = generateTrajectory(mesh, side, maneuver, isTram);

    let steerAngle = 0;
    if (maneuver === 'left') steerAngle = -0.42;
    else if (maneuver === 'right') steerAngle = 0.42;

    isResolving = true;
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

    // Следы экстренного торможения (skid marks) на асфальте
    createSkidMarks(tStartWrong, crashPoint, wrongActor.data.side);
    createSkidMarks(tStartPriority, crashPoint, priorityActor.data.side);

    activeCollision = {
      wrongActor,
      priorityActor,
      tStartWrong,
      tStartPriority,
      crashPoint,
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
    activeActors.forEach(({ badge }) => {
      if (badge) {
        const u = badge.userData;
        badge.position.y = u.baseY + Math.sin(time * 3.5 + u.order) * 0.12;
      }
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

      c.wrongActor.mesh.position.lerpVectors(c.tStartWrong, c.crashPoint, ease * 0.88);
      c.priorityActor.mesh.position.lerpVectors(c.tStartPriority, c.crashPoint, ease * 0.88);

      const wheelsWrong = c.wrongActor.mesh.userData.wheels || [];
      const wheelsPriority = c.priorityActor.mesh.userData.wheels || [];
      wheelsWrong.forEach(w => { w.rotation.x += dt * 16.0; });
      wheelsPriority.forEach(w => { w.rotation.x += dt * 16.0; });

      if (progress >= 1.0 && !c.impactHandled) {
        c.impactHandled = true;
        camShake = 0.55;
        createCrashParticles(c.crashPoint);
        createCrashSmoke(c.crashPoint);

        c.wrongActor.mesh.position.add(new THREE.Vector3(
          (c.tStartWrong.x - c.crashPoint.x) * 0.08,
          0.06,
          (c.tStartWrong.z - c.crashPoint.z) * 0.08
        ));
        c.wrongActor.mesh.rotation.z += 0.09;
        c.wrongActor.mesh.rotation.x -= 0.04;

        c.priorityActor.mesh.position.add(new THREE.Vector3(
          (c.tStartPriority.x - c.crashPoint.x) * 0.08,
          0.06,
          (c.tStartPriority.z - c.crashPoint.z) * 0.08
        ));
        c.priorityActor.mesh.rotation.z -= 0.09;
        c.priorityActor.mesh.rotation.x -= 0.04;

        c.wrongActor.mesh.userData.hazardLights = true;
        c.priorityActor.mesh.userData.hazardLights = true;

        updateBadgeText(c.wrongActor.badge, '✗', 'error');
        updateBadgeText(c.priorityActor.badge, '!', 'priority');

        notifyFlutter({
          type: 'collision',
          chosenId: c.wrongActor.data.id,
          priorityId: c.priorityActor.data.id,
          reason: c.priorityActor.data.ruleExplanation || c.wrongActor.data.ruleExplanation,
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
    updateWeather(dt);

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

  window.setWeather = (kind, immediate) => setWeather(kind, immediate);
  window.getWeather = () => ({
    current: currentTargetWeather,
    rain: curRain,
    fog: curFog,
    overcast: curOvercast,
  });
  window.randomizeWeather = () => setWeather(pickNextWeather(), false);

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
