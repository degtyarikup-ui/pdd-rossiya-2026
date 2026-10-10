// 3D-симулятор и игра «Регулировщик 3D» на Three.js
// Мини-игра проверяет сигналы для автомобиля по п. 6.10 ПДД РФ.
// Высокодетализированная городская сцена перекрёстка с аутентичными моделями.

(() => {
  'use strict';

  // --- Константы правил п. 6.10 ПДД ---
  const GESTURES = {
    HANDS_DOWN: 'handsDown',
    HANDS_SIDES: 'handsSides',
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
    if (gesture === GESTURES.HANDS_DOWN || gesture === GESTURES.HANDS_SIDES) {
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
  };

  // --- Переменные сцены ---
  let scene, camera, renderer;
  let container;
  let inspectorGroup, leftArmPivot, rightArmPivot, vestMesh;
  let ambientLight, sunLight;
  const seasonName = window.PDD_SEASONS.fromDate();
  const season = window.PDD_SEASONS.palettes[seasonName];
  // Match the main game: WebKit caps core counts, so four cores alone
  // should not degrade image quality on modern iPhones.
  const lowEnd = (navigator.hardwareConcurrency || 8) <= 2 || (navigator.deviceMemory || 8) <= 3;
  const weak = lowEnd || (navigator.hardwareConcurrency || 8) <= 4 || (navigator.deviceMemory || 8) <= 4;
  let leaves;
  const walkers = [];
  const leafCentre = new THREE.Vector3(0, 0, 0);
  let carMesh;
  let arrowsGroup;
  let envGroup;
  let skyDome;
  let isMoving = false;
  let moveProgress = 0;
  let moveCurve = null;
  let movingObject = null;
  let moveElapsed = 0;
  let moveDuration = 1.8;
  let activeMove = null;
  let activeMoveId = null;

  // Состояние
  let currentGesture = GESTURES.RIGHT_ARM_FORWARD;
  let currentApproach = APPROACHES.LEFT;
  const currentVehicle = VEHICLES.CAR;
  let currentCameraMode = 'driver';   // 'overview' | 'driver' (игрок — водитель)
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

  // --- Погодная система «Регулировщик 3D»: ясно, дождь, туман ---
  const WEATHERS = ['clear', 'rain', 'fog'];
  let currentTargetWeather = 'clear';
  let weatherAutoTimer = 240 + Math.random() * 180; // 55-85 секунд до плавной смены
  let weatherFx = null;

  // Текущие сглаженные параметры погоды (0..1)
  let curRain = 0;
  let curFog = 0;
  let curOvercast = 0;

  function pickNextWeather() {
    // Match the bright city: brief rain, long clear intervals, no random fog.
    return currentTargetWeather === 'clear' && Math.random() < 0.15 ? 'rain' : 'clear';
  }

  function setWeather(kind, immediate = false) {
    if (kind === 'random') {
      kind = pickNextWeather();
    }
    if (!WEATHERS.includes(kind)) kind = 'clear';
    currentTargetWeather = kind;

    if (immediate) {
      curRain = kind === 'rain' ? 1 : 0;
      curFog = kind === 'fog' ? 1 : 0;
      curOvercast = kind === 'clear' ? 0 : (kind === 'rain' ? 1 : 0.85);
      applyWeather(1);
    }
    notifyFlutter({ type: 'weather_changed', weather: currentTargetWeather });
  }

  function ensureWeatherFx() {
    if (weatherFx) return weatherFx;

    // Объёмная 3D система дождя: 3 слоя глубины (ближний, средний, дальний план)
    // Создаёт естественное восприятие объёма пространства без перегрузки GPU
    const isWeak = !!weak;
    const dropCount = isWeak ? 1000 : 2100;
    const dropPositions = new Float32Array(dropCount * 2 * 3);
    const drops = [];

    const nearCount = Math.floor(dropCount * 0.22);
    const midCount = Math.floor(dropCount * 0.42);
    const farCount = dropCount - nearCount - midCount;

    // 1. Ближний план: длинные капли вблизи камеры с выраженным параллаксом
    for (let i = 0; i < nearCount; i++) {
      drops.push({
        x: (Math.random() - 0.5) * 22,
        y: Math.random() * 22,
        z: 4 + Math.random() * 20,
        speed: 15.0 + Math.random() * 3.5,
        len: 1.2 + Math.random() * 0.6,
        layer: 'near',
      });
    }

    // 2. Средний план: капли над перекрёстком, машинами и регулировщиком
    for (let i = 0; i < midCount; i++) {
      drops.push({
        x: (Math.random() - 0.5) * 44,
        y: Math.random() * 24,
        z: (Math.random() - 0.5) * 36,
        speed: 14.0 + Math.random() * 3.0,
        len: 0.75 + Math.random() * 0.35,
        layer: 'mid',
      });
    }

    // 3. Дальний план: мягкая плотная сетка дождя на фоне города
    for (let i = 0; i < farCount; i++) {
      drops.push({
        x: (Math.random() - 0.5) * 76,
        y: Math.random() * 26,
        z: -12 - Math.random() * 40,
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
      roadMat: null,
      walkMat: null,
      headlights: [],
    };
    return weatherFx;
  }

  function attachCarHeadlights(car) {
    if (!car) return;
    ensureWeatherFx();
    if (car.headlightsAttached) return;
    car.headlightsAttached = true;

    // 1. Светящиеся линзы фар на переднем бампере автомобиля
    const lensMat = new THREE.MeshBasicMaterial({ color: 0xFFFEE8, transparent: true, opacity: 0 });
    const lensL = new THREE.Mesh(new THREE.BoxGeometry(0.30, 0.12, 0.04), lensMat);
    lensL.position.set(0.55, 0.65, 2.15);
    car.add(lensL);

    const lensR = new THREE.Mesh(new THREE.BoxGeometry(0.30, 0.12, 0.04), lensMat);
    lensR.position.set(-0.55, 0.65, 2.15);
    car.add(lensR);

    // 2. Мягкий физический свет фар (SpotLight) без каких-либо полигональных ребер на дороге
    // penumbra: 0.95 даёт идеальный мягкий спад
    const spot = new THREE.SpotLight(0xFFF5DD, 0, 32, Math.PI / 4.0, 0.95, 1.2);
    spot.position.set(0, 0.70, 2.10);
    const spotTarget = new THREE.Object3D();
    spotTarget.position.set(0, 0, 16.0);
    spot.target = spotTarget;
    car.add(spot);
    car.add(spotTarget);

    weatherFx.headlights.push({ car, lensMat, spot });
  }

  function applyWeather(dt) {
    if (!weatherFx) return;

    // Целевые параметры погоды
    const targetRain = currentTargetWeather === 'rain' ? 1 : 0;
    const targetFog = currentTargetWeather === 'fog' ? 1 : 0;
    const targetOvercast = currentTargetWeather === 'clear' ? 0 : (currentTargetWeather === 'rain' ? 1 : 0.85);

    // Плавная естественная интерполяция к целевым значениям (~4-5 секунд)
    const k = Math.min(1, dt * 0.22);
    curRain += (targetRain - curRain) * k;
    curFog += (targetFog - curFog) * k;
    curOvercast += (targetOvercast - curOvercast) * k;

    // 1. Цвета неба и атмосферы
    const clearSky = new THREE.Color(season.sky);
    const rainSky = new THREE.Color(0x8E9CA8);
    const fogSky = new THREE.Color(0xC2CCD5);

    scene.background.copy(clearSky).lerp(rainSky, curRain).lerp(fogSky, curFog);

    if (skyDome) {
      skyDome.material.uniforms.horizon.value.copy(scene.background);
      skyDome.material.uniforms.zenith.value.copy(scene.background).lerp(new THREE.Color(0x76A3D4), 0.45 * (1 - curOvercast));
      // В дождь и туман облака полностью растворяются в сплошной атмосферной дымке/пасмурности
      const cloudVisibility = Math.max(0, 1.0 - curRain * 1.6 - curFog * 1.6);
      skyDome.material.uniforms.cloud.value = 0.45 * cloudVisibility;
    }

    if (scene.fog) {
      scene.fog.color.copy(scene.background);
      const targetNear = THREE.MathUtils.lerp(120, THREE.MathUtils.lerp(45, 18, curFog), Math.max(curRain, curFog));
      const targetFar = THREE.MathUtils.lerp(330, THREE.MathUtils.lerp(145, 82, curFog), Math.max(curRain, curFog));
      scene.fog.near = targetNear;
      scene.fog.far = targetFar;
    }

    // 2. Освещение (баланс солнца и рассеянного света)
    if (ambientLight) {
      ambientLight.intensity = THREE.MathUtils.lerp(0.75, 0.72, curRain * 0.85 + curFog * 0.45);
    }
    if (sunLight) {
      const sunInt = THREE.MathUtils.lerp(0.85, THREE.MathUtils.lerp(0.55, 0.5, curFog), Math.max(curRain, curFog));
      sunLight.intensity = sunInt;
      sunLight.color.setHex(season.sun).lerp(new THREE.Color(0xCCD8E4), Math.max(curRain, curFog));
    }

    // 3. Дорожное покрытие и тротуары: чистое естественное потемнение мокрого асфальта
    if (weatherFx.roadMat) {
      const dryAsphalt = new THREE.Color(BRAND.asphalt);
      const wetAsphalt = new THREE.Color(0x181A20);
      weatherFx.roadMat.color.copy(dryAsphalt).lerp(wetAsphalt, curRain * 0.90 + curFog * 0.25);
    }
    if (weatherFx.walkMat) {
      const dryWalk = new THREE.Color(season.sidewalk);
      const wetWalk = new THREE.Color(season.sidewalk).multiplyScalar(0.72);
      weatherFx.walkMat.color.copy(dryWalk).lerp(wetWalk, curRain * 0.35 + curFog * 0.15);
    }

    // 4. Дождь: 3-слойная объёмная симуляция с глубиной и параллаксом
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
            d.x = (Math.random() - 0.5) * 22;
            d.z = 4 + Math.random() * 20;
          } else if (d.layer === 'mid') {
            d.x = (Math.random() - 0.5) * 44;
            d.z = (Math.random() - 0.5) * 36;
          } else {
            d.x = (Math.random() - 0.5) * 76;
            d.z = -12 - Math.random() * 40;
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

    // 5. Фары: светящиеся линзы + физический SpotLight без полигональных наклеек
    const targetHeadlight = Math.max(curRain * 0.85, curFog * 0.95);
    weatherFx.headlights = weatherFx.headlights.filter(h => h.car.parent);
    weatherFx.headlights.forEach(h => {
      h.lensMat.opacity = targetHeadlight;
      h.spot.intensity = targetHeadlight * 3.6;
    });
  }

  function updateWeather(dt) {
    if (!weatherFx) return;

    // Таймер автоматической смены погоды в случайном порядке
    weatherAutoTimer -= dt;
    if (weatherAutoTimer <= 0) {
      setWeather(pickNextWeather());
      weatherAutoTimer = currentTargetWeather === 'clear' ? 240 + Math.random() * 180 : 25 + Math.random() * 20;
    }

    applyWeather(dt);
  }

  function init() {
    container = document.getElementById('canvas-container');
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(season.sky);
    // Дымка в цвет горизонта: дальний город растворяется, края мира не видно.
    scene.fog = new THREE.Fog(season.sky, 120, 330);

    // Процедурный градиентный купол неба с облаками (как во флагманской игре)
    skyDome = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 16), new THREE.ShaderMaterial({
      uniforms: { horizon: { value: new THREE.Color(season.sky) }, zenith: { value: new THREE.Color(season.sky) }, cloud: { value: 0.55 } },
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

    camera = new THREE.PerspectiveCamera(42, width / height, 0.5, 420);
    updateCameraPosition();

    renderer = new THREE.WebGLRenderer({ antialias: !lowEnd, alpha: false, powerPreference: 'high-performance' });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, lowEnd ? 1.25 : 1.75));
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap;
    renderer.toneMapping = THREE.NoToneMapping;
    renderer.toneMappingExposure = 1.05;
    container.appendChild(renderer.domElement);

    setupLighting();
    ensureWeatherFx();
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

    // Bright daytime on entry, as in the city game.
    const initialWeather = 'clear';
    setWeather(initialWeather, true);

    // Сообщаем Flutter о готовности
    notifyFlutter({ type: 'ready' });

    if (seasonName === 'autumn') leaves = window.PDD_SEASONS.createLeaves(scene, {
      lowEnd, palette: () => season.canopy, count: lowEnd ? 6 : 12,
      scaleMin: 0.55, scaleMax: 0.85, spanX: 32, spanZ: 44, height: 7, spreadEvenly: true,
    });
    animate();
  }

  function setupLighting() {
    // Рассеянный дневной свет (как во флагманской игре)
    ambientLight = new THREE.AmbientLight(0xFFFFFF, season.ambient);
    scene.add(ambientLight);

    // Верхнее солнце с естественными мягкими тенями
    sunLight = new THREE.DirectionalLight(season.sun, season.sunIntensity);
    sunLight.position.set(16, 68, 14);
    sunLight.castShadow = true;
    sunLight.shadow.mapSize.width = lowEnd ? 512 : 1024;
    sunLight.shadow.mapSize.height = lowEnd ? 512 : 1024;
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
    const groundGeo = new THREE.PlaneGeometry(900, 900);
    const groundMat = new THREE.MeshLambertMaterial({ color: season.ground });
    groundMat.userData.pddKind = 'grass';
    const ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -0.01;
    ground.receiveShadow = true;
    envGroup.add(ground);

    // Проезжая часть с фактурой асфальта (микропоры и каменная крошка)
    const roadMat = new THREE.MeshLambertMaterial({ color: BRAND.asphalt });
    roadMat.userData.pddKind = 'asphalt';
    if (weatherFx) weatherFx.roadMat = roadMat;
    const roadWidth = 13.6;
    const roadLen = CITY_REACH * 2 + 20;

    const roadNS = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth, roadLen, 6, 64), roadMat);
    roadNS.rotation.x = -Math.PI / 2;
    roadNS.position.y = 0.02;
    roadNS.userData.surface = 'road';
    roadNS.receiveShadow = true;
    envGroup.add(roadNS);

    const roadEW = new THREE.Mesh(new THREE.PlaneGeometry(roadLen, roadWidth, 64, 6), roadMat);
    roadEW.rotation.x = -Math.PI / 2;
    roadEW.position.y = 0.02;
    roadEW.userData.surface = 'road';
    roadEW.receiveShadow = true;
    envGroup.add(roadEW);

    // Центр перекрестка
    const centerMesh = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth, roadWidth, 8, 8), roadMat);
    centerMesh.rotation.x = -Math.PI / 2;
    centerMesh.position.y = 0.025;
    centerMesh.userData.surface = 'road';
    centerMesh.receiveShadow = true;
    envGroup.add(centerMesh);

    // Дорожная разметка (чистый белый базовый термопластик как во флагмане)
    const markMat = new THREE.MeshBasicMaterial({ color: BRAND.asphaltMarking });

    buildRoadMarkings(envGroup, markMat, roadWidth);
    buildSidewalks(envGroup, roadWidth);
    buildCity(envGroup, roadWidth);
    buildStreetFurniture(envGroup, roadWidth);
    buildPedestrians(envGroup, roadWidth);
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
    const lineLen = CITY_REACH - 14;
    const lineCentre = 14 + lineLen / 2;
    const doubleLineGeo = new THREE.PlaneGeometry(0.14, lineLen);
    [-0.14, 0.14].forEach(off => {
      // Южная ветка
      const lineS = new THREE.Mesh(doubleLineGeo, markMat);
      lineS.rotation.x = -Math.PI / 2;
      lineS.position.set(off, 0.034, lineCentre);
      parent.add(lineS);
      // Северная ветка
      const lineN = new THREE.Mesh(doubleLineGeo, markMat);
      lineN.rotation.x = -Math.PI / 2;
      lineN.position.set(off, 0.034, -lineCentre);
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
      color: season.sidewalk,
    });
    walkMat.userData.pddKind = 'pavement';
    if (weatherFx) weatherFx.walkMat = walkMat;
    const lawnMat = new THREE.MeshLambertMaterial({
      color: season.verge[1],
    });
    lawnMat.userData.pddKind = 'grass';

    const walkSize = CITY_REACH;
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

  // --- Город вокруг перекрёстка ---
  // Те же ассеты, что в основной игре: панельные, кирпичные и оштукатуренные
  // фасады, окна, плоские кровли, кора и листва из PDD_ROADS. Каждый дом
  // фактурируется отдельно, затем всё склеивается в несколько мешей по
  // материалу — на весь город около двадцати вызовов отрисовки.
  const CITY_REACH = 190;      // докуда тянутся улицы с домами
  const SIDEWALK = 4.2;        // тротуар между бордюром и газоном двора

  function cityRandom(seed) {
    let t = seed >>> 0;
    return () => {
      t += 0x6D2B79F5;
      let r = Math.imul(t ^ (t >>> 15), 1 | t);
      r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
      return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
  }

  // Склейка мешей одного материала в один (позиции и нормали — в мировых
  // координатах группы, UV и pddSide уже запечены skinObject).
  function mergeMeshes(meshes, material, kind) {
    if (!meshes.length) return null;
    const geos = meshes.map(m => {
      m.updateMatrix();
      const g = m.geometry.index ? m.geometry.toNonIndexed() : m.geometry.clone();
      g.applyMatrix4(m.matrix);
      return g;
    });
    const merged = new THREE.BufferGeometry();
    Object.keys(geos[0].attributes).forEach(name => {
      const size = geos[0].attributes[name].itemSize;
      let total = 0;
      geos.forEach(g => { if (g.attributes[name]) total += g.attributes[name].count * size; });
      const data = new Float32Array(total);
      let offset = 0;
      geos.forEach(g => {
        const a = g.attributes[name];
        if (!a) return;
        data.set(a.array, offset);
        offset += a.array.length;
      });
      merged.setAttribute(name, new THREE.BufferAttribute(data, size));
    });
    geos.forEach(g => g.dispose());
    meshes.forEach(m => m.geometry.dispose());
    merged.computeBoundingSphere();
    const mesh = new THREE.Mesh(merged, material);
    if (kind) mesh.userData.pddSkinned = kind;
    return mesh;
  }

  function skin(mesh, kind, opts) {
    if (window.PDD_ROADS) window.PDD_ROADS.skinObject(mesh, kind, opts);
    return mesh;
  }

  function buildCity(parent, roadWidth) {
    const halfW = roadWidth / 2;
    const rnd = cityRandom(6100);
    const pick = list => list[Math.floor(rnd() * list.length)];

    const bodies = new Map();      // `${kind}:${color}` -> { kind, material, meshes }
    const bodyOf = (kind, color) => {
      const key = kind + ':' + color;
      if (!bodies.has(key)) {
        bodies.set(key, { kind, material: new THREE.MeshLambertMaterial({ color }), meshes: [] });
      }
      return bodies.get(key);
    };
    const roofMat = new THREE.MeshLambertMaterial({ color: season.roof ?? 0x94A3B8 });
    const glassMat = new THREE.MeshBasicMaterial({ color: 0x708995 });
    const awningColors = [0xE0533F, 0x2F6F9F, 0x3E8E5E, 0xD9A441];
    const awningMats = awningColors.map(c => new THREE.MeshLambertMaterial({ color: c }));
    const roofs = [], windows = [], awnings = awningColors.map(() => []);
    const winGeoNarrow = new THREE.PlaneGeometry(1, 1.25);
    const winGeoWide = new THREE.PlaneGeometry(1.3, 1.25);

    // Один дом: корпус, парапет кровли, окна на фасаде к улице и торцах.
    // Локально фасад к улице смотрит в +Z; place() ставит дом на место.
    function house(width, height, depth, place) {
      const brickColor = 0xB5675A;
      const color = pick([...BRAND.buildingColors, brickColor, 0xA9B4C2]);
      const kind = color === brickColor ? 'brick' : (rnd() < 0.25 ? 'plaster' : 'panel');
      const opts = kind === 'panel' ? { u0: -0.4, v0: -0.45 } : kind === 'plaster' ? { v0: -0.2 } : undefined;

      const parts = [];
      const body = new THREE.Mesh(new THREE.BoxGeometry(width, height, depth), bodyOf(kind, color).material);
      body.position.y = height / 2;
      skin(body, kind, opts);
      parts.push([body, bodyOf(kind, color).meshes]);

      const roof = new THREE.Mesh(new THREE.BoxGeometry(width + 0.4, 0.4, depth + 0.4), roofMat);
      roof.position.y = height + 0.2;
      skin(roof, 'roofFlat');
      parts.push([roof, roofs]);

      const winGeo = rnd() < 0.5 ? winGeoNarrow : winGeoWide;
      for (let y = 1.8; y < height - 0.6; y += 2.7) {
        for (let x = -width / 2 + 1.3; x < width / 2 - 0.6; x += 2) {
          const w = new THREE.Mesh(winGeo.clone(), glassMat);
          w.position.set(x, y, depth / 2 + 0.015);
          skin(w, 'window');
          parts.push([w, windows]);
        }
        for (const side of [-1, 1]) {
          for (let z = -depth / 2 + 1.4; z < depth / 2 - 0.6; z += 2) {
            const w = new THREE.Mesh(winGeo.clone(), glassMat);
            w.position.set(side * (width / 2 + 0.015), y, z);
            w.rotation.y = side * Math.PI / 2;
            skin(w, 'window');
            parts.push([w, windows]);
          }
        }
      }
      if (kind !== 'plaster' && rnd() > 0.45) {
        const i = Math.floor(rnd() * awningColors.length);
        const awning = new THREE.Mesh(new THREE.BoxGeometry(Math.min(width - 2, 6), 0.08, 0.9), awningMats[i]);
        awning.position.set(0, 2.45, depth / 2 + 0.45);
        awning.rotation.x = 0.28;
        parts.push([awning, awnings[i]]);
      }

      // Дом как группа: переносим каждую часть в координаты сцены.
      const holder = new THREE.Group();
      place(holder);
      holder.updateMatrix();
      parts.forEach(([mesh, bucket]) => {
        mesh.updateMatrix();
        mesh.matrix.premultiply(holder.matrix);
        mesh.matrix.decompose(mesh.position, mesh.quaternion, mesh.scale);
        bucket.push(mesh);
      });
    }

    // Ряды домов вдоль четырёх улиц. Угловые участки — у улиц север-юг,
    // поперечные ряды начинаются за ними, чтобы дома не пересекались.
    const frontLine = halfW + SIDEWALK + 1.5;
    const arms = [
      { axis: 'z', dir: -1, start: frontLine },
      { axis: 'z', dir: 1, start: frontLine },
      { axis: 'x', dir: -1, start: frontLine + 18 },
      { axis: 'x', dir: 1, start: frontLine + 18 },
    ];
    arms.forEach(arm => {
      [-1, 1].forEach(side => {
        let along = arm.start;
        while (along < CITY_REACH) {
          const width = 14 + rnd() * 10;
          const depth = 12 + rnd() * 4;
          // Ближе к перекрёстку пониже, дальше — высотки, закрывающие горизонт.
          const far = along > 70;
          const height = (far ? 22 : 13) + rnd() * (far ? 20 : 9);
          const centre = along + width / 2;
          const offset = frontLine + depth / 2;
          house(width, height, depth, holder => {
            if (arm.axis === 'z') {
              holder.position.set(side * offset, 0, arm.dir * centre);
              holder.rotation.y = side > 0 ? -Math.PI / 2 : Math.PI / 2;
            } else {
              holder.position.set(arm.dir * centre, 0, side * offset);
              holder.rotation.y = side > 0 ? Math.PI : 0;
            }
          });
          along += width + 3 + rnd() * 5;
        }
      });
    });

    bodies.forEach(b => {
      const mesh = mergeMeshes(b.meshes, b.material, b.kind);
      mesh.receiveShadow = true;
      parent.add(mesh);
    });
    const roofMesh = mergeMeshes(roofs, roofMat, 'roofFlat');
    if (roofMesh) parent.add(roofMesh);
    const windowMesh = mergeMeshes(windows, glassMat, 'window');
    if (windowMesh) parent.add(windowMesh);
    awnings.forEach((list, i) => {
      const m = mergeMeshes(list, awningMats[i]);
      if (m) parent.add(m);
    });
    winGeoNarrow.dispose();
    winGeoWide.dispose();

    buildStreetTrees(parent, halfW, rnd);
    buildSkyline(parent, rnd);
  }

  // Деревья по тротуарам всех четырёх улиц: стволы одним мешем, кроны — двумя.
  function buildStreetTrees(parent, halfW, rnd) {
    const trunkMat = new THREE.MeshLambertMaterial({ color: 0x5D4534 });
    const leafMats = [
      new THREE.MeshLambertMaterial({ color: season.canopy[0] }),
      new THREE.MeshLambertMaterial({ color: season.canopy[1] }),
    ];
    const trunks = [], crowns = [[], []];
    const line = halfW + SIDEWALK - 1.4;
    const plant = (x, z) => {
      const s = 0.85 + rnd() * 0.35;
      const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.16 * s, 0.26 * s, 3 * s, 6), trunkMat);
      trunk.position.set(x, 0.18 + 1.5 * s, z);
      skin(trunk, 'bark');
      trunks.push(trunk);
      const i = rnd() < 0.5 ? 0 : 1;
      const big = new THREE.Mesh(new THREE.DodecahedronGeometry(1.5 * s, 1), leafMats[i]);
      big.position.set(x, 0.18 + 3.6 * s, z);
      big.rotation.y = rnd() * Math.PI;
      skin(big, 'leaves');
      crowns[i].push(big);
      const top = new THREE.Mesh(new THREE.DodecahedronGeometry(1.05 * s, 1), leafMats[1 - i]);
      top.position.set(x + 0.3 * s, 0.18 + 4.6 * s, z + 0.2 * s);
      skin(top, 'leaves');
      crowns[1 - i].push(top);
    };
    for (let along = halfW + 10; along < 125; along += 12 + rnd() * 3) {
      [-1, 1].forEach(dir => [-1, 1].forEach(side => {
        plant(side * line, dir * along);       // улицы север-юг
        plant(dir * along, side * line);       // улицы запад-восток
      }));
    }
    const trunkMesh = mergeMeshes(trunks, trunkMat, 'bark');
    trunkMesh.castShadow = true;
    parent.add(trunkMesh);
    crowns.forEach((list, i) => {
      const m = mergeMeshes(list, leafMats[i], 'leaves');
      m.castShadow = true;
      parent.add(m);
    });
  }

  // Дальний город по кругу: простые силуэты одним мешем, которые растворяются
  // в дымке. Закрывают пустой горизонт за последними домами улиц.
  function buildSkyline(parent, rnd) {
    const mat = new THREE.MeshLambertMaterial({ color: 0xB4C2CE });
    const blocks = [];
    const count = 46;
    for (let i = 0; i < count; i++) {
      const a = (i / count) * Math.PI * 2 + rnd() * 0.06;
      const r = 235 + rnd() * 60;
      const w = 22 + rnd() * 26, h = 26 + rnd() * 46, d = 18 + rnd() * 14;
      const b = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
      b.position.set(Math.cos(a) * r, h / 2, Math.sin(a) * r);
      b.rotation.y = -a;
      blocks.push(b);
    }
    const mesh = mergeMeshes(blocks, mat);
    mesh.userData.distant = true;
    parent.add(mesh);
  }

  // Same lamp factory and workshop edits as the main game. Bake all static
  // parts into one mesh per material (normally just grey pole + light).
  function buildStreetFurniture(parent, roadWidth) {
    const halfW = roadWidth / 2;
    const parts = new Map();
    function place(x, z, angle) {
      const model = window.PDD_VEHICLES.applyModelEdits('lamp', window.PDD_STREET.createLampPost());
      model.position.set(x, 0.18, z); model.rotation.y = angle;
      model.updateMatrixWorld(true);
      model.traverse(node => {
        if (!node.isMesh || !node.visible) return;
        const mat = node.material;
        const key = `${mat.type}:${mat.color.getHex()}:${mat.side}:${mat.opacity}`;
        if (!parts.has(key)) parts.set(key, {mat, meshes: []});
        const mesh = new THREE.Mesh(node.geometry.clone(), mat);
        node.matrixWorld.decompose(mesh.position, mesh.quaternion, mesh.scale);
        parts.get(key).meshes.push(mesh);
        node.geometry.dispose();
      });
    }
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
      place(sx * (halfW + 1.2), sz * (halfW + 1.2), Math.atan2(-sz, sx));
    }
    const line = halfW + 0.9;
    for (let along = halfW + 22; along < 150; along += 24) {
      for (const dir of [-1, 1]) for (const side of [-1, 1]) {
        place(side * line, dir * along, side > 0 ? 0 : Math.PI);
        place(dir * along, side * line, side > 0 ? -Math.PI / 2 : Math.PI / 2);
      }
    }
    parts.forEach(({meshes, mat}) => {
      const mesh = mergeMeshes(meshes, mat);
      mesh.userData.streetLamp = true;
      mesh.castShadow = mat.type !== 'MeshBasicMaterial';
      mesh.receiveShadow = true;
      parent.add(mesh);
    });
  }

  function buildPedestrians(parent, roadWidth) {
    const colours = window.PDD_STREET.peopleColors;
    const halfW = roadWidth / 2;
    // One/two walkers per corner. Both coordinates always stay outside
    // BOTH roads: no crossings, diagonal cuts or traffic/collision actors.
    const corners = [[-1, -1], [1, 1], [1, -1], [-1, 1]];
    const count = weak ? 4 : 8;
    for (let i = 0; i < count; i++) {
      const [sx, sz] = corners[i % 4];
      const axis = i % 2 === Math.floor(i / 4) ? 'z' : 'x';
      const mesh = window.PDD_VEHICLES.applyModelEdits('pedestrian',
        window.PDD_STREET.createPedestrian(colours[i % colours.length], (i * 3 + 1) % 12));
      mesh.position.y = 0.18;
      mesh.userData.ambient = true; mesh.userData.noCollision = true;
      mesh.traverse(node => { if (node.isMesh) node.castShadow = !weak; });
      parent.add(mesh);
      walkers.push({mesh, sx, sz, axis, curb: halfW + 1.8, centre: halfW + 17,
        distance: 11, time: 0, phase: i * 1.9, pace: 0.075 + (i % 3) * 0.008});
    }
    updatePedestrians(0);
  }

  function updatePedestrians(delta) {
    for (const walker of walkers) {
      walker.time += delta;
      const phase = walker.phase + walker.time * walker.pace;
      const along = walker.centre + Math.sin(phase) * walker.distance;
      const {mesh, sx, sz, axis, curb} = walker;
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
    inspectorGroup = window.PDD_CONTROLLER.create('right_arm_forward');
    const rig = inspectorGroup.controllerRig;
    leftArmPivot = rig.left; rightArmPivot = rig.right; vestMesh = rig.vest;
    scene.add(inspectorGroup);
  }

  function buildVehicles() {
    // 1. Легковой автомобиль (использует официальную систему моделей PDD_VEHICLES)
    if (window.PDD_VEHICLES && typeof window.PDD_VEHICLES.create === 'function') {
      carMesh = window.PDD_VEHICLES.create('hatch', 'red');
    } else {
      carMesh = buildFallbackCar();
    }

    // Располагаем машину на правой полосе южного въезда лицом к перекрестку
    carMesh.position.set(3.2, 0, 13.5);
    carMesh.rotation.y = Math.PI; // Лицом к перекрёстку (на север)
    scene.add(carMesh);
    attachCarHeadlights(carMesh);
  }

  // Машина из гаража основной игры (Flutter передаёт выбор игрока).
  function setPlayerCar(id, paint) {
    if (!window.PDD_VEHICLES || typeof window.PDD_VEHICLES.create !== 'function') return;
    const next = window.PDD_VEHICLES.create(id, paint);
    if (carMesh) {
      next.position.copy(carMesh.position);
      next.rotation.copy(carMesh.rotation);
      next.visible = carMesh.visible;
      scene.remove(carMesh);
    }
    if (next.blinkerL) next.blinkerL.visible = false;
    if (next.blinkerR) next.blinkerR.visible = false;
    if (movingObject === carMesh) movingObject = next;
    carMesh = next;
    scene.add(carMesh);
    attachCarHeadlights(carMesh);
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

  // --- Стрелки разрешенных траекторий на асфальте ---
  function buildTrajectoryArrows() {
    arrowsGroup = new THREE.Group();
    scene.add(arrowsGroup);
    updateTrajectoryArrows();
  }

  // --- Траектории манёвров: прямо → дуга → прямо ---
  // A car up to 5 x 2 m clears the officer's island by at least 1.5 m.
  const CAR_PATH = { x: 3.2, right: { r: 4, lane: 3.4 }, left: { r: 4, lane: -3.6 }, uturn: { lane: -3.4, at: 7.5 } };

  function movePath(move, startZ, reach, y) {
    const spec = CAR_PATH;
    const x0 = spec.x;
    const pts = [];
    const P = (x, z) => pts.push(new THREE.Vector3(x, y, z));
    const line = (ax, az, bx, bz, n) => {
      for (let i = 0; i < n; i++) { const t = i / n; P(ax + (bx - ax) * t, az + (bz - az) * t); }
    };
    const arc = (cx, cz, r, a0, a1, n) => {
      for (let i = 0; i < n; i++) { const a = a0 + (a1 - a0) * i / n; P(cx + r * Math.cos(a), cz + r * Math.sin(a)); }
    };
    if (move === MOVES.LEFT) {
      const { r, lane } = spec.left, cx = x0 - r, cz = lane + r;
      line(x0, Math.max(startZ, cz), x0, cz, 6);
      arc(cx, cz, r, 0, -Math.PI / 2, 18);
      line(cx, lane, -reach, lane, 6); P(-reach, lane);
    } else if (move === MOVES.RIGHT) {
      const { r, lane } = spec.right, cx = x0 + r, cz = lane + r;
      line(x0, Math.max(startZ, cz), x0, cz, 6);
      arc(cx, cz, r, Math.PI, Math.PI * 1.5, 18);
      line(cx, lane, reach, lane, 6); P(reach, lane);
    } else if (move === MOVES.UTURN) {
      const { lane, at } = spec.uturn, rr = (x0 - lane) / 2, cx = x0 - rr;
      line(x0, Math.max(startZ, at), x0, at, 6);
      arc(cx, at, rr, 0, -Math.PI, 20);
      line(lane, at, lane, reach, 6); P(lane, reach);
    } else {
      line(x0, startZ, x0, -reach, 8); P(x0, -reach);
    }
    return new THREE.CatmullRomCurve3(pts, false, 'centripetal');
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
    const originX = 3.2;
    const originZ = 8.8;

    const canStraight = allowed.includes(MOVES.STRAIGHT);
    const canRight = allowed.includes(MOVES.RIGHT);
    const canLeft = allowed.includes(MOVES.LEFT);
    const canUturn = allowed.includes(MOVES.UTURN);

    const arrow = move => addRoadRibbonArrow(movePath(move, originZ, 12.0, 0.052));
    if (canStraight) arrow(MOVES.STRAIGHT);
    if (canRight) arrow(MOVES.RIGHT);
    if (canLeft) arrow(MOVES.LEFT);
    if (canUturn && currentVehicle === VEHICLES.CAR) arrow(MOVES.UTURN);

    // Если движение запрещено (например, грудь/спина или поднятая рука)
    if (allowed.length === 1 && allowed[0] === MOVES.NONE) {
      addStopProhibitionMarker(originX, originZ);
    }
  }

  function addRoadRibbonArrow(curve, width = 0.55) {
    const numPoints = 32;
    const points = curve.getSpacedPoints(numPoints);
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
  function setScenario(gesture, approach) {
    if (resetTimer) {
      clearTimeout(resetTimer);
      resetTimer = null;
    }

    currentGesture = gesture;
    currentApproach = approach;

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

    const pose = gesture === GESTURES.ARM_UP ? 'arm_up'
      : gesture === GESTURES.RIGHT_ARM_FORWARD ? 'right_arm_forward'
      : gesture === GESTURES.HANDS_SIDES ? 'arms_sides' : 'arms_down';
    const angles = window.PDD_CONTROLLER.poses[pose];
    targetLeftArm.set(...angles.left);
    targetRightArm.set(...angles.right);
    inspectorGroup.userData.pose = pose;

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
    activeBlinkerSide = null;
    isMoving = false;
    moveProgress = 0;
    moveElapsed = 0;
    activeMove = null;
    activeMoveId = null;
  }

  // --- Запуск анимации движения ТС при ответе игрока ---
  function makeMove(moveType, moveId) {
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

    if (moveType === MOVES.NONE || !isCorrect) {
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

    movingObject = carMesh;
    const startZ = movingObject.position.z;

    // Все манёвры завершаются за перекрёстком и пешеходным переходом (на отметке ±13.5)
    moveCurve = movePath(moveType, startZ, 13.5, 0);

    isMoving = true;
    moveProgress = 0;
    moveElapsed = 0;
    activeMove = moveType;
    activeMoveId = moveId;
    moveDuration = moveType === MOVES.STRAIGHT ? 1.8 : moveType === MOVES.UTURN ? 2.05 : 1.95;

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

  function updateCameraPosition(delta = 1 / 60) {
    if (currentCameraMode === 'overview') {
      const radius = camDistance;
      camera.position.x = Math.sin(camAngle) * radius;
      camera.position.y = camHeight;
      camera.position.z = Math.cos(camAngle) * radius;
      camera.lookAt(0, 1.2, 0);
    } else if (currentCameraMode === 'portrait') {
      const rot = inspectorGroup ? inspectorGroup.rotation.y : 0;
      const dist = 0.92;
      camera.position.set(Math.sin(rot) * dist, 1.73, Math.cos(rot) * dist);
      camera.lookAt(0, 1.72, 0);
    } else if (currentCameraMode === 'portrait_angle') {
      const rot = (inspectorGroup ? inspectorGroup.rotation.y : 0) + 0.42;
      const dist = 1.05;
      camera.position.set(Math.sin(rot) * dist, 1.76, Math.cos(rot) * dist);
      camera.lookAt(0, 1.71, 0);
    } else {
      updateDriverCamera(delta);
    }
  }

  // Near: officer at eye level. Far: all junction exits. The camera keeps
  // looking at the junction instead of swinging with the steering wheel.
  // A maneuver gently widens the view; the next question restores user zoom.
  const driverCamPos = new THREE.Vector3();
  const driverCamLook = new THREE.Vector3();
  const driverWantPos = new THREE.Vector3();
  const driverWantLook = new THREE.Vector3();
  let driverCamReady = false;
  let cameraZoom = 1;

  function setZoom(value) {
    cameraZoom = Math.min(Math.max(Number(value) || 1, 0.4), 2.6);
  }

  function updateDriverCamera(delta = 1 / 60) {
    const maneuver = THREE.MathUtils.smoothstep(moveProgress, 0, 0.65);
    const zoom = THREE.MathUtils.lerp(cameraZoom, Math.max(cameraZoom, 2.1), maneuver);
    if (zoom < 1) {
      const close = THREE.MathUtils.smoothstep(zoom, 0.4, 1);
      driverWantPos.set(1.4 + close, 2.4 + 2.1 * close, 6.8 + 15.2 * close);
      driverWantLook.set(0.8 * close, 1.25 - 0.2 * close, 0);
    } else {
      const far = (zoom - 1) / 1.6;
      driverWantPos.set(2.4, 4.5 + 33.5 * far, 22 + 28 * far);
      driverWantLook.set(0.8 * (1 - far), 1.05 * (1 - far), 0);
    }

    if (!driverCamReady) {
      driverCamPos.copy(driverWantPos);
      driverCamLook.copy(driverWantLook);
      driverCamReady = true;
    } else {
      const blend = 1 - Math.exp(-7 * delta);
      driverCamPos.lerp(driverWantPos, blend);
      driverCamLook.lerp(driverWantLook, blend);
    }
    camera.position.copy(driverCamPos);
    camera.lookAt(driverCamLook);
  }

  // Доля высоты экрана, закрытая снизу панелью Flutter. Центр перспективы
  // ставим в середину видимой части, иначе сцена «уезжает» под панель.
  let viewInsetBottom = 0;

  function applyViewport(width, height) {
    const visible = Math.max(height * (1 - viewInsetBottom), 1);
    camera.aspect = width / visible;
    camera.setViewOffset(width, visible, 0, 0, width, height);
    camera.updateProjectionMatrix();
  }

  function setViewInsetBottom(fraction) {
    viewInsetBottom = Math.min(Math.max(Number(fraction) || 0, 0), 0.8);
    if (!container || !camera) return;
    applyViewport(
      container.clientWidth || window.innerWidth,
      container.clientHeight || window.innerHeight
    );
  }

  function onWindowResize() {
    if (!container) return;
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;
    applyViewport(width, height);
    renderer.setSize(width, height);
  }

  // --- Главный цикл анимации ---
  let lastRenderedAt = 0;
  function animate(timestamp) {
    requestAnimationFrame(animate);
    const now = timestamp || performance.now();
    // A stationary question needs only 30 FPS on a weak phone. Maneuvers
    // still use every frame; interpolation below is independent of FPS.
    if (weak && !isMoving && now - lastRenderedAt < 32) return;
    lastRenderedAt = now;

    const delta = Math.min(clock.getDelta(), 0.05);
    const time = clock.elapsedTime;
    const poseBlend = 1 - Math.exp(-8 * delta);

    // Плавное вращение камеры
    camAngle += (targetAngle - camAngle) * poseBlend;

    // Плавный поворот регулировщика к целевому направлению
    curInspectorRotY += (targetInspectorRotY - curInspectorRotY) * poseBlend;
    if (inspectorGroup) {
      inspectorGroup.rotation.y = curInspectorRotY;
    }

    // Дыхание регулировщика и легкое покачивание жезла (живая анимация)
    if (vestMesh) {
      const breathe = Math.sin(time * 2.2) * 0.006;
      vestMesh.scale.set(1 + breathe, 1, 1 + breathe);
    }

    // Плавная интерполяция рук регулировщика
    curLeftArm.x += (targetLeftArm.x - curLeftArm.x) * poseBlend;
    curLeftArm.y += (targetLeftArm.y - curLeftArm.y) * poseBlend;
    curLeftArm.z += (targetLeftArm.z - curLeftArm.z) * poseBlend;
    if (leftArmPivot) {
      leftArmPivot.rotation.set(curLeftArm.x, curLeftArm.y, curLeftArm.z);
    }

    curRightArm.x += (targetRightArm.x - curRightArm.x) * poseBlend;
    curRightArm.y += (targetRightArm.y - curRightArm.y) * poseBlend;
    curRightArm.z += (targetRightArm.z - curRightArm.z) * poseBlend;
    if (rightArmPivot) {
      rightArmPivot.rotation.set(curRightArm.x, curRightArm.y, curRightArm.z);
    }

    // Short signal lead-in, gentle acceleration and braking; arc-length
    // sampling keeps turns continuous and independent of render frame rate.
    if (isMoving && moveCurve && movingObject) {
      moveElapsed += delta;
      const elapsed = THREE.MathUtils.clamp((moveElapsed - 0.12) / moveDuration, 0, 1);
      moveProgress = (1 - Math.cos(Math.PI * elapsed)) / 2;
      movingObject.position.copy(moveCurve.getPointAt(moveProgress));
      const tangent = moveCurve.getTangentAt(Math.min(moveProgress + 0.006, 1));
      const heading = Math.atan2(tangent.x, tangent.z);
      const turn = Math.atan2(Math.sin(heading - movingObject.rotation.y), Math.cos(heading - movingObject.rotation.y));
      movingObject.rotation.y += turn * (1 - Math.exp(-22 * delta));

      if (elapsed >= 1) {
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
        notifyFlutter({ type: 'move_complete', move: activeMove, id: activeMoveId });
      }
    }
    updateCameraPosition(delta);

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

    updatePedestrians(delta);
    if (leaves) leaves.update(Math.min(delta, 0.05), { enabled: seasonName === 'autumn', centre: leafCentre });
    updateWeather(delta);
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
    getAllowedMoves,
    getState() { return {gesture: currentGesture, approach: currentApproach, vehicle: currentVehicle, season: seasonName, weather: currentTargetWeather, rain: curRain, fog: curFog, pose: inspectorGroup?.userData.pose, rightHandX: rightArmPivot?.position.x, leafCount: leaves?.mesh?.count || 0, drawCalls: renderer.info.render.calls}; },
    makeMove,
    setMode(mode) {
      currentMode = mode;
      updateTrajectoryArrows();
    },
    setCameraView,
    setViewInsetBottom,
    setPlayerCar,
    setZoom,
    rotateCamera,
    setWeather,
    randomizeWeather() {
      setWeather(pickNextWeather());
    },
    getWeather() {
      return { weather: currentTargetWeather, rain: curRain, fog: curFog, overcast: curOvercast };
    },
    getCamera() { return camera; },
    getInspector() { return inspectorGroup; },
    reset() {
      resetVehiclePositions();
      updateTrajectoryArrows();
    },
  };

  window.addEventListener('DOMContentLoaded', init);
})();
