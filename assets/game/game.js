/**
 * PDD 3D Simulator Game Engine
 * Built with Three.js (Isometric View, Low-Poly Stylization, Procedural Road & PDD Situations)
 */

(function() {
  'use strict';

  // --- Constants & Brand Colors ---
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
    grass: 0x496D42,
    grassDark: 0x3D5C38,
    sidewalk: 0x747970,
    curb: 0x737870,
    buildingColors: [0xF5F6FA, 0xE9ECF2, 0xDDE1EA, 0xC6CCD8],
    windowColor: 0x64748B,
    playerCar: 0xED4621, // Red car as in reference
    tramRed: 0xD32F2F,
    tramWhite: 0xF5F5F5
  };

  // --- Game State ---
  const ENVIRONMENT_GROUND = 0x86A97A;
  // Seasons follow the player's calendar (debug override via setSeason).
  // Each one tints ground, pavement, roofs and tree canopies, sets the light
  // and sky mood and decides what falls from the sky.
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
  function seasonFromDate() {
    const m = new Date().getMonth() + 1;
    return m >= 9 && m <= 11 ? 'autumn' : (m === 12 || m <= 2) ? 'winter' : 'summer';
  }
  let currentSeason = SEASONS[seasonFromDate()];
  const season = () => currentSeason;
  const state = {
    speed: 0,
    maxSpeed: 18, // m/s, follows the speed limit in force (see effectiveLimitKmH)
    baseLimitKmH: 60, // built-up area unless a sign says otherwise
    busBays: [], // bus bays in the world; walkers detour round them
    acceleration: 24, // m/s^2
    braking: 35, // m/s^2
    coasting: 10, // m/s^2
    isAccelerating: false,
    distanceTraveled: 0,
    targetLane: 1, // 0 = left, 1 = right
    currentLaneOffset: -1.8,
    targetLaneOffset: -1.8,
    laneWidth: 3.6,
    isAtSituation: false,
    isResolvingSituation: false,
    currentSituation: null,
    isDarkTheme: false,
    roadSegments: [],
    intersections: [],
    activeIntersection: null,
    actors: [],
    splinePoints: [],
    spline: null,
    splineLength: 0,
    carSplineDist: 0,
    score: 0
  };
  state.paused = false;
  state.oncoming = false;
  state.violationEpisode = 0;
  state.oncomingSeconds = 0;
  state.oncomingPenalized = false;
  state.resolution = null;
  state.driveFaults = new Set();
  state.lastSafePosition = new THREE.Vector3(-1.8, 0, 0);
  state.driveRecovery = 0;
  state.ambient = [];
  state.occluders = [];
  state.district = 0;
  state.viewportInsets = { top: 64, bottom: 150 };
  state.labels = { player: 'ВЫ' };
  const signTextureCache = new Map();

  // --- Three.js Globals ---
  let scene, camera, renderer;
  let dirLight, ambientLight, sunTarget;
  let playerCarGroup, playerWheels = [];
  let rainParticles = null;
  let terrainMesh = null;
  let streetLights = [];
  let nextSegmentZ = 0;
  let currentCorridor = null;
  let situationIndex = 0;
  let situationBag = [], lastSituationId = null;
  let container = document.getElementById('canvas-container');
  let gameAudio = null;

  // --- Situations Database (MVP set matching Russian PDD tickets) ---
  const SITUATIONS = [
  {
    "id": "ticket_1_13",
    "ticket": "Билет 1 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "При повороте направо Вы должны уступить дорогу:",
    "explanation": "При повороте направо или налево водитель обязан уступить дорогу пешеходам, переходящим проезжую часть дороги, на которую он поворачивает, лицам, использующим для передвижения средства индивидуальной мобильности (далее СИМ) и велосипедистам, независимо от того, регулируемый или нерегулируемый это перекресток.(Пункт 13.1 ПДД)",
    "pddRule": "п. 13.1",
    "options": [
      "Только велосипедисту",
      "Только пешеходам",
      "Пешеходам и велосипедисту",
      "Никому"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы направо",
        "color": "#ED4621"
      },
      {
        "label": "Велосипедист",
        "color": "#2BC280"
      },
      {
        "label": "Пешеход",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "cyclist",
        "id": "cyclist",
        "name": "Велосипедист",
        "badge": "Вело",
        "side": "cross_right_edge",
        "targetAction": "straight",
        "color": "#2BC280"
      },
      {
        "type": "pedestrian",
        "id": "pedestrian",
        "name": "Пешеход",
        "badge": "Пешеход",
        "side": "crosswalk_right",
        "targetAction": "cross",
        "color": "#0574F8"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_1_14",
    "ticket": "Билет 1 · Вопрос 14",
    "type": "crossroad_tram",
    "title": "Вы намерены проехать перекресток в прямом направлении. Кому Вы должны уступить дорогу?",
    "explanation": "Перекрёсток равнозначный. Трамваи в равнозначных условиях имеют преимущество перед безрельсовыми транспортными средствами. Между собой руководствуются «правилом правой руки». Помеха справа у трамвая «А». Соответственно первым проезжает трамвай «Б», за ним «А», Вы последним.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Обоим трамваям",
      "Только трамваю А",
      "Только трамваю Б",
      "Никому"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай А",
        "color": "#0574F8"
      },
      {
        "label": "Трамвай Б",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_b",
        "name": "Трамвай Б",
        "badge": "Б",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "type": "tram",
        "id": "tram_a",
        "name": "Трамвай А",
        "badge": "А",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_1_15",
    "ticket": "Билет 1 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество, а водители между собой руководствуются «правилом правой руки». Никому не уступая, первым проезжаете Вы, вторым автобус, легковой автомобиль последним, так как он находится на второстепенной дороге.(«Дорожные знаки», пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только автобусу",
      "Только легковому автомобилю",
      "Никому"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "bus",
        "id": "npc_bus",
        "name": "Автобус",
        "badge": "Автобус",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "badge": "Авто",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_2_13",
    "ticket": "Билет 2 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены повернуть налево. Кому Вы должны уступить дорогу?",
    "explanation": "Перекрёсток регулируемый. Знаки приоритета «не работают». При повороте налево Вы уступаете автобусу, движущемуся прямо со встречного направления, и пешеходам, переходящим проезжую часть дороги, на которую Вы поворачиваете.(Пункты 13.1, 13.3, 13.4 ПДД).",
    "pddRule": "п. 13.4",
    "options": [
      "Только пешеходам",
      "Только автобусу",
      "Автобусу и пешеходам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Пешеход",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "bus",
        "id": "npc_bus",
        "name": "Автобус",
        "badge": "Автобус",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "type": "pedestrian",
        "id": "pedestrian",
        "name": "Пешеход",
        "badge": "Пешеход",
        "side": "crosswalk_left",
        "targetAction": "cross",
        "color": "#0574F8"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_2_14",
    "ticket": "Билет 2 · Вопрос 14",
    "type": "crossroad",
    "title": "В каком случае Вы имеете преимущество?",
    "explanation": "Перекресток равнозначный. Водители между собой руководствуются «правилом правой руки», т. е. у кого помеха справа, тот и уступает. У Вас преимущество и при повороте направо и при повороте налево, т. е. в обоих перечисленных случаях.(Пункт 13.11 ПДД).",
    "pddRule": "п. 13.11",
    "options": [
      "Только при повороте направо",
      "Только при повороте налево",
      "В обоих перечисленных случаях"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Встречный автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Встречный автомобиль",
        "badge": "Встречный",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_2_15",
    "ticket": "Билет 2 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Обязан ли водитель мотоцикла уступить Вам дорогу?",
    "explanation": "Мотоциклист выезжает на дорогу, обозначенную знаком 5.1 «Автомагистраль», которая является главной дорогой по отношению к примыкающей. На перекрёстке неравнозначных дорог преимущество имеют транспортные средства, движущиеся по главной дороге. Мотоциклист обязан уступить Вам дорогу.(Пункты 1.2, 13.9 ПДД).",
    "pddRule": "п. 13.9",
    "options": [
      "Обязан",
      "Не обязан"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Мотоцикл",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "motorcycle",
        "id": "npc_moto",
        "name": "Мотоцикл",
        "badge": "Мото",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_3_13",
    "ticket": "Билет 3 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "При движении прямо Вы:",
    "explanation": "Перекрёсток регулируемый. В этом случае знаки приоритета, а в их число входит и знак 2.5 «Движение без остановки запрещено», согласно принципу приоритетности регулирования дорожного движения, «не работают», т.е. ими мы не руководствуемся. Горит зелёный сигнал светофора. Продолжаете движение через перекрёсток без остановки.(Пункты 6.2, 6.15, 13.3 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Должны остановиться перед стоп-линией",
      "Можете продолжить движение через перекрёсток без остановки",
      "Должны уступить дорогу транспортным средствам, движущимся с других направлений"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль слева",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "badge": "Авто",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": [
      {
        "code": "2.5",
        "name": "STOP"
      }
    ]
  },
  {
    "id": "ticket_3_14",
    "ticket": "Билет 3 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены повернуть направо. Ваши действия?",
    "explanation": "Перекрёсток равнозначный. Водители при определении порядка проезда перекрёстка руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает дорогу. У Вас помехи справа при повороте направо нет, т.к. при повороте направо Ваша траектория не пересекается с мотоциклом. Проезжаете перекресток первым.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проедете перекрёсток первым",
      "Уступите дорогу легковому автомобилю",
      "Уступите дорогу обоим транспортным средствам"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы направо",
        "color": "#ED4621"
      },
      {
        "label": "Легковой авто",
        "color": "#2BC280"
      },
      {
        "label": "Мотоцикл",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Легковой авто",
        "badge": "Авто",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#2BC280"
      },
      {
        "type": "motorcycle",
        "id": "npc_moto",
        "name": "Мотоцикл",
        "badge": "Мото",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_3_15",
    "ticket": "Билет 3 · Вопрос 15",
    "type": "crossroad_tram",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество; между собой безрельсовые транспортные средства руководствуются «правилом правой руки», уступая трамваю, имеющему преимущество в равнозначных условиях. Трамвай «А» проезжает первым, Вы после него. Легковой автомобиль и трамвай «Б» одновременно, так как их траектории не пересекаются.(«Дорожные знаки», пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Трамваям А и Б",
      "Трамваю А и легковому автомобилю",
      "Только трамваю А",
      "Никому"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай А",
        "color": "#0574F8"
      },
      {
        "label": "Трамвай Б",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_a",
        "name": "Трамвай А",
        "badge": "А",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#0574F8"
      },
      {
        "type": "tram",
        "id": "tram_b",
        "name": "Трамвай Б",
        "badge": "Б",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "badge": "Авто",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_4_13",
    "ticket": "Билет 4 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены проехать перекрёсток в прямом направлении. Ваши действия?",
    "explanation": "Перекресток регулируемый. Первым проедет «оперативник» со специальными сигналами, который может отступать от требований сигналов светофора. Другие водители должны обеспечить ему беспрепятственный проезд перекрёстка. Водитель грузовика обязан уступить Вам, т.е. транспортному средству, движущемуся прямо со встречного направления.(Пункты 3.1, 3.2, 13.3, 13.4 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Проедете перекресток первым",
      "Уступите дорогу только встречному автомобилю",
      "Уступите дорогу только автомобилю с включенными проблесковым маячком и специальным звуковым сигналом",
      "Уступите дорогу обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Спецмашина",
        "color": "#0574F8"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "special",
        "id": "npc_special",
        "name": "Спецмашина",
        "badge": "Спец",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#0574F8"
      },
      {
        "type": "truck",
        "id": "npc_truck",
        "name": "Грузовик",
        "badge": "Грузовик",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_4_14",
    "ticket": "Билет 4 · Вопрос 14",
    "type": "crossroad_traffic_light",
    "title": "Кому Вы должны уступить дорогу при повороте направо?",
    "explanation": "Первоначально Вы должны уступить дорогу пешеходу, находящемуся на нерегулируемом пешеходном переходе. (Пункт 14.1 ПДД). В последующем, при повороте направо уступите дорогу пешеходам, переходящим проезжую часть дороги, на которую Вы поворачиваете. (Пункт 13.1 ПДД). Так же Вы должны поступить и с лицами, использующими для передвижения СИМ. Это правило распространяется при проезде как регулируемых, так и нерегулируемых перекрестков.",
    "pddRule": "п. 14.1",
    "options": [
      "Только пешеходу, переходящему проезжую часть по нерегулируемому пешеходному переходу",
      "Только пешеходам, переходящим проезжую часть, на которую Вы поворачиваете",
      "Всем пешеходам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы направо",
        "color": "#ED4621"
      },
      {
        "label": "Пешеход 1",
        "color": "#0574F8"
      },
      {
        "label": "Пешеход 2",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "pedestrian",
        "id": "ped_1",
        "name": "Пешеход",
        "badge": "Пешеход",
        "side": "crosswalk_right",
        "targetAction": "cross",
        "color": "#0574F8"
      },
      {
        "type": "pedestrian",
        "id": "ped_2",
        "name": "Пешеход",
        "badge": "Пешеход",
        "side": "crosswalk_left",
        "targetAction": "cross",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_4_15",
    "ticket": "Билет 4 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Как Вам следует поступить при выполнении разворота?",
    "explanation": "Перекрёсток неравнозначный. Транспортные средства, находящиеся на главной дороге, имеют преимущество. При повороте налево и развороте Вы уступаете дорогу транспортным средствам, движущимся прямо со встречного направления. В данной ситуации уступаете дорогу только легковому автомобилю.(Пункты 13.9, 13.12 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Проехать перекресток первым",
      "Уступить дорогу только легковому автомобилю",
      "Уступить дорогу обоим транспортным средствам"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы на разворот",
        "color": "#ED4621"
      },
      {
        "label": "Встречный автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Встречный автомобиль",
        "badge": "Встречный",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_5_13",
    "ticket": "Билет 5 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены развернуться. Ваши действия?",
    "explanation": "Перекрёсток регулируемый. Правая рука регулировщика вытянута вперёд. Со стороны левого бока транспортные средства могут продолжить движение в любом направлении, соблюдая правила расположения транспортных средств на проезжей части.Производя разворот из крайней левой полосы, у Вас будет помеха справа. Вы уступите дорогу легковому автомобилю, поворачивающему направо. (Пункты 6.10, 13.4 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Проедете перекресток первым",
      "Выполните разворот, уступив дорогу легковому автомобилю",
      "Дождетесь, когда регулировщик опустит правую руку"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы на разворот",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "badge": "Авто",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_5_14",
    "ticket": "Билет 5 · Вопрос 14",
    "type": "crossroad_tram",
    "title": "Кому Вы должны уступить дорогу при движении в прямом направлении?",
    "explanation": "Перекрёсток равнозначный. В равнозначных условиях трамвай имеет преимущество, а безрельсовые транспортные средства между собой руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает.Уступаете дорогу в данной ситуации только трамваю.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только трамваю",
      "Только легковому автомобилю",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      },
      {
        "label": "Легковой автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "badge": "Трамвай",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#0574F8"
      },
      {
        "type": "car",
        "id": "npc_car",
        "name": "Легковой автомобиль",
        "badge": "Авто",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_5_15",
    "ticket": "Билет 5 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Как Вам следует поступить при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Проблесковый маячок жёлтого цвета на грузовике преимущество ему не предоставляет. Преимущество имеют транспортные средства, находящиеся на главной дороге. Вы проезжаете первым, после Вас проезжают автомобили, находящиеся на второстепенной дороге, которые между собой руководствуются «правилом правой руки». Легковой автомобиль проедет вторым, грузовик - последним.(Пункты 3.4, 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Проехать перекрёсток первым",
      "Уступить дорогу только грузовому автомобилю с включенным проблесковым маячком",
      "Уступить дорогу обоим транспортным средствам"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_6_13",
    "ticket": "Билет 6 · Вопрос 13",
    "type": "crossroad_tram",
    "title": "Вы намерены повернуть налево. Ваши действия?",
    "explanation": "Светофор с сигналами бело-лунного цвета, предназначенный для водителей маршрутных транспортных средств, разрешает им движение прямо.Согласно зелёного сигнала светофора, разрешено движение и Вам в любом направлении.Для поворота налево, Вы должны пропустить трамвай, перестроиться на трамвайные пути попутного направления и с них выполнить поворот налево. (Пункты 6.2, 6.8, 8.5).",
    "pddRule": "п. 13.4",
    "options": [
      "Проедете перекресток первым",
      "Уступите дорогу трамваю, выполнив поворот с проезжей части",
      "Пропустите трамвай, перестроитесь на трамвайные пути попутного направления и выполните с них поворот"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_6_14",
    "ticket": "Билет 6 · Вопрос 14",
    "type": "crossroad_traffic_light",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "На перекрёстках, независимо регулируемые они или нет, при повороте налево или направо водитель обязан уступить дорогу пешеходам, переходящим проезжую часть, на которую он поворачивает. Следует уступить и велосипедисту, движущемуся навстречу прямо.(Пункты 13.1, 13.2 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только пешеходам",
      "Пешеходам и велосипедисту",
      "Никому"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_6_15",
    "ticket": "Билет 6 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "В каком случае Вы должны будете уступить дорогу автомобилю ДПС?",
    "explanation": "В данном случае Вы должны уступить дорогу «оперативнику», если на данном автомобиле одновременно будут включены проблесковые маячки синего цвета и специальный звуковой сигнал.(Пункт 3.2 ПДД)",
    "pddRule": "п. 3.2",
    "options": [
      "Если на автомобиле ДПС будут включены проблесковые маячки синего цвета",
      "Если на автомобиле ДПС одновременно будут включены проблесковые маячки синего цвета и специальный звуковой сигнал",
      "В любом"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_7_13",
    "ticket": "Билет 7 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Как Вам следует поступить при повороте налево?",
    "explanation": "Остановка не далее стоп-линии обязательна при запрещающем сигнале светофора. Вам же горит «зелёный». Без остановки выезжаете на перекрёсток и перед поворотом налево останавливаетесь, чтобы уступить дорогу легковому автомобилю, движущемуся прямо со встречного направления.(«Горизонтальная разметка», пункты 6.13, 6.2, 13.3, 13.4 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Проехать перекресток первым",
      "Выехать за стоп-линию и остановиться на перекрестке, чтобы уступить дорогу встречному автомобилю",
      "Остановиться перед стоп-линией и после проезда легкового автомобиля повернуть налево"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_7_14",
    "ticket": "Билет 7 · Вопрос 14",
    "type": "crossroad",
    "title": "Разрешено ли Вам выехать на перекресток, за которым образовался затор?",
    "explanation": "В данной ситуации Вы можете выехать на перекресток только для поворота, так как образовавшийся затор делает невозможным движение в прямом направлении без вынужденной остановки на перекрестке, а это создаст препятствие для движения в поперечном направлении.(Пункт 13.2 ПДД).",
    "pddRule": "п. 13.2",
    "options": [
      "Разрешено",
      "Разрешено, если Вы намерены выполнить поворот",
      "Запрещено"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Встречный автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Встречный автомобиль",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_7_15",
    "ticket": "Билет 7 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Вы намерены продолжить движение прямо. Кому Вы обязаны уступить дорогу?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество, между собой руководствуются «правилом правой руки». После их проезда, пользуясь этим же правилом, проезжают транспортные средства, находящиеся на второстепенной дороге. Первым проезжаете Вы, никому не уступая, мотоциклист – вторым, грузовик – третьим, легковой автомобиль – последним.(«Дорожные знаки», пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только мотоциклу",
      "Мотоциклу и легковому автомобилю",
      "Никому"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_8_13",
    "ticket": "Билет 8 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Кто из водителей, выполняющих поворот, нарушит Правила?",
    "explanation": "Знак 4.1.1 «Движение прямо» в данном случае установлен непосредственно перед пересечением проезжих частей, т.е перед перекрестком. Можно продолжать движение только прямо. В данной ситуации нарушают Правила оба водителя.(«Дорожные знаки»)",
    "pddRule": "п. 13.4",
    "options": [
      "Оба",
      "Только водитель легкового автомобиля",
      "Только водитель мотоцикла",
      "Никто не нарушит"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_8_14",
    "ticket": "Билет 8 · Вопрос 14",
    "type": "crossroad_priority_signs",
    "title": "Вы намерены продолжить движение в прямом направлении. Ваши действия?",
    "explanation": "Перекрёсток равнозначный. При определении порядка проезда перекрёстка транспортными средствами руководствуемся «правилом правой руки», т.е. у кого помеха справа тот и уступает. Особенность решения этого вопроса - в выкатывании и остановке на перекрёстке транспортного средства, начинающего движение. Первым начинает движение водитель легкового автомобиля, поворачивающий налево, поскольку он в первоначальный момент не имеет помехи справа. Доехав до середины перекрёстка, перед тем как повернуть налево, он остановится, так как должен уступить дорогу мотоциклисту, находящемуся от него справа. После этого на траектории движения Вашего автомобиля помеха справа будет отсутствовать - проезжаете перекрёсток первым. Мотоциклист после Вас. И последним закончит проезд перекрёстка водитель, который начинал движение.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проедете перекресток первым",
      "Уступите дорогу легковому автомобилю",
      "Уступите дорогу легковому автомобилю и мотоциклу"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_8_15",
    "ticket": "Билет 8 · Вопрос 15",
    "type": "crossroad_tram",
    "title": "Кому Вы должны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество. Между собой безрельсовые транспортные средства руководствуются «правилом правой руки», уступая дорогу трамваю, который в равнозначных условиях имеет перед ними преимущество. Первым проезжает трамвай «Б», после него легковой автомобиль, Вы после них. Последним проедет трамвай «А», так как он находится на второстепенной дороге.(Пункты 13.9, 13.1, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только трамваям",
      "Трамваю Б и легковому автомобилю",
      "Всем транспортным средствам"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_9_13",
    "ticket": "Билет 9 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Разрешено ли Вам выехать на перекресток, за которым образовался затор?",
    "explanation": "Перекрёсток регулируемый. Вам «зелёный свет», но впереди «пробка». Если Вы выедете на перекрёсток для движения в прямом направлении, то при смене сигналов будете оказывать помехи движению, особенно в поперечном направлении. Поэтому на перекрёсток Вы можете выехать только для поворота направо или налево.(Пункты 6.2, 13.2 ПДД).(14.12.18 обновлен вариант ответа (правильный). Теперь нельзя выезжать на перекресток с затором, если вы собираетесь сделать разворот)",
    "pddRule": "п. 13.4",
    "options": [
      "Разрешено",
      "Разрешено, если Вы намерены выполнить поворот",
      "Запрещено"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_9_14",
    "ticket": "Билет 9 · Вопрос 14",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены продолжить движение в прямом направлении. Ваши действия?",
    "explanation": "Перекрёсток нерегулируемый, равнозначный. При разводке транспортных средств руководствуемся «правилом правой руки», т.е. у кого помеха справа, тот и уступает. Вы обязаны уступить дорогу грузовику.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проедете перекресток первым",
      "Уступите дорогу грузовому автомобилю"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_9_15",
    "ticket": "Билет 9 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество. А между собой руководствуются «правилом правой руки». У Вас помехи справа нет. Проезжаете первым, водитель легкового автомобиля после Вас, автобус последним, так как находится на второстепенной дороге.(Пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только автобусу",
      "Только легковому автомобилю",
      "Никому"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_10_13",
    "ticket": "Билет 10 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "При включении зелёного сигнала светофора Вам следует:",
    "explanation": "Грузовик закрывает обзорность справа, откуда могут неожиданно появиться пешеходы, начавшие движение после смены сигнала светофора. Следует убедиться в отсутствии ТС, завершающих движение через перекресток. Поэтому поступите с максимальной осторожностью.(Пункт 13.8 ПДД)",
    "pddRule": "п. 13.8",
    "options": [
      "Сразу начать движение",
      "Начать движение, убедившись в отсутствии только пешеходов, завершающих переход проезжей части",
      "Начать движение, убедившись в отсутствии пешеходов и транспортных средств, завершающих движение после смены сигнала светофора"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_10_14",
    "ticket": "Билет 10 · Вопрос 14",
    "type": "crossroad_tram",
    "title": "Вы намерены проехать перекрёсток в прямом направлении. Кому Вы обязаны уступить дорогу?",
    "explanation": "Перекрёсток равнозначный. В равнозначных условиях трамвай имеет преимущество, а безрельсовые транспортные средства руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. Вы уступаете и трамваю, и грузовому автомобилю, которые проедут перекрёсток одновременно, т.к. их траектории движения не пересекаются.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только трамваю",
      "Только грузовому автомобилю",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_10_15",
    "ticket": "Билет 10 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы должны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Преимуществом пользуются транспортные средства, находящиеся на главной дороге, которые между собой руководствуются «правилом правой руки». Вы проезжаете первым, так как для легкового автомобиля Вы являетесь помехой справа, а автобус находится на второстепенной дороге.(Пункты 13.3, 13.10 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только автобусу",
      "Только легковому автомобилю",
      "Никому"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_11_13",
    "ticket": "Билет 11 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Обязаны ли Вы при повороте направо уступить дорогу автомобилю, выполняющему разворот?",
    "explanation": "При движении «под дополнительную секцию», включённую одновременно с основным красным сигналом светофора, Вы обязаны уступить дорогу ВСЕМ движущимся с других направлений, независимо от их дальнейшего направления движения.(Пункт 13.5 ПДД)",
    "pddRule": "п. 13.5",
    "options": [
      "Обязаны",
      "Не обязаны"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_11_14",
    "ticket": "Билет 11 · Вопрос 14",
    "type": "crossroad",
    "title": "В каком случае Вы имеете право проехать перекресток первым?",
    "explanation": "Перекрёсток равнозначный. Водители руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. Помеха справа у водителя легкового автомобиля. Вы проезжаете перекрёсток первым при движении прямо и налево. При развороте у Вас справа будет помеха.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только при движении прямо",
      "При движении прямо и налево",
      "При движении прямо, налево и в обратном направлении"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Встречный автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Встречный автомобиль",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_11_15",
    "ticket": "Билет 11 · Вопрос 15",
    "type": "crossroad_tram",
    "title": "Вы намерены продолжить движение прямо. При жёлтом мигающем сигнале светофора следует:",
    "explanation": "При жёлтом мигающем сигнале светофора перекрёсток является нерегулируемым. Согласно знакам приоритета – неравнозначным. Транспортные средства, находящиеся на главной дороге, имеют преимущество. Вы проезжаете первым, никому не уступая, так как трамвай и грузовик находятся на второстепенной дороге.(Пункты 13.3, 13.9 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Проехать перекрёсток первым",
      "Уступить дорогу только грузовому автомобилю",
      "Уступить дорогу только трамваю",
      "Уступить дорогу обоим транспортным средствам"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_12_13",
    "ticket": "Билет 12 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены повернуть направо. Ваши действия?",
    "explanation": "Руки регулировщика опущены («Грудь, спина – стена»). Со стороны правого и левого бока разрешено движение безрельсовым транспортным средствам прямо и направо, пешеходам разрешено переходить проезжую часть. (Пункт 6.10 ПДД). При повороте направо вы обязаны уступить дорогу пешеходам, переходящим проезжую часть дороги, на которую поворачиваете.(Пункт 13.1 ПДД)",
    "pddRule": "п. 6.10",
    "options": [
      "Повернете направо, не уступая дорогу пешеходам",
      "Повернете направо, уступив дорогу пешеходам",
      "Остановитесь перед перекрестком и дождетесь другого сигнала регулировщика"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_12_14",
    "ticket": "Билет 12 · Вопрос 14",
    "type": "crossroad_priority_signs",
    "title": "При движении в каком направлении Вы должны уступить дорогу автомобилю с включенными проблесковым маячком и специальным звуковым сигналом?",
    "explanation": "Вы обязаны обеспечить беспрепятственный проезд перекрёстка «оперативнику» с включенными специальными сигналами независимо от направления его движения. Сделать это необходимо при движении в любом направлении.(Пункты 3.1, 3.2 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только налево",
      "Налево и в обратном направлении",
      "В любом"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_12_15",
    "ticket": "Билет 12 · Вопрос 15",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены продолжить движение прямо. Ваши действия при жёлтом мигающем сигнале светофора?",
    "explanation": "При жёлтом мигающем сигнале светофора перекрёсток является нерегулируемым, неравнозначным. Главная дорога меняет направление. Преимущество имеют транспортные средства, находящиеся на главной дороге, которые между собой руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. У Вас помеха справа, уступаете дорогу только легковому автомобилю.(«Дорожные знаки», пункты 13.3, 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Уступите дорогу обоим транспортным средствам",
      "Уступите дорогу только трамваю",
      "Уступите дорогу только автомобилю",
      "Проедете первым"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_13_13",
    "ticket": "Билет 13 · Вопрос 13",
    "type": "crossroad_tram",
    "title": "В данной ситуации Вы не обязаны уступать дорогу трамваю при движении:",
    "explanation": "Перекресток регулируемый. Светофор с одноцветной сигнализацией, предназначенный для маршрутных ТС, разрешает движение прямо. Трамвай, поворачивающий направо, дожидается смены сигнала. Зеленый сигнал светофора разрешает Вам движение – проезжайте перекресток прямо первым.(Пункты 6.2, 6.8 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Прямо или направо",
      "Только прямо",
      "Только направо"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_13_14",
    "ticket": "Билет 13 · Вопрос 14",
    "type": "crossroad_traffic_light",
    "title": "Кто из водителей, выполняющих поворот, должен уступить дорогу пешеходам?",
    "explanation": "При повороте направо или налево при проезде перекрёстков, как регулируемых, так и нерегулируемых, водитель обязан уступить дорогу пешеходам, переходящим проезжую часть дороги, на которую он поворачивает. Оба водителя уступают дорогу пешеходам.(Пункт 13.1 ПДД)",
    "pddRule": "п. 13.1",
    "options": [
      "Только водитель легкового автомобиля",
      "Только водитель грузового автомобиля",
      "Оба"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_13_15",
    "ticket": "Билет 13 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Можете ли Вы в данной ситуации приступить к повороту налево?",
    "explanation": "Перекрёсток неравнозначный. Транспортные средства, находящиеся на главной дороге, имеют преимущество. Но так как Ваша траектория движения не пересекается с грузовиком, можете совершить движение через перекрёсток одновременно, при этом Вы должны учитывать преимущество грузовика, т.е. не создавать ему помех.(«Дорожные знаки», пункты 1.2 термин «Уступить дорогу», 13.9 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Можете",
      "Можете, только убедившись в том, что не создадите помех встречному автомобилю, выполняющему поворот налево",
      "Не можете"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_14_13",
    "ticket": "Билет 14 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "При включении зелёного сигнала светофора Вы должны уступить дорогу:",
    "explanation": "Правила предусматривают такую ситуацию. При включении разрешающего сигнала светофора водитель обязан уступить дорогу транспортным средствам, завершающим движение через перекрёсток.У Вас именно такая ситуация – уступаете дорогу всем автомобилям, находящимся в границах перекрестка, в данном случае – обоим автомобилям.(Пункт 13.8 ПДД)",
    "pddRule": "п. 13.8",
    "options": [
      "Только грузовому автомобилю, завершающему разворот на перекрёстке",
      "Только легковому автомобилю",
      "Обоим автомобилям"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_14_14",
    "ticket": "Билет 14 · Вопрос 14",
    "type": "crossroad_tram",
    "title": "Вы намерены проехать перекрёсток в прямом направлении. Кому Вы обязаны уступить дорогу?",
    "explanation": "Перекрёсток равнозначный. В равнозначных условиях трамваи имеют преимущество. В данной ситуации траектории движения трамваев не пересекаются, проезжают перекрёсток одновременно. Вы – после них.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только трамваю А",
      "Только трамваю Б",
      "Обоим трамваям"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_14_15",
    "ticket": "Билет 14 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "При повороте налево Вы:",
    "explanation": "Перекрёсток неравнозначный. Преимущество имеют транспортные средства, находящиеся на главной дороге. При повороте налево следует уступить дорогу транспортным средствам, движущимся прямо со встречного направления. Вы должны уступить только автобусу.(Пункты 13.9, 13.12 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Имеете преимущество",
      "Должны уступить дорогу только автобусу",
      "Должны уступить дорогу легковому автомобилю и автобусу"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_15_13",
    "ticket": "Билет 15 · Вопрос 13",
    "type": "crossroad_tram",
    "title": "В каком случае Вы обязаны пропустить трамвай?",
    "explanation": "Перекресток регулируется светофором, траектории движения трамвая и ваша пересекаются. Находясь в равнозначных условиях трамвай имеет преимущество перед безрельсовыми Т.С.Вы уступаете дорогу в обоих перечисленных случаях.(Пункты 6.2, 13.6 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "При повороте налево, перестроившись на трамвайные пути попутного направления",
      "При движении прямо",
      "В обоих перечисленных случаях"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_15_14",
    "ticket": "Билет 15 · Вопрос 14",
    "type": "crossroad_tram",
    "title": "При движении в прямом направлении, Вам следует:",
    "explanation": "Перекрёсток равнозначный. Трамвай в равнозначных условиях имеет преимущество перед безрельсовыми транспортными средствами. Проезжает первым. Вы с водителем легкового автомобиля руководствуетесь «правилом правой руки». У Вас помехи справа нет. Проезжаете перекрёсток, уступая только трамваю.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проехать перекрёсток первым",
      "Уступить дорогу только трамваю",
      "Уступить дорогу трамваю и легковому автомобилю"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_15_15",
    "ticket": "Билет 15 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы должны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество, между собой руководствуются «правилом правой руки». У Вас помеха справа, уступаете автобусу. Легковой автомобиль проедет последним, так как находится на второстепенной дороге.(Пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только автобусу",
      "Только легковому автомобилю",
      "Никому"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_16_13",
    "ticket": "Билет 16 · Вопрос 13",
    "type": "crossroad_tram",
    "title": "Вы намерены проехать перекрёсток в прямом направлении. Кому вы должны уступить дорогу?",
    "explanation": "Перекрёсток регулируемый. Трамвай в равнозначных условиях имеет преимущество перед безрельсовыми транспортными средствами. Проезжает первым. Легковой автомобиль при повороте налево обязан уступить дорогу транспортным средствам, движущимся со встречного направления прямо и направо. Вы уступаете дорогу только трамваю.(Пункты 13.3, 13.4, 13.6 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Трамваю и автомобилю",
      "Только трамваю",
      "Никому"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "type": "tram",
        "id": "tram_1",
        "name": "Трамвай",
        "side": "left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_16_14",
    "ticket": "Билет 16 · Вопрос 14",
    "type": "crossroad_priority_signs",
    "title": "При въезде на перекрёсток Вы:",
    "explanation": "При въезде на перекресток, на котором организовано круговое движение, обозначенный знаком 4.3 «Круговое движение», Вы обязаны уступить дорогу всем ТС, движущимся по такому перекрестку.(Пункт 13.11.1 ПДД)(Изменения ПДД от 8 ноября 2017)",
    "pddRule": "п. 13.11.1",
    "options": [
      "Должны уступить дорогу обоим транспортным средствам",
      "Должны уступить дорогу только автомобилю",
      "Имеете преимущество перед обоими транспортными средствами"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_16_15",
    "ticket": "Билет 16 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Преимущество имеют транспортные средства, находящиеся на главной дороге. Вы находитесь на второстепенной дороге и уступаете обоим транспортным средствам, независимо от направления их дальнейшего движения.(«Дорожные знаки», пункт 13.9 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только автобусу",
      "Только легковому автомобилю",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_17_13",
    "ticket": "Билет 17 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Обязаны ли Вы уступить дорогу автобусу?",
    "explanation": "«Правило правой руки» универсально. Оно не работает в двух случаях – один из случаев, когда ТС движется под дополнительную секцию, включенную одновременно с основным желтым или красным сигналом. В данной ситуации Вы обязаны уступить дорогу всем ТС, движущимся с других направлений. Вы обязаны уступить дорогу автобусу.(Пункт 13.5 ПДД)",
    "pddRule": "п. 13.5",
    "options": [
      "Обязаны",
      "Не обязаны"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_17_14",
    "ticket": "Билет 17 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены повернуть налево. Ваши действия?",
    "explanation": "Перекрёсток равнозначный. При «разводке» транспортных средств руководствуемся «правилом правой руки», т.е. у кого помеха справа, тот и уступает. Первым проедет грузовик, движущийся прямо, после него грузовик с маячком оранжевого цвета (который не предоставляет «преимущество»), последним Вы.(«Дорожные знаки», пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Уступите дорогу обоим грузовым автомобилям",
      "Выехав на перекрёсток, уступите дорогу встречному грузовому автомобилю и завершите поворот",
      "Проедете перекресток первым"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Встречный автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Встречный автомобиль",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_17_15",
    "ticket": "Билет 17 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "После въезда на этот перекресток:",
    "explanation": "После въезда на перекресток, на котором организовано круговое движение, обозначенный знаком 4.3 «Круговое движение», Вы будете иметь преимущество в движении перед легковым автомобилем, поскольку при въезде на этот перекресток его водитель обязан уступить дорогу ТС, движущимся по нему п. 13.11.1.(Изменения ПДД от 8 ноября 2017)",
    "pddRule": "п. 13.11.1",
    "options": [
      "Вы должны уступить дорогу легковому автомобилю, въезжающему на него",
      "Вы будете иметь преимущество перед легковым автомобилем, въезжающим на него",
      "Вам следует действовать по взаимной договоренности с водителем легкового автомобиля"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_18_13",
    "ticket": "Билет 18 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Обязаны ли Вы уступить дорогу легковому автомобилю при повороте направо?",
    "explanation": "Перекрёсток регулируемый. Знаки приоритета «не работают». При повороте налево водитель легкового автомобиля обязан уступить дорогу транспортным средствам, движущимся со встречного направления прямо или направо. У Вас преимущество.(Пункты 13.3, 13.4 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Обязаны",
      "Обязаны, если легковой автомобиль поворачивает налево",
      "Не обязаны"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_18_14",
    "ticket": "Билет 18 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены выполнить разворот. Ваши возможные действия?",
    "explanation": "Перекрёсток равнозначный. Водители ТС, траектории которых пересекаются в границах перекрестка, руководствуются «правилом правой руки».Правильный ответ – допускаются оба варианта действий.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Отказаться от преимущества в движении и приступить к развороту после проезда легкового автомобиля",
      "Выехать на перекресток первым и, уступив дорогу легковому автомобилю, закончить разворот",
      "Допускаются оба варианта действий"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Встречный автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Встречный автомобиль",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_18_15",
    "ticket": "Билет 18 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Вы намерены проехать перекрёсток в прямом направлении. В данной ситуации:",
    "explanation": "Перекрёсток неравнозначный. Специальный жёлтый мигающий сигнал на грузовике преимуществ не предоставляет. Транспортные средства находятся на равнозначной дороге. При повороте налево водитель грузовика обязан уступить дорогу Вам, движущемуся прямо со встречного направления.Проезжаете перекресток первым.(«Дорожные знаки», пункты 3.4, 13.12 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Вы обязаны уступить дорогу грузовому автомобилю",
      "Вы имеете право проехать перекресток первым"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_19_13",
    "ticket": "Билет 19 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены проехать перекрёсток в прямом направлении. Ваши действия?",
    "explanation": "Перекрёсток регулируемый. Вы продолжаете движение под дополнительную секцию светофора, включенную одновременно с основным красным сигналом светофора без остановки у стоп-линии. Но в этом случае, продолжая движение, необходимо учитывать, что уступаете дорогу всем транспортным средствам, движущимся с других направлений. В случае создания помехи, Вы создадите опасную ситуацию, которая может перейти в аварийную, и тогда Вы станете виновником ДТП.(Пункты 13.3, 13.5 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Остановитесь перед стоп-линией",
      "Продолжите движение, уступая дорогу легковому автомобилю",
      "Продолжите движение, имея преимущество перед легковым автомобилем"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_19_14",
    "ticket": "Билет 19 · Вопрос 14",
    "type": "crossroad",
    "title": "Как Вам следует поступить при повороте направо?",
    "explanation": "Перекрёсток равнозначный. Водители руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. Мотоциклист и легковой автомобиль имеют помеху справа. У Вас помехи нет, проедете перекрёсток первым, вторым - легковой автомобиль, мотоциклист - последним.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проехать перекрёсток первым",
      "Уступить дорогу только легковому автомобилю",
      "Уступить дорогу легковому автомобилю и мотоциклу"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Встречный автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Встречный автомобиль",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_19_15",
    "ticket": "Билет 19 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Если невозможно определить наличие покрытия на дороге (темное время суток, грязь, снег и тому подобное), а знаков приоритета нет, то:",
    "explanation": "Если водитель не может определить наличие покрытия на дороге (темное время суток, грязь, снег и тому подобное), а знаков приоритета нет, он должен считать, что находится на второстепенной дороге(Дорожные знаки, пункт 13.13 ПДД)",
    "pddRule": "п. 13.13",
    "options": [
      "Вы имеете право считать, что находитесь на главной дороге",
      "Вам следует считать, что находитесь на равнозначной дороге",
      "Вы должны считать, что находитесь на второстепенной дороге"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_20_13",
    "ticket": "Билет 20 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток регулируемый. При повороте налево Вы обязаны уступить дорогу легковому автомобилю, движущемуся прямо со встречного направления, и пешеходам, переходящим проезжую часть дороги, на которую поворачиваете.(Пункты 13.1, 13.4 ПДД)",
    "pddRule": "п. 13.4",
    "options": [
      "Только встречному автомобилю",
      "Только пешеходам",
      "Встречному автомобилю и пешеходам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "clear_crossroad",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "red"
    },
    "signs": []
  },
  {
    "id": "ticket_20_14",
    "ticket": "Билет 20 · Вопрос 14",
    "type": "crossroad",
    "title": "При повороте направо Вам следует:",
    "explanation": "Перекрёсток равнозначный. При определении порядка проезда перекрёстка водители руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. У Вас помеха справа отсутствует, проезжаете перекрёсток первым.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Уступить дорогу легковому автомобилю",
      "Проехать перекрёсток первым"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Встречный автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Встречный автомобиль",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_20_15",
    "ticket": "Билет 20 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество, между собой руководствуются «правилом правой руки». После их проезда этим же правилом пользуются транспортные средства, находящиеся на второстепенной дороге. Первым проезжает мотоциклист, вторым – автобус, далее легковой автомобиль. Вы последним, уступив всем транспортным средствам.(«Дорожные знаки», пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Автобусу и мотоциклу",
      "Легковому автомобилю и автобусу",
      "Всем транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "type": "car",
        "id": "npc_car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_21_13",
    "ticket": "Билет 21 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Кому Вы должны уступить дорогу при повороте налево.",
    "explanation": "Перекрёсток регулируемый. Знаки приоритета «не работают». Первым на красный сигнал светофора выезжает на перекрёсток «оперативник» (от сигналов светофора он имеет право отступать) с включенными проблесковым маячком и специальным звуковым сигналом, которому остальные обязаны обеспечить беспрепятственный проезд. При повороте налево Вы уступаете дорогу мотоциклисту, движущемуся прямо со стороны встречного направления. Проезжаете перекрёсток последним, уступая обоим транспортным средствам.(Пункты 3.1, 3.2, 13.3, 13.4 ПДД)",
    "pddRule": "п. 3.1",
    "options": [
      "Только мотоциклу",
      "Только автомобилю с включенными проблесковым маячком и специальным звуковым сигналом",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Спецмашина",
        "color": "#0574F8"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_special",
        "type": "special",
        "name": "Спецмашина",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#0574F8",
        "beacon": "blue",
        "siren": true
      },
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#8B5CF6"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_21_14",
    "ticket": "Билет 21 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены повернуть налево. Ваши действия?",
    "explanation": "Перекрёсток равнозначный. Водители между собой руководствуются «правилом правой руки». У Вас помеха справа. У мотоциклиста тоже. Отсутствует помеха справа у водителя легкового автомобиля, траектория движения которого не пересекается с Вашей. Он проезжает первым, мотоциклист – вторым, Вы – последним.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проедете перекрёсток первым",
      "Проедете перекресток одновременно со встречным автомобилем до проезда мотоцикла",
      "Проедете перекрёсток последним"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "opposite",
        "targetAction": "turn_right",
        "color": "#2BC280"
      },
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#8B5CF6"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_21_15",
    "ticket": "Билет 21 · Вопрос 15",
    "type": "crossroad",
    "title": "Как Вам следует поступить при движении в прямом направлении?",
    "explanation": "В прямом направлении дорога с твердым покрытием. Грузовик будет выезжать на перекресток с грунтовой дороги, которая в данной ситуации является второстепенной. Перекресток неравнозначный. Вы двигаетесь на главной дороге, поэтому проезжаете перекресток первым.(Пункты 1.2 термин «Главная дорога», 13.9 ПДД)",
    "pddRule": "п. 1.2",
    "options": [
      "Уступить дорогу грузовому автомобилю, выезжающему с грунтовой дороги",
      "Проехать перекресток первым"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_22_13",
    "ticket": "Билет 22 · Вопрос 13",
    "type": "crossroad",
    "title": "Вы намерены повернуть налево. Ваши действия?",
    "explanation": "Зеленый сигнал светофора дает вам право двигаться налево п. 6.2. При этом вы должны выехать в намеченном направлении независимо от сигнала светофора на выезде с перекрестка п. 13.7.",
    "pddRule": "",
    "options": [
      "Выполните маневр без остановки на перекрестке",
      "Повернете налево и остановитесь в разрыве разделительной полосы, дождетесь зеленого сигнала светофора на выезде с перекрестка и завершите маневр",
      "Остановитесь перед перекрестком, дождетесь зеленого сигнала светофора на выезде с перекрестка и начнете выполнение маневра"
    ],
    "correctAnswerIndex": 0,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_22_14",
    "ticket": "Билет 22 · Вопрос 14",
    "type": "crossroad",
    "title": "В каком случае Вы должны уступить дорогу трамваю?",
    "explanation": "Перекрёсток равнозначный. Трамвай в равнозначных условиях имеет преимущество перед безрельсовыми транспортными средствами. Вы уступаете дорогу в обоих перечисленных случаях.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "При повороте налево",
      "При движении прямо",
      "В обоих перечисленных случаях"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_22_15",
    "ticket": "Билет 22 · Вопрос 15",
    "type": "crossroad",
    "title": "Вы намерены повернуть направо. Можете ли Вы приступить к повороту?",
    "explanation": "При повороте направо Вы должны двигаться по возможности ближе к правому краю проезжей части, т.е. по крайней правой полосе, которая свободна. Если Вы убеждены, что не создадите помеху находящемуся на главной дороге и имеющему преимущество грузовому автомобилю, выезжаете на перекрёсток, не дожидаясь его проезда через перекрёсток, так как знак 2.4 «Уступите дорогу» не предписывает совершать обязательную остановку перед пересечением.(Пункты 1.2 термин «Уступить дорогу», 13.9 ПДД, «Дорожные знаки»)",
    "pddRule": "п. 1.2",
    "options": [
      "Можете",
      "Можете, когда убедитесь, что при этом не будут созданы помехи грузовому автомобилю",
      "Не можете"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_23_13",
    "ticket": "Билет 23 · Вопрос 13",
    "type": "crossroad",
    "title": "Как следует поступить в этой ситуации, если Вам необходимо повернуть направо?",
    "explanation": "Правая рука регулировщика вытянута вперед. Со стороны левого бока безрельсовым транспортным средствам разрешено движение во всех направлениях – прямо, направо, налево и разворот. При повороте направо Вы обязаны уступить дорогу пешеходам, переходящим проезжую часть, на которую поворачиваете.(Пункты 6.10, 13.1 ПДД)",
    "pddRule": "п. 6.10",
    "options": [
      "Остановиться и дождаться другого сигнала регулировщика",
      "Повернуть направо, уступив дорогу пешеходам",
      "Повернуть направо, имея преимущество в движении перед пешеходами"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_23_14",
    "ticket": "Билет 23 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены проехать перекрёсток в прямом направлении. В данной ситуации:",
    "explanation": "Перекрёсток равнозначный. Водители руководствуются «правилом правой руки», т.е. у кого помеха справа тот и уступает. Постоянно контролируя отсутствие помехи справа, проезжаете перекрёсток первым.(Пункты 13.11, 13.12 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Вы обязаны уступить дорогу легковому автомобилю",
      "Вы имеете право проехать перекресток первым"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_23_15",
    "ticket": "Билет 23 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество, между собой руководствуются «правилом правой руки». У Вас помеха справа – уступаете автобусу.(Пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Обоим транспортным средствам",
      "Только автобусу",
      "Только легковому автомобилю",
      "Никому"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "cross_right",
        "targetAction": "turn_left",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "south",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_24_13",
    "ticket": "Билет 24 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "При повороте налево Вы:",
    "explanation": "Перекрёсток регулируемый. Всем трем ТС разрешено движение. Трамвай в равнозначных условиях имеет преимущество перед безрельсовыми ТС. Он проезжает первым. Вы - при повороте налево обязаны уступить автомобилю, движущемуся навстречу прямо.Правильный ответ – должны уступить дорогу обоим транспортным средствам.(Пункты 6.2, 13.4, 13.6 ПДД)",
    "pddRule": "п. 6.2",
    "options": [
      "Должны уступить дорогу обоим транспортным средствам",
      "Должны уступить дорогу только легковому автомобилю",
      "Имеете право проехать перекресток первым"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "tram_1",
        "type": "tram",
        "name": "Трамвай",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#0574F8"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_24_14",
    "ticket": "Билет 24 · Вопрос 14",
    "type": "crossroad",
    "title": "Кто имеет право проехать перекресток первым, если все намерены двигаться прямо?",
    "explanation": "Перекрёсток равнозначный. Мигающий маячок жёлтого цвета водителю грузовика преимущества не предоставляет (пункт 3.4 ПДД). «Правило правой руки» не применить, так как у всех помеха справа. Действительно, объяснения такой ситуации в Правилах нет. Водителям следует по договорённости обеспечить беспрепятственный проезд только одного транспортного средства, а далее начнёт действовать «правило правой руки».",
    "pddRule": "п. 3.4",
    "options": [
      "Водитель троллейбуса",
      "Вы вместе с водителем троллейбуса",
      "В данной ситуации очередность проезда определяется по взаимной договоренности водителей"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_24_15",
    "ticket": "Билет 24 · Вопрос 15",
    "type": "crossroad",
    "title": "В каком случае Вы обязаны уступить дорогу пешеходам?",
    "explanation": "При проезде любых перекрёстков с поворотом налево или направо водитель обязан уступить дорогу пешеходам, переходящим проезжую часть дороги, на которую он поворачивает.(Пункт 13.1 ПДД)",
    "pddRule": "п. 13.1",
    "options": [
      "Только при повороте налево",
      "Только при повороте направо",
      "В обоих случаях"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_25_13",
    "ticket": "Билет 25 · Вопрос 13",
    "type": "crossroad",
    "title": "Значения каких дорожных знаков отменяются сигналами светофора?",
    "explanation": "Движение регулируется: регулировщиком, сигналами светофора, знаками приоритета, разметкой, дорожным покрытием, «правилом правой руки». По вышеперечисленному «принципу приоритетности регулирования дорожного движения» знаки приоритета работают (т.е. ими мы руководствуемся) в том случае, когда отсутствует регулировщик, светофор выключен, неисправен, переведён в «жёлтый мигающий режим».(«Дорожные знаки», пункты 6.15 и 13.3 ПДД)",
    "pddRule": "п. 6.15",
    "options": [
      "Знаков приоритета",
      "Запрещающих знаков",
      "Предписывающих знаков",
      "Всех перечисленных знаков"
    ],
    "correctAnswerIndex": 0,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_25_14",
    "ticket": "Билет 25 · Вопрос 14",
    "type": "crossroad",
    "title": "При повороте направо Вы должны уступить дорогу:",
    "explanation": "При повороте направо или налево водитель обязан уступить дорогу пешеходам, лицам, использующим для передвижения СИМ и велосипедистам, пересекающим проезжую часть дороги, на которую он поворачивает.Это правило проезда перекрестков касается как регулируемых, так и нерегулируемых перекрестков.(Пункт 13.1 ПДД)",
    "pddRule": "п. 13.1",
    "options": [
      "Только велосипедисту",
      "Только пешеходам",
      "Пешеходам и велосипедисту"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы направо",
        "color": "#ED4621"
      },
      {
        "label": "Велосипедист",
        "color": "#2BC280"
      },
      {
        "label": "Пешеход",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "id": "cyclist",
        "type": "cyclist",
        "name": "Велосипедист",
        "side": "cross_right_edge",
        "targetAction": "straight",
        "color": "#2BC280"
      },
      {
        "id": "pedestrian",
        "type": "pedestrian",
        "name": "Пешеход",
        "side": "crosswalk_right",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_25_15",
    "ticket": "Билет 25 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Вы намерены повернуть налево. Кому Вы обязаны уступить дорогу?",
    "explanation": "Перекрёсток неравнозначный. Транспортные средства, находящиеся на главной дороге, имеют преимущество. Между собой руководствуются «правилом правой руки». После их проезда, руководствуясь тем же правилом, проедут транспортные средства, находящиеся на второстепенной дороге. Первым проезжает перекрёсток легковой автомобиль, Вы – вторым, мотоциклист – третьим, автобус – последним.(Пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Никому",
      "Только легковому автомобилю",
      "Легковому автомобилю и автобусу",
      "Всем транспортным средствам"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      },
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#8B5CF6"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "south",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_26_13",
    "ticket": "Билет 26 · Вопрос 13",
    "type": "crossroad",
    "title": "Вы намерены повернуть налево. Ваши действия?",
    "explanation": "В обычной ситуации водитель выезжает с перекрёстка независимо от сигналов светофора на выходе с перекрёстка. Но здесь ситуация иная. Применено раздельное действие светофоров.На перекрёстке два пересечения проезжих частей. Повернув налево, Вы обязаны при запрещающем сигнале светофора остановиться у «стоп-линии» (разметки 1.12). После включения разрешающего сигнала продолжаете движение через перекрёсток.(Пункт 13.7 ПДД)",
    "pddRule": "п. 13.7",
    "options": [
      "Остановитесь перед перекрестком, дождетесь зеленого сигнала светофора, установленного на разделительной полосе, и начнете выполнение маневра",
      "Выехав на перекрёсток, остановитесь у стоп-линии и, дождавшись зелёного сигнала светофора, установленного на разделительной полосе, завершите маневр",
      "Выполните маневр без остановки на перекрестке"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_26_14",
    "ticket": "Билет 26 · Вопрос 14",
    "type": "crossroad",
    "title": "Кому Вы должны уступить дорогу при повороте налево ?",
    "explanation": "Перекрёсток равнозначный. При любой его конфигурации водители руководствуются «правилом правой руки». Первым проезжает грузовик, так как у него нет помехи справа, вторым легковой автомобиль, Вы – последним.Вам следует уступить обоим транспортным средствам.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только легковому автомобилю",
      "Только грузовому автомобилю",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "turn_left",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_26_15",
    "ticket": "Билет 26 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "При движении прямо Вы обязаны уступить дорогу:",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Преимущество имеют транспортные средства, находящиеся на главной дороге. После их проезда проезжают транспортные средства, находящиеся на второстепенной дороге, которые между собой руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. Помеха справа у мотоциклиста, он уступает Вам. Транспортные средства проедут перекрёсток в следующем порядке: автобус, легковой автомобиль, Вы, мотоциклист.(«Дорожные знаки», пункты 13.9, 13.10 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только легковому автомобилю",
      "Автобусу и легковому автомобилю",
      "Всем транспортным средствам"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      },
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#8B5CF6"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "north",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_27_13",
    "ticket": "Билет 27 · Вопрос 13",
    "type": "crossroad",
    "title": "Как Вам следует поступить при повороте направо?",
    "explanation": "Перекрёсток регулируемый. Со стороны левого бока при таком жесте регулировщика безрельсовым транспортным средствам движение разрешается во всех направлениях. Трамваи двигаются только «по направлению рук регулировщика». В данной ситуации трамвай продолжать движение не может. Его водитель будет дожидаться смены сигнала регулировщика. Вы продолжаете движение через перекрёсток, т.е. проезжаете его первым.(Пункт 6.10 ПДД)",
    "pddRule": "п. 6.10",
    "options": [
      "Остановиться и дождаться другого сигнала регулировщика",
      "Проехать перекресток, уступив дорогу трамваю",
      "Проехать перекресток первым"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_27_14",
    "ticket": "Билет 27 · Вопрос 14",
    "type": "crossroad",
    "title": "Как Вам следует поступить, двигаясь по перекрестку с круговым движением?",
    "explanation": "При въезде по дороге, не являющейся главной, на перекресток, на котором организовано круговое движение и который обозначен знаком 4.3, водитель транспортного средства обязан уступить дорогу транспортным средствам, движущимся по такому перекрестку. (Третий исключительный случай, когда «правило правой руки» не работает).В данной ситуации Вы имеете преимущество и проезжаете перекресток первым.При въезде на перекресток водитель грузового автомобиля обязан уступить дорогу ВСЕМ ТС, движущимся по такому перекрестку.(Пункт 13.11.1 ПДД)",
    "pddRule": "п. 13.11.1",
    "options": [
      "Уступить дорогу грузовому автомобилю",
      "Проехать перекресток первым",
      "Действовать по взаимной договоренности с водителем грузового автомобиля"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_27_15",
    "ticket": "Билет 27 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Преимущество имеют транспортные средства, находящиеся на главной дороге. После их проезда проезжают транспортные средства, находящиеся на второстепенной дороге, которые между собой руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. Помеха справа у мотоциклиста, он уступает Вам. Транспортные средства проедут перекрёсток в следующем порядке: автобус, легковой автомобиль, Вы, мотоциклист.(«Дорожные знаки», пункты 13.9, 13.10 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только легковому автомобилю",
      "Легковому автомобилю и автобусу",
      "Всем транспортным средствам"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      },
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#8B5CF6"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "north",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_28_13",
    "ticket": "Билет 28 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток регулируемый. Трамвай в равнозначных условиях имеет преимущество перед безрельсовыми транспортными средствами. Вместе с ним одновременно, так как траектории движения не пересекаются, проедет легковой автомобиль, поворачивающий направо, которому Вы при повороте налево обязаны также уступить. Вы проедете перекрёсток последним.(Пункты 13.3, 13.4, 13.6 ПДД)",
    "pddRule": "п. 13.3",
    "options": [
      "Только автомобилю",
      "Только трамваю",
      "Автомобилю и трамваю",
      "Никому"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "tram_1",
        "type": "tram",
        "name": "Трамвай",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#0574F8",
        "position": [
          -0.6,
          0,
          13
        ],
        "rotationY": 3.141592653589793
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "opposite",
        "targetAction": "turn_right",
        "color": "#2BC280",
        "position": [
          -3.6,
          0,
          10.5
        ],
        "rotationY": 3.141592653589793
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_28_14",
    "ticket": "Билет 28 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы должны уступить дорогу грузовому автомобилю:",
    "explanation": "Перекрёсток равнозначный. Водители руководствуются «правилом правой руки». У Вас помеха справа будет только при движении прямо - Вы уступаете дорогу грузовому автомобилю. При повороте направо помеха справа отсутствует.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только при движении прямо",
      "Только при повороте направо",
      "В обоих перечисленных случаях"
    ],
    "correctAnswerIndex": 0,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_28_15",
    "ticket": "Билет 28 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Вы намерены развернуться. Кому Вам необходимо уступить дорогу?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество перед остальными независимо от их дальнейшего направления движения. Между собой руководствуются «правилом правой руки». Грузовик проезжает первым, Вы после него, легковой автомобиль - последним.(Пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только грузовому автомобилю",
      "Только легковому автомобилю",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы на разворот",
        "color": "#ED4621"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "south",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_29_13",
    "ticket": "Билет 29 · Вопрос 13",
    "type": "crossroad",
    "title": "При выполнении какого маневра водитель легкового автомобиля имеет преимущество в движении?",
    "explanation": "Водитель легкового автомобиля, движущийся под включенную зеленую стрелку в дополнительной секции, включенную одновременно с основным зеленым сигналом, может повернуть налево и совершить разворот. При этом движущиеся под включенную зеленую стрелку, в дополнительной секции, включенную одновременно с основным красным сигналом, автобус и грузовой автомобиль обязаны уступить всем другим Т.С, движущимся со всех других направлений. Водитель легкового автомобиля имеет преимущество в данной ситуации при выполнении любого маневра из перечисленных.(Пункт 13.5 ПДД)",
    "pddRule": "п. 13.5",
    "options": [
      "Только при повороте налево",
      "Только при развороте",
      "При выполнении любого маневра из перечисленных"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_29_14",
    "ticket": "Билет 29 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены повернуть налево. Ваши действия?",
    "explanation": "Вы и трамвай находитесь в равнозначных условиях. Трамвай в таком случае имеет преимущество перед безрельсовыми транспортными средствами. Уступаете дорогу трамваю.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Уступите дорогу трамваю, выполнив поворот с левой полосы",
      "Пропустите трамвай, перестроитесь на трамвайные пути попутного направления, после чего выполните поворот",
      "Проедете перекресток первым"
    ],
    "correctAnswerIndex": 0,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_29_15",
    "ticket": "Билет 29 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при движении в прямом направлении?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Преимущество имеют транспортные средства, находящиеся на главной дороге. Между собой они руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. Вы находитесь на второстепенной дороге - уступаете обоим транспортным средствам.(«Дорожные знаки» 2.4, 8.13, пункты 13.9, 13.10 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только легковому автомобилю",
      "Только автобусу",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "north",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_30_13",
    "ticket": "Билет 30 · Вопрос 13",
    "type": "crossroad",
    "title": "В каком случае Вы обязаны уступить дорогу грузовому автомобилю?",
    "explanation": "Перекрёсток регулируемый. Вам разрешено движение. При повороте налево, развороте следует уступить дорогу транспортным средствам, движущимся со встречного направления прямо и направо. Уступаете грузовику в обоих перечисленных случаях.(Пункты 13.3, 13.4 ПДД)",
    "pddRule": "п. 13.3",
    "options": [
      "При повороте налево",
      "При развороте",
      "В обоих перечисленных случаях"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_30_14",
    "ticket": "Билет 30 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены продолжить движение прямо при желтом мигающем сигнале светофора. Ваши действия?",
    "explanation": "Перекрёсток при жёлтом мигающем светофоре является нерегулируемым, в данном случае равнозначным, так как знаков приоритета нет. Руководствуемся «правилом правой руки», т.е. у кого помеха справа, тот и уступает. У Вас помеха справа – проедете перекрёсток последним, уступив дорогу гужевой повозке.(Пункты 13.3, 13.11 ПДД)",
    "pddRule": "п. 13.3",
    "options": [
      "Остановитесь и продолжите движение только после включения зеленого сигнала светофора",
      "Уступите дорогу гужевой повозке",
      "Проедете перекресток первым вместе со встречным автомобилем"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_30_15",
    "ticket": "Билет 30 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Вы намерены повернуть налево. Кому Вы обязаны уступить дорогу?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге, имеют преимущество, между собой руководствуются «правилом правой руки». После их проезда, руководствуясь этим же правилом, проедут транспортные средства, находящиеся на второстепенной дороге. Вы проезжаете первым, никому не уступая. Мотоциклист – вторым, автобус – третьим, легковой автомобиль – последним.(Пункты 13.9, 13.1, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Легковому автомобилю и автобусу",
      "Только автобусу",
      "Только мотоциклу",
      "Никому"
    ],
    "correctAnswerIndex": 3,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "turn_right",
        "color": "#2BC280"
      },
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#8B5CF6"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "south",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_31_13",
    "ticket": "Билет 31 · Вопрос 13",
    "type": "crossroad",
    "title": "Как Вам следует поступить при повороте налево?",
    "explanation": "Перекрёсток регулируемый. У регулировщика руки опущены. Движение со стороны правого и левого бока безрельсовым транспортным средствам разрешается прямо и направо. Вы же намереваетесь повернуть налево. Поэтому Вам необходимо остановиться перед стоп-линией и дождаться соответствующего Вашему намерению сигнала регулировщика, после чего выполнить маневр.(Пункты 6.10, 6.13, 13.3 ПДД, «Горизонтальная разметка» 1.12)",
    "pddRule": "п. 6.10",
    "options": [
      "Остановиться у стоп-линии и дождаться сигнала регулировщика, разрешающего поворот",
      "Выехав на перекресток, остановиться и дождаться сигнала регулировщика, разрешающего поворот",
      "Повернуть, уступив дорогу встречному автомобилю"
    ],
    "correctAnswerIndex": 0,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_31_14",
    "ticket": "Билет 31 · Вопрос 14",
    "type": "crossroad_tram",
    "title": "Вы намерены проехать перекрёсток в прямом направлении. Ваши действия?",
    "explanation": "Перекрёсток равнозначный. Трамвай на равнозначных перекрёстках имеет преимущество перед безрельсовыми транспортными средствами независимо от его дальнейшего направления движения. Безрельсовые транспортные средства руководствуются между собой «правилом правой руки», т.е. у кого помеха справа, тот и уступает дорогу. У Вас помеха справа – уступаете дорогу грузовику.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проедете перекресток вместе с трамваем, не уступая дорогу грузовому автомобилю",
      "Проедете перекресток, уступив дорогу грузовому автомобилю"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "id": "tram_1",
        "type": "tram",
        "name": "Трамвай",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#0574F8"
      },
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_31_15",
    "ticket": "Билет 31 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при движении прямо?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Транспортные средства, находящиеся на главной дороге имеют преимущество, между собой руководствуются «правилом правой руки». После них, руководствуясь этим же правилом, проезжают перекрёсток транспортные средства, находящиеся на второстепенной дороге. Первым проедет мотоциклист, вторым – автобус, третьим – легковой автомобиль. Вы последним, уступив всем транспортным средствам.(Пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только мотоциклу",
      "Мотоциклу и легковому автомобилю",
      "Автобусу и мотоциклу",
      "Всем транспортным средствам"
    ],
    "correctAnswerIndex": 3,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#8B5CF6"
      },
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "turn_left",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "north",
          "west"
        ]
      }
    ]
  },
  {
    "id": "ticket_32_13",
    "ticket": "Билет 32 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Как Вам следует поступить при повороте налево?",
    "explanation": "Перекрёсток регулируемый. Знаки приоритета «не работают». Грузовик с «жёлтой мигалкой» стоит и дожидается разрешающего ему движение сигнала светофора, так как отступать от требований сигналов светофора жёлтый специальный сигнал не разрешает. Вы при повороте налево обязаны уступить дорогу транспортным средствам, движущимся прямо со встречного направления. Уступаете дорогу автобусу.(Пункты 3.4, 13.3, 13.4 ПДД)",
    "pddRule": "п. 3.4",
    "options": [
      "Проехать перекрёсток первым",
      "Уступить дорогу только грузовому автомобилю с включенным проблесковым маячком",
      "Уступить дорогу только автобусу"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C",
        "beacon": "amber"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  },
  {
    "id": "ticket_32_14",
    "ticket": "Билет 32 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены развернуться. Ваши действия?",
    "explanation": "Перекрёсток равнозначный. При определении порядка проезда перекрёстка водители руководствуются «правилом правой руки». Во время разворота у Вас будет помеха справа, уступаете дорогу.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Развернётесь первым",
      "Выедете на перекрёсток и, уступив дорогу легковому автомобилю, завершите разворот",
      "Будете действовать по взаимной договоренности с водителем легкового автомобиля"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_32_15",
    "ticket": "Билет 32 · Вопрос 15",
    "type": "crossroad",
    "title": "Кому Вы обязаны уступить дорогу при движении прямо?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Преимущество имеют транспортные средства, находящиеся на главной дороге, при этом безрельсовые транспортные средства между собой руководствуются «правилом правой руки», уступая трамваю, находящемуся с ними в равнозначных условиях. Вы уступаете дорогу трамваю и легковому автомобилю, которые проедут перекрёсток одновременно, так как их траектории движения не пересекаются. Мотоциклист уступает всем, потому что находится на второстепенной дороге.(«Дорожные знаки», пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только трамваю",
      "Только легковому автомобилю",
      "Трамваю и легковому автомобилю",
      "Всем транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_33_13",
    "ticket": "Билет 33 · Вопрос 13",
    "type": "crossroad",
    "title": "Как Вам следует поступить при повороте направо?",
    "explanation": "Для поворота направо Вы должны пересечь трамвайные пути. Оба трамвая так же, как и Вы, имеют право на движение, они двигаются «по рукам регулировщика». Вы им уступаете, так как при одновременном праве на движение трамвай имеет преимущество перед безрельсовыми транспортными средствами.(Пункты 6.10, 13.6 ПДД)",
    "pddRule": "п. 6.10",
    "options": [
      "Проехать перекресток первым",
      "Уступить дорогу только трамваю А",
      "Уступить дорогу только трамваю Б",
      "Уступить дорогу обоим трамваям"
    ],
    "correctAnswerIndex": 3,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_33_14",
    "ticket": "Билет 33 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены повернуть налево. Ваши действия?",
    "explanation": "Перекрёсток равнозначный. Водители между собой руководствуются «правилом правой руки». Первым начинаете движение Вы, поскольку в первоначальный момент не имеете помехи справа. Выкатившись на перекрёсток, перед самым поворотом налево останавливаетесь, так как справа от Вас по траектории движения находится мотоцикл. После того, как мотоцикл проедет, Вы можете завершить маневр. Легковое ТС проедет перекресток последним.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проедете перекрёсток первым",
      "Выедете на перекресток первым и, уступив дорогу мотоциклу, завершите поворот",
      "Уступите дорогу обоим транспортным средствам"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_33_15",
    "ticket": "Билет 33 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Вы обязаны уступить дорогу при движении прямо:",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Преимущество имеют транспортные средства, находящиеся на главной дороге, которые между собой руководствуются «правилом правой руки». Вы находитесь на второстепенной дороге, уступаете дорогу обоим транспортным средствам.(«Дорожные знаки» 2.4, 8.13; пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Только легковому автомобилю",
      "Только грузовому автомобилю",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#2BC280"
      },
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "north",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_34_13",
    "ticket": "Билет 34 · Вопрос 13",
    "type": "crossroad",
    "title": "Как Вам следует поступить при движении в прямом направлении?",
    "explanation": "Перекрёсток регулируемый. Трамваи двигаются только «по направлению рук регулировщика», т.е. прямо. Водителю трамвая поворот направо запрещён. Соответственно он стоит и дожидается смены сигнала регулировщика. Вам можно продолжить движение прямо или направо. Проезжаете перекрёсток первым.(Пункт 6.10 ПДД)",
    "pddRule": "п. 6.10",
    "options": [
      "Проехать перекрёсток первым",
      "Уступить дорогу трамваю",
      "Дождаться другого сигнала регулировщика"
    ],
    "correctAnswerIndex": 0,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_34_14",
    "ticket": "Билет 34 · Вопрос 14",
    "type": "crossroad",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перекрёсток равнозначный. Водители руководствуются «правилом правой руки». У вас помехой справа является только автомобиль, поэтому вы обязаны ему уступить дорогу.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только мотоциклу",
      "Только легковому автомобилю",
      "Никому"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      },
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#8B5CF6"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_34_15",
    "ticket": "Билет 34 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Вы намерены повернуть налево. Ваши действия?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Преимущество имеют транспортные средства, находящиеся на главной дороге, которые между собой руководствуются «правилом правой руки». После их проезда, проезжают транспортные средства, находящиеся на второстепенной дороге. Вы находитесь на второстепенной дороге. Уступаете обоим транспортным средствам.(Пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Уступите дорогу обоим транспортным средствам",
      "Уступите дорогу только легковому автомобилю",
      "Уступите дорогу только автобусу"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "cross_left",
        "targetAction": "turn_right",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "north",
          "west"
        ]
      }
    ]
  },
  {
    "id": "ticket_35_13",
    "ticket": "Билет 35 · Вопрос 13",
    "type": "crossroad",
    "title": "Вам необходимо уступить дорогу другим участникам движения:",
    "explanation": "При повороте направо Вы обязаны уступить дорогу пешеходам. При повороте налево или развороте – трамваю, имеющему преимущество в равнозначных условиях. Никаких помех нет при движении прямо.Правильный ответ - в обоих перечисленных случаях.(Пункты 6.2, 13.1, 13.6 ПДД)",
    "pddRule": "п. 6.2",
    "options": [
      "Только при повороте налево или развороте",
      "Только при повороте направо",
      "В обоих перечисленных случаях"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_35_14",
    "ticket": "Билет 35 · Вопрос 14",
    "type": "crossroad",
    "title": "Вы намерены продолжить движение прямо. Ваши действия?",
    "explanation": "Перекрёсток равнозначный. Водители руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает. У Вас помеха справа, грузовик имеет преимущество.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Проедете перекресток первым",
      "Уступите дорогу грузовому автомобилю, так как он приближается справа",
      "Уступите дорогу грузовому автомобилю, так как он находится на главной дороге"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_35_15",
    "ticket": "Билет 35 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Бесспорно преимущество имеет «оперативник» с мигалкой синего цвета и включенной сиреной. Все остальные обязаны обеспечить ему беспрепятственный проезд перекрёстка. После его проезда проезжаете Вы, так как находитесь на главной дороге и имеете преимущество перед грузовиком, находящимся на второстепенной дороге.(Пункты 3.1, 13.9 ПДД)",
    "pddRule": "п. 3.1",
    "options": [
      "Обоим транспортным средствам",
      "Автомобилю с включенными проблесковым маячком и специальным звуковым сигналом",
      "Никому"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Спецмашина",
        "color": "#0574F8"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_special",
        "type": "special",
        "name": "Спецмашина",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#0574F8",
        "beacon": "blue",
        "siren": true
      },
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "south",
          "west"
        ]
      }
    ]
  },
  {
    "id": "ticket_36_13",
    "ticket": "Билет 36 · Вопрос 13",
    "type": "crossroad",
    "title": "Вы намерены повернуть направо. Ваши действия?",
    "explanation": "Со стороны вытянутой правой руки регулировщика безрельсовым транспортным средствам движение разрешается только направо. При этом разворачивающийся автомобиль, руководствуясь «правилом правой руки», уступает Вам дорогу.(Пункт 6.10 ПДД)",
    "pddRule": "п. 6.10",
    "options": [
      "Дождетесь другого сигнала регулировщика",
      "Уступите дорогу легковому автомобилю, осуществляющему разворот",
      "Проедете перекресток первым"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_36_14",
    "ticket": "Билет 36 · Вопрос 14",
    "type": "crossroad",
    "title": "В каком случае Вы должны пропустить трамвай?",
    "explanation": "Вы и трамвай находитесь на одной дороге в равнозначных условиях. В таком случае трамвай всегда имеет преимущество перед безрельсовыми транспортными средствами. Вы должны уступить дорогу трамваю в обоих перечисленных случаях.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "При повороте налево, перестроившись на трамвайные пути попутного направления",
      "При движении прямо",
      "В обоих перечисленных случаях"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_36_15",
    "ticket": "Билет 36 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Как Вам следует поступить при повороте налево?",
    "explanation": "Перекрёсток нерегулируемый, неравнозначный. Преимущество имеют транспортные средства, находящиеся на главной дороге, которые между собой руководствуются «правилом правой руки». После проезжают перекрёсток транспортные средства, находящиеся на второстепенной дороге. Первым проезжает грузовик, Вы ему уступаете. Последним проедет легковой автомобиль.(Пункты 13.3, 13.9, 13.12 ПДД)",
    "pddRule": "п. 13.3",
    "options": [
      "Уступить дорогу обоим транспортным средствам",
      "Уступить дорогу только грузовому автомобилю",
      "Проехать перекресток первым"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_37_13",
    "ticket": "Билет 37 · Вопрос 13",
    "type": "crossroad",
    "title": "Как Вам следует поступить при повороте направо?",
    "explanation": "При повороте направо, налево на любом перекрёстке (регулируемом, нерегулируемом) водитель обязан уступить дорогу пешеходам, переходящим проезжую часть дороги, на которую он поворачивает.(Пункты 6.2, 13.1 ПДД)",
    "pddRule": "п. 6.2",
    "options": [
      "Остановиться перед стоп-линией и, пропустив пешеходов, повернуть направо",
      "Выехав на перекрёсток, остановиться перед пешеходным переходом, чтобы пропустить пешеходов",
      "Продолжить движение без остановки на перекрёстке"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_37_14",
    "ticket": "Билет 37 · Вопрос 14",
    "type": "crossroad",
    "title": "При движении в каком направлении Вы будете иметь преимущество?",
    "explanation": "Перекрёсток равнозначный. Водители руководствуются «правилом правой руки». У Вас помехи справа нет, в любом направлении из перечисленных. Проезжаете перекрёсток первым.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только при повороте направо",
      "Только при повороте налево",
      "В любом направлении из перечисленных"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_37_15",
    "ticket": "Билет 37 · Вопрос 15",
    "type": "crossroad_tram",
    "title": "Вы намерены продолжить движение прямо. Ваши действия:",
    "explanation": "Перекрёсток неравнозначный. Вы и трамвай находитесь на главной дороге. «Правило правой руки» в этом случае не работает. Трамвай в равнозначных условиях имеет преимущество перед безрельсовыми транспортными средствами. Уступаете дорогу трамваю.(Пункт 13.11 ПДД, «Дорожные знаки»)",
    "pddRule": "п. 13.11",
    "options": [
      "Проедете перекрёсток первым",
      "Уступите дорогу трамваю"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "id": "tram_1",
        "type": "tram",
        "name": "Трамвай",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#0574F8"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_38_13",
    "ticket": "Билет 38 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Как Вам следует поступить при повороте налево?",
    "explanation": "Перекрёсток регулируемый. Знаки приоритета «не работают». «Оперативник» со специальными сигналами отступает от требований сигналов светофора. Другие водители обязаны обеспечить его беспрепятственный проезд. При повороте налево Вы обязаны уступить легковому автомобилю, движущемуся прямо со встречного направления.(Пункты 3.1, 3.2, 13.3, 13.4 ПДД)",
    "pddRule": "п. 3.1",
    "options": [
      "Проехать перекресток первым",
      "Уступить дорогу только автомобилю с включенными проблесковым маячком и специальным звуковым сигналом",
      "Уступить дорогу обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Спецмашина",
        "color": "#0574F8"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_special",
        "type": "special",
        "name": "Спецмашина",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#0574F8",
        "beacon": "blue",
        "siren": true
      },
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "south",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_38_14",
    "ticket": "Билет 38 · Вопрос 14",
    "type": "crossroad",
    "title": "При движении в каком направлении Вы обязаны уступить дорогу трамваю?",
    "explanation": "Перекрёсток равнозначный. Вы и трамвай находитесь в равнозначных условиях. В таком случае трамвай всегда имеет преимущество перед безрельсовыми транспортными средствами.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Только налево",
      "Только прямо",
      "В обоих перечисленных"
    ],
    "correctAnswerIndex": 2,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_38_15",
    "ticket": "Билет 38 · Вопрос 15",
    "type": "crossroad",
    "title": "Вы намерены повернуть направо. Можете ли Вы приступить к повороту?",
    "explanation": "Перекрёсток неравнозначный. Знак 2.4 обязывает Вас уступить дорогу транспортным средствам, движущимся по пересекаемой дороге. Только после того как убедитесь, что грузовой автомобиль действительно поворачивает налево и Ваше движение не может создать ему помеху, выезжаете на перекрёсток, чтобы совершить поворот направо.(Пункты 1.2, 13.9 ПДД, «Дорожные знаки»)",
    "pddRule": "п. 1.2",
    "options": [
      "Можете",
      "Можете после того, как грузовой автомобиль начнет выполнять поворот налево",
      "Не можете"
    ],
    "correctAnswerIndex": 1,
    "legend": [],
    "actorsConfig": [],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_39_13",
    "ticket": "Билет 39 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены проехать перекресток в прямом направлении. Ваши действия?",
    "explanation": "Перекресток регулируется светофором. Знаки приоритета «не работают». Вы и трамвай находитесь в равнозначных условиях. Трамвай в таких ситуациях всегда имеет преимущество перед безрельсовыми ТС, поэтому Вы уступаете дорогу трамваю.(Пункт 13.6 ПДД)",
    "pddRule": "п. 13.6",
    "options": [
      "Проедете первым, руководствуясь сигналом светофора",
      "Проедете первым, руководствуясь знаком «Главная дорога»",
      "Уступите дорогу трамваю"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "id": "tram_1",
        "type": "tram",
        "name": "Трамвай",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#0574F8"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      }
    ]
  },
  {
    "id": "ticket_39_14",
    "ticket": "Билет 39 · Вопрос 14",
    "type": "crossroad",
    "title": "Как Вам следует поступить при повороте налево?",
    "explanation": "Перекрёсток равнозначный. Водители безрельсовых транспортных средств между собой руководствуются «правилом правой руки», т.е. у кого помеха справа, тот и уступает дорогу. У Вас помеха справа, легковой автомобиль проезжает первым.(Пункт 13.11 ПДД)",
    "pddRule": "п. 13.11",
    "options": [
      "Уступить дорогу легковому автомобилю",
      "Проехать перекресток первым"
    ],
    "correctAnswerIndex": 0,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_39_15",
    "ticket": "Билет 39 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы должны уступить дорогу при движении прямо?",
    "explanation": "Перекрёсток неравнозначный. Главная дорога меняет направление. Первоначально проезжают перекрёсток транспортные средства, находящиеся на главной дороге. Они имеют преимущество. Между собой они руководствуются «правилом правой руки». У Вас помеха справа, уступаете только легковому автомобилю.(Пункты 13.9, 13.10, 13.11 ПДД)",
    "pddRule": "п. 13.9",
    "options": [
      "Легковому автомобилю и мотоциклу",
      "Только легковому автомобилю",
      "Никому"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Автомобиль",
        "color": "#2BC280"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_car",
        "type": "car",
        "name": "Автомобиль",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#2BC280"
      },
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "opposite",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#8B5CF6"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.1",
        "name": "Главная дорога"
      },
      {
        "code": "8.13",
        "name": "Направление главной дороги",
        "mainRoad": [
          "south",
          "east"
        ]
      }
    ]
  },
  {
    "id": "ticket_40_13",
    "ticket": "Билет 40 · Вопрос 13",
    "type": "crossroad_traffic_light",
    "title": "Вы намерены повернуть направо. Ваши действия?",
    "explanation": "При одновременном праве на движение трамваи имеют преимущество перед безрельсовыми транспортными средствами.(Пункт 13.6 ПДД)",
    "pddRule": "п. 13.6",
    "options": [
      "Проедете перекрёсток первым",
      "Уступите дорогу только трамваю А",
      "Уступите дорогу только трамваю Б",
      "Уступите дорогу обоим трамваям"
    ],
    "correctAnswerIndex": 3,
    "legend": [
      {
        "label": "Вы направо",
        "color": "#ED4621"
      },
      {
        "label": "Трамвай Б",
        "color": "#FFA53C"
      },
      {
        "label": "Трамвай А",
        "color": "#0574F8"
      }
    ],
    "actorsConfig": [
      {
        "id": "tram_b",
        "type": "tram",
        "name": "Трамвай Б",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C",
        "badge": "Б"
      },
      {
        "id": "tram_a",
        "type": "tram",
        "name": "Трамвай А",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#0574F8",
        "badge": "А"
      }
    ],
    "trafficLights": {
      "state": "green"
    },
    "signs": []
  },
  {
    "id": "ticket_40_14",
    "ticket": "Билет 40 · Вопрос 14",
    "type": "crossroad",
    "title": "При движении прямо Вы:",
    "explanation": "Перекрёсток равнозначный. Мигающий маячок оранжевого или жёлтого цвета на грузовике преимуществ его водителю не предоставляет. Водители руководствуются «правилом правой руки». У Вас помеха справа – мотоциклист. Вы уступаете дорогу только мотоциклисту, который начнёт первым движение, выкатится на перекрёсток. После этого Вы проедете через перекрёсток, за Вами грузовик, мотоциклист последним закончит движение.(Пункты 3.4, 13.11 ПДД)",
    "pddRule": "п. 3.4",
    "options": [
      "Имеете преимущество",
      "Должны уступить дорогу только мотоциклу",
      "Должны уступить дорогу только автомобилю",
      "Должны уступить дорогу обоим транспортным средствам"
    ],
    "correctAnswerIndex": 1,
    "legend": [
      {
        "label": "Вы прямо",
        "color": "#ED4621"
      },
      {
        "label": "Мотоцикл",
        "color": "#8B5CF6"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_moto",
        "type": "motorcycle",
        "name": "Мотоцикл",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#8B5CF6"
      },
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "opposite",
        "targetAction": "turn_left",
        "color": "#FFA53C",
        "beacon": "amber"
      }
    ],
    "trafficLights": null,
    "signs": []
  },
  {
    "id": "ticket_40_15",
    "ticket": "Билет 40 · Вопрос 15",
    "type": "crossroad_priority_signs",
    "title": "Кому Вы обязаны уступить дорогу при повороте налево?",
    "explanation": "Перед Вами знак 2.4 «Уступите дорогу». Уступаете дорогу транспортным средствам, движущимся по пересекаемой дороге, в данной ситуации обоим транспортным средствам.(Пункт 13.9 ПДД, «Дорожные знаки»)",
    "pddRule": "п. 13.9",
    "options": [
      "Только автобусу",
      "Только грузовому автомобилю",
      "Обоим транспортным средствам"
    ],
    "correctAnswerIndex": 2,
    "legend": [
      {
        "label": "Вы налево",
        "color": "#ED4621"
      },
      {
        "label": "Автобус",
        "color": "#FFA53C"
      },
      {
        "label": "Грузовик",
        "color": "#FFA53C"
      }
    ],
    "actorsConfig": [
      {
        "id": "npc_bus",
        "type": "bus",
        "name": "Автобус",
        "side": "cross_left",
        "targetAction": "straight",
        "color": "#FFA53C"
      },
      {
        "id": "npc_truck",
        "type": "truck",
        "name": "Грузовик",
        "side": "cross_right",
        "targetAction": "straight",
        "color": "#FFA53C"
      }
    ],
    "trafficLights": null,
    "signs": [
      {
        "code": "2.4",
        "name": "Уступите дорогу"
      }
    ]
  }
];

  // --- Flutter Bridge Helper ---
  function sendToFlutter(messageObj) {
    const json = JSON.stringify(messageObj);
    if (window.FlutterChannel && window.FlutterChannel.postMessage) {
      window.FlutterChannel.postMessage(json);
    } else {
      // Development console fallback
      console.log('[FlutterBridge MSG]:', json);
    }
  }

  // Procedural audio keeps the simulator self-contained and lets every layer
  // react continuously to speed, traffic and distance instead of looping one
  // generic recording at a fixed pitch.
  function createGameAudio() {
    const audio = { enabled: true, paused: false, context: null, master: null,
      nodes: {}, engineLevel: 0, trafficLevel: 0, sirenLevel: 0, tramLevel: 0,
      trackPhase: 0, birdAt: 4, blinkerOn: false };
    const contextClass = window.AudioContext || window.webkitAudioContext;
    const ramp = (param, value, seconds = 0.08) => {
      if (!audio.context || !param) return;
      param.cancelScheduledValues(audio.context.currentTime);
      param.linearRampToValueAtTime(value, audio.context.currentTime + seconds);
    };
    const noiseBuffer = context => {
      const buffer = context.createBuffer(1, context.sampleRate * 2, context.sampleRate);
      const data = buffer.getChannelData(0);
      let last = 0;
      for (let i = 0; i < data.length; i++) {
        last = last * 0.72 + (Math.random() * 2 - 1) * 0.28;
        data[i] = last;
      }
      return buffer;
    };
    const loopNoise = (context, filterType, frequency) => {
      const source = context.createBufferSource();
      source.buffer = noiseBuffer(context); source.loop = true;
      const filter = context.createBiquadFilter();
      filter.type = filterType; filter.frequency.value = frequency;
      const gain = context.createGain(); gain.gain.value = 0;
      source.connect(filter).connect(gain).connect(audio.master); source.start();
      return { source, filter, gain };
    };
    audio.ensure = () => {
      if (!audio.enabled || audio.context || !contextClass) return;
      try {
        const context = new contextClass();
        audio.context = context;
        audio.master = context.createGain(); audio.master.gain.value = 0;
        audio.master.connect(context.destination);
        const makeTone = (type, frequency) => {
          const oscillator = context.createOscillator(); oscillator.type = type; oscillator.frequency.value = frequency;
          const gain = context.createGain(); gain.gain.value = 0;
          oscillator.connect(gain).connect(audio.master); oscillator.start();
          return { oscillator, gain };
        };
        // Engine: sub + fundamental + fifth through one low-pass "exhaust" filter
        // and a gentle soft-clip; the filter opens with rpm/throttle. A band of
        // filtered noise adds combustion grit. Per-vehicle profile scales pitch.
        const engineBus = context.createGain(); engineBus.gain.value = 0;
        const engineFilter = context.createBiquadFilter(); engineFilter.type = 'lowpass';
        engineFilter.frequency.value = 260; engineFilter.Q.value = 1.4;
        const shaper = context.createWaveShaper();
        const curve = new Float32Array(256);
        for (let i = 0; i < 256; i++) { const x = i / 127.5 - 1; curve[i] = Math.tanh(x * 1.8) / Math.tanh(1.8); }
        shaper.curve = curve; shaper.oversample = '2x';
        engineBus.connect(engineFilter).connect(shaper).connect(audio.master);
        const engineVoice = (type, frequency, level) => {
          const oscillator = context.createOscillator(); oscillator.type = type; oscillator.frequency.value = frequency;
          const gain = context.createGain(); gain.gain.value = level;
          oscillator.connect(gain).connect(engineBus); oscillator.start();
          return { oscillator, gain };
        };
        audio.nodes.engineSub = engineVoice('sine', 30, 0.55);
        audio.nodes.engine = engineVoice('sawtooth', 60, 0.5);
        audio.nodes.engineFifth = engineVoice('triangle', 90, 0.28);
        audio.nodes.engineBus = engineBus; audio.nodes.engineFilter = engineFilter;
        audio.nodes.grit = loopNoise(context, 'bandpass', 220);
        audio.nodes.grit.filter.Q.value = 0.9;
        audio.nodes.squeal = loopNoise(context, 'bandpass', 1900);
        audio.nodes.squeal.filter.Q.value = 6;
        audio.nodes.scrape = loopNoise(context, 'bandpass', 520);
        audio.nodes.rain = loopNoise(context, 'highpass', 1600);
        audio.nodes.scrape.filter.Q.value = 1.2;
        audio.rpm = 0.15; audio.reverseBeepAt = 0;
        audio.nodes.traffic = makeTone('triangle', 48);
        audio.nodes.tram = makeTone('sawtooth', 34);
        audio.nodes.sirenLow = makeTone('sine', 620);
        audio.nodes.sirenHigh = makeTone('sine', 820);
        audio.nodes.road = loopNoise(context, 'lowpass', 900);
        audio.nodes.wind = loopNoise(context, 'bandpass', 700);
        audio.nodes.ambience = loopNoise(context, 'lowpass', 420);
      } catch (_) { audio.context = null; }
    };
    // Each garage model has its own voice: pitch, brightness, grit, loudness.
    audio.profiles = {
      hatch: { pitch: 1.18, bright: 1.15, grit: 0.7, level: 0.9 },
      sedan: { pitch: 1.0, bright: 1.0, grit: 0.8, level: 1.0 },
      suv: { pitch: 0.84, bright: 0.85, grit: 1.1, level: 1.1 },
      pickup: { pitch: 0.74, bright: 0.8, grit: 1.4, level: 1.2 },
    };
    audio.profile = audio.profiles.hatch;
    audio.setVehicle = id => { audio.profile = audio.profiles[id] || audio.profiles.hatch; };
    audio.unlock = () => {
      audio.ensure();
      if (audio.context?.state === 'suspended') audio.context.resume().catch(() => {});
    };
    audio.setEnabled = enabled => {
      audio.enabled = Boolean(enabled);
      if (audio.enabled) audio.unlock();
      ramp(audio.master?.gain, audio.enabled && !audio.paused ? 0.72 : 0, 0.12);
    };
    audio.setPaused = paused => {
      audio.paused = Boolean(paused);
      ramp(audio.master?.gain, audio.enabled && !audio.paused ? 0.72 : 0, 0.1);
    };
    audio.transient = (frequency, duration, volume, type = 'sine') => {
      audio.unlock();
      const context = audio.context;
      if (!audio.enabled || !context || audio.paused) return;
      const oscillator = context.createOscillator(), gain = context.createGain();
      oscillator.type = type; oscillator.frequency.setValueAtTime(frequency, context.currentTime);
      oscillator.frequency.exponentialRampToValueAtTime(Math.max(35, frequency * 0.55), context.currentTime + duration);
      gain.gain.setValueAtTime(volume, context.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + duration);
      oscillator.connect(gain).connect(audio.master); oscillator.start(); oscillator.stop(context.currentTime + duration);
    };
    const burst = (filterType, frequency, q, volume, duration) => {
      const context = audio.context;
      if (!context || !audio.enabled || audio.paused) return;
      const source = context.createBufferSource(), filter = context.createBiquadFilter(), gain = context.createGain();
      source.buffer = noiseBuffer(context); filter.type = filterType; filter.frequency.value = frequency; filter.Q.value = q;
      gain.gain.setValueAtTime(volume, context.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + duration);
      source.connect(filter).connect(gain).connect(audio.master); source.start(); source.stop(context.currentTime + duration + 0.02);
    };
    // Vehicle-on-vehicle: deep body thump, crunch of panels, a glass tinkle.
    audio.impact = strength => {
      audio.unlock();
      const k = THREE.MathUtils.clamp(strength / 18, 0.25, 1);
      audio.transient(70, 0.42, 0.22 + k * 0.18, 'sine');
      burst('lowpass', 700 + k * 500, 0.7, 0.16 + k * 0.2, 0.32);
      burst('bandpass', 3400, 2.5, 0.05 + k * 0.08, 0.5);
    };
    // A person or a bicycle: dull soft thud, no crunch; the bike adds a short
    // metallic clatter. Deliberately restrained for a driving-school game.
    audio.softImpact = type => {
      audio.unlock();
      audio.transient(120, 0.2, 0.16, 'sine');
      audio.scream();
      burst('lowpass', 380, 0.8, 0.12, 0.18);
      if (type === 'cyclist') { burst('bandpass', 2600, 3, 0.07, 0.35); audio.transient(1700, 0.12, 0.03, 'triangle'); }
    };
    // A short startled cry: a sawtooth "voice" through two vowel formants,
    // pitch falling, quiet and brief — a signal, not a horror effect.
    audio.scream = () => {
      const context = audio.context;
      if (!context || !audio.enabled || audio.paused) return;
      const t0 = context.currentTime;
      const voice = context.createOscillator(); voice.type = 'sawtooth';
      voice.frequency.setValueAtTime(420, t0); voice.frequency.linearRampToValueAtTime(470, t0 + 0.08);
      voice.frequency.exponentialRampToValueAtTime(240, t0 + 0.42);
      const f1 = context.createBiquadFilter(); f1.type = 'bandpass'; f1.frequency.value = 760; f1.Q.value = 5;
      const f2 = context.createBiquadFilter(); f2.type = 'bandpass'; f2.frequency.value = 1300; f2.Q.value = 6;
      const g1 = context.createGain(), g2 = context.createGain(), out = context.createGain();
      g1.gain.value = 0.6; g2.gain.value = 0.35;
      out.gain.setValueAtTime(0.0001, t0); out.gain.linearRampToValueAtTime(0.09, t0 + 0.04);
      out.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.45);
      voice.connect(f1).connect(g1).connect(out); voice.connect(f2).connect(g2).connect(out); out.connect(audio.master);
      voice.start(t0); voice.stop(t0 + 0.47);
    };
    audio.scrapeHit = () => { audio.unlock(); burst('bandpass', 600, 1.5, 0.08, 0.14); };
    audio.beep = () => audio.transient(960, 0.07, 0.03, 'square');
    audio.click = () => audio.transient(1180, 0.035, 0.055, 'square');
    audio.chirp = () => {
      audio.unlock();
      const context = audio.context;
      if (!audio.enabled || !context || audio.paused) return;
      const oscillator = context.createOscillator(), gain = context.createGain();
      oscillator.type = 'sine'; oscillator.frequency.setValueAtTime(1450, context.currentTime);
      oscillator.frequency.linearRampToValueAtTime(2250, context.currentTime + 0.07);
      oscillator.frequency.linearRampToValueAtTime(1650, context.currentTime + 0.16);
      gain.gain.setValueAtTime(0.0001, context.currentTime); gain.gain.linearRampToValueAtTime(0.018, context.currentTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + 0.2);
      oscillator.connect(gain).connect(audio.master); oscillator.start(); oscillator.stop(context.currentTime + 0.21);
    };
    audio.update = (dt, elapsed) => {
      if (!audio.enabled || audio.paused) return;
      audio.ensure();
      if (!audio.context) return;
      const speedRatio = THREE.MathUtils.clamp(Math.abs(state.speed) / state.maxSpeed, 0, 1);
      const throttle = state.isAccelerating && !state.isBraking ? 1 : 0;
      // Three virtual gears: rpm climbs within a gear and drops at the shift,
      // which is what makes an engine sound like it is working rather than
      // a siren sliding up with speed.
      const gearPos = speedRatio * 2.85, inGear = gearPos - Math.floor(Math.min(2, gearPos));
      const targetRpm = state.speed < -0.2 ? 0.3 : 0.14 + inGear * 0.68 + throttle * 0.08;
      audio.rpm += (targetRpm - audio.rpm) * Math.min(1, dt * (throttle ? 5 : 3));
      const rpm = audio.rpm, pr = audio.profiles[state.vehicleId] || audio.profile;
      const f0 = (52 + rpm * 118) * pr.pitch;
      ramp(audio.nodes.engineSub.oscillator.frequency, f0 / 2);
      ramp(audio.nodes.engine.oscillator.frequency, f0);
      ramp(audio.nodes.engineFifth.oscillator.frequency, f0 * 1.5);
      ramp(audio.nodes.engineFilter.frequency, (240 + rpm * 900 + throttle * 260) * pr.bright);
      audio.engineLevel = (0.05 + rpm * 0.1 + throttle * 0.04) * pr.level;
      ramp(audio.nodes.engineBus.gain, audio.engineLevel);
      ramp(audio.nodes.grit.filter.frequency, 160 + rpm * 260);
      ramp(audio.nodes.grit.gain.gain, (0.012 + rpm * 0.03 + throttle * 0.012) * pr.grit);
      // Tyres: squeal under hard braking from speed, scrape along a curb.
      ramp(audio.nodes.squeal.gain.gain, state.isBraking && state.speed > 6 ? 0.03 + speedRatio * 0.05 : 0, 0.06);
      ramp(audio.nodes.scrape.gain.gain, state.curbClearTime === 0 && Math.abs(state.speed) > 0.5 ? 0.04 : 0, 0.05);
      if (state.speed < -0.3 && elapsed >= audio.reverseBeepAt) { audio.beep(); audio.reverseBeepAt = elapsed + 0.7; }
      ramp(audio.nodes.rain.gain.gain, (state.rain || 0) * 0.045, 0.3);
      ramp(audio.nodes.road.gain.gain, speedRatio * 0.035);
      ramp(audio.nodes.wind.gain.gain, Math.max(0, speedRatio - 0.3) * 0.012);
      ramp(audio.nodes.ambience.gain.gain, 0.013 + (state.district === 1 ? 0.006 : 0));
      const nearby = state.actors.filter(a => !a.done && a.mesh.visible && !a.fall &&
        actorFootprint(a).p.distanceTo(playerCarGroup.position) < 45);
      const trafficEnergy = nearby.reduce((sum, a) => sum + Math.max(0.1, a.speed / Math.max(1, a.maxSpeed)), 0);
      audio.trafficLevel = Math.min(0.055, trafficEnergy * 0.012);
      ramp(audio.nodes.traffic.gain.gain, audio.trafficLevel);
      ramp(audio.nodes.traffic.oscillator.frequency, 45 + trafficEnergy * 7);
      const trams = nearby.filter(a => a.config.type === 'tram');
      audio.tramLevel = Math.min(0.07, trams.reduce((sum, a) => sum + a.speed, 0) / 150);
      ramp(audio.nodes.tram.gain.gain, audio.tramLevel);
      audio.trackPhase += dt * trams.reduce((sum, a) => sum + a.speed, 0);
      if (audio.trackPhase > 5.5) { audio.trackPhase %= 5.5; audio.transient(180, 0.045, 0.035, 'square'); }
      const siren = nearby.find(a => a.config.siren && a.active && !a.crashed);
      audio.sirenLevel = siren ? Math.max(0, 1 - actorFootprint(siren).p.distanceTo(playerCarGroup.position) / 45) * 0.11 : 0;
      const high = Math.sin(elapsed * Math.PI * 2.4) > 0;
      ramp(audio.nodes.sirenLow.gain.gain, high ? 0 : audio.sirenLevel, 0.04);
      ramp(audio.nodes.sirenHigh.gain.gain, high ? audio.sirenLevel : 0, 0.04);
      if (elapsed >= audio.birdAt && state.speed < 8 && state.district !== 1) {
        audio.chirp(); audio.birdAt = elapsed + 7 + Math.random() * 8;
      }
      ramp(audio.master.gain, 0.72, 0.15);
    };
    audio.snapshot = () => ({ enabled: audio.enabled, paused: audio.paused,
      engine: audio.engineLevel, traffic: audio.trafficLevel, siren: audio.sirenLevel, tram: audio.tramLevel });
    return audio;
  }

  // --- Initialization ---
  function init() {
    // A native WebView can load before Flutter has given it a layout size.
    // Never put a zero viewport into the camera's projection matrix.
    const width = Math.max(1, container.clientWidth || window.innerWidth);
    const height = Math.max(1, container.clientHeight || window.innerHeight);
    gameAudio = createGameAudio();

    // Scene
    scene = new THREE.Scene();
    scene.background = new THREE.Color(BRAND.asphaltMarking);
    scene.fog = new THREE.FogExp2(BRAND.asphaltMarking, 0.007);

    // Orthographic Camera looking straight forward/up
    const aspect = width / height;
    const viewSize = 42;
    camera = new THREE.OrthographicCamera(
      -viewSize * aspect / 2,
       viewSize * aspect / 2,
       viewSize / 2,
      -viewSize / 2,
      -200,
       800
    );

    // Initial camera position (directly behind and above car looking forward)
    camera.position.set(0, 42, -36);
    camera.lookAt(0, 0, 14);

    // Renderer
    // Weak phones (few cores / little memory) get a cheaper profile: no soft
    // shadow filtering, a smaller shadow map and 1x pixel ratio.
    const lowEnd = (navigator.hardwareConcurrency || 8) <= 4 || (navigator.deviceMemory || 8) <= 3;
    state.lowEnd = lowEnd;
    renderer = new THREE.WebGLRenderer({ antialias: !lowEnd, powerPreference: 'high-performance' });
    renderer.setSize(width, height);
    renderer.setPixelRatio(lowEnd ? 1 : Math.min(window.devicePixelRatio, 1.75));
    renderer.shadowMap.enabled = true;
    // PCF with a blur radius: soft-edged shadows (PCFSoft ignores radius).
    renderer.shadowMap.type = THREE.PCFShadowMap;
    renderer.localClippingEnabled = true;
    container.appendChild(renderer.domElement);

    // Lights
    setupLights();

    // Global continuous terrain ground (no cutoffs ever)
    const groundGeo = new THREE.PlaneGeometry(800, 4000);
    groundGeo.rotateX(-Math.PI / 2);
    const groundMat = new THREE.MeshLambertMaterial({ color: season().ground });
    groundMat.userData.seasonal = 'ground';
    const groundMesh = new THREE.Mesh(groundGeo, groundMat);
    groundMesh.position.set(0, -0.05, 500);
    groundMesh.receiveShadow = true;
    scene.add(groundMesh);
    terrainMesh = groundMesh;

    // Player Car
    playerCarGroup = createPlayerCar();
    playerCarGroup.position.x = -1.8;
    scene.add(playerCarGroup);

    // Build initial road segments
    buildInitialTrack();

    // Event Listeners
    window.addEventListener('resize', onWindowResize);
    setupTouchControls();

    // Hide loader
    const loader = document.getElementById('loading-overlay');
    if (loader) loader.style.display = 'none';

    // Notify Flutter that engine is ready
    sendToFlutter({ event: 'ready' });

    // Animation Loop
    animate(0);
  }

  // --- Lighting Setup ---
  function setupLights() {
    ambientLight = new THREE.AmbientLight(0xFFFFFF, 0.75);
    scene.add(ambientLight);

    // A high sun: short, soft daytime shadows that read as ground contact,
    // not long dramatic streaks.
    dirLight = new THREE.DirectionalLight(0xFFF9EE, 0.85);
    dirLight.position.set(12, 70, -7);
    dirLight.castShadow = true;
    dirLight.shadow.mapSize.width = state.lowEnd ? 512 : 1024;
    dirLight.shadow.mapSize.height = state.lowEnd ? 512 : 1024;
    dirLight.shadow.camera.near = 10;
    dirLight.shadow.camera.far = 200;
    const d = 40;
    dirLight.shadow.camera.left = -d;
    dirLight.shadow.camera.right = d;
    dirLight.shadow.camera.top = d;
    dirLight.shadow.camera.bottom = -d;
    dirLight.shadow.bias = -0.0005;
    dirLight.shadow.radius = state.lowEnd ? 2 : 5;
    scene.add(dirLight);

    sunTarget = new THREE.Object3D();
    scene.add(sunTarget);
    dirLight.target = sunTarget;
  }

  // --- Actor Floating Badge Factory ---
  function createActorBadge(text, bgColor = '#0574F8') {
    const canvas = document.createElement('canvas');
    canvas.width = 160;
    canvas.height = 70;
    const ctx = canvas.getContext('2d');

    const fill = typeof bgColor === 'number' ? '#' + bgColor.toString(16).padStart(6, '0') : bgColor;
    ctx.fillStyle = fill;
    ctx.beginPath();
    ctx.roundRect(6, 6, 148, 58, 14);
    ctx.fill();

    ctx.fillStyle = '#FFFFFF';
    ctx.font = '600 28px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, 80, 35, 138);

    const texture = new THREE.CanvasTexture(canvas);
    texture.minFilter = THREE.LinearFilter;
    const mat = new THREE.SpriteMaterial({ map: texture, depthTest: false });
    const sprite = new THREE.Sprite(mat);
    sprite.scale.set(3.2, 1.25, 1);
    return sprite;
  }

  // --- Touch & Gesture Controls ---
  let touchStartX = 0, touchStartY = 0;
  function setupTouchControls() {
    const el = renderer.domElement;

    // Acceleration on press
    el.addEventListener('touchstart', (e) => {
      if (e.touches.length > 0) { state.dragX = e.touches[0].clientX; state.dragMoved = 0; }
      if (state.nativeControls) return;
      e.preventDefault();
      if (!state.paused && !state.isAtSituation && !state.isResolvingSituation) state.isAccelerating = true;
      if (e.touches.length > 0) {
        touchStartX = e.touches[0].clientX;
        touchStartY = e.touches[0].clientY;
      }
    }, { passive: false });

    el.addEventListener('touchmove', (e) => {
      if (!e.touches.length || !(state.attract || reveal)) return;
      const x = e.touches[0].clientX, dx = x - (state.dragX ?? x); state.dragX = x; state.dragMoved = (state.dragMoved || 0) + Math.abs(dx);
      if (reveal) { if (reveal.phase === 'shown') { reveal.yaw += dx * 0.012; reveal.spin = dx * 0.6; } }
      else state.orbitYaw = (state.orbitYaw || 0) + dx * 0.006;
      e.preventDefault();
    }, { passive: false });
    el.addEventListener('touchend', (e) => {
      if (reveal && reveal.phase === 'closed' && (state.dragMoved || 0) < 12) { reveal.phase = 'opening'; reveal.t = 0; gameAudio?.click(); }
      if (state.nativeControls) return;
      e.preventDefault();
      state.isAccelerating = false;
      if (e.changedTouches.length > 0) {
        const dx = e.changedTouches[0].clientX - touchStartX;
        const dy = e.changedTouches[0].clientY - touchStartY;
        // Horizontal swipe: change lane
        if (Math.abs(dx) > 35 && Math.abs(dx) > Math.abs(dy)) {
          if (dx > 0) switchLane('right');
          else switchLane('left');
        }
      }
    }, { passive: false });

    el.addEventListener('touchcancel', () => {
      if (state.nativeControls) return;
      state.isAccelerating = false;
    });

    // Mouse fallback for testing
    el.addEventListener('mousedown', () => { if (!state.nativeControls && !state.paused && !state.isAtSituation && !state.isResolvingSituation) state.isAccelerating = true; });
    window.addEventListener('mouseup', () => { if (!state.nativeControls) state.isAccelerating = false; });
  }

  function switchLane(direction) {
    if (state.paused || state.isAtSituation || state.isResolvingSituation) return;
    if (direction === 'left' && state.targetLane > 0) {
      state.targetLane--;
      triggerBlinker('left');
    } else if (direction === 'right' && state.targetLane < 1) {
      state.targetLane++;
      triggerBlinker('right');
    }
    // With forward = +Z, the driver's right is -X (also screen-right).
    state.targetLaneOffset = (state.targetLane === 0 ? 1.8 : -1.8);
  }

  function triggerBlinker(side) {
    if (!playerCarGroup) return;
    const blinker = side === 'left' ? playerCarGroup.blinkerL : playerCarGroup.blinkerR;
    if (!blinker) return;
    state.blinker = { side, remaining: 2.2, elapsed: 0 };
  }

  // --- Low-Poly Car Factory ---
  function createPlayerCar() {
    const car = window.PDD_VEHICLES.create(state.vehicleId || "hatch", state.vehiclePaint || null);
    playerWheels = car.userData.wheels;
    return car;
  }

  function selectVehicle(id, paint = null) {
    if (!window.PDD_VEHICLES.specs[id] || (!state.paused && Math.abs(state.speed) > 0.1)) return;
    state.speed = 0; state.isAccelerating = false; state.isBraking = false; state.steering = 0;
    if (state.vehicleId === id && (state.vehiclePaint || null) === (paint || null)) {
      sendToFlutter({ event: 'vehicle_selected', vehicleId: id });
      return;
    }
    const previous = playerCarGroup;
    const previousId = state.vehicleId || 'hatch', previousPaint = state.vehiclePaint || null;
    state.vehicleId = id; state.vehiclePaint = paint || null;
    gameAudio?.setVehicle(id);
    playerCarGroup = createPlayerCar();
    playerCarGroup.position.copy(previous.position);
    playerCarGroup.quaternion.copy(previous.quaternion);
    // A larger body must fit before it replaces the old one. Find the closest
    // free position without turning the car or moving any surrounding traffic.
    const free = () => playerOnRoad() && !state.actors.some(a => !a.done && !a.fall &&
      footprintsOverlap(playerFootprint(), actorFootprint(a), 0.05));
    let fits = free();
    for (let radius = 0.1; !fits && radius <= 3; radius += 0.1) {
      for (let i = 0; i < 32; i++) {
        const angle = i * Math.PI / 16;
        playerCarGroup.position.copy(previous.position).add(new THREE.Vector3(Math.cos(angle) * radius, 0, Math.sin(angle) * radius));
        if (free()) { fits = true; break; }
      }
    }
    if (!fits) {
      disposeSegment(playerCarGroup);
      playerCarGroup = previous;
      playerWheels = previous.userData.wheels;
      state.vehicleId = previousId; state.vehiclePaint = previousPaint;
      sendToFlutter({ event: 'vehicle_selected', vehicleId: previousId });
      return;
    }
    scene.add(playerCarGroup);
    disposeSegment(previous);
    sendToFlutter({ event: 'vehicle_selected', vehicleId: id });
    renderer.render(scene, camera);
  }

  // --- Tram Model Factory ---
  function createTram(color = BRAND.tramRed) {
    const tram = new THREE.Group();
    const bodyMat = new THREE.MeshLambertMaterial({ color: color });
    const whiteMat = new THREE.MeshLambertMaterial({ color: BRAND.tramWhite });
    const glassMat = new THREE.MeshLambertMaterial({ color: 0x1E293B });
    const metalMat = new THREE.MeshLambertMaterial({ color: 0x71717A });

    // Lower body (color)
    const lowerGeo = new THREE.BoxGeometry(2.2, 1.0, 9.5);
    const lower = new THREE.Mesh(lowerGeo, bodyMat);
    lower.position.y = 0.7;
    lower.castShadow = true;
    tram.add(lower);
    tram.userData.lampSpec = { front: { x: 0.6, y: 0.75, z: 4.75 }, rear: { x: 0.6, y: 0.75, z: -4.75 } };

    // Upper stripe / roof (white)
    const upperGeo = new THREE.BoxGeometry(2.15, 1.1, 9.4);
    const upper = new THREE.Mesh(upperGeo, whiteMat);
    upper.position.y = 1.7;
    upper.castShadow = true;
    tram.add(upper);

    // Continuous glass strip on sides
    const sideWindowsGeo = new THREE.BoxGeometry(2.24, 0.65, 8.8);
    const sideWindows = new THREE.Mesh(sideWindowsGeo, glassMat);
    sideWindows.position.y = 1.75;
    tram.add(sideWindows);

    // Front/Back glass
    const frontGlassGeo = new THREE.BoxGeometry(1.9, 0.8, 0.1);
    const fg = new THREE.Mesh(frontGlassGeo, glassMat);
    fg.position.set(0, 1.65, 4.76);
    tram.add(fg);

    // Pantograph (current collector on roof)
    const pantoBase = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.15, 0.8), metalMat);
    pantoBase.position.set(0, 2.35, 1.5);
    tram.add(pantoBase);

    const barGeo = new THREE.CylinderGeometry(0.04, 0.04, 1.1);
    const bar1 = new THREE.Mesh(barGeo, metalMat);
    bar1.position.set(0, 2.85, 1.5);
    bar1.rotation.x = 0.35;
    tram.add(bar1);

    const headGeo = new THREE.BoxGeometry(1.6, 0.06, 0.2);
    const head = new THREE.Mesh(headGeo, metalMat);
    head.position.set(0, 3.3, 1.7);
    tram.add(head);

    return tram;
  }

  // --- NPC Car Factory ---
  // Details that turn a box into a car: bumpers, grille, head/tail lights,
  // mirrors, rims, side windows and a door line. Coordinates: +Z = front.
  function addVehicleDetails(group, o) {
    const dark = new THREE.MeshLambertMaterial({ color: 0x23272C });
    const chrome = new THREE.MeshLambertMaterial({ color: 0xC9D1D6 });
    const head = new THREE.MeshBasicMaterial({ color: 0xFFF3CC }), tail = new THREE.MeshBasicMaterial({ color: 0xD33D38 });
    const glass = new THREE.MeshLambertMaterial({ color: 0x1E293B });
    const box = (w, h, d, x, y, z, mat) => { const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); m.position.set(x, y, z); group.add(m); return m; };
    const { width: W, length: L, baseY, lampY, cabinY, cabinH, cabinZ, cabinL } = o;
    box(W + 0.06, 0.16, 0.18, 0, baseY - 0.16, L / 2 - 0.02, dark);   // front bumper
    box(W + 0.06, 0.16, 0.18, 0, baseY - 0.16, -L / 2 + 0.02, dark);  // rear bumper
    box(W * 0.42, 0.14, 0.04, 0, lampY, L / 2 + 0.02, dark);          // grille
    [-1, 1].forEach(sx => {
      box(0.32, 0.13, 0.05, sx * W * 0.34, lampY, L / 2 + 0.03, head);
      box(0.3, 0.12, 0.05, sx * W * 0.34, lampY, -L / 2 - 0.03, tail);
      box(0.05, 0.05, 0.1, sx * W * 0.34, lampY - 0.11, -L / 2 - 0.02, chrome); // exhaust hint / reflector
      const mirror = box(0.08, 0.1, 0.16, sx * (W / 2 + 0.1), cabinY + 0.05, cabinZ + cabinL / 2 - 0.15, dark);
      mirror.rotation.y = sx * 0.2;
      if (cabinH) {
        box(0.02, cabinH * 0.62, cabinL * 0.82, sx * (o.cabinW / 2 + 0.005), cabinY + cabinH * 0.06, cabinZ, glass); // side windows
        box(0.02, baseY * 0.9, 0.03, sx * (W / 2 + 0.005), baseY, cabinZ + 0.1, dark);                              // door line
      }
    });
    if (o.wheels) o.wheels.forEach(w => {
      const rim = new THREE.Mesh(new THREE.CylinderGeometry(o.wheelR * 0.55, o.wheelR * 0.55, o.wheelW + 0.02, 8).rotateZ(Math.PI / 2), chrome);
      rim.position.copy(w.position); group.add(rim);
    });
  }

  function createNpcCar(color = 0x2BC280) {
    const car = new THREE.Group();
    const bodyMat = new THREE.MeshLambertMaterial({ color });
    const glassMat = new THREE.MeshLambertMaterial({ color: 0x1E293B });
    const wheelMat = new THREE.MeshLambertMaterial({ color: 0x18181B });

    const body = new THREE.Mesh(new THREE.BoxGeometry(1.75, 0.55, 3.6), bodyMat);
    body.position.y = 0.5;
    body.castShadow = true;
    car.add(body);
    car.userData.lampSpec = { front: { x: 0.6, y: 0.62, z: 1.8 }, rear: { x: 0.6, y: 0.62, z: -1.8 } };

    const cabin = new THREE.Mesh(new THREE.BoxGeometry(1.45, 0.5, 1.9), bodyMat);
    cabin.position.set(0, 0.95, -0.2);
    cabin.castShadow = true;
    car.add(cabin);

    const glass = new THREE.Mesh(new THREE.BoxGeometry(1.48, 0.38, 1.6), glassMat);
    glass.position.set(0, 0.95, -0.2);
    car.add(glass);

    const wheelGeo = new THREE.CylinderGeometry(0.32, 0.32, 0.25, 10);
    wheelGeo.rotateZ(Math.PI / 2);
    const wheels = [[-0.88, 0.32, 1.05], [0.88, 0.32, 1.05], [-0.88, 0.32, -1.05], [0.88, 0.32, -1.05]].map(p => {
      const w = new THREE.Mesh(wheelGeo, wheelMat);
      w.position.set(p[0], p[1], p[2]);
      car.add(w); return w;
    });
    addVehicleDetails(car, { width: 1.75, length: 3.6, baseY: 0.5, lampY: 0.62, cabinY: 0.95, cabinH: 0.5, cabinZ: -0.2, cabinL: 1.9, cabinW: 1.45, wheels, wheelR: 0.32, wheelW: 0.25 });

    return car;
  }

  // --- Bus Model Factory ---
  function createBus(color = 0xF59E0B) {
    const bus = new THREE.Group();
    const bodyMat = new THREE.MeshLambertMaterial({ color });
    const roofMat = new THREE.MeshLambertMaterial({ color: 0xF1F5F9 });
    const glassMat = new THREE.MeshLambertMaterial({ color: 0x1E293B });
    const darkMat = new THREE.MeshLambertMaterial({ color: 0x334155 });
    const wheelMat = new THREE.MeshLambertMaterial({ color: 0x18181B });
    const lightMat = new THREE.MeshBasicMaterial({ color: 0xFEF08A });

    // Lower & main body
    const body = new THREE.Mesh(new THREE.BoxGeometry(2.15, 1.4, 6.8), bodyMat);
    body.position.y = 1.0;
    body.castShadow = true;
    bus.add(body);
    bus.userData.lampSpec = { front: { x: 0.75, y: 0.75, z: 3.4 }, rear: { x: 0.75, y: 0.95, z: -3.4 } };

    // Upper roof
    const roof = new THREE.Mesh(new THREE.BoxGeometry(2.1, 0.4, 6.7), roofMat);
    roof.position.y = 1.85;
    roof.castShadow = true;
    bus.add(roof);

    // AC unit on roof
    const ac = new THREE.Mesh(new THREE.BoxGeometry(1.2, 0.25, 2.0), darkMat);
    ac.position.set(0, 2.15, 0.4);
    bus.add(ac);

    // Side windows strip
    const sideGlass = new THREE.Mesh(new THREE.BoxGeometry(2.18, 0.65, 6.2), glassMat);
    sideGlass.position.y = 1.45;
    bus.add(sideGlass);

    // Front windshield
    const frontGlass = new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.85, 0.1), glassMat);
    frontGlass.position.set(0, 1.4, 3.41);
    bus.add(frontGlass);

    // Front Headlights
    [-0.8, 0.8].forEach(x => {
      const hl = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.2, 0.08), lightMat);
      hl.position.set(x, 0.6, 3.42);
      bus.add(hl);
    });

    // Wheels
    const wheelGeo = new THREE.CylinderGeometry(0.42, 0.42, 0.3, 12);
    wheelGeo.rotateZ(Math.PI / 2);
    const wheels = [[-1.0, 0.42, 2.1], [1.0, 0.42, 2.1], [-1.0, 0.42, -1.8], [1.0, 0.42, -1.8]].map(p => {
      const w = new THREE.Mesh(wheelGeo, wheelMat);
      w.position.set(p[0], p[1], p[2]);
      bus.add(w); return w;
    });
    const dark = new THREE.MeshLambertMaterial({ color: 0x23272C }), chrome = new THREE.MeshLambertMaterial({ color: 0xC9D1D6 });
    const put = (geo, mat, x, y, z) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); bus.add(m); return m; };
    put(new THREE.BoxGeometry(2.2, 0.16, 0.2), dark, 0, 0.35, 3.42);
    put(new THREE.BoxGeometry(2.2, 0.16, 0.2), dark, 0, 0.35, -3.42);
    [-1, 1].forEach(sx => {
      put(new THREE.BoxGeometry(0.3, 0.16, 0.06), new THREE.MeshBasicMaterial({ color: 0xD33D38 }), sx * 0.8, 0.7, -3.43);
      put(new THREE.BoxGeometry(0.1, 0.22, 0.2), dark, sx * 1.18, 1.55, 3.1);
    });
    put(new THREE.BoxGeometry(0.02, 1.2, 0.9), new THREE.MeshLambertMaterial({ color: 0x2B3640 }), -1.09, 0.95, 1.4); // door (right side)
    wheels.forEach(w => { const rim = put(new THREE.CylinderGeometry(0.22, 0.22, 0.32, 8).rotateZ(Math.PI / 2), chrome, 0, 0, 0); rim.position.copy(w.position); });

    return bus;
  }

  // --- Truck Model Factory ---
  // Farm tractor: big rear wheels, small front wheels, narrow bonnet, open
  // cab with a roof, exhaust stack. Faces +Z like every other vehicle.
  function createTractor(color = 0xF2B233) {
    const t = new THREE.Group();
    const body = new THREE.MeshLambertMaterial({ color });
    const dark = new THREE.MeshLambertMaterial({ color: 0x2B2F33 });
    const rim = new THREE.MeshLambertMaterial({ color: 0xD9D2C0 });
    const glass = new THREE.MeshLambertMaterial({ color: 0x1E293B });
    const add = (mesh, x, y, z) => { mesh.position.set(x, y, z); mesh.castShadow = true; t.add(mesh); return mesh; };
    add(new THREE.Mesh(new THREE.BoxGeometry(1.1, 0.9, 2.0), body), 0, 1.15, 1.3);          // bonnet
    add(new THREE.Mesh(new THREE.BoxGeometry(1.0, 0.1, 0.4), dark), 0, 1.62, 2.1);           // radiator top
    t.userData.lampSpec = { front: { x: 0.35, y: 1.2, z: 2.3 }, rear: { x: 0.6, y: 1.15, z: -1.25 } };
    add(new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.5, 1.5), body), 0, 1.05, -0.5);          // seat deck
    add(new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.6, 0.35), dark), 0, 1.55, -0.95);        // seat back
    add(new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.1, 1.5), body), 0, 2.85, -0.45);         // cab roof
    [[-0.75, 0.5], [0.75, 0.5], [-0.75, -1.35], [0.75, -1.35]].forEach(([x, z]) =>
      add(new THREE.Mesh(new THREE.BoxGeometry(0.08, 1.6, 0.08), dark), x, 2.05, z));        // cab posts
    add(new THREE.Mesh(new THREE.BoxGeometry(1.5, 1.0, 0.06), glass), 0, 2.25, 0.5);         // windscreen
    add(new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 1.2, 6), dark), 0.45, 2.2, 1.9); // exhaust
    add(new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 0.08, 10).rotateX(Math.PI / 2), dark), 0, 2.1, 0.45); // steering wheel
    const wheel = (r, w, x, z) => {
      const tyre = add(new THREE.Mesh(new THREE.CylinderGeometry(r, r, w, 14).rotateZ(Math.PI / 2), dark), x, r, z);
      add(new THREE.Mesh(new THREE.CylinderGeometry(r * 0.55, r * 0.55, w + 0.02, 10).rotateZ(Math.PI / 2), rim), x, r, z);
      return tyre;
    };
    t.userData.wheels = [wheel(0.85, 0.5, -0.95, -0.7), wheel(0.85, 0.5, 0.95, -0.7), wheel(0.42, 0.3, -0.7, 1.6), wheel(0.42, 0.3, 0.7, 1.6)];
    return t;
  }

  function createTruck(color = 0x3B82F6) {
    const truck = new THREE.Group();
    const cabMat = new THREE.MeshLambertMaterial({ color });
    const containerMat = new THREE.MeshLambertMaterial({ color: 0x64748B });
    const glassMat = new THREE.MeshLambertMaterial({ color: 0x1E293B });
    const wheelMat = new THREE.MeshLambertMaterial({ color: 0x18181B });

    // Driver Cab
    const cab = new THREE.Mesh(new THREE.BoxGeometry(2.1, 1.6, 2.0), cabMat);
    cab.position.set(0, 1.15, 1.8);
    cab.castShadow = true;
    truck.add(cab);

    // Cab windshield
    const wind = new THREE.Mesh(new THREE.BoxGeometry(2.0, 0.65, 0.1), glassMat);
    wind.position.set(0, 1.45, 2.81);
    truck.add(wind);
    truck.userData.lampSpec = { front: { x: 0.75, y: 0.85, z: 2.8 }, rear: { x: 0.8, y: 0.75, z: -3.6 } };

    // Cargo Box
    const cargo = new THREE.Mesh(new THREE.BoxGeometry(2.2, 2.1, 4.4), containerMat);
    cargo.position.set(0, 1.5, -1.4);
    cargo.castShadow = true;
    truck.add(cargo);

    // Chassis frame
    const chassis = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.28, 6.2), new THREE.MeshLambertMaterial({ color: 0x334155 }));
    chassis.position.set(0, 0.45, 0.1);
    truck.add(chassis);

    // Wheels
    const wheelGeo = new THREE.CylinderGeometry(0.42, 0.42, 0.3, 12);
    wheelGeo.rotateZ(Math.PI / 2);
    const wheels = [[-1.0, 0.42, 1.8], [1.0, 0.42, 1.8], [-1.0, 0.42, -1.0], [1.0, 0.42, -1.0], [-1.0, 0.42, -2.4], [1.0, 0.42, -2.4]].map(p => {
      const w = new THREE.Mesh(wheelGeo, wheelMat);
      w.position.set(p[0], p[1], p[2]);
      truck.add(w); return w;
    });
    // Cab lights, grille, mirrors and rims; a rear light bar on the box.
    const dark = new THREE.MeshLambertMaterial({ color: 0x23272C }), chrome = new THREE.MeshLambertMaterial({ color: 0xC9D1D6 });
    const put = (geo, mat, x, y, z) => { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); truck.add(m); return m; };
    put(new THREE.BoxGeometry(1.4, 0.34, 0.05), dark, 0, 0.95, 2.82);
    put(new THREE.BoxGeometry(2.2, 0.18, 0.2), dark, 0, 0.5, 2.85);
    [-1, 1].forEach(sx => {
      put(new THREE.BoxGeometry(0.34, 0.16, 0.06), new THREE.MeshBasicMaterial({ color: 0xFFF3CC }), sx * 0.75, 0.85, 2.84);
      put(new THREE.BoxGeometry(0.3, 0.14, 0.06), new THREE.MeshBasicMaterial({ color: 0xD33D38 }), sx * 0.85, 0.75, -3.63);
      put(new THREE.BoxGeometry(0.1, 0.2, 0.22), dark, sx * 1.18, 1.55, 2.4);
      put(new THREE.BoxGeometry(0.02, 0.5, 1.2), new THREE.MeshLambertMaterial({ color: 0x1E293B }), sx * 1.06, 1.35, 1.7);
    });
    wheels.forEach(w => { const rim = put(new THREE.CylinderGeometry(0.22, 0.22, 0.32, 8).rotateZ(Math.PI / 2), chrome, 0, 0, 0); rim.position.copy(w.position); });

    return truck;
  }

  // --- Special / Police Car Model Factory ---
  function createSpecialCar(color = 0xFFFFFF) {
    const car = createNpcCar(color);
    // Blue side stripe
    const stripeMat = new THREE.MeshLambertMaterial({ color: 0x0574F8 });
    const s1 = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.22, 3.2), stripeMat);
    s1.position.set(-0.9, 0.6, 0);
    const s2 = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.22, 3.2), stripeMat);
    s2.position.set(0.9, 0.6, 0);
    car.add(s1);
    car.add(s2);

    // Flashing light bar on roof
    const bar = new THREE.Group();
    bar.position.set(0, 1.25, -0.2);
    const mount = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.08, 0.2), new THREE.MeshLambertMaterial({ color: 0x1E293B }));
    bar.add(mount);

    const blueBeacon = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.16, 0.18), new THREE.MeshBasicMaterial({ color: 0x0574F8 }));
    blueBeacon.position.set(-0.2, 0.1, 0);
    const redBeacon = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.16, 0.18), new THREE.MeshBasicMaterial({ color: 0xEF4444 }));
    redBeacon.position.set(0.2, 0.1, 0);
    bar.add(blueBeacon);
    bar.add(redBeacon);
    car.add(bar);
    car.userData.beacons = [blueBeacon, redBeacon];
    window.PDD_VEHICLES.addGlow(blueBeacon, 0x208CFF, 1.7);
    window.PDD_VEHICLES.addGlow(redBeacon, 0xFF3434, 1.7);

    return car;
  }

  // --- Motorcycle Model Factory ---
  function createMotorcycle(color = 0xF59E0B) {
    const moto = new THREE.Group();
    const bodyMat = new THREE.MeshLambertMaterial({ color });
    const darkMat = new THREE.MeshLambertMaterial({ color: 0x1E293B });
    const wheelMat = new THREE.MeshLambertMaterial({ color: 0x18181B });
    const riderMat = sceneryMat(PEOPLE_COLORS[Math.floor(Math.random() * PEOPLE_COLORS.length)]);

    // Chassis
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.48, 0.55, 1.7), bodyMat);
    body.position.set(0, 0.58, 0);
    body.castShadow = true;
    moto.add(body);

    // Handlebars
    moto.userData.lampSpec = { front: { x: 0, y: 0.85, z: 0.85 }, rear: { x: 0, y: 0.72, z: -0.85 }, single: true };
    const hb = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.75, 8), darkMat);
    hb.rotateZ(Math.PI / 2);
    hb.position.set(0, 0.92, 0.6);
    moto.add(hb);

    // 2 Wheels
    const wheelGeo = new THREE.CylinderGeometry(0.34, 0.34, 0.14, 12);
    wheelGeo.rotateZ(Math.PI / 2);
    [0.72, -0.72].forEach(z => {
      const w = new THREE.Mesh(wheelGeo, wheelMat);
      w.position.set(0, 0.34, z);
      moto.add(w);
    });

    // Rider
    const torso = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.52, 0.32), riderMat);
    torso.position.set(0, 1.0, -0.1);
    torso.rotation.x = -0.15;
    moto.add(torso);

    const helmet = new THREE.Mesh(new THREE.SphereGeometry(0.2, 10, 8), bodyMat);
    helmet.position.set(0, 1.38, -0.05);
    moto.add(helmet);

    return moto;
  }

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
  function modelBar(group, start, end, width, color) {
    const a = new THREE.Vector3(...start), b = new THREE.Vector3(...end);
    const mesh = modelBox(group, [width, a.distanceTo(b), width], color, ...a.clone().add(b).multiplyScalar(0.5).toArray());
    mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), b.sub(a).normalize());
    return mesh;
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

  // --- Cyclist Model Factory ---
  function createCyclist(color = 0x10B981, variant = Math.floor(Math.random() * 12)) {
    const bike = new THREE.Group(), rider = new THREE.Group();
    const look = personLook(variant), style = variant % 3;
    bike.add(rider); bike.userData.rider = rider;
    bike.userData.wheels = [];
    const dark = 0x303942, tyre = 0x23282D;
    // Open low-poly rims and spokes have the same triangle count as solid tyres.
    [0.65, -0.65].forEach(z => {
      const wheel = new THREE.Group(); wheel.position.set(0, 0.36, z);
      const ring = modelPart(wheel, new THREE.RingGeometry(0.31, 0.36, 12), tyre, 0, 0, 0);
      ring.rotation.y = Math.PI / 2;
      modelBox(wheel, [0.045, 0.63, 0.025], 0x9AA7AD, 0, 0, 0);
      modelBox(wheel, [0.045, 0.025, 0.63], 0x9AA7AD, 0, 0, 0);
      mergeModelParts(wheel, true); bike.add(wheel); bike.userData.wheels.push(wheel);
    });
    const rear = [0, 0.36, -0.65], crank = [0, 0.48, -0.06];
    const saddle = [0, 0.83, -0.25], fork = [0, 0.84, 0.45];
    [[rear, crank], [rear, saddle], [saddle, crank], [crank, fork],
      [style === 0 ? crank : saddle, fork], [fork, [0, 0.36, 0.65]]].forEach(([a, b]) => modelBar(bike, a, b, 0.055, color));
    modelBox(bike, [0.24, 0.07, 0.3], dark, 0, 0.85, -0.27);
    modelBar(bike, fork, [0, 1.01, 0.48], 0.045, dark);
    modelBox(bike, [0.48, 0.045, 0.06], dark, 0, 1.01, 0.48);
    if (style === 0) modelBox(bike, [0.4, 0.24, 0.28], 0xB59C70, 0, 0.91, 0.66);
    if (style === 2) modelBox(bike, [0.32, 0.3, 0.32], look.pants, 0.16, 0.58, -0.65);

    const torso = modelBox(rider, [0.3, 0.44, 0.25], look.top, 0, 1.06, -0.15);
    torso.rotation.x = 0.24 + style * 0.08;
    modelPart(rider, new THREE.SphereGeometry(0.15, 8, 6), look.skin, 0, 1.38, -0.05);
    modelPart(rider, new THREE.SphereGeometry(0.18, 8, 4, 0, Math.PI * 2, 0, Math.PI / 2), style === 1 ? 0xE8E2CF : color, 0, 1.4, -0.05);
    modelBox(rider, [0.09, 0.035, 0.27], dark, 0, 1.565, -0.05);
    if (style === 2) modelBox(rider, [0.25, 0.33, 0.14], 0xD6AA50, 0, 1.04, -0.34);
    [-1, 1].forEach(side => {
      modelBar(rider, [side * 0.18, 1.2, -0.07], [side * 0.2, 1.02, 0.47], 0.09, look.top);
      modelBox(rider, [0.085, 0.08, 0.1], look.skin, side * 0.2, 1.02, 0.47);
      modelBar(rider, [side * 0.13, 0.87, -0.2], [side * 0.13, 0.65, 0.15], 0.12, look.pants);
      modelBar(rider, [side * 0.13, 0.65, 0.15], [side * 0.13, 0.34, -0.04], 0.1, look.pants);
    });
    const pedals = new THREE.Group(); pedals.position.set(0, 0.48, -0.06);
    [-1, 1].forEach(side => {
      modelBox(pedals, [0.07, 0.28, 0.06], dark, side * 0.16, side * 0.1, 0);
      modelBox(pedals, [0.18, 0.05, 0.08], dark, side * 0.19, side * 0.24, 0);
    });
    mergeModelParts(pedals); bike.add(pedals); bike.userData.pedals = pedals;
    mergeModelParts(rider); mergeModelParts(bike);
    bike.userData.appearance = variant;
    return bike;
  }

  // --- Pedestrian Model Factory ---
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

  // --- Russian Road Sign Factory (GOST 52290) ---
  function createRoadSign(code, poleHeight = 3.2) {
    const group = new THREE.Group();
    const pole = new THREE.Mesh(
      new THREE.CylinderGeometry(0.045, 0.055, poleHeight, 8),
      new THREE.MeshLambertMaterial({ color: 0x697477 })
    );
    pole.position.y = poleHeight / 2;
    pole.castShadow = true;
    group.add(pole);
    let texture = signTextureCache.get(code);
    if (!texture && window.PDD_SIGN_TEXTURES && window.PDD_SIGN_TEXTURES[code]) {
      texture = new THREE.TextureLoader().load(window.PDD_SIGN_TEXTURES[code]);
      texture.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
      signTextureCache.set(code, texture);
    }
    // A transparent exact SVG face, no nested coplanar coloured primitives.
    const face = new THREE.Mesh(
      new THREE.PlaneGeometry(1.6, 1.6),
      new THREE.MeshBasicMaterial({ map: texture, transparent: true, alphaTest: 0.12, side: THREE.DoubleSide })
    );
    face.position.set(0, poleHeight - 0.25, -0.065);
    face.rotation.y = Math.PI;
    group.add(face);
    return group;
  }

  function createTriangleMesh(size, depth, color) {
    const shape = new THREE.Shape();
    const h = size * Math.sqrt(3) / 2;
    shape.moveTo(-size / 2, -h / 3);
    shape.lineTo(size / 2, -h / 3);
    shape.lineTo(0, 2 * h / 3);
    shape.closePath();

    const geom = new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: false });
    return new THREE.Mesh(geom, new THREE.MeshBasicMaterial({ color }));
  }

  // --- Working Traffic Light Factory ---
  function createPriorityPlate(mainRoad = ['south', 'north']) {
    const canvas = document.createElement('canvas');
    canvas.width = 240; canvas.height = 180;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fafafa'; ctx.fillRect(0, 0, 240, 180);
    ctx.strokeStyle = '#20252a'; ctx.lineWidth = 8; ctx.strokeRect(5, 5, 230, 170);
    const ends = { north: [120, 25], south: [120, 155], west: [30, 90], east: [210, 90] };
    Object.keys(ends).forEach(direction => {
      ctx.lineWidth = mainRoad.includes(direction) ? 24 : 6;
      ctx.beginPath(); ctx.moveTo(120, 90); ctx.lineTo(...ends[direction]); ctx.stroke();
    });
    const face = new THREE.Mesh(new THREE.PlaneGeometry(1.25, 0.94),
      new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(canvas), side: THREE.DoubleSide }));
    face.rotation.y = Math.PI;
    const group = new THREE.Group(); group.add(face);
    return group;
  }

  function createTrafficLight(initialState = 'red', arrow = null) {
    const tl = new THREE.Group();
    const metalMat = new THREE.MeshLambertMaterial({ color: 0x334155 });
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 4.2, 8), metalMat);
    post.position.y = 2.1;
    post.castShadow = true;
    tl.add(post);

    // Housing box
    const box = new THREE.Mesh(new THREE.BoxGeometry(0.65, 1.6, 0.4), new THREE.MeshLambertMaterial({ color: 0x1E293B }));
    box.position.set(0, 3.4, 0.25);
    box.castShadow = true;
    tl.add(box);

    // 3 Lamps
    const redMat = new THREE.MeshBasicMaterial({ color: initialState === 'red' ? 0xEF4444 : 0x4B1818 });
    const yellowMat = new THREE.MeshBasicMaterial({ color: initialState === 'yellow' ? 0xF59E0B : 0x4D3608 });
    const greenMat = new THREE.MeshBasicMaterial({ color: initialState === 'green' ? 0x10B981 : 0x063B26 });

    const lampGeo = new THREE.CylinderGeometry(0.21, 0.21, 0.06, 20);
    lampGeo.rotateX(Math.PI / 2);

    const redLamp = new THREE.Mesh(lampGeo, redMat);
    redLamp.position.set(0, 3.85, 0.46);
    tl.add(redLamp);

    const yellowLamp = new THREE.Mesh(lampGeo, yellowMat);
    yellowLamp.position.set(0, 3.4, 0.46);
    tl.add(yellowLamp);

    const greenLamp = new THREE.Mesh(lampGeo, greenMat);
    greenLamp.position.set(0, 2.95, 0.46);
    tl.add(greenLamp);
    const lamps = [redLamp, yellowLamp, greenLamp];
    const activeColors = [0xFF3838, 0xFFD52A, 0x36FF88];
    const glows = lamps.map((lamp, i) => {
      const glow = window.PDD_VEHICLES.addGlow(lamp, activeColors[i], 1.2);
      glow.position.z = 0.08;
      return glow;
    });
    function showSignal(s) {
      lamps.forEach((lamp, i) => {
        const active = ['red', 'yellow', 'green'][i] === s || (s === 'flashing_yellow' && i === 1);
        lamp.material.color.setHex(active ? activeColors[i] : [0x351719, 0x352D14, 0x123126][i]);
        glows[i].visible = active;
      });
    }
    showSignal(initialState);
    if (arrow) {
      const canvas = document.createElement('canvas');
      canvas.width = canvas.height = 128;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#172020'; ctx.fillRect(0, 0, 128, 128);
      ctx.strokeStyle = '#35F088'; ctx.lineWidth = 12;
      ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      ctx.beginPath();
      if (arrow === 'right') {
        ctx.moveTo(24, 64); ctx.lineTo(102, 64); ctx.moveTo(70, 32); ctx.lineTo(102, 64); ctx.lineTo(70, 96);
      } else {
        ctx.moveTo(64, 104); ctx.lineTo(64, 24); ctx.moveTo(32, 56); ctx.lineTo(64, 24); ctx.lineTo(96, 56);
      }
      ctx.stroke();
      const face = new THREE.Mesh(new THREE.PlaneGeometry(0.64, 0.64),
        new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(canvas) }));
      face.position.set(-0.7, 2.95, 0.47);
      tl.add(face);
      window.PDD_VEHICLES.addGlow(face, 0x36FF88, 0.85).material.opacity = 0.4;
      tl.userData.arrow = arrow;
    }
    if (initialState === 'flashing_yellow') {
      yellowMat.color.setHex(0xF59E0B);
      tl.userData.beacons = [yellowLamp];
    }

    tl.setLightState = function(s) {
      lamps.forEach(lamp => { lamp.visible = true; });
      tl.userData.beacons = s === 'flashing_yellow' ? [yellowLamp] : [];
      showSignal(s);
    };
    tl.scale.setScalar(1.16);
    return tl;
  }

  // --- Low-Poly Environment Props (Trees, Buildings) ---
  // One material per mesh, never shared: retired segments receive clipping
  // planes and faded buildings change opacity on their materials, so a shared
  // material would clip or fade every tree/house of that colour in the world.
  const sceneryMat = color => new THREE.MeshLambertMaterial({ color });
  // Bake many small static meshes (windows, dashes, zebra stripes, posts) into
  // ONE mesh: draw calls, not triangles, are what weak phone GPUs choke on.
  function mergeStatic(meshes, material) {
    const positions = [], normals = [], uvs = [];
    const normalMatrix = new THREE.Matrix3();
    meshes.forEach(mesh => {
      if (mesh.matrixAutoUpdate) mesh.updateMatrix();
      const geometry = mesh.geometry.index ? mesh.geometry.toNonIndexed() : mesh.geometry;
      const p = geometry.attributes.position, n = geometry.attributes.normal, uv = geometry.attributes.uv;
      normalMatrix.getNormalMatrix(mesh.matrix);
      const v = new THREE.Vector3();
      for (let i = 0; i < p.count; i++) {
        v.fromBufferAttribute(p, i).applyMatrix4(mesh.matrix); positions.push(v.x, v.y, v.z);
        v.fromBufferAttribute(n, i).applyMatrix3(normalMatrix).normalize(); normals.push(v.x, v.y, v.z);
        if (uv) uvs.push(uv.getX(i), uv.getY(i));
      }
      if (geometry !== mesh.geometry) geometry.dispose();
    });
    const merged = new THREE.BufferGeometry();
    merged.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    merged.setAttribute('normal', new THREE.Float32BufferAttribute(normals, 3));
    if (uvs.length) merged.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
    return new THREE.Mesh(merged, material);
  }
  // Bake several scenery groups (trees, houses) into one mesh per colour:
  // the far background costs a handful of draw calls per row, not dozens.
  function bakeGroups(groups) {
    const buckets = new Map();
    groups.forEach(group => {
      group.updateMatrixWorld(true);
      group.traverse(child => {
        if (!child.isMesh || !child.material?.color) return;
        const key = child.material.color.getHex() + (child.material.isMeshBasicMaterial ? 'b' : 'l');
        if (!buckets.has(key)) buckets.set(key, { material: child.material, meshes: [] });
        const proxy = new THREE.Mesh(child.geometry, null);
        proxy.matrix.copy(child.matrixWorld); proxy.matrixAutoUpdate = false;
        buckets.get(key).meshes.push(proxy);
      });
    });
    return [...buckets.values()].map(b => { const m = mergeStatic(b.meshes, b.material); m.castShadow = false; m.userData.baked = true; return m; });
  }
  function createTree(kind) {
    const tree = new THREE.Group();
    kind = kind || ['pine', 'pine', 'round', 'round', 'birch'][Math.floor(Math.random() * 5)];
    const sn = season(), pick = list => list[Math.floor(Math.random() * list.length)];
    if (kind === 'birch') {
      const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.18, 3.2, 6), sceneryMat(0xE8E4DA));
      trunk.position.y = 1.6; trunk.castShadow = true; tree.add(trunk);
      const canopy = new THREE.Mesh(new THREE.SphereGeometry(1.1, 7, 6), sceneryMat(Math.random() < 0.7 ? sn.birch : pick(sn.canopy)));
      canopy.material.userData.seasonal = 'birch';
      canopy.scale.set(0.8, 1.35, 0.8); canopy.position.y = 3.6; canopy.castShadow = true; tree.add(canopy);
    } else if (kind === 'round') {
      const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.3, 1.6, 6), sceneryMat(0x5D4037));
      trunk.position.y = 0.8; trunk.castShadow = true; tree.add(trunk);
      const canopy = new THREE.Mesh(new THREE.SphereGeometry(1.5, 8, 6), sceneryMat(pick(sn.canopy)));
      canopy.material.userData.seasonal = 'canopy';
      canopy.position.y = 2.6; canopy.castShadow = true; tree.add(canopy);
    } else {
      const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.28, 1.5, 6), sceneryMat(0x5D4037));
      trunk.position.y = 0.75; trunk.castShadow = true; tree.add(trunk);
      const foliageColor = pick(sn.pine);
      const lower = new THREE.Mesh(new THREE.ConeGeometry(1.4, 2.4, 7), sceneryMat(foliageColor));
      lower.position.y = 2.2; lower.castShadow = true; tree.add(lower);
      const upper = new THREE.Mesh(new THREE.ConeGeometry(0.95, 1.9, 7), sceneryMat(foliageColor));
      upper.position.y = 3.5; upper.castShadow = true; tree.add(upper);
    }
    const scale = 0.8 + Math.random() * 0.5;
    tree.scale.set(scale, scale, scale);
    tree.rotation.y = Math.random() * Math.PI * 2;
    return tree;
  }
  function createBush(color) {
    const sn = season();
    color = color || (sn.precipitation === 'snow' ? 0xC9D2D8 : sn.roof === null && sn.sun === 0xFFE3B8 ? 0x9A8A3E : 0x56764C);
    const bush = new THREE.Mesh(new THREE.SphereGeometry(0.6, 7, 5), sceneryMat(color));
    bush.scale.set(0.7 + Math.random() * 0.5, 0.6, 1 + Math.random() * 0.6);
    bush.position.y = 0.55;
    return bush;
  }
  // A small dog on a leash, attached to a walker (local coords: +Z is the
  // walker's forward). Legs swing with the walker's gait.
  function createDog(color = 0x8A6A4A) {
    const dog = new THREE.Group();
    const fur = sceneryMat(color), dark = sceneryMat(0x2B2F33);
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.22, 0.5), fur); body.position.set(0, 0.36, 0); dog.add(body);
    const head = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.2, 0.22), fur); head.position.set(0, 0.5, 0.32); dog.add(head);
    const nose = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.08, 0.06), dark); nose.position.set(0, 0.46, 0.45); dog.add(nose);
    [-1, 1].forEach(sx => { const ear = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.12, 0.08), fur); ear.position.set(sx * 0.09, 0.6, 0.28); dog.add(ear); });
    const tail = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.05, 0.22), fur); tail.position.set(0, 0.45, -0.32); tail.rotation.x = -0.6; dog.add(tail);
    dog.userData.legs = [];
    [[-0.07, 0.17], [0.07, 0.17], [-0.07, -0.17], [0.07, -0.17]].forEach(([x, z]) => {
      const hip = new THREE.Group(); hip.position.set(x, 0.27, z);
      const leg = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.27, 0.06), fur); leg.position.y = -0.13; hip.add(leg);
      dog.add(hip); dog.userData.legs.push(hip);
    });
    dog.traverse(o => { if (o.isMesh) o.castShadow = true; });
    return dog;
  }
  // A cat that potters about on a front lawn.
  function createCat(color = 0x5B5B5B) {
    const cat = new THREE.Group();
    const fur = sceneryMat(color);
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.16, 0.42), fur); body.position.set(0, 0.2, 0); cat.add(body);
    const head = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.15, 0.15), fur); head.position.set(0, 0.3, 0.26); cat.add(head);
    [-1, 1].forEach(sx => { const ear = new THREE.Mesh(new THREE.ConeGeometry(0.035, 0.08, 4), fur); ear.position.set(sx * 0.055, 0.4, 0.24); cat.add(ear); });
    const tail = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.04, 0.3), fur); tail.position.set(0, 0.32, -0.3); tail.rotation.x = -1.1; cat.add(tail);
    cat.userData.legs = []; cat.userData.tail = tail;
    [[-0.05, 0.14], [0.05, 0.14], [-0.05, -0.14], [0.05, -0.14]].forEach(([x, z]) => {
      const hip = new THREE.Group(); hip.position.set(x, 0.14, z);
      const leg = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.14, 0.04), fur); leg.position.y = -0.07; hip.add(leg);
      cat.add(hip); cat.userData.legs.push(hip);
    });
    return cat;
  }
  function createLampPost() {
    const lamp = new THREE.Group();
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.1, 5.2, 6), null);
    pole.position.y = 2.6;
    const arm = new THREE.Mesh(new THREE.BoxGeometry(1.4, 0.08, 0.08), null);
    arm.position.set(-0.6, 5.1, 0);
    lamp.add(mergeStatic([pole, arm], sceneryMat(0x5B646A))); pole.geometry.dispose(); arm.geometry.dispose();
    const head = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.16, 0.26), new THREE.MeshBasicMaterial({ color: 0xE6E9D8 }));
    head.position.set(-1.25, 5.05, 0); lamp.add(head);
    return lamp;
  }
  function createFence(length) {
    const fence = new THREE.Group();
    const rail = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.08, length), sceneryMat(0x7A6A55));
    rail.position.y = 0.9; fence.add(rail);
    const postGeo = new THREE.BoxGeometry(0.1, 1, 0.1), posts = [];
    for (let z = -length / 2; z <= length / 2; z += 1.2) {
      const post = new THREE.Mesh(postGeo, null);
      post.position.set(0, 0.5, z); posts.push(post);
    }
    fence.add(mergeStatic(posts, sceneryMat(0x7A6A55))); postGeo.dispose();
    return fence;
  }
  function createParkedCar() {
    const colors = [0xE8E8E8, 0x2F3A46, 0x8B1E2D, 0x6E86A6, 0xC9B36B, 0x4D756A, 0xB87847, 0xD1CEC4];
    const car = createNpcCar(colors[Math.floor(Math.random() * colors.length)]);
    const shape = Math.floor(Math.random() * 3);
    car.scale.set(1, shape === 1 ? 1.18 : 1, shape === 2 ? 1.14 : shape === 1 ? 0.88 : 1);
    car.traverse(o => { o.userData.scenery = true; });
    return car;
  }
  function createKiosk() {
    const kiosk = new THREE.Group();
    const palette = [[0x4F7C8A, 0xE0533F], [0x879077, 0xE1BF74], [0xB78972, 0x3D6A81]][Math.floor(Math.random() * 3)];
    const body = new THREE.Mesh(new THREE.BoxGeometry(2.4, 2.4, 2), sceneryMat(palette[0]));
    body.position.y = 1.2; kiosk.add(body);
    const glass = new THREE.Mesh(new THREE.PlaneGeometry(1.8, 1), new THREE.MeshBasicMaterial({ color: 0xB9D7E0 }));
    glass.position.set(0, 1.4, 1.01); kiosk.add(glass);
    const awning = new THREE.Mesh(new THREE.BoxGeometry(2.8, 0.08, 0.9), sceneryMat(palette[1]));
    awning.position.set(0, 2.15, 1.35); awning.rotation.x = 0.25; kiosk.add(awning);
    return kiosk;
  }
  function createPond() {
    const pond = new THREE.Group();
    const water = new THREE.Mesh(new THREE.CircleGeometry(4.2, 18), sceneryMat(season().precipitation === 'snow' ? 0xD7E6EE : 0x6FA8C9));
    water.material.userData.seasonal = 'water';
    water.rotation.x = -Math.PI / 2; water.scale.set(1.4, 1, 1); water.position.y = 0.012; pond.add(water);
    const shore = new THREE.Mesh(new THREE.CircleGeometry(4.7, 18), sceneryMat(0xC9BFA6));
    shore.rotation.x = -Math.PI / 2; shore.scale.set(1.4, 1, 1); shore.position.y = 0.006; pond.add(shore);
    for (let i = 0; i < 3; i++) {
      const reed = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.08, 1.1, 5), sceneryMat(0x6C8C3F));
      const a = i * 2.1 + 0.4; reed.position.set(Math.cos(a) * 5.4, 0.55, Math.sin(a) * 3.9); pond.add(reed);
    }
    return pond;
  }
  function createBuilding(width = 12, height = 14, depth = 12, style = 2) {
    const b = new THREE.Group();
    b.userData.cameraOccluder = true;
    const palettes = { 1: [0xF3E3C3, 0xE8CFA8, 0xD9B99B, 0xC8D9C0, 0xE9D5CC], 2: [...BRAND.buildingColors, 0xB5675A, 0xA9B4C2] };
    const palette = palettes[style] || BRAND.buildingColors;
    const color = palette[Math.floor(Math.random() * palette.length)];
    // Own materials only: the camera-occlusion fade mutates them per building.
    const body = new THREE.Mesh(new THREE.BoxGeometry(width, height, depth), sceneryMat(color));
    body.position.y = height / 2;
    body.castShadow = false; // Avoid square shadows cast by buildings outside the viewport.
    body.receiveShadow = true;
    b.add(body);

    if (style === 1) {
      // Low houses: hip roof in tile or slate.
      // Unit square pyramid (rotated in the geometry so scaling stays axis-aligned),
      // stretched to the footprint plus a small eave.
      const roofGeo = new THREE.ConeGeometry(Math.SQRT2 / 2, 1, 4); roofGeo.rotateY(Math.PI / 4);
      const roof = new THREE.Mesh(roofGeo, sceneryMat(season().roof || (Math.random() > 0.5 ? 0x8C4A3C : 0x5D6B75)));
      roof.material.userData.seasonal = 'roof';
      // Eaves: a dark strip under the roof edge keeps the silhouette readable
      // against snow (and reads as a shadow line in any season).
      const eave = new THREE.Mesh(new THREE.BoxGeometry(width + 0.9, 0.18, depth + 0.9), sceneryMat(0x4A4F55));
      eave.position.y = height + 0.02; b.add(eave);
      roof.scale.set(width + 0.8, 2.4, depth + 0.8);
      roof.position.y = height + 1.2; b.add(roof);
    } else {
      // Flat roof slab (tar; snow-grey in winter) so the top never shows the facade colour.
      const slab = new THREE.Mesh(new THREE.BoxGeometry(width - 0.2, 0.08, depth - 0.2), sceneryMat(season().precipitation === 'snow' ? 0xB9C2CA : 0x6B7480));
      slab.position.y = height + 0.04; b.add(slab);
      const roofBorder = new THREE.Mesh(new THREE.BoxGeometry(width + 0.4, 0.4, depth + 0.4), sceneryMat(season().precipitation === 'snow' ? 0x7F8B99 : 0x94A3B8));
      roofBorder.position.y = height + 0.2; b.add(roofBorder);
      if (Math.random() > 0.5) {
        const box = new THREE.Mesh(new THREE.BoxGeometry(2.2, 1.4, 2), sceneryMat(0x8391A0));
        box.position.set(width * 0.2, height + 0.7, -depth * 0.2); b.add(box);
      }
    }

    const glass = new THREE.MeshBasicMaterial({ color: [0x708995, 0x647D87, 0x87988F][Math.floor(Math.random() * 3)] });
    const windowGeo = new THREE.PlaneGeometry(Math.random() < 0.5 ? 1 : 1.3, 1.25);
    const windows = [];
    for (const side of [-1, 1]) {
      for (let y = 1.8; y < height - 0.6; y += 2.7) {
        for (let z = -depth / 2 + 1.4; z < depth / 2 - 0.6; z += 2) {
          const window = new THREE.Mesh(windowGeo, glass);
          window.position.set(side * (width / 2 + 0.015), y, z);
          window.rotation.y = side * Math.PI / 2;
          windows.push(window);
        }
        for (let x = -width / 2 + 1.3; x < width / 2 - 0.6; x += 2) {
          const window = new THREE.Mesh(windowGeo, glass);
          window.position.set(x, y, side * (depth / 2 + 0.015));
          window.rotation.y = side > 0 ? 0 : Math.PI;
          windows.push(window);
        }
      }
      const door = new THREE.Mesh(new THREE.PlaneGeometry(0.95, 1.9), sceneryMat(0x536666));
      door.position.set(side * (width / 2 + 0.02), 0.95, 0);
      door.rotation.y = side * Math.PI / 2; b.add(door);
      if (side === 1) { const merged = mergeStatic(windows, glass); b.add(merged); b.userData.windows = merged; windowGeo.dispose(); }
      if (style === 2 && Math.random() > 0.4) {
        // Ground-floor shop awning on the street side.
        const awning = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.08, Math.min(depth - 1, 4)),
          sceneryMat([0xE0533F, 0x2F6F9F, 0x3E8E5E, 0xD9A441][Math.floor(Math.random() * 4)]));
        awning.position.set(side * (width / 2 + 0.45), 2.45, 0); awning.rotation.z = -side * 0.28; b.add(awning);
      }
    }
    return b;
  }

  // Adjacent surfaces overlap by this much: quads that merely touch leave a
  // sub-pixel antialiased seam through which the ground shows as a 1px line.
  // Overlaps are same-colour, so the coplanar overlap itself is invisible.
  const SEAM = 0.12;

  function buildStraightSegment(startZ, length = 70, preview = false, district = state.district) {
    const seg = new THREE.Group();
    const roadWidth = 8.4; // 2 lanes (4.2m each)

    // Asphalt
    const asphalt = new THREE.Mesh(
      new THREE.PlaneGeometry(roadWidth, length + 2 * SEAM),
      new THREE.MeshLambertMaterial({ color: BRAND.asphalt })
    );
    asphalt.rotation.x = -Math.PI / 2;
    asphalt.position.set(0, 0.02, startZ + length / 2);
    asphalt.receiveShadow = true;
    seg.add(asphalt);

    // Sidewalks
    const swWidth = 3.2;
    const swL = new THREE.Mesh(
      new THREE.BoxGeometry(swWidth + SEAM, 0.18, length + 2 * SEAM),
      new THREE.MeshLambertMaterial({ color: BRAND.sidewalk })
    );
    swL.position.set(-(roadWidth / 2 + swWidth / 2 - SEAM / 2), 0.09, startZ + length / 2);
    swL.receiveShadow = true;
    seg.add(swL);

    const swR = new THREE.Mesh(
      new THREE.BoxGeometry(swWidth + SEAM, 0.18, length + 2 * SEAM),
      new THREE.MeshLambertMaterial({ color: BRAND.sidewalk })
    );
    swR.position.set(roadWidth / 2 + swWidth / 2 - SEAM / 2, 0.09, startZ + length / 2);
    swR.receiveShadow = true;
    seg.add(swR);

    // Center Dashed Marking (1.5)
    const dashLength = 2.0;
    const gapLength = 3.0;
    const markingMat = new THREE.MeshBasicMaterial({ color: BRAND.asphaltMarking });
    const dashGeo = new THREE.PlaneGeometry(0.18, dashLength);
    dashGeo.rotateX(-Math.PI / 2);

    const dashes = [];
    for (let z = startZ + 2; z < startZ + length - 2; z += (dashLength + gapLength)) {
      const dash = new THREE.Mesh(dashGeo, markingMat);
      dash.position.set(0, 0.025, z + dashLength / 2);
      dashes.push(dash);
    }
    seg.add(mergeStatic(dashes, markingMat));

    // Outer Solid Lines (1.2)
    const solidLineGeo = new THREE.PlaneGeometry(0.15, length);
    solidLineGeo.rotateX(-Math.PI / 2);
    const lineL = new THREE.Mesh(solidLineGeo, markingMat);
    lineL.position.set(-roadWidth / 2 + 0.25, 0.025, startZ + length / 2);
    seg.add(lineL);

    const lineR = new THREE.Mesh(solidLineGeo, markingMat);
    lineR.position.set(roadWidth / 2 - 0.25, 0.025, startZ + length / 2);
    seg.add(lineR);

    // Districts blend over the road's length, and are built with the road,
    // never spawned in response to a camera turn: park / homes / boulevard.
    seg.userData.district = district;
    for (let z = startZ + 8, row = 0; z < startZ + length - 8; z += 20, row++) {
      const t = THREE.MathUtils.smoothstep((z - startZ) / length, 0.2, 0.8);
      const next = (district + 1) % 3;
      const style = row % 5 / 4 < t ? next : district;
      for (const side of [-1, 1]) {
        const vergeGeometry = new THREE.PlaneGeometry(22 + SEAM, 20 + SEAM);
        const verge = new THREE.Mesh(vergeGeometry, new THREE.MeshLambertMaterial({ color: season().verge[style] }));
        verge.material.userData.seasonal = 'verge' + style;
        verge.rotation.x = -Math.PI / 2; verge.position.set(side * 18.4, -0.015, z);
        verge.receiveShadow = true; seg.add(verge);
        // The far background beyond the verge (x 30-70): forest, distant
        // houses or tall blocks, fields and a hill, so a glance sideways never
        // ends in empty grass. Baked per row into a few meshes.
        const far = [];
        if (style === 0 || row % 3 === 2) {
          for (let i = 0; i < 7; i++) {
            const tree = createTree(i % 3 === 0 ? 'pine' : undefined);
            tree.position.set(side * (28 + Math.random() * 18), 0, z - 9 + Math.random() * 18);
            tree.scale.multiplyScalar(1.1); far.push(tree);
          }
          if (row % 2 === 0) {
            const field = new THREE.Mesh(new THREE.PlaneGeometry(26, 18), new THREE.MeshLambertMaterial({ color: season().verge[1] }));
            field.rotation.x = -Math.PI / 2; field.position.set(side * 50, -0.012, z); far.push(field);
          }
        } else if (style === 1) {
          for (let i = 0; i < 2; i++) {
            const house = createBuilding(6 + Math.random() * 2, 4.5, 6 + Math.random() * 2, 1);
            house.position.set(side * (30 + i * 10 + Math.random() * 3), 0, z - 4 + Math.random() * 8);
            house.rotation.y = Math.random() * 0.6 - 0.3; far.push(house);
          }
          for (let i = 0; i < 3; i++) { const tree = createTree('round'); tree.position.set(side * (32 + Math.random() * 16), 0, z - 8 + Math.random() * 16); far.push(tree); }
        } else {
          for (let i = 0; i < 2; i++) {
            const block = createBuilding(10 + Math.random() * 4, 12 + Math.random() * 12, 9 + Math.random() * 3, 2);
            block.position.set(side * (31 + i * 13 + Math.random() * 4), 0, z - 6 + Math.random() * 12); far.push(block);
          }
        }
        if (row === 0 && Math.random() < 0.5) {
          const hill = new THREE.Mesh(new THREE.SphereGeometry(22, 12, 8), new THREE.MeshLambertMaterial({ color: season().hillColor }));
          hill.scale.set(1.6, 0.32, 1); hill.position.set(side * 66, -2, z + 20); far.push(hill);
        }
        bakeGroups(far).forEach(m => seg.add(m));
        // Rows are 20 m apart; a building of depth D leaves a gap of 20 - D
        // where trees, hedges and parked cars go (never under a facade).
        const depth = style === 0 ? 0 : style === 1 ? 6 + Math.random() * 2 : 8 + Math.random() * 2;
        const gapZ = z + depth / 2 + (20 - depth) / 2;
        // The chase camera looks down +Z: scenery must sit in FRONT of a facade
        // (smaller z) to stay visible, never right behind one.
        // A facade of height H hides ~H metres of ground behind it at this camera
        // pitch, so trees stand just in front of the NEXT facade; on the boulevard
        // (tall facades) they are street trees on the outer half of the pavement.
        const tree = createTree(); tree.position.set(side * 8.6, 0, style === 0 ? z - 3 : gapZ + 3.5);
        tree.scale.setScalar(style === 2 ? 0.8 : 1); seg.add(tree);
        if (style !== 0) {
          const floors = style === 1 ? (Math.random() < 0.7 ? 1 : 2) : 3 + Math.floor(Math.random() * 3);
          const building = createBuilding(style === 1 ? 6 + Math.random() * 2 : 10 + Math.random() * 3, floors * 3 + 1.5, depth, style);
          building.position.set(side * (style === 1 ? 11.5 : 13.5), 0, z); seg.add(building);
          state.occluders.push(building);
        }
        // Street furniture and district flavour, all outside the carriageway.
        if (row % 2 === (side > 0 ? 1 : 0)) {
          const lamp = createLampPost(); lamp.position.set(side * 7.0, 0, z - 9); lamp.rotation.y = side > 0 ? Math.PI : 0; seg.add(lamp);
        }
        if (style === 0) {
          // Park: second tree line, bushes, an occasional pond.
          const back = createTree(); back.position.set(side * (14 + Math.random() * 6), 0, z + 4 + Math.random() * 6); seg.add(back);
          const shrub = createBush(); shrub.position.x = side * (10.5 + Math.random() * 2); shrub.position.z = z - 1; seg.add(shrub);
          if (row % 3 === 1) { const pond = createPond(); pond.position.set(side * 20, 0, z + 2); seg.add(pond); }
        } else if (style === 1) {
          // Homes: fenced yards with a parked car or a hedge.
          const fence = createFence(depth + 6); fence.position.set(side * 8.0, 0, z + 1); seg.add(fence);
          if (Math.random() < 0.22) {
            const cat = createCat([0x5B5B5B, 0xD8863B, 0xEDE6DA, 0x2A2A2A][Math.floor(Math.random() * 4)]);
            cat.position.set(side * 9.4, 0, gapZ + 1); seg.add(cat);
            state.ambient.push({ mesh: cat, center: gapZ + 1, phase: Math.random() * 6, time: 0, kind: 'cat', seg, side, lane: 0, targetLane: 0 });
          }
          if (row % 2 === 0) {
            const parked = createParkedCar(); parked.position.set(side * 12.8, 0, gapZ - 0.5); parked.rotation.y = side * Math.PI / 2 + 0.15; seg.add(parked);
          } else {
            const hedge = createBush(); hedge.scale.set(1.2, 0.9, 3); hedge.position.set(side * 12.8, 0.5, gapZ - 0.5); seg.add(hedge);
          }
        } else {
          // Boulevard: kiosk or billboard between the tall facades.
          if (row % 3 === 0) { const kiosk = createKiosk(); kiosk.position.set(side * 9.4, 0, gapZ - 3.2); kiosk.rotation.y = side > 0 ? -Math.PI / 2 : Math.PI / 2; seg.add(kiosk); }
          else if (row % 3 === 2) {
            const board = new THREE.Mesh(new THREE.BoxGeometry(0.1, 1.6, 3), sceneryMat([0xF2C14E, 0x5DA9E9, 0xE07A5F][row % 3]));
            board.position.set(side * 8.6, 2.2, gapZ - 3.2); seg.add(board);
            const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.06, 1.4, 6), sceneryMat(0x5B646A));
            leg.position.set(side * 8.6, 0.7, gapZ - 3.2); seg.add(leg);
          }
        }
        // A bench and planter form a quiet park edge, outside the walking lane.
        const bench = new THREE.Group();
        const wood = new THREE.MeshLambertMaterial({ color: 0x987856 });
        const pieces = [];
        for (const [w, h, d, y, offset] of [[1.6, 0.12, 0.5, 0.55, 0], [1.6, 0.5, 0.12, 0.85, 0.2]]) {
          const piece = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), wood);
          piece.position.set(0, y, offset); pieces.push(piece);
        }
        const legs = [];
        for (const x of [-0.6, 0.6]) {
          const leg = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.5, 0.4), null);
          leg.position.set(x, 0.25, 0); legs.push(leg);
        }
        bench.add(mergeStatic(pieces, wood), mergeStatic(legs, sceneryMat(0x495452)));
        [...pieces, ...legs].forEach(m => m.geometry.dispose());
        bench.position.set(side * 8.1, 0, z + (style === 0 ? 4 : 6)); bench.rotation.y = side * Math.PI / 2; seg.add(bench);
        const planter = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.45, 1.8),
          new THREE.MeshLambertMaterial({ color: style === 2 ? 0x8D999E : 0xB79774 }));
        planter.position.set(side * 8.1, 0.22, z + (style === 0 ? 7 : 8.5)); seg.add(planter);
        const bush = new THREE.Mesh(new THREE.SphereGeometry(0.6, 7, 5),
          new THREE.MeshLambertMaterial({ color: 0x56764C }));
        bush.scale.set(0.7, 0.6, 1.2); bush.position.set(side * 8.1, 0.6, z + (style === 0 ? 7 : 8.5)); seg.add(bush);
        // Ambient walkers have no traffic IDs, answers, badges or collisions.
        if (row % 2 === (side > 0 ? 0 : 1)) {
          const walker = createPedestrian(PEOPLE_COLORS[Math.floor(Math.random() * PEOPLE_COLORS.length)]);
          if (Math.random() < 0.14) {
            // Now and then someone walks a dog: it trots beside, on a leash.
            const dog = createDog([0x8A6A4A, 0xD9C6A5, 0x3A3A3A, 0xB88A5A][Math.floor(Math.random() * 4)]);
            dog.position.set(0.55, -0.18, -0.85); walker.add(dog); walker.userData.dog = dog;
            const leash = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(0.3, 0.9, 0), new THREE.Vector3(0.55, 0.3, -0.55)]),
              new THREE.LineBasicMaterial({ color: 0x2B2F33 }));
            walker.add(leash);
          }
          const lane = row % 4 < 2 ? 0 : 1; // pavement has two walking lanes
          walker.position.set(side * (5.2 + lane * 1.1), 0.18, z);
          seg.add(walker);
          state.ambient.push({ mesh: walker, center: z, phase: row * 1.7, time: 0, side, lane, targetLane: lane, seg });
        }
      }
    }

    registerRoadSegment(seg);
    seg.userData.roadEnds = [new THREE.Vector3(0, 0, startZ), new THREE.Vector3(0, 0, startZ + length)];
    addPuddles(seg, startZ, length);
    state.weatherDirty = true;
    if (preview) return seg;
    state.roadSegments.push(seg);
    return length;
  }

  // --- Crossroad & Situation Segment Generator ---
  // One model per actor config, with beacons, badge and measured collision half-sizes.
  function createActorMesh(cfg) {
    let actorMesh;
    let badgeHeight = 2.4;

    if (cfg.type === 'tram') {
      actorMesh = createTram(cfg.color);
      actorMesh.scale.set(0.75, 0.75, 0.75);
      badgeHeight = 3.6;
    } else if (cfg.type === 'bus') {
      actorMesh = createBus(cfg.color);
      actorMesh.scale.set(0.85, 0.85, 0.85);
      badgeHeight = 3.2;
    } else if (cfg.type === 'tractor') {
      actorMesh = createTractor(cfg.color);
      badgeHeight = 3.6;
    } else if (cfg.type === 'truck') {
      actorMesh = createTruck(cfg.color);
      actorMesh.scale.set(0.85, 0.85, 0.85);
      badgeHeight = 3.4;
    } else if (cfg.type === 'special') {
      actorMesh = createSpecialCar(cfg.color);
      badgeHeight = 2.4;
    } else if (cfg.type === 'motorcycle') {
      actorMesh = createMotorcycle(cfg.color);
      badgeHeight = 2.7;
    } else if (cfg.type === 'cyclist') {
      actorMesh = createCyclist(cfg.color);
      badgeHeight = 2.7;
    } else if (cfg.type === 'pedestrian') {
      actorMesh = createPedestrian(cfg.color);
      badgeHeight = 2.8;
    } else {
      actorMesh = createNpcCar(cfg.color);
      badgeHeight = 2.4;
    }
    if (cfg.beacon === 'amber') {
      const beacon = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.2, 0.2, 10),
        new THREE.MeshBasicMaterial({ color: 0xFFB21C }));
      beacon.position.set(0, badgeHeight - 0.4, 0);
      actorMesh.add(beacon);
      actorMesh.userData.beacons = [beacon];
      window.PDD_VEHICLES.addGlow(beacon, 0xFFB21C, 1.7);
    }
    if (cfg.beacon === 'blue' && actorMesh.userData.beacons) {
      actorMesh.userData.beacons.forEach(l => {
        l.material.color.setHex(0x208CFF);
        l.children.forEach(glow => glow.material.color.setHex(0x208CFF));
      });
    }

    if (cfg.scale) actorMesh.scale.multiplyScalar(cfg.scale);
    const visual = new THREE.Group();
    [...actorMesh.children].forEach(child => visual.add(child));
    actorMesh.add(visual);
    actorMesh.userData.body = visual;
    // Glow sprites are presentation only, never collision geometry.
    actorMesh.updateMatrixWorld(true);
    const physicalBounds = new THREE.Box3();
    actorMesh.traverse(part => {
      if (!part.isMesh) return;
      part.geometry.computeBoundingBox();
      physicalBounds.union(part.geometry.boundingBox.clone().applyMatrix4(part.matrixWorld));
    });
    const modelSize = physicalBounds.getSize(new THREE.Vector3());
    const halfLength = modelSize.z / 2;
    // Add badge above roof
    const badgeLabel = cfg.siren ? 'Маячок + сирена' : cfg.badge || (
      cfg.name ? (
        cfg.name.includes('Трамвай А') ? 'А' :
        cfg.name.includes('Трамвай Б') ? 'Б' :
        cfg.name.includes('Трамвай') ? 'Трамвай' :
        cfg.name.includes('Автобус') ? 'Автобус' :
        cfg.name.includes('Грузовик') ? 'Грузовик' :
        cfg.name.includes('Спец') ? 'Спец' :
        cfg.name.includes('Мотоцикл') ? 'Мото' :
        cfg.name.includes('Велосипед') ? 'Вело' :
        cfg.name.includes('Пешеход') ? 'Пешеход' :
        cfg.name.includes('Встреч') ? 'Встречный' :
        'Авто'
      ) : 'Авто'
    );
    const badge = createActorBadge(badgeLabel, cfg.color || BRAND.accent);
    badge.position.y = badgeHeight;
    actorMesh.add(badge);
    actorMesh.userData.badge = badge;
    actorMesh.traverse(obj => { obj.userData.actor = true; });
    if (cfg.blinker || cfg.maneuver) {
      // Turn signals readable from the chase camera, on both sides; which side
      // blinks (if any) follows the actor's manoeuvre plan.
      const k = actorMesh.scale.x;
      const lamps = side => [-halfLength + 0.15, halfLength - 0.15].map(z => {
        const lamp = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.14, 0.3), new THREE.MeshBasicMaterial({ color: 0xFFB21C }));
        lamp.position.set(side * (modelSize.x / 2 - 0.02) / k, 0.85 / k, z / k);
        lamp.visible = false;
        window.PDD_VEHICLES.addGlow(lamp, 0xFFB21C, 1.1);
        actorMesh.userData.body.add(lamp);
        return lamp;
      });
      actorMesh.userData.blinkerLamps = { left: lamps(1), right: lamps(-1) };
      actorMesh.userData.blinkerSide = cfg.blinker || null;
    }
    return { actorMesh, halfLength, halfWidth: modelSize.x / 2 };
  }

  function buildIntersectionSegment(startZ, situation, incomingRoad = null) {
    const spec = routeSpec(situation);
    situation = { ...situation, ...(spec.overrides || {}) };
    const intentions = { straight: 'Вы прямо', left: 'Вы налево', right: 'Вы направо', uturn: 'Вы на разворот' };
    situation.legend = [{ label: intentions[spec.maneuver], color: '#ED4621' },
      ...(situation.actorsConfig || []).map(a => ({ label: a.name, color: a.color || '#0574F8' }))];
    const seg = new THREE.Group();
    const roadWidth = 8.4;
    const intersectionLength = 52;
    const centerZ = startZ + 26;
    const crossStreetLength = 70;
    const districtGround = new THREE.Mesh(new THREE.PlaneGeometry(crossStreetLength + SEAM, intersectionLength + SEAM),
      new THREE.MeshLambertMaterial({ color: season().ground }));
    districtGround.material.userData.seasonal = 'ground';
    districtGround.rotation.x = -Math.PI / 2;
    districtGround.position.set(0, -0.02, centerZ);
    districtGround.receiveShadow = true;
    seg.add(districtGround);

    // Main longitudinal asphalt
    const mainAsphalt = new THREE.Mesh(
      new THREE.PlaneGeometry(roadWidth, intersectionLength + 2 * SEAM),
      new THREE.MeshLambertMaterial({ color: BRAND.asphalt })
    );
    mainAsphalt.rotation.x = -Math.PI / 2;
    mainAsphalt.position.set(0, 0.02, centerZ);
    mainAsphalt.receiveShadow = true;
    seg.add(mainAsphalt);

    // Crossing street asphalt (extends left and right across entire screen)
    const crossAsphalt = new THREE.Mesh(
      new THREE.PlaneGeometry(crossStreetLength + 2 * SEAM, roadWidth),
      new THREE.MeshLambertMaterial({ color: BRAND.asphalt })
    );
    crossAsphalt.rotation.x = -Math.PI / 2;
    crossAsphalt.position.set(0, 0.021, centerZ);
    crossAsphalt.receiveShadow = true;
    seg.add(crossAsphalt);

    // Sidewalks on all 4 corners
    const swW = 3.2;
    const cornerL = (crossStreetLength - roadWidth) / 2;
    const cornerH = (intersectionLength - roadWidth) / 2;

    // Corners run along the cross street only, from the outer edge of the
    // main-street pavement outwards: no coplanar overlap with those pavements.
    const cornerW = cornerL - swW + SEAM, cornerX = roadWidth / 2 + swW - 0.03 + cornerW / 2;
    const corner = (sx, sz) => {
      const box = new THREE.Mesh(new THREE.BoxGeometry(cornerW, 0.18, swW + SEAM), new THREE.MeshLambertMaterial({ color: BRAND.sidewalk }));
      box.position.set(sx * cornerX, 0.09, centerZ + sz * (roadWidth / 2 + swW / 2 - SEAM / 2));
      seg.add(box); return box;
    };
    corner(-1, -1); corner(1, -1); corner(-1, 1); corner(1, 1);

    // Main street entrance sidewalks
    const swMainL = new THREE.Mesh(new THREE.BoxGeometry(swW + SEAM, 0.18, cornerH + 2 * SEAM), new THREE.MeshLambertMaterial({ color: BRAND.sidewalk }));
    swMainL.position.set(-(roadWidth / 2 + swW / 2) + SEAM / 2, 0.09, startZ + cornerH / 2);
    seg.add(swMainL);

    const swMainR = new THREE.Mesh(new THREE.BoxGeometry(swW + SEAM, 0.18, cornerH + 2 * SEAM), new THREE.MeshLambertMaterial({ color: BRAND.sidewalk }));
    swMainR.position.set(roadWidth / 2 + swW / 2 - SEAM / 2, 0.09, startZ + cornerH / 2);
    seg.add(swMainR);

    // Main street exit sidewalks
    const swMainL_exit = new THREE.Mesh(new THREE.BoxGeometry(swW + SEAM, 0.18, cornerH + 2 * SEAM), new THREE.MeshLambertMaterial({ color: BRAND.sidewalk }));
    swMainL_exit.position.set(-(roadWidth / 2 + swW / 2) + SEAM / 2, 0.09, centerZ + roadWidth / 2 + cornerH / 2);
    seg.add(swMainL_exit);

    const swMainR_exit = new THREE.Mesh(new THREE.BoxGeometry(swW + SEAM, 0.18, cornerH + 2 * SEAM), new THREE.MeshLambertMaterial({ color: BRAND.sidewalk }));
    swMainR_exit.position.set(roadWidth / 2 + swW / 2 - SEAM / 2, 0.09, centerZ + roadWidth / 2 + cornerH / 2);
    seg.add(swMainR_exit);

    // Markings
    const markingMat = new THREE.MeshBasicMaterial({ color: BRAND.asphaltMarking });

    // Four continuous approaches. Edges join the adjoining straight roads,
    // but all longitudinal paint stops before the crossings (no zebra overlap).
    function approachLine(x, from, to, width, yaw) {
      const line = new THREE.Mesh(new THREE.PlaneGeometry(width, to - from), markingMat);
      line.rotation.x = -Math.PI / 2;
      const local = new THREE.Vector3(x, 0.032, (from + to) / 2);
      local.applyAxisAngle(new THREE.Vector3(0, 1, 0), yaw);
      line.position.copy(local); line.position.z += centerZ;
      line.rotation.z = yaw;
      line.userData.roadMarking = true;
      seg.add(line);
    }
    for (const [yaw, end] of [[0, 26], [Math.PI, 26], [Math.PI / 2, 35], [-Math.PI / 2, 35]]) {
      for (const edge of [-1, 1]) approachLine(edge * (roadWidth / 2 - 0.25), 7.6, end, 0.15, yaw);
      approachLine(0, 7.6, 16, 0.18, yaw);
      // Transition back to the same 2m / 3m dashed centre as the open road.
      for (let z = 18; z < end; z += 5) approachLine(0, z, Math.min(z + 2, end), 0.18, yaw);
    }

    // Stop line 1.12: across player's right lane (x: 0.1 to 4.2)
    const stopLineZ = centerZ - 8.5;
    const stopLine = new THREE.Mesh(new THREE.PlaneGeometry(roadWidth / 2, 0.45), markingMat);
    stopLine.rotation.x = -Math.PI / 2;
    stopLine.position.set(roadWidth / 4, 0.027, stopLineZ);
    seg.add(stopLine);

    // Pedestrian Zebra 1.14.1 (entrance)
    const zebraZ = centerZ - 6.0;
    const numStripes = 10;
    const stripeGeo = new THREE.PlaneGeometry(0.4, 2.6);
    stripeGeo.rotateX(-Math.PI / 2);
    const stripes = [];
    for (let i = 0; i < numStripes; i++) {
      const stripe = new THREE.Mesh(stripeGeo, markingMat);
      stripe.position.set(-roadWidth / 2 + 0.45 + i * (roadWidth / numStripes), 0.027, zebraZ);
      stripes.push(stripe);
    }

    // Pedestrian Zebra 1.14.1 (exit)
    const exitZebraZ = centerZ + 6.0;
    for (let i = 0; i < numStripes; i++) {
      const stripe = new THREE.Mesh(stripeGeo, markingMat);
      stripe.position.set(-roadWidth / 2 + 0.45 + i * (roadWidth / numStripes), 0.027, exitZebraZ);
      stripes.push(stripe);
    }

    // Destination-road crossings for right/left turns, aligned with pedestrian routes.
    for (const side of [-1, 1]) {
      for (let i = 0; i < numStripes; i++) {
        const stripe = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 0.4), markingMat);
        stripe.rotation.x = -Math.PI / 2;
        stripe.position.set(side * 6.1, 0.028, centerZ - roadWidth / 2 + 0.45 + i * roadWidth / numStripes);
        stripes.push(stripe);
      }
    }
    seg.add(mergeStatic(stripes, markingMat));

    // Rails are generated from actual tram trajectories below.

    // Traffic light
    let tlMesh = null;
    if (situation.trafficLights) {
      tlMesh = createTrafficLight(situation.trafficLights.state || 'green', situation.trafficLights.arrow);
      tlMesh.position.set(roadWidth / 2 + 1.2, 0, stopLineZ);
      tlMesh.rotation.y = Math.PI;
      seg.add(tlMesh);
    }

    // Signs
    if (situation.signs && situation.signs.length > 0) {
      situation.signs.forEach((s, index) => {
        const sign = s.code === '8.13' ? createPriorityPlate(s.mainRoad) : createRoadSign(s.code);
        const plate = s.code === '8.13';
        sign.position.set(roadWidth / 2 + 1.2, plate ? 1.85 : 0, stopLineZ - 2.4 - (plate ? Math.max(0, index - 1) : index) * 2);
        sign.rotation.y = 0; // Facing oncoming player
        seg.add(sign);
      });
    }

    // Place Actors
    const actorsInScene = [];
    if (situation.actorsConfig) {
      situation.actorsConfig.forEach(cfg => {
        const { actorMesh, halfLength, halfWidth } = createActorMesh(cfg);
        const approachOffset = Math.max(10, 5.5 + halfLength);
        // Reserve room for the whole vehicle, especially a bus/tram nose.
        if (cfg.position) {
          actorMesh.position.set(cfg.position[0], cfg.position[1] || 0, centerZ + cfg.position[2]);
          if (cfg.rotationY !== undefined) actorMesh.rotation.y = cfg.rotationY;
        } else if (cfg.side === 'cross_left' || cfg.side === 'left') {
          actorMesh.position.set(-approachOffset, 0, centerZ - 2.05);
          actorMesh.rotation.y = Math.PI / 2;
        } else if (cfg.side === 'cross_left_2') {
          actorMesh.position.set(-19, 0, centerZ - 2.05);
          actorMesh.rotation.y = Math.PI / 2;
        } else if (cfg.side === 'cross_right' || cfg.side === 'right') {
          actorMesh.position.set(approachOffset, 0, centerZ + 2.05);
          actorMesh.rotation.y = -Math.PI / 2;
        } else if (cfg.side === 'cross_right_2') {
          actorMesh.position.set(19, 0, centerZ + 2.05);
          actorMesh.rotation.y = -Math.PI / 2;
        } else if (cfg.side === 'opposite') {
          actorMesh.position.set(-1.8, 0, centerZ + Math.max(9, 5.5 + halfLength));
          actorMesh.rotation.y = Math.PI;
        } else if (cfg.side === 'opposite_right') {
          actorMesh.position.set(-1.8, 0, centerZ + 18);
          actorMesh.rotation.y = Math.PI;
        } else if (cfg.side === 'crosswalk_right') {
          actorMesh.position.set(6.1, 0.18, centerZ - 5.6);
        } else if (cfg.side === 'crosswalk_left') {
          actorMesh.position.set(-6.1, 0.18, centerZ - 5.6);
        } else if (cfg.side === 'cross_right_edge') {
          actorMesh.position.set(3.35, 0, centerZ - 7.5);
          actorMesh.rotation.y = 0;
        } else {
          actorMesh.position.set(-6.8, 0, centerZ - 2.05);
          actorMesh.rotation.y = Math.PI / 2;
        }


        seg.add(actorMesh);
        actorsInScene.push({
          mesh: actorMesh,
          config: cfg,
          halfLength,
          halfWidth,
          initialPos: actorMesh.position.clone()
        });
      });
    }

    registerRoadSegment(seg);
    actorsInScene.forEach(a => {
      a.initialPos = a.mesh.position.clone();
      a.viewBounds = new THREE.Box3().setFromObject(a.mesh);
    });
    state.roadSegments.push(seg);

    const intersectionData = {
      seg,
      startZ,
      centerZ,
      stopZ: stopLineZ - 2.2,
      situation,
      actors: actorsInScene,
      trafficLight: tlMesh
    };
    state.intersections.push(intersectionData);
    // Visible participants already occupy the road, even before their question.
    // Register them now so traffic departing an earlier task can queue behind them.
    ensureTraffic(intersectionData);
    const guide = new THREE.Group();
    const action = spec.maneuver;
    let guidePoints = action === 'right' ? [[-1.8, -7], [-1.8, -4], [-4, -1.8], [-16, -1.8]] :
      action === 'left' ? [[-1.8, -7], [-1.8, -1], [2, 1.8], [16, 1.8]] :
      action === 'uturn' ? [[-1.8, -7], [-2.5, 0], [0, 2.5], [2.5, 0], [1.8, -15]] : [[-1.8, -7], [-1.8, 16]];
    const guidePath = curve(guidePoints.map(([x, z]) => new THREE.Vector3(x, 0.12, centerZ + z)));
    const guideMat = new THREE.MeshBasicMaterial({ color: BRAND.accent, transparent: true, opacity: 0.78, depthWrite: false, side: THREE.DoubleSide });
    const guideLength = guidePath.getLength();
    // A chain of compact racing-line arrows stays readable through the whole
    // manoeuvre without looking like another piece of road marking.
    // Racing-game chevrons: two joined strokes, no stem.
    const arrowShape = new THREE.Shape();
    arrowShape.moveTo(0, 0.62); arrowShape.lineTo(-0.78, -0.2); arrowShape.lineTo(-0.78, -0.72);
    arrowShape.lineTo(0, 0.08); arrowShape.lineTo(0.78, -0.72); arrowShape.lineTo(0.78, -0.2); arrowShape.closePath();
    const arrowGeo = new THREE.ShapeGeometry(arrowShape);
    arrowGeo.rotateX(Math.PI / 2);
    for (let distance = 0.8; distance <= guideLength; distance += 1.85) {
      const t = Math.min(1, distance / guideLength);
      const arrow = new THREE.Mesh(arrowGeo, guideMat);
      arrow.position.copy(guidePath.getPointAt(t)); arrow.position.y += 0.01;
      const direction = guidePath.getTangentAt(t);
      arrow.rotation.y = Math.atan2(direction.x, direction.z);
      arrow.scale.setScalar(t >= 0.98 ? 0.82 : 0.68);
      arrow.userData.guideArrow = true;
      guide.add(arrow);
    }
    seg.add(guide); guide.visible = false;
    intersectionData.guide = guide;
    // Build every visible exit BEFORE a question or a camera turn. These
    // lightweight continuations are replaced seamlessly by the next full road.
    intersectionData.previews = {};
    for (const [direction, yaw, x, z] of [
      ['straight', 0, 0, startZ + intersectionLength],
      ['left', Math.PI / 2, crossStreetLength / 2, centerZ],
      ['right', -Math.PI / 2, -crossStreetLength / 2, centerZ],
    ]) {
      const extension = buildStraightSegment(0, 200, true, (state.district + 1) % 3);
      extension.rotation.y = yaw;
      extension.position.set(x, 0, z);
      seg.add(extension);
      intersectionData.previews[direction] = extension;
    }
    if (incomingRoad) {
      // Reuse the actual approach, including its trees. A U-turn must not lay
      // another street and another junction over the one we just drove along.
      scene.updateMatrixWorld(true);
      const world = incomingRoad.matrixWorld.clone();
      seg.add(incomingRoad);
      incomingRoad.matrix.copy(world);
      world.decompose(incomingRoad.position, incomingRoad.quaternion, incomingRoad.scale);
      state.roadSegments = state.roadSegments.filter(s => s !== incomingRoad);
      intersectionData.previews.uturn = incomingRoad;
    }
    actorsInScene.filter(a => a.config.type === 'tram').forEach(a => {
      const motion = buildActorMotion(a, intersectionData);
      const incoming = motion.path.getTangentAt(0);
      const outgoing = motion.path.getTangentAt(1);
      const points = [a.initialPos.clone().addScaledVector(incoming, -70)];
      for (let i = 0; i <= 60; i++) points.push(motion.path.getPointAt(i / 60));
      // Actors continue beyond their authored curve until they have completely
      // left the camera. Rails must cover that same visual lifetime.
      points.push(motion.path.getPointAt(1).addScaledVector(outgoing, 320));
      const centerline = curve(points);
      [-0.7, 0.7].forEach(offset => {
        const rail = [];
        for (let i = 0; i <= 100; i++) {
          const t = i / 100, p = centerline.getPointAt(t), v = centerline.getTangentAt(t);
          p.add(new THREE.Vector3(-v.z, 0, v.x).multiplyScalar(offset));
          p.y = 0.055;
          rail.push(p);
        }
        const mesh = new THREE.Mesh(new THREE.TubeGeometry(curve(rail), 120, 0.035, 5, false),
          new THREE.MeshLambertMaterial({ color: 0x8E999C }));
        mesh.userData.tramRail = true;
        mesh.userData.railEnd = rail[rail.length - 1].clone();
        seg.add(mesh);
      });
    });

    refreshRoadBounds();
    return intersectionLength;
  }

  // Road factories use X = driver's right. Convert once at their boundary to
  // Three's right-handed coordinates; never mirror meshes/textures themselves.
  function registerRoadSegment(seg) {
    // Quiet pavement joints and a darker curb give scale without bright white slabs.
    const pavement = seg.children.filter(child => child.geometry && child.geometry.type === 'BoxGeometry' &&
      child.material && child.material.color && child.material.color.getHex() === BRAND.sidewalk);
    const joints = [];
    pavement.forEach(slab => {
      const { width, depth } = slab.geometry.parameters;
      const x = slab.position.x, z = slab.position.z;
      if (depth > width) {
        for (let offset = -depth / 2 + 2; offset < depth / 2; offset += 2.5) {
          joints.push(new THREE.Vector3(x - width / 2, 0.184, z + offset), new THREE.Vector3(x + width / 2, 0.184, z + offset));
        }
      } else {
        for (let offset = -width / 2 + 2; offset < width / 2; offset += 2.5) {
          joints.push(new THREE.Vector3(x + offset, 0.184, z - depth / 2), new THREE.Vector3(x + offset, 0.184, z + depth / 2));
        }
      }
    });
    if (joints.length) {
      // Points, unlike top-level object positions, are baked into the geometry.
      joints.forEach(p => { p.x *= -1; });
      seg.add(new THREE.LineSegments(new THREE.BufferGeometry().setFromPoints(joints),
        new THREE.LineBasicMaterial({ color: BRAND.curb, transparent: true, opacity: 0.35 })));
    }
    seg.children.forEach(child => {
      child.position.x *= -1;
      child.rotation.y *= -1;
    });
    seg.traverse(child => {
      if (child.isMesh && child.material && child.material.isMeshLambertMaterial) child.receiveShadow = true;
      if (!child.userData.actor && child.material?.color?.getHex() === BRAND.sidewalk) child.userData.surface = 'sidewalk';
      if (!child.userData.actor && child.material?.color?.getHex() === BRAND.asphalt && child.geometry?.type === 'PlaneGeometry') child.userData.surface = 'road';
    });
    seg.traverse(child => {
      if (child.userData.surface === 'sidewalk') { child.material.color.setHex(season().sidewalk); child.material.userData.seasonal = 'sidewalk'; }
    });
    scene.add(seg);
  }

  function disposeSegment(seg) {
    if (state.roadEvent?.group === seg) finishRoadEvent(state.roadEvent.phase === 'manual');
    const removed = new Set(); seg.traverse(o => removed.add(o));
    state.ambient = state.ambient.filter(a => !removed.has(a.mesh));
    state.occluders = state.occluders.filter(o => !removed.has(o));
    if (seg.parent) seg.parent.remove(seg);
    const geometries = new Set(), materials = new Set(), textures = new Set();
    seg.traverse(obj => {
      if (obj.geometry) geometries.add(obj.geometry);
      if (obj.material) (Array.isArray(obj.material) ? obj.material : [obj.material]).forEach(m => {
        materials.add(m);
        if (m.map && ![...signTextureCache.values()].includes(m.map)) textures.add(m.map);
      });
    });
    geometries.forEach(g => g.dispose());
    materials.forEach(m => m.dispose());
    textures.forEach(t => t.dispose());
    state.actors = state.actors.filter(a => a.segment !== seg);
  }

  function routeSpec(situation) {
    return (window.PDD_SCENARIO_ROUTES || {})[situation.id] ||
      { maneuver: 'straight', yieldTo: [], reviewed: false };
  }

  function nextSituation() {
    // Unreviewed geometry must not silently teach an incorrect scene.
    const pool = SITUATIONS.filter(s => routeSpec(s).reviewed);
    if (!pool.length) throw new Error('No validated driving scenarios loaded');
    if (!situationBag.length) {
      situationBag = pool.slice();
      for (let i = situationBag.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [situationBag[i], situationBag[j]] = [situationBag[j], situationBag[i]];
      }
      if (situationBag.length > 1 && situationBag[situationBag.length - 1].id === lastSituationId) {
        [situationBag[0], situationBag[situationBag.length - 1]] =
          [situationBag[situationBag.length - 1], situationBag[0]];
      }
    }
    const selected = situationBag.pop();
    lastSituationId = selected.id;
    return selected;
  }

  function buildInitialTrack() {
    buildStraightSegment(-150, 200);
    const incoming = state.roadSegments[state.roadSegments.length - 1];
    currentCorridor = incoming;
    buildIntersectionSegment(50, nextSituation(), incoming);
    nextSegmentZ = 102;
  }

  function checkAndSpawnNext() {
    if (!state.isAtSituation && !state.resolution && maybeReverseWorld()) return;
    if (state.isResolvingSituation || state.intersections.length) return;
    if (playerCarGroup.position.z + 110 > nextSegmentZ) {
      situationIndex++;
      buildIntersectionSegment(nextSegmentZ, nextSituation(), state.exitRoad);
      state.exitRoad = null;
    }
    trimSegments();
  }

  // Both the removed geometry and its GPU resources have a bounded lifetime,
  // whatever pushed the newest segment (junction, exit road or road event).
  function trimSegments() {
    if (state.roadSegments.length <= 8) return;
    while (state.roadSegments.length > 8) disposeSegment(state.roadSegments.shift());
    refreshRoadBounds();
  }

  function corridorWorldEnds() {
    if (!currentCorridor?.userData.roadEnds) return [];
    currentCorridor.updateWorldMatrix(true, false);
    return currentCorridor.userData.roadEnds.map(p => p.clone().applyMatrix4(currentCorridor.matrixWorld));
  }

  function maybeReverseWorld(force = false) {
    if (!currentCorridor || state.isAtSituation || state.resolution || Math.cos(playerCarGroup.rotation.y) > -0.55) return false;
    const forward = new THREE.Vector3(Math.sin(playerCarGroup.rotation.y), 0, Math.cos(playerCarGroup.rotation.y));
    const distanceToEnd = Math.max(...corridorWorldEnds().map(p => p.clone().sub(playerCarGroup.position).dot(forward)));
    if (!force && distanceToEnd > 105) return false;

    // Passive coordinate rebase around the road centre beside the player.
    // Applying the same transform to camera and world keeps the rendered frame
    // unchanged, while the player's travel direction becomes local +Z again.
    const pivot = new THREE.Vector3(0, 0, playerCarGroup.position.z);
    const transform = new THREE.Matrix4().makeTranslation(pivot.x, 0, pivot.z)
      .multiply(new THREE.Matrix4().makeRotationY(Math.PI))
      .multiply(new THREE.Matrix4().makeTranslation(-pivot.x, 0, -pivot.z));
    state.roadSegments.forEach(seg => seg.applyMatrix4(transform));
    camera.position.applyMatrix4(transform); cameraLook.applyMatrix4(transform);
    playerCarGroup.applyMatrix4(transform);
    state.lastSafePosition.applyMatrix4(transform);
    cameraHeading += Math.PI;

    scene.updateMatrixWorld(true);
    const corridorWorld = currentCorridor.matrixWorld.clone();
    if (currentCorridor.parent) currentCorridor.parent.remove(currentCorridor);
    scene.add(currentCorridor);
    corridorWorld.decompose(currentCorridor.position, currentCorridor.quaternion, currentCorridor.scale);
    cancelRoadEvent();
    const retired = state.roadSegments.filter(seg => seg !== currentCorridor);
    retired.forEach(disposeSegment);
    state.roadSegments = [currentCorridor];
    state.intersections = [];
    state.activeIntersection = null;
    state.actors = [];
    state.exitRoad = currentCorridor;
    clearOncoming();
    state.speedLimitKmH = null;
    state.speedingTime = 0;
    state.speedingPenalized = false;

    const ends = corridorWorldEnds();
    const startZ = Math.max(...ends.map(p => p.z));
    state.district = (state.district + 1) % 3;
    buildIntersectionSegment(startZ, nextSituation(), currentCorridor);
    nextSegmentZ = startZ + 52;
    refreshRoadBounds();
    return true;
  }

  function curve(points) {
    return new THREE.CatmullRomCurve3(points, false, 'centripetal');
  }

  function buildActorMotion(actor, intersection) {
    const p = actor.initialPos.clone();
    const cfg = actor.config;
    const z = intersection.centerZ;
    let points, clearDistance;
    if (cfg.type === 'pedestrian') {
      // Cross the side street at its zebra, then continue along the pavement.
      const x = p.x;
      points = [p, new THREE.Vector3(x, 0.03, z - 3.8),
        new THREE.Vector3(x, 0.03, z + 3.8),
        new THREE.Vector3(x, 0.18, z + 5.8),
        new THREE.Vector3(x * 1.8, 0.18, z + 6.1),
        new THREE.Vector3(Math.sign(x) * 48, 0.18, z + 6.1)];
      clearDistance = 12.5;
    } else {
      const yaw = actor.mesh.rotation.y;
      const forward = new THREE.Vector3(Math.sin(yaw), 0, Math.cos(yaw));
      if (cfg.targetAction === 'uturn') {
        const side = new THREE.Vector3(Math.cos(yaw), 0, -Math.sin(yaw));
        const entry = p.clone().addScaledVector(forward, 5);
        const exit = entry.clone().addScaledVector(side, 3.6);
        points = [p, entry, entry.clone().addScaledVector(forward, 2).addScaledVector(side, 1.8),
          exit, exit.clone().addScaledVector(forward, -50)];
        clearDistance = 20;
      } else if (cfg.targetAction === 'turn_left' || cfg.targetAction === 'turn_right') {
        const turn = cfg.targetAction === 'turn_left' ? Math.PI / 2 : -Math.PI / 2;
        const outgoing = new THREE.Vector3(Math.sin(yaw + turn), 0, Math.cos(yaw + turn));
        const center = new THREE.Vector3(0, 0, z);
        // Keep the actual approach lane (including offset tram tracks) until
        // the junction. Snapping all approaches to 1.8m made turning trams
        // sweep into the adjacent waiting car before reaching the crossing.
        const lateral = p.clone().sub(center);
        lateral.addScaledVector(forward, -lateral.dot(forward));
        const approach = center.clone().addScaledVector(forward, -6).add(lateral);
        const entry = center.clone().addScaledVector(forward, -2).add(lateral);
        // Stay on the right-hand half of the outgoing carriageway.
        const right = new THREE.Vector3(-outgoing.z, 0, outgoing.x);
        const exit = center.clone().addScaledVector(outgoing, 6).addScaledVector(right, 1.8);
        points = [p, approach, entry, exit, exit.clone().addScaledVector(outgoing, 10), exit.clone().addScaledVector(outgoing, 45)];
        clearDistance = p.distanceTo(entry) + entry.distanceTo(exit) + actor.halfLength + 3;
      } else {
        points = [p, p.clone().addScaledVector(forward, 16), p.clone().addScaledVector(forward, 65)];
        clearDistance = cfg.type === 'cyclist' ? 15 :
          (Math.abs(p.x) > 5 ? Math.abs(p.x) : Math.abs(p.z - z)) + 5.5 + actor.halfLength;
      }
    }
    const path = curve(points);
    // Turning traffic signals its manoeuvre until the turn is complete.
    const signalPlan = cfg.targetAction === 'turn_right' ? [{ from: 0, to: clearDistance, side: 'right' }] :
      (cfg.targetAction === 'turn_left' || cfg.targetAction === 'uturn') ? [{ from: 0, to: clearDistance, side: 'left' }] : null;
    return { ...actor, segment: intersection.seg, path, length: path.getLength(),
      distance: 0, speed: 0, maxSpeed: cfg.type === 'pedestrian' ? 3.6 : cfg.type === 'cyclist' ? 7 : 12,
      clearDistance, active: false, waitsForPlayer: true, cleared: false, done: false, gait: 0, signalPlan };
  }

  function ensureTraffic(intersection) {
    if (!intersection.motions) {
      intersection.motions = intersection.actors.map(a => buildActorMotion(a, intersection));
      state.actors.push(...intersection.motions);
    }
    return intersection.motions;
  }

  function releaseTraffic(situationId) {
    if (state.roadEvent?.phase === 'question' && state.roadEvent.situation.id === situationId) {
      releaseRoadActors(state.roadEvent);
      return;
    }
    const intersection = state.activeIntersection;
    if (!intersection || intersection.situation.id !== situationId || intersection.trafficReleased) return;
    intersection.trafficReleased = true;
    if (intersection.trafficLight && !intersection.trafficLight.userData.arrow &&
        intersection.situation.trafficLights.state !== 'flashing_yellow') {
      intersection.trafficLight.setLightState('green');
    }
    const motions = ensureTraffic(intersection);
    const priority = routeSpec(intersection.situation).yieldTo;
    const ordered = [...motions.filter(a => priority.includes(a.config.id)), ...motions.filter(a => !priority.includes(a.config.id))];
    ordered.forEach((a, i) => {
      a.waitsForPlayer = false;
      a.dependencies = ordered.slice(0, i).filter(b => pathsConflict(a, b));
    });
  }

  function resolveSituationAnimation(isCorrect, situationId) {
    if (state.roadEvent?.phase === 'question' && state.roadEvent.situation.id === situationId) {
      if (!state.paused && state.isAtSituation) startRoadManual();
      return;
    }
    const intersection = state.activeIntersection;
    if (state.paused || state.isResolvingSituation || !state.isAtSituation || !intersection) return;
    if (situationId && situationId !== intersection.situation.id) return;
    state.isResolvingSituation = true;
    state.isAccelerating = false;
    state.speed = 0;
    const spec = routeSpec(intersection.situation);
    const motions = ensureTraffic(intersection);
    const yielding = spec.yieldTo.map(id => motions.find(a => a.config.id === id)).filter(Boolean);
    state.resolution = { intersection, spec, motions, yielding, phase: 'manual', elapsed: 0,
      entry: playerCarGroup.position.clone(), entryYaw: playerCarGroup.rotation.y, faults: new Set(), recovery: 0 };
    state.steering = 0;
    startPlayerManeuver();
    const r = state.resolution;
    const intended = { path: r.path, length: r.length, clearDistance: r.length, halfWidth: 0.9, halfLength: 2 };
    const ordered = [...yielding, ...motions.filter(a => !yielding.includes(a))];
    ordered.forEach((a, i) => {
      a.dependencies = ordered.slice(0, i).filter(b => pathsConflict(a, b));
      a.waitsForPlayer = !intersection.trafficReleased && !yielding.includes(a) && pathsConflict(a, intended);
    });
  }

  function startPlayerManeuver() {
    const r = state.resolution;
    if (!r) return;
    const z = r.intersection.centerZ;
    const start = playerCarGroup.position.clone();
    const action = r.spec.maneuver;
    let points, exitYaw = 0;
    if (action === 'right') {
      exitYaw = -Math.PI / 2;
      points = [start, new THREE.Vector3(-1.8, 0, z - 4.8),
        new THREE.Vector3(-4.8, 0, z - 1.8), new THREE.Vector3(-22, 0, z - 1.8)];
    } else if (action === 'left') {
      exitYaw = Math.PI / 2;
      points = [start, new THREE.Vector3(-1.8, 0, z - 1.5),
        new THREE.Vector3(1.5, 0, z + 1.8), new THREE.Vector3(22, 0, z + 1.8)];
    } else if (action === 'uturn') {
      exitYaw = Math.PI;
      points = [start, new THREE.Vector3(-2.8, 0, z - 3), new THREE.Vector3(-2.8, 0, z),
        new THREE.Vector3(0, 0, z + 3), new THREE.Vector3(2.8, 0, z), new THREE.Vector3(1.8, 0, z - 6),
        new THREE.Vector3(1.8, 0, z - 22)];
    } else {
      points = [start, new THREE.Vector3(-1.8, 0, z), new THREE.Vector3(-1.8, 0, z + 16)];
    }
    r.phase = 'manual';
    r.path = curve(points);
    r.length = r.path.getLength();
    r.distance = 0;
    r.exitYaw = exitYaw;
    if (action !== 'straight') triggerBlinker(action === 'right' ? 'right' : 'left');
    if (r.intersection.trafficLight && !r.intersection.trafficLight.userData.arrow &&
        r.intersection.situation.trafficLights.state !== 'flashing_yellow') {
      r.intersection.trafficLight.setLightState('green');
    }
  }

  function followingSpeed(actor, traffic, dt) {
    if (actor.config.type === 'pedestrian') return actor.maxSpeed;
    const box = traffic.get(actor).box;
    const forward = new THREE.Vector3(Math.sin(box.yaw), 0, Math.cos(box.yaw));
    const right = new THREE.Vector3(forward.z, 0, -forward.x);
    let limit = actor.maxSpeed;
    for (const [other, entry] of traffic) {
      if (other === actor || other.config.type === 'pedestrian') continue;
      const leader = entry.box, alignment = Math.cos(leader.yaw - box.yaw);
      if (alignment < 0.4) continue; // Crossing traffic uses the conflict rules.
      const delta = leader.p.clone().sub(box.p), ahead = delta.dot(forward);
      if (ahead <= 0) continue;
      const across = Math.abs(Math.sin(leader.yaw - box.yaw));
      const width = alignment * leader.halfWidth + across * leader.halfLength;
      if (Math.abs(delta.dot(right)) >= box.halfWidth + width + 0.15) continue;
      const gap = ahead - box.halfLength - alignment * leader.halfLength - across * leader.halfWidth;
      const room = Math.max(0, gap - 1.4);
      const speed = entry.speed * alignment;
      // Stopping distance plus 0.8s headway; stopped queues retain a 1.4m gap.
      // Also cap this frame's travel, including long frames and a stopped leader.
      const braking = 8, headway = 0.8;
      const safe = Math.sqrt((braking * headway) ** 2 + speed * speed + 2 * braking * room) - braking * headway;
      limit = Math.min(limit, safe, room / Math.max(dt, 0.001));
    }
    return Math.max(0, limit);
  }

  function updateActors(dt) {
    state.busBays = state.busBays.filter(b => b.mesh.parent);
    // Walkers meeting on the same pavement lane step to the other lane and
    // pass each other instead of walking through one another.
    for (let i = 0; i < state.ambient.length; i++) {
      const a = state.ambient[i];
      if (a.targetLane !== a.lane && Math.abs(a.mesh.position.z - a.meetZ) > 4) a.targetLane = a.lane;
      if (a.kind === 'cat') continue;
      for (let j = i + 1; j < state.ambient.length; j++) {
        const b = state.ambient[j];
        if (b.kind === 'cat' || b.seg !== a.seg || b.side !== a.side || a.targetLane !== b.targetLane) continue;
        if (Math.abs(a.mesh.position.z - b.mesh.position.z) < 2.4) { a.targetLane = 1 - a.targetLane; a.meetZ = a.mesh.position.z; }
      }
    }
    state.ambient.forEach(a => {
      a.time += dt;
      if (a.kind === 'cat') {
        // Short strolls with long pauses, a flick of the tail while sitting.
        const cycle = a.time * 0.09 + a.phase, moving = Math.abs(Math.cos(cycle)) > 0.55;
        if (moving) a.mesh.position.z = a.center + Math.sin(cycle) * 1.6;
        a.mesh.rotation.y = Math.cos(cycle) >= 0 ? 0 : Math.PI;
        a.mesh.userData.legs.forEach((leg, i) => { leg.rotation.x = moving ? Math.sin(a.time * 9 + i * Math.PI / 2) * 0.5 : 0; });
        a.mesh.userData.tail.rotation.z = Math.sin(a.time * 1.7) * 0.35;
        return;
      }
      const phase = a.phase + a.time * 0.14;
      a.mesh.position.z = a.center + Math.sin(phase) * 6;
      // Near a bus bay on their side, walkers take the path behind it.
      let laneX = 5.2 + (a.targetLane ?? a.lane ?? 0) * 1.1;
      for (const bay of state.busBays || []) {
        if (!bay.mesh.parent) continue;
        const local = a.seg.worldToLocal(bay.mesh.parent.localToWorld(bay.center.clone()));
        if (Math.sign(local.x) === Math.sign(a.mesh.position.x || 1) && Math.abs(local.z - a.mesh.position.z) < 24) { laneX = 8.5; break; }
      }
      const targetX = Math.sign(a.mesh.position.x || 1) * laneX;
      a.mesh.position.x += (targetX - a.mesh.position.x) * Math.min(1, dt * 3);
      const direction = Math.cos(phase);
      a.mesh.rotation.y = direction >= 0 ? 0 : Math.PI;
      a.mesh.userData.legs.forEach((leg, i) => { leg.rotation.x = Math.sin(a.time * 5 + i * Math.PI) * 0.32 * Math.abs(direction); });
      if (a.mesh.userData.dog) a.mesh.userData.dog.userData.legs.forEach((leg, i) => { leg.rotation.x = Math.sin(a.time * 9 + i * Math.PI / 2) * 0.55 * Math.abs(direction); });
      a.mesh.userData.arms.forEach((arm, i) => { arm.rotation.x = Math.sin(a.time * 5 + i * Math.PI) * -0.2 * Math.abs(direction); });
    });
    // One world-space snapshot makes following independent of actor order and
    // works after turns/rebasing, where neighbouring tasks have different parents.
    const traffic = new Map(state.actors.filter(a => !a.done && !a.fall).map(a =>
      [a, { box: actorFootprint(a), speed: a.active && !a.crashed ? a.speed : 0 }]));
    // The player's car is a leader too: traffic behind it brakes to a gap
    // (e.g. while the player waits at a question) instead of ramming it.
    const playerLeader = { config: { type: 'player' }, done: false, fall: false };
    traffic.set(playerLeader, { box: playerFootprint(), speed: Math.max(0, state.speed) });
    const currentBoxes = new Map([...traffic].filter(([a]) => a !== playerLeader).map(([a, entry]) => [a, entry.box]));
    state.actors.forEach(a => {
      if (a.done) return;
      if (a.fall) { updateActorFall(a, dt); return; }
      if (a.crashed) {
        a.speed = 0;
        if (a.knock) {
          const k = a.knock; k.t += dt;
          const u = Math.min(1, k.t / k.duration), e = 1 - Math.pow(1 - u, 3);
          a.mesh.position.lerpVectors(k.from, k.to, e);
          a.mesh.rotation.y = k.fromYaw + (k.toYaw - k.fromYaw) * e;
          if (u >= 1) a.knock = null;
        }
        if (actorFootprint(a).p.distanceTo(playerCarGroup.position) > 90 && !actorInView(a.mesh)) {
          a.done = true;
          a.mesh.visible = false;
        }
        return;
      }
      if (!a.active && !a.waitsForPlayer && a.dependencies?.every(b => b.cleared)) a.active = true;
      if (!a.active || a.done) return;
      a.speed = Math.min(followingSpeed(a, traffic, dt), a.speed + dt * (a.config.type === 'pedestrian' ? 8 : 12));
      const advance = a.speed * dt;
      const steps = Math.max(1, Math.ceil(advance / 0.15));
      for (let i = 0; i < steps; i++) {
        const before = a.mesh.position.clone(), yaw = a.mesh.rotation.y, distance = a.distance;
        a.distance += advance / steps;
        const t = Math.min(1, a.distance / a.length), tangent = a.path.getTangentAt(t);
        a.mesh.position.copy(a.path.getPointAt(t));
        if (a.distance > a.length) a.mesh.position.addScaledVector(tangent, a.distance - a.length);
        a.mesh.rotation.y = Math.atan2(tangent.x, tangent.z);
        const box = actorFootprint(a);
        const playerContact = footprintsOverlap(box, playerFootprint(), 0.04);
        let trafficContact = false;
        for (const [b, other] of currentBoxes) {
          if (b !== a && !b.done && footprintsOverlap(box, other, 0.04)) { trafficContact = true; break; }
        }
        if (playerContact || trafficContact) {
          a.mesh.position.copy(before); a.mesh.rotation.y = yaw; a.distance = distance; a.speed = 0;
          if (playerContact && !state.attract && (!state.isAtSituation || state.resolution?.phase === 'manual')) {
            handleCollision(a, 'collision:' + a.config.id);
          }
          if (a.fall) currentBoxes.delete(a);
          else currentBoxes.set(a, actorFootprint(a));
          break;
        }
        currentBoxes.set(a, box);
      }
      const t = Math.min(1, a.distance / a.length);
      a.gait += a.speed * dt * 3.5;
      if (a.mesh.userData.legs) a.mesh.userData.legs.forEach((leg, i) => {
        leg.rotation.x = Math.sin(a.gait + i * Math.PI) * 0.42;
      });
      if (a.mesh.userData.wheels) a.mesh.userData.wheels.forEach(w => w.rotateX(a.speed * dt / 0.36));
      if (a.mesh.userData.pedals) a.mesh.userData.pedals.rotation.x += a.speed * dt * 1.8;
      a.cleared = a.crashed || !!a.fall || a.distance >= a.clearDistance;
      // Keep walking/riding beyond the planned path. Removal is permitted only
      // once the WHOLE actor is outside the camera, never at a fixed timer/distance.
      if (t >= 1 && !actorInView(a.mesh)) { a.done = true; a.mesh.visible = false; }
    });
  }

  function actorInView(mesh) {
    // Only the actor's ancestor chain and subtree need fresh matrices here.
    // Updating every prebuilt district for each departing actor is quadratic.
    mesh.updateWorldMatrix(true, true);
    camera.updateMatrixWorld(true);
    const frustum = new THREE.Frustum().setFromProjectionMatrix(
      new THREE.Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse));
    return frustum.intersectsBox(new THREE.Box3().setFromObject(mesh).expandByScalar(3));
  }

  function startActorFall(actor) {
    if (actor.fall || !['pedestrian', 'cyclist'].includes(actor.config.type)) return;
    const relativeYaw = playerCarGroup.rotation.y + (state.speed < 0 ? Math.PI : 0) - actorFootprint(actor).yaw;
    const push = new THREE.Vector3(Math.sin(relativeYaw), 0, Math.cos(relativeYaw));
    actor.fall = { time: 0, clearTime: 0, direction: Math.sin(relativeYaw) >= 0 ? 1 : -1,
      push, axis: new THREE.Vector3(push.z, 0, -push.x),
      impulse: Math.min(1.2, Math.max(0.25, Math.abs(state.speed) * 0.08)) };
    actor.speed = 0;
    actor.cleared = true;
    actor.done = false;
    actor.mesh.visible = true;
    actor.mesh.userData.badge.visible = false;
  }

  function updateActorFall(actor, dt) {
    const fall = actor.fall;
    fall.time += dt;
    const body = actor.mesh.userData.body;
    const dropping = Math.min(1, fall.time / 0.65);
    // A struck pedestrian/cyclist stays down for the rest of the scene and
    // has no collision shape: the run can never get stuck on them.
    const amount = Math.sin(dropping * Math.PI / 2);
    if (actor.config.type === 'cyclist') body.quaternion.setFromAxisAngle(new THREE.Vector3(0, 0, 1), fall.direction * amount * 1.5);
    else body.quaternion.setFromAxisAngle(fall.axis, amount * 1.48);
    body.position.x = fall.push.x * fall.impulse * amount;
    body.position.z = fall.push.z * fall.impulse * amount;
    body.position.y = 0;
    if (actor.mesh.userData.legs) actor.mesh.userData.legs.forEach((leg, i) => {
      leg.rotation.x = amount * (i ? -0.55 : 0.35);
    });
    if (actor.mesh.userData.arms) actor.mesh.userData.arms.forEach((arm, i) => {
      arm.rotation.z = (i ? 1 : -1) * (0.1 + amount * 0.8);
      arm.rotation.x = -amount * 0.5;
    });
    if (actor.mesh.userData.rider) {
      const rider = actor.mesh.userData.rider;
      rider.position.z = amount * 0.45;
      rider.rotation.x = -amount * 0.4;
      rider.rotation.z = -fall.direction * amount * 0.2;
    }
    // Ground contact prevents limbs/bicycle sinking through the road. A small
    // damped rebound communicates inertia without violence or injury effects.
    actor.mesh.updateMatrixWorld(true);
    const bounds = new THREE.Box3().setFromObject(body);
    const groundY = actor.mesh.getWorldPosition(new THREE.Vector3()).y;
    body.position.y = Math.max(0, groundY - bounds.min.y) +
      (fall.time < 0.65 ? Math.sin(dropping * Math.PI) * 0.12 : 0);
    if (fall.time > 2 && actorFootprint(actor).p.distanceTo(playerCarGroup.position) > 90 && !actorInView(actor.mesh)) {
      actor.done = true;
      actor.mesh.visible = false;
    }
  }

  function footprintsOverlap(a, b, margin = 0) {
    const axes = box => [new THREE.Vector3(Math.cos(box.yaw), 0, -Math.sin(box.yaw)),
      new THREE.Vector3(Math.sin(box.yaw), 0, Math.cos(box.yaw))];
    const aa = axes(a), bb = axes(b), delta = b.p.clone().sub(a.p);
    return [...aa, ...bb].every(axis => {
      const ra = Math.abs(axis.dot(aa[0])) * a.halfWidth + Math.abs(axis.dot(aa[1])) * a.halfLength;
      const rb = Math.abs(axis.dot(bb[0])) * b.halfWidth + Math.abs(axis.dot(bb[1])) * b.halfLength;
      return Math.abs(delta.dot(axis)) < ra + rb + margin;
    });
  }

  function playerFootprint() {
    return { p: playerCarGroup.position, yaw: playerCarGroup.rotation.y,
      halfWidth: playerCarGroup.userData.halfWidth, halfLength: playerCarGroup.userData.halfLength };
  }

  function actorFootprint(actor) {
    const p = actor.mesh.getWorldPosition(new THREE.Vector3());
    const q = actor.mesh.getWorldQuaternion(new THREE.Quaternion());
    const forward = new THREE.Vector3(0, 0, 1).applyQuaternion(q);
    let halfWidth = actor.halfWidth, halfLength = actor.halfLength;
    if (actor.fall) {
      // The visible body is displaced by the impact inside the actor group.
      // Fallen actors take part in no collision test; this footprint is only
      // used to keep traffic from spawning/driving through the visible body.
      const body = actor.mesh.userData.body;
      p.add(new THREE.Vector3(body.position.x, 0, body.position.z).applyQuaternion(q));
    }
    return { p, yaw: Math.atan2(forward.x, forward.z), halfWidth, halfLength };
  }

  function pathsConflict(a, b) {
    const samples = motion => {
      const points = [];
      for (let d = 0; d <= Math.min(motion.length, motion.clearDistance + 5); d += 1) {
        const t = d / motion.length, v = motion.path.getTangentAt(t);
        points.push({ p: motion.path.getPointAt(t), yaw: Math.atan2(v.x, v.z),
          halfWidth: motion.halfWidth, halfLength: motion.halfLength });
      }
      return points;
    };
    const aa = samples(a), bb = samples(b);
    return aa.some(p => bb.some(q => footprintsOverlap(p, q, 0.2)));
  }

  function drivingFault(type, key = type) {
    const r = state.resolution;
    const faults = r ? r.faults : state.driveFaults;
    if (faults.has(key)) return;
    faults.add(key);
    sendToFlutter({ event: 'violation', type, episode: ++state.violationEpisode });
  }

  function placeActorAtDistance(actor, distance) {
    actor.distance = Math.max(0, distance);
    const t = Math.min(1, actor.distance / actor.length);
    const tangent = actor.path.getTangentAt(t);
    actor.mesh.position.copy(actor.path.getPointAt(t));
    if (distance < 0) actor.mesh.position.addScaledVector(actor.path.getTangentAt(0), distance);
    else if (actor.distance > actor.length) actor.mesh.position.addScaledVector(tangent, actor.distance - actor.length);
    actor.mesh.rotation.y = Math.atan2(tangent.x, tangent.z);
  }

  function playerContacts(margin = 0) {
    return new Set(state.actors.filter(a => !a.done && !a.fall &&
      footprintsOverlap(playerFootprint(), actorFootprint(a), margin)));
  }

  function separateCrashedActor(actor) {
    // Guarantee a usable escape gap: first back the vehicle along its own
    // route, then (if the route itself runs into the player) push it straight
    // away from the player's car. An unresolved overlap would re-trigger the
    // collision every frame, freezing the run even when trying to reverse.
    // The vehicle does not teleport: it slides to the resting spot (a.knock).
    if (!actor || ['pedestrian', 'cyclist'].includes(actor.config.type)) return;
    // Wide enough to steer around the wreck from a standstill.
    const gap = 0.9;
    if (!footprintsOverlap(playerFootprint(), actorFootprint(actor), gap)) return;
    const startPosition = actor.mesh.position.clone(), startYaw = actor.mesh.rotation.y;
    const finish = () => {
      actor.knock = { from: startPosition, fromYaw: startYaw, to: actor.mesh.position.clone(), toYaw: actor.mesh.rotation.y, t: 0, duration: 0.34 };
      actor.mesh.position.copy(startPosition); actor.mesh.rotation.y = startYaw;
    };
    const originalDistance = actor.distance;
    for (let retreat = 0.2; retreat <= 6; retreat += 0.2) {
      placeActorAtDistance(actor, originalDistance - retreat);
      if (!footprintsOverlap(playerFootprint(), actorFootprint(actor), gap)) { finish(); return; }
    }
    placeActorAtDistance(actor, originalDistance);
    const away = actorFootprint(actor).p.clone().sub(playerCarGroup.position); away.y = 0;
    if (away.lengthSq() < 1e-4) away.set(Math.cos(playerCarGroup.rotation.y), 0, -Math.sin(playerCarGroup.rotation.y));
    away.normalize();
    const parent = actor.mesh.parent;
    const localAway = parent ? away.clone().transformDirection(parent.matrixWorld.clone().invert()) : away;
    for (let push = 0.1; push <= 8; push += 0.1) {
      actor.mesh.position.addScaledVector(localAway, 0.1);
      actor.mesh.updateMatrixWorld(true);
      if (!footprintsOverlap(playerFootprint(), actorFootprint(actor), gap)) { finish(); return; }
    }
    finish();
  }

  function parkCrashedActor(actor) {
    if (!actor || actor.crashed || ['pedestrian', 'cyclist'].includes(actor.config.type)) return;
    separateCrashedActor(actor);
    actor.speed = 0;
    actor.active = false;
    actor.crashed = true;
    actor.cleared = true;
  }

  function handleCollision(actor, key) {
    if (['pedestrian', 'cyclist'].includes(actor.config.type)) gameAudio?.softImpact(actor.config.type);
    else gameAudio?.impact(Math.abs(state.speed));
    startActorFall(actor);
    parkCrashedActor(actor);
    resetAfterImpact('collision', key);
  }

  function resetAfterImpact(type, key) {
    drivingFault(type, key);
    state.speed = 0;
    state.isAccelerating = false;
    state.isBraking = false;
    state.steering = 0;
    // A short control release makes the impact legible, but never teleports or
    // rotates the player's car. After it expires the player can immediately
    // steer around the stationary crash participant.
    if (state.resolution) state.resolution.recovery = 0.38;
    else state.driveRecovery = 0.38;
    sendToFlutter({ event: 'maneuver_reset' });
  }

  function updateResolution(dt) {
    const r = state.resolution;
    if (!r) return;
    r.elapsed += dt;
    if (r.recovery > 0) {
      r.recovery = Math.max(0, r.recovery - dt);
      if (!r.recovery) {
        r.faults.delete('offroad');
        r.motions.forEach(a => r.faults.delete('collision:' + a.config.id));
        sendToFlutter({ event: 'maneuver_ready' });
      }
      return;
    }
    const contactsBefore = playerContacts();
    integrateDriving(dt);
    if (r.recovery > 0) return;
    const p = playerCarGroup.position, z = r.intersection.centerZ, yaw = playerCarGroup.rotation.y;
    const playerBox = { p, yaw, halfWidth: playerCarGroup.userData.halfWidth, halfLength: playerCarGroup.userData.halfLength };
    for (const a of r.motions) {
      if (a.done || a.fall) continue;
      const other = actorFootprint(a);
      if (footprintsOverlap(playerBox, other)) {
        // A contact that already existed at the start of the frame is being
        // resolved (the player is driving out of it) — never a new ДТП.
        if (contactsBefore.has(a)) { if (a.crashed && !a.knock) separateCrashedActor(a); continue; }
        handleCollision(a, 'collision:' + a.config.id);
        return;
      }
      if (state.speed > 0.5 && r.yielding.includes(a) && !a.cleared) {
        const predicted = { ...playerBox, p: p.clone().add(new THREE.Vector3(Math.sin(yaw), 0, Math.cos(yaw)).multiplyScalar(state.speed)) };
        const obstacle = { ...other, p: other.p.clone().add(new THREE.Vector3(Math.sin(other.yaw), 0, Math.cos(other.yaw)).multiplyScalar(a.speed)) };
        if (footprintsOverlap(predicted, obstacle, 0.5)) drivingFault('priority');
      }
    }
    const sideStreet = Math.abs(p.x) > 7;
    const mainStreet = Math.abs(p.z - z) > 7;
    updateLaneViolation(dt, sideStreet ? Math.sin(yaw) * (p.z - z) < -0.85 : mainStreet && Math.cos(yaw) * p.x > 0.85);
    const exits = [
      ['left', Math.PI / 2, p.x > 24, Math.abs(p.z - z)],
      ['right', -Math.PI / 2, p.x < -24, Math.abs(p.z - z)],
      ['straight', 0, p.z > z + 24, Math.abs(p.x)],
      ['uturn', Math.PI, p.z < z - 24, Math.abs(p.x)],
    ];
    for (const [direction, heading, beyond, lateral] of exits) {
      const error = Math.atan2(Math.sin(yaw - heading), Math.cos(yaw - heading));
      if (beyond && lateral < 3.3 && Math.abs(error) < 0.35) {
        r.exitDirection = direction;
        r.exitYaw = heading;
        if (direction !== r.spec.maneuver) drivingFault('wrong_maneuver');
        finishManeuver();
        break;
      }
    }
  }

  function finishManeuver() {
    const r = state.resolution;
    if (!r) return;
    const trailing = r.motions.filter(a => !r.yielding.includes(a));
    trailing.forEach(a => { a.waitsForPlayer = false; });
    const id = r.intersection.situation.id;
    state.district = (state.district + 1) % 3;
    r.intersection.guide.visible = false;
    state.intersections = state.intersections.filter(i => i !== r.intersection);
    const outgoingPreview = r.intersection.previews[r.exitDirection || r.spec.maneuver];
    scene.updateMatrixWorld(true);
    const roadWorld = outgoingPreview.matrixWorld.clone();
    const ends = outgoingPreview.userData.roadEnds.map(p => p.clone().applyMatrix4(roadWorld));
    scene.add(outgoingPreview);
    roadWorld.decompose(outgoingPreview.position, outgoingPreview.quaternion, outgoingPreview.scale);
    state.roadSegments.push(outgoingPreview);
    let transform = new THREE.Matrix4();
    if (r.exitYaw !== 0) {
      // Rebase the whole visible world, including the camera, without a visual cut.
      // New road geometry can then continue along local +Z after any number of turns.
      const forward = new THREE.Vector3(Math.sin(r.exitYaw), 0, Math.cos(r.exitYaw));
      const center = new THREE.Vector3(0, 0, r.intersection.centerZ);
      const endpoint = center.clone().addScaledVector(forward, playerCarGroup.position.clone().sub(center).dot(forward));
      const rotation = new THREE.Matrix4().makeRotationY(-r.exitYaw);
      transform = rotation.multiply(new THREE.Matrix4().makeTranslation(-endpoint.x, 0, -endpoint.z));
      state.roadSegments.forEach(seg => seg.applyMatrix4(transform));
      const oldPlanes = new Set();
      state.roadSegments.forEach(seg => seg.traverse(obj => {
        for (const p of obj.material?.clippingPlanes || []) oldPlanes.add(p);
      }));
      oldPlanes.forEach(p => p.applyMatrix4(transform));
      camera.position.applyMatrix4(transform);
      cameraLook.applyMatrix4(transform);
      cameraHeading -= r.exitYaw;
      playerCarGroup.position.applyMatrix4(transform);
      playerCarGroup.rotation.y -= r.exitYaw;
      state.intersections = [];
    }
    ends.forEach(p => p.applyMatrix4(transform));
    const boundary = Math.min(...ends.map(p => p.z));
    nextSegmentZ = Math.max(...ends.map(p => p.z));
    state.exitRoad = outgoingPreview;
    currentCorridor = outgoingPreview;
    // The outgoing road owns everything past this seam. Retired cross streets
    // cannot cut through future junctions even after several turns or U-turns.
    const cut = new THREE.Plane(new THREE.Vector3(0, 0, -1), boundary);
    state.roadSegments.filter(seg => seg !== outgoingPreview).forEach(seg => seg.traverse(obj => {
      if (obj.userData.actor || obj.userData.tramRail || !obj.material) return;
      obj.material.clippingPlanes = [...(obj.material.clippingPlanes || []), cut];
      obj.material.clipShadows = true;
    }));
    refreshRoadBounds();
    state.currentLaneOffset = playerCarGroup.position.x;
    state.targetLaneOffset = state.currentLaneOffset > 0 ? 1.8 : -1.8;
    state.targetLane = state.currentLaneOffset > 0 ? 0 : 1;
    state.lastSafePosition.copy(playerCarGroup.position);
    state.lastSafeYaw = playerCarGroup.rotation.y;
    if (state.targetLane === 1) clearOncoming();
    state.isAtSituation = false;
    state.isResolvingSituation = false;
    state.activeIntersection = null;
    state.resolution = null;
    state.speedLimitKmH = null;
    state.speedingTime = 0;
    state.speedingPenalized = false;
    placeRoadEvent(boundary);
    // Populate the exit in this same update, not after the next rendered frame.
    checkAndSpawnNext();
    sendToFlutter({ event: 'situation_cleared', situationId: id });
  }

  // --- Straight-road situations: speed limits, overtaking, pedestrian crossings ---
  // A road event lives in its own group that is transformed with the world
  // (it is listed in state.roadSegments), so world coordinates stay valid
  // across rebases. Driver's right is negative X, the player's lane is x=-1.8.
  let roadBag = [], lastRoadId = null;
  function nextRoadSituation() {
    const pool = window.PDD_ROAD_SITUATIONS || [];
    if (!pool.length) return null;
    if (!roadBag.length) {
      roadBag = pool.slice();
      for (let i = roadBag.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [roadBag[i], roadBag[j]] = [roadBag[j], roadBag[i]];
      }
      if (roadBag.length > 1 && roadBag[roadBag.length - 1].id === lastRoadId) {
        [roadBag[0], roadBag[roadBag.length - 1]] = [roadBag[roadBag.length - 1], roadBag[0]];
      }
    }
    const selected = roadBag.pop();
    lastRoadId = selected.id;
    return selected;
  }

  function createTextPlate(text) {
    const canvas = document.createElement('canvas');
    canvas.width = 240; canvas.height = 120;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fafafa'; ctx.fillRect(0, 0, 240, 120);
    ctx.strokeStyle = '#20252a'; ctx.lineWidth = 8; ctx.strokeRect(5, 5, 230, 110);
    ctx.fillStyle = '#20252a'; ctx.font = 'bold 64px sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(text, 120, 62);
    const face = new THREE.Mesh(new THREE.PlaneGeometry(1.25, 0.62),
      new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(canvas), side: THREE.DoubleSide }));
    face.rotation.y = Math.PI;
    const group = new THREE.Group(); group.add(face);
    return group;
  }

  const roadMarkingMat = () => new THREE.MeshBasicMaterial({ color: BRAND.asphaltMarking });
  function addFlatPlane(group, width, length, x, z, y, material) {
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, length), material);
    mesh.rotation.x = -Math.PI / 2; mesh.position.set(x, y, z);
    group.add(mesh);
    return mesh;
  }
  // Replace the default broken centre line over [from, to] with the given
  // marking: 'solid' (1.1), 'double_solid_right' / 'double_dashed_right' (1.11,
  // the named line being the one on the player's side).
  function addCentreMarking(group, from, to, marking) {
    const cover = new THREE.MeshLambertMaterial({ color: BRAND.asphalt });
    // Clearly above the road's own paint (0.025): no z-fighting from the chase camera.
    addFlatPlane(group, 0.7, to - from, 0, (from + to) / 2, 0.034, cover);
    const paint = roadMarkingMat();
    const solid = x => addFlatPlane(group, 0.13, to - from, x, (from + to) / 2, 0.04, paint);
    const dashed = x => { const parts = []; for (let z = from + 1; z < to - 2; z += 5) parts.push(addFlatPlane(new THREE.Group(), 0.13, 2, x, z + 1, 0.04, paint)); group.add(mergeStatic(parts, paint)); };
    if (marking === 'solid') solid(0);
    else if (marking === 'double_solid_right') { solid(-0.14); dashed(0.14); }
    else if (marking === 'double_dashed_right') { dashed(-0.14); solid(0.14); }
  }
  function addZebra(group, z) {
    const cover = new THREE.MeshLambertMaterial({ color: BRAND.asphalt });
    addFlatPlane(group, 0.7, 5.2, 0, z, 0.034, cover);
    const paint = roadMarkingMat();
    const parts = []; for (let x = -3.6; x <= 3.6 + 0.01; x += 0.9) parts.push(addFlatPlane(new THREE.Group(), 0.45, 4, x, z, 0.04, paint));
    group.add(mergeStatic(parts, paint));
  }
  function addRoadSign(group, code, z, side = 'right', plate = null, offsetX = 0) {
    const x = (side === 'left' ? 5.4 : -5.4) + offsetX;
    const sign = createRoadSign(code);
    // Larger than junction signs: on a straight the camera sits further back.
    sign.scale.setScalar(1.35);
    sign.position.set(x, 0, z);
    group.add(sign);
    if (plate) { const p = createTextPlate(plate); p.scale.setScalar(1.35); p.position.set(x, 2.5, z); group.add(p); }
    return sign;
  }
  function addRoadActor(group, cfg, position, yaw, pathPoints, maxSpeed, signalPlan = null) {
    const { actorMesh, halfLength, halfWidth } = createActorMesh(cfg);
    actorMesh.position.copy(position); actorMesh.rotation.y = yaw;
    group.add(actorMesh);
    const path = curve(pathPoints);
    const actor = { mesh: actorMesh, config: cfg, halfLength, halfWidth, initialPos: position.clone(), segment: group,
      path, length: path.getLength(), distance: 0, speed: 0, maxSpeed, clearDistance: Infinity,
      active: false, cleared: false, done: false, gait: 0, waitsForPlayer: true, dependencies: [], road: true,
      signalPlan };
    state.actors.push(actor);
    return actor;
  }

  function placeRoadEvent(boundary) {
    if (state.roadEvent) return;
    const group = new THREE.Group();
    group.userData.roadEvent = true;
    scene.add(group);
    state.roadSegments.push(group);
    state.roadTurn = (state.roadTurn || 0) + 1;
    const situation = state.roadTurn % 2 === 1 ? nextRoadSituation() : null;
    const kind = state.forceRoadEvent || (Math.random() < 0.45 ? 'busstop' : 'crosswalk'); // forceRoadEvent: tests
    state.roadEvent = situation ? buildQuestionEvent(group, boundary, situation) :
      (kind === 'busstop' ? buildBusStopEvent(group, boundary + 62) : buildCrosswalkEvent(group, boundary + 70));
    // Life on the road: oncoming traffic on many stretches, question or not.
    if (!state.forceRoadEvent && Math.random() < 0.65) addOncomingTraffic(group, boundary, situation ? situation.scene : null);
    trimSegments();
    return state.roadEvent;
  }

  function buildQuestionEvent(group, boundary, situation) {
    const sc = situation.scene;
    const stopZ = boundary + 45;
    const ev = { group, situation, kind: sc.kind, scene: sc, stopZ, startZ: stopZ, endZ: stopZ + 120,
      phase: 'approach', actors: [], overtakePenalized: false };
    if (sc.overtake === 'before_intersection') {
      // The next junction segment starts 200 m past the seam; be back in lane
      // well before its crossing (its stop line is ~24 m into the segment).
      ev.laneDeadlineZ = boundary + 200 + 4;
      ev.endZ = boundary + 200 + 12;
    }
    (sc.signs || []).forEach(sg => addRoadSign(group, sg.code, stopZ + sg.z, sg.side, sg.plate || null));
    if (sc.kind === 'speed') {
      ev.signZ = stopZ + (sc.signs?.[0]?.z ?? 12);
      if (sc.zoneLength) ev.endZ = stopZ + sc.zoneLength;
      // The zone ends with its counterpart sign (5.22, 5.2, 5.26, 5.23.1):
      // past it the built-up limit applies again, as the rules require.
      if (sc.endSign) { ev.endSignZ = ev.endZ - 6; addRoadSign(group, sc.endSign, ev.endSignZ, 'right'); }
    }
    if (sc.marking) addCentreMarking(group, stopZ - 12, ev.endZ, sc.marking);
    if (sc.crosswalkZ !== undefined) { ev.crosswalkZ = stopZ + sc.crosswalkZ; addZebra(group, ev.crosswalkZ); }
    (sc.vehicles || []).forEach((v, i) => {
      const cfg = { id: `road_${i}_${v.type}`, type: v.type, name: v.name, color: v.color,
        badge: v.badge, blinker: v.blinker, maneuver: v.maneuver, scale: v.scale };
      if (v.lane === 'oncoming') {
        const p = new THREE.Vector3(1.8, 0, stopZ + v.z);
        ev.actors.push(addRoadActor(group, cfg, p, Math.PI,
          [p, p.clone().add(new THREE.Vector3(0, 0, -90)), p.clone().add(new THREE.Vector3(0, 0, -280))], v.speed));
      } else {
        const p = new THREE.Vector3(-1.8, 0, stopZ + v.z);
        const V = (x, z) => new THREE.Vector3(x, 0, z);
        if (v.maneuver === 'turn_left_at_junction') {
          // A signalled left turn happens at the next junction (its centre is
          // 226 m past the seam) and the signal goes off once the turn is done.
          const c = boundary + 226;
          const points = [p, V(-1.8, c - 30), V(-1.8, c - 6), V(-1.8, c - 1.5), V(1.5, c + 1.8), V(22, c + 1.8), V(90, c + 1.8)];
          const actor = addRoadActor(group, cfg, p, 0, points, v.speed);
          const turnEnd = actor.path.getLength() - 68;
          actor.signalPlan = [{ from: 0, to: turnEnd - 14, side: 'left' }];
          actor.holdSpeedUntil = turnEnd + 8;
          ev.actors.push(actor);
        } else if (v.maneuver === 'overtake') {
          // Pulls out into the oncoming lane, passes the vehicle ahead and
          // returns: left signal out, right signal back, then nothing.
          const points = [p, V(-1.8, p.z + 8), V(1.8, p.z + 22), V(1.8, p.z + 62), V(-1.8, p.z + 78), V(-1.8, p.z + 120), V(-1.8, p.z + 320)];
          const actor = addRoadActor(group, cfg, p, 0, points, v.speed);
          actor.signalPlan = [{ from: 0, to: 20, side: 'left' }, { from: 56, to: 80, side: 'right' }];
          ev.actors.push(actor);
        } else {
          ev.actors.push(addRoadActor(group, cfg, p, 0,
            [p, p.clone().add(new THREE.Vector3(0, 0, 60)), p.clone().add(new THREE.Vector3(0, 0, 320))], v.speed));
        }
      }
    });
    return ev;
  }

  // A bus bay on the right with a shelter and sign 5.16: a bus pulls in,
  // waits a few seconds and merges back. No question, no gameplay rule.
  function buildBusStopEvent(group, bayZ) {
    const ev = { group, kind: 'busstop', phase: 'approach', actors: [], bayZ };
    const asphalt = new THREE.MeshLambertMaterial({ color: BRAND.asphalt });
    // Tapered pocket over the pavement edge; drivable (registered as road) so
    // the player can pull in too. Separated from the lane by a broken line.
    const shape = new THREE.Shape();
    shape.moveTo(-4.1, -16); shape.lineTo(-4.1, 16); shape.lineTo(-7.0, 11); shape.lineTo(-7.0, -11); shape.closePath();
    const bay = new THREE.Mesh(new THREE.ShapeGeometry(shape), asphalt);
    bay.rotation.x = -Math.PI / 2; bay.position.set(0, 0.19, bayZ); bay.userData.surface = 'road'; group.add(bay);
    const paint = roadMarkingMat(), dashes = [];
    for (let z = bayZ - 15; z < bayZ + 15; z += 3) dashes.push(addFlatPlane(new THREE.Group(), 0.12, 1.5, -4.15, z + 0.75, 0.196, paint));
    group.add(mergeStatic(dashes, paint));
    // Pedestrians walk round the pocket on a paved path behind it.
    // A proper pavement behind the pocket (2.4 m wide, with ramps at both
    // ends) — walkers move onto it early and leave it late.
    const pave = new THREE.MeshLambertMaterial({ color: season().sidewalk });
    const path = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.18, 44), pave);
    path.position.set(-8.5, 0.09, bayZ); group.add(path);
    [-1, 1].forEach(end => {
      const ramp = new THREE.Mesh(new THREE.BoxGeometry(2.4, 0.18, 6), pave);
      ramp.position.set(-7.6, 0.09, bayZ + end * 24.5); ramp.rotation.y = end * 0.45; group.add(ramp);
    });
    clearRoadside(bayZ);
    // Shelter behind the path, bench, and the stop sign at the head of the bay.
    const dark = sceneryMat(0x3B4450), glassMat = new THREE.MeshLambertMaterial({ color: 0x9DB8C6, transparent: true, opacity: 0.55 });
    const roof = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.1, 4.2), dark); roof.position.set(-10.4, 2.5, bayZ); group.add(roof);
    [-1.9, 1.9].forEach(dz => { const post = new THREE.Mesh(new THREE.BoxGeometry(0.08, 2.5, 0.08), dark); post.position.set(-11.0, 1.25, bayZ + dz); group.add(post); });
    const back = new THREE.Mesh(new THREE.BoxGeometry(0.05, 2.1, 4.0), glassMat); back.position.set(-11.15, 1.3, bayZ); group.add(back);
    const bench = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.1, 3), sceneryMat(0x987856)); bench.position.set(-10.6, 0.55, bayZ); group.add(bench);
    // 5.16 stands at the entry to the pocket, on the road side of the path.
    addRoadSign(group, '5.16', bayZ - 17, 'right', null, -1.9);
    refreshRoadBounds();
    // The bus: ahead in the player's lane, pulls in, waits, pulls out.
    const V = (x, z) => new THREE.Vector3(x, 0, z);
    const p = V(-1.8, bayZ - 46);
    const cfg = { id: 'road_bus', type: 'bus', name: 'Автобус', color: '#FFA53C' };
    const bus = addRoadActor(group, cfg, p, 0, [p, V(-1.8, bayZ - 26), V(-5.5, bayZ - 8), V(-5.5, bayZ + 4), V(-2.6, bayZ + 20), V(-1.8, bayZ + 40), V(-1.8, bayZ + 300)], 9);
    // Stop roughly at the middle of the bay: find the path distance there.
    let best = 0, bestD = 1e9;
    for (let d = 0; d < 120; d += 0.5) { const q = bus.path.getPointAt(Math.min(1, d / bus.length)); const dd = Math.abs(q.z - bayZ) + Math.abs(q.x + 5.5); if (dd < bestD) { bestD = dd; best = d; } }
    bus.stopAtDistance = best; bus.stopFor = 3.5;
    ev.actors.push(bus);
    state.busBays.push({ mesh: bay, center: new THREE.Vector3(-5.5, 0, bayZ) });
    return ev;
  }
  // Remove houses, fences, trees and parked cars from the exit road's right
  // side around a bus bay, so the shelter and the path get a clear lot.
  function clearRoadside(bayZ) {
    const seg = state.exitRoad;
    if (!seg) return;
    seg.updateMatrixWorld(true);
    const doomed = [];
    seg.children.forEach(o => {
      if (o.userData.surface || o.userData.baked || o.isLine || o.userData.puddle) return;
      if (state.ambient.some(a => a.mesh === o)) return;
      const box = new THREE.Box3().setFromObject(o);
      if (box.isEmpty()) return;
      const c = box.getCenter(new THREE.Vector3());
      if (c.x < -7 && Math.abs(c.z - bayZ) < 26 && box.max.y > 0.3) doomed.push(o);
    });
    doomed.forEach(o => { seg.remove(o); state.occluders = state.occluders.filter(b => b !== o); });
  }
  // Vehicles coming the other way on a straight: they pass and vanish behind.
  function addOncomingTraffic(group, boundary, scene) {
    // Overtaking questions author their own traffic; never add random cars there.
    if (scene && scene.kind !== 'speed') return;
    const V = (x, z) => new THREE.Vector3(x, 0, z);
    const kinds = [['car', 'Встречный', '#2BC280'], ['car', 'Встречный', '#6E86A6'], ['truck', 'Грузовик', '#9AA0A6'],
      ['tractor', 'Трактор', '#F2B233'], ['motorcycle', 'Мотоцикл', '#8B5CF6'], ['bus', 'Автобус', '#FFA53C']];
    const n = 1 + (Math.random() < 0.4 ? 1 : 0);
    for (let i = 0; i < n; i++) {
      const [type, name, color] = kinds[Math.floor(Math.random() * kinds.length)];
      const z = boundary + 140 + i * 45 + Math.random() * 30;
      const p = V(1.8, z);
      const actor = addRoadActor(group, { id: `road_oncoming_${i}`, type, name, color, badge: type === 'tractor' ? 'Трактор' : undefined },
        p, Math.PI, [p, V(1.8, z - 60), V(1.8, boundary + 2)], type === 'tractor' ? 5 : type === 'truck' || type === 'bus' ? 10 : 12);
      actor.waitsForPlayer = false; // already on the move
    }
  }

  // Unregulated zebra without a question: a pedestrian steps out when the
  // player approaches; passing the crossing while they are on the carriageway
  // is a 'pedestrian' violation (14.1), a hit is an ordinary collision.
  function buildCrosswalkEvent(group, crosswalkZ) {
    const ev = { group, kind: 'crosswalk', crosswalkZ, phase: 'approach', actors: [], passedZ: null };
    addZebra(group, crosswalkZ);
    addRoadSign(group, '5.19.1', crosswalkZ - 2.6, 'right');
    addRoadSign(group, '5.19.2', crosswalkZ + 2.6, 'left');
    const start = new THREE.Vector3(-6.2, 0.18, crosswalkZ);
    const cfg = { id: 'road_pedestrian', type: 'pedestrian', name: 'Пешеход', color: '#0574F8' };
    ev.pedestrian = addRoadActor(group, cfg, start, Math.PI / 2, [start,
      new THREE.Vector3(-4.4, 0.03, crosswalkZ), new THREE.Vector3(4.4, 0.03, crosswalkZ),
      new THREE.Vector3(6.2, 0.18, crosswalkZ), new THREE.Vector3(6.2, 0.18, crosswalkZ + 3),
      new THREE.Vector3(6.2, 0.18, crosswalkZ + 60)], 1.9);
    ev.actors.push(ev.pedestrian);
    return ev;
  }

  function roadEventLimit(z, limit) {
    const ev = state.roadEvent;
    if (!ev || ev.phase !== 'approach' || ev.stopZ === undefined) return limit;
    const distance = ev.stopZ - z;
    if (distance + 3 <= 0) return limit;
    return Math.min(limit, Math.sqrt(Math.max(0, 2 * 8 * distance)));
  }

  function startRoadQuestion() {
    const ev = state.roadEvent;
    ev.phase = 'question';
    state.speed = 0; state.isAccelerating = false; state.steering = 0;
    state.isAtSituation = true;
    sendToFlutter({ event: 'approach_situation', situation: ev.situation });
  }

  function releaseRoadActors(ev) { ev.actors.forEach(a => { a.waitsForPlayer = false; }); }

  function startRoadManual() {
    const ev = state.roadEvent;
    ev.phase = 'manual';
    releaseRoadActors(ev);
    state.isAtSituation = false;
    state.isResolvingSituation = false;
    state.speed = 0;
  }

  function finishRoadEvent(cleared = true) {
    const ev = state.roadEvent;
    if (!ev) return;
    const id = ev.situation?.id;
    releaseRoadActors(ev);
    ev.phase = 'done';
    state.roadEvent = null;
    state.isAtSituation = false;
    if (cleared && id) sendToFlutter({ event: 'situation_cleared', situationId: id });
  }

  // Called when the world is about to be rebuilt behind the player (U-turn).
  function cancelRoadEvent() {
    const ev = state.roadEvent;
    if (!ev) return;
    finishRoadEvent(ev.phase === 'manual' || ev.phase === 'question');
  }

  function roadOvertakeAllowedAt(z) {
    const ev = state.roadEvent;
    if (!ev || ev.phase !== 'manual' || ev.kind !== 'overtake') return false;
    const o = ev.scene.overtake;
    if (o === true) return z >= ev.startZ - 12 && z <= ev.endZ;
    if (o === 'before_intersection') return z >= ev.startZ - 12 && z < ev.laneDeadlineZ;
    if (o === 'after_crosswalk') return z >= ev.startZ - 12 && z <= ev.endZ && Math.abs(z - ev.crosswalkZ) > 6;
    return false;
  }

  // The limit in force: a sign from a speed question, else the built-up 60.
  function effectiveLimitKmH() { return state.speedLimitKmH || state.baseLimitKmH; }
  function roadViolation(type) {
    sendToFlutter({ event: 'violation', type, episode: ++state.violationEpisode });
  }

  function updateRoadEvent(dt) {
    const ev = state.roadEvent;
    // Simulated time, so signals freeze on pause and stay deterministic in tests.
    state.signalClock = (state.signalClock || 0) + dt;
    const now = state.signalClock * 1000;
    // Parked junction traffic (not yet released) signals too: use the
    // situation's motions when they exist, else the static config side.
    const parked = state.intersections.flatMap(it => it.motions ? [] : it.actors.map(a => ({ mesh: a.mesh, distance: 0,
      signalPlan: a.config.targetAction === 'turn_right' ? [{ from: 0, to: 1, side: 'right' }] :
        (a.config.targetAction === 'turn_left' || a.config.targetAction === 'uturn') ? [{ from: 0, to: 1, side: 'left' }] : null })));
    [...state.actors, ...parked].forEach(a => {
      const lamps = a.mesh.userData.blinkerLamps;
      if (!lamps) return;
      const planned = a.signalPlan ? a.signalPlan.find(p => a.distance >= p.from && a.distance < p.to)?.side || null
        : a.mesh.userData.blinkerSide;
      const on = Math.floor(now / 380) % 2 === 0;
      lamps.left.forEach(l => { l.visible = on && planned === 'left'; });
      lamps.right.forEach(l => { l.visible = on && planned === 'right'; });
    });
    // The car can always exceed the limit (that is what a violation is); its
    // top speed only rises where a higher limit allows it: 65 km/h in town,
    // up to 120 past a motorway sign. Over the limit by 5+ km/h for 0.8 s is
    // a violation.
    const limit = effectiveLimitKmH();
    state.maxSpeed = Math.min(33, limit / 3.6);
    {
      const over = state.speed * 3.6 > limit + 5;
      state.speedingTime = over ? (state.speedingTime || 0) + dt : 0;
      if (!over) state.speedingPenalized = false;
      if (over && state.speedingTime > 0.8 && !state.speedingPenalized) {
        state.speedingPenalized = true;
        roadViolation('speeding');
      }
    }
    if (!ev) return;
    const z = playerCarGroup.position.z, x = playerCarGroup.position.x;
    if (ev.kind === 'busstop') {
      const bus = ev.actors[0];
      if (ev.phase === 'approach' && z > ev.bayZ - 120) { ev.phase = 'manual'; releaseRoadActors(ev); }
      if (bus && !bus.done && bus.stopAtDistance !== undefined) {
        if (bus.distance >= bus.stopAtDistance && bus.stopFor > 0) {
          // Dwell with the doors open, then merge back at full speed.
          bus.stopFor -= dt; bus.maxSpeed = 0; bus.speed = 0;
        } else if (bus.stopFor <= 0) bus.maxSpeed = 11;
      }
      if (z > ev.bayZ + 60 || z < ev.bayZ - 200) finishRoadEvent(false);
      return;
    }
    if (ev.kind === 'crosswalk') {
      const ped = ev.pedestrian;
      if (ev.phase === 'approach' && z > ev.crosswalkZ - 58 && z < ev.crosswalkZ - 6) { ev.phase = 'manual'; releaseRoadActors(ev); }
      const front = z + playerCarGroup.userData.halfLength;
      if (ev.phase === 'manual' && ev.passedZ === null && front >= ev.crosswalkZ - 2.4) {
        ev.passedZ = z;
        if (!ped.fall && !ped.done && Math.abs(ped.mesh.position.x) < 4.6 && Math.cos(playerCarGroup.rotation.y) > 0.5) roadViolation('pedestrian');
      }
      if (z > ev.crosswalkZ + 8 || z < ev.crosswalkZ - 120) finishRoadEvent(false);
      return;
    }
    if (ev.phase === 'approach' && z > ev.stopZ + 6) {
      // The stop was skipped (e.g. after a collision push); ask no question here.
      finishRoadEvent(false);
      return;
    }
    if (ev.phase !== 'manual') return;
    if (ev.kind === 'speed' && z > ev.signZ) state.speedLimitKmH = ev.scene.limitKmH;
    if (ev.kind === 'speed' && ev.endSignZ !== undefined && z > ev.endSignZ) state.speedLimitKmH = null;
    // Vehicles ahead leave the scene once the stretch is over so that they
    // never block the next junction or its question.
    ev.actors.forEach(a => {
      if (a.holdSpeedUntil !== undefined ? a.distance > a.holdSpeedUntil :
          (a.config.name !== 'Встречный' && a.mesh.position.z > ev.endZ - 15)) a.maxSpeed = state.maxSpeed;
    });
    if (ev.kind === 'overtake') {
      const oncomingLane = Math.cos(playerCarGroup.rotation.y) * x > 0.85;
      const o = ev.scene.overtake;
      const forbiddenHere = oncomingLane && (
        (o === false && z >= ev.startZ - 12 && z <= ev.endZ) ||
        (o === 'before_intersection' && z >= ev.laneDeadlineZ) ||
        (o === 'after_crosswalk' && Math.abs(z - ev.crosswalkZ) <= 6));
      if (forbiddenHere && !ev.overtakePenalized) { ev.overtakePenalized = true; roadViolation('overtaking'); }
      if (!oncomingLane) ev.overtakePenalized = false;
    }
    if (z > ev.endZ || z < ev.startZ - 45) finishRoadEvent(true);
  }

  // --- Weather: clear / overcast / rain, changing every minute or two ---
  // state.rain (0..1) and state.overcast (0..1) blend sky, fog, light, the
  // wet look of the asphalt and the rain particles. No gameplay effect.
  let weatherFx = null;
  function pickWeather(previous) {
    const options = previous === 'rain' ? ['clear', 'overcast'] :
      previous === 'overcast' ? ['rain', 'rain', 'clear'] : ['overcast', 'overcast', 'rain', 'clear'];
    return options[Math.floor(Math.random() * options.length)];
  }
  function weatherDuration(kind) {
    return kind === 'rain' ? 45 + Math.random() * 50 : kind === 'overcast' ? 35 + Math.random() * 45 : 60 + Math.random() * 90;
  }
  function ensureWeatherFx() {
    if (weatherFx) return weatherFx;
    // Rain: short vertical streaks in a box that travels with the player.
    const count = state.lowEnd ? 350 : 900;
    const positions = new Float32Array(count * 2 * 3);
    const drops = [];
    for (let i = 0; i < count; i++) {
      drops.push({ x: (Math.random() - 0.5) * 60, y: Math.random() * 30, z: (Math.random() - 0.5) * 70, speed: 20 + Math.random() * 8, len: 0.5 + Math.random() * 0.5 });
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    const lines = new THREE.LineSegments(geometry, new THREE.LineBasicMaterial({ color: 0xDCE6F0, transparent: true, opacity: 0 }));
    lines.frustumCulled = false;
    scene.add(lines);
    // Puddles: soft dark ellipses on the road that appear with the rain.
    const puddleTexture = (() => {
      const canvas = document.createElement('canvas'); canvas.width = canvas.height = 64;
      const ctx = canvas.getContext('2d');
      const g = ctx.createRadialGradient(32, 32, 2, 32, 32, 32);
      g.addColorStop(0, 'rgba(120,140,165,0.55)'); g.addColorStop(0.7, 'rgba(120,140,165,0.3)'); g.addColorStop(1, 'rgba(120,140,165,0)');
      ctx.fillStyle = g; ctx.fillRect(0, 0, 64, 64);
      return new THREE.CanvasTexture(canvas);
    })();
    weatherFx = { lines, drops, count, puddleTexture, puddles: [] };
    return weatherFx;
  }
  function addPuddles(seg, startZ, length) {
    const fx = ensureWeatherFx();
    for (let z = startZ + 6 + Math.random() * 10; z < startZ + length - 6; z += 14 + Math.random() * 16) {
      const puddle = new THREE.Mesh(new THREE.PlaneGeometry(2.2 + Math.random() * 2, 1.2 + Math.random() * 1.2),
        new THREE.MeshBasicMaterial({ map: fx.puddleTexture, transparent: true, opacity: 0, depthWrite: false }));
      puddle.rotation.x = -Math.PI / 2; puddle.rotation.z = Math.random() * Math.PI;
      puddle.position.set((Math.random() - 0.5) * 6.4, 0.031, z);
      puddle.userData.puddle = true;
      seg.add(puddle);
    }
  }
  function applyWeather() {
    const rain = state.rain || 0, overcast = Math.max(state.overcast || 0, rain);
    const dark = state.isDarkTheme;
    const sn = season();
    const clearSky = new THREE.Color(dark ? sn.skyDark : sn.sky), greySky = new THREE.Color(dark ? 0x1F2427 : 0xC3CACF), rainSky = new THREE.Color(dark ? 0x1B1F23 : 0xAEB6BD);
    scene.background.copy(clearSky).lerp(greySky, overcast).lerp(rainSky, rain);
    scene.fog.color.copy(scene.background);
    scene.fog.density = 0.007 + overcast * 0.002 + rain * 0.004;
    ambientLight.intensity = THREE.MathUtils.lerp(dark ? 0.52 : sn.ambient, dark ? 0.5 : sn.ambient - 0.06, overcast);
    dirLight.intensity = THREE.MathUtils.lerp(dark ? 0.45 : sn.sunIntensity, 0.18, overcast);
    dirLight.color.setHex(sn.sun).lerp(new THREE.Color(0xDDE4EC), overcast);
    if (!weatherFx) return;
    const snow = sn.precipitation === 'snow';
    weatherFx.lines.material.color.setHex(snow ? 0xFFFFFF : 0xDCE6F0);
    weatherFx.lines.material.opacity = rain * (snow ? 0.85 : 0.55);
    scene.traverse(o => {
      if (o.userData.puddle) o.material.opacity = rain * (snow ? 0.35 : 0.9);
      else if (o.userData.surface === 'road' && o.material?.color) o.material.color.setHex(BRAND.asphalt).lerp(new THREE.Color(0x1F2228), rain * 0.8);
    });
  }
  function updateWeather(dt) {
    if (!state.sky) state.sky = { kind: 'clear', left: 70 + Math.random() * 80 };
    const w = state.sky;
    if (!state.weatherOverride && !state.firstRun) {
      w.left -= dt;
      if (w.left <= 0) { w.kind = pickWeather(w.kind); w.left = weatherDuration(w.kind); }
    }
    const targetRain = w.kind === 'rain' ? 1 : 0, targetOvercast = w.kind === 'clear' ? 0 : 1;
    const k = Math.min(1, dt * 0.35);
    const before = [state.rain || 0, state.overcast || 0];
    state.rain = before[0] + (targetRain - before[0]) * k;
    state.overcast = before[1] + (targetOvercast - before[1]) * k;
    if (Math.abs(state.rain - before[0]) + Math.abs(state.overcast - before[1]) > 0.0005 || state.weatherDirty) { applyWeather(); state.weatherDirty = false; }
    if (state.rain < 0.02) { if (weatherFx) weatherFx.lines.visible = false; return; }
    const fx = ensureWeatherFx();
    fx.lines.visible = true;
    const p = fx.lines.geometry.attributes.position.array;
    const cx = playerCarGroup.position.x, cz = playerCarGroup.position.z + 12;
    const snow = season().precipitation === 'snow';
    fx.drops.forEach((d, i) => {
      // Snow drifts down slowly and sways; rain falls fast with the wind.
      d.y -= (snow ? d.speed * 0.12 : d.speed) * dt; d.z -= (snow ? 1 : 4) * dt;
      if (snow) d.x += Math.sin(d.y * 0.8 + i) * 0.6 * dt;
      if (d.y < 0) { d.y = 28 + Math.random() * 4; d.x = (Math.random() - 0.5) * 60; d.z = (Math.random() - 0.5) * 70; }
      if (d.z < -35) d.z += 70;
      const o = i * 6;
      p[o] = cx + d.x; p[o + 1] = d.y; p[o + 2] = cz + d.z;
      const len = snow ? 0.16 : d.len;
      p[o + 3] = cx + d.x + (snow ? 0.12 : 0); p[o + 4] = d.y + len; p[o + 5] = cz + d.z + (snow ? 0 : 0.12);
    });
    fx.lines.geometry.attributes.position.needsUpdate = true;
  }

  // --- Attract mode (signed-out visitors): the city lives, the player waits ---
  // The engine keeps running; the player's car stays put while traffic
  // passes: oncoming cars, and cars from behind that swing round the parked
  // player. Spawns are spaced so that the two never meet beside the player.
  function updateAttract(dt) {
    if (!state.attract) return;
    state.speed = 0; state.isAccelerating = false; state.isBraking = false;
    state.attractClock = (state.attractClock || 0) + dt;
    if (state.attractClock < (state.attractNext ?? 2)) return;
    // Laid out along the road beside the player: the world is rebased so
    // travel is +Z, the right-hand lane sits at the driver's right (-X).
    const yaw = playerCarGroup.rotation.y;
    const fwd = new THREE.Vector3(Math.sin(yaw), 0, Math.cos(yaw));
    const right = new THREE.Vector3(-Math.cos(yaw), 0, Math.sin(yaw));
    const own = playerCarGroup.position.clone().setY(0);
    const axis = new THREE.Vector3(0, 0, own.z);
    const at = (lane, d) => axis.clone().addScaledVector(fwd, d).addScaledVector(right, lane === 'own' ? 1.8 : -1.8);
    // Stalled attract cars (a stand-off nobody resolves) quietly leave.
    state.actors.forEach(a => {
      if (!a.config?.id?.startsWith('attract_') || a.done) return;
      a.attractStill = a.speed < 0.1 && a.distance > 5 ? (a.attractStill || 0) + dt : 0;
      if (a.attractStill > 6) { a.done = true; a.mesh.visible = false; }
    });
    // Finished cars are disposed with their own group; the road segments are
    // never touched (they are trimmed by count, so extra entries would evict
    // the actual road).
    state.attractGroups = (state.attractGroups || []).filter(g => {
      const alive = state.actors.some(a => a.segment === g && !a.done);
      if (!alive) disposeSegment(g);
      return alive;
    });
    // One car at a time in the oncoming lane: the overtaking car uses it
    // too, so the two kinds never meet beside the player.
    const live = state.actors.filter(a => a.config?.id?.startsWith('attract_') && !a.done);
    const busy = live.some(a => {
      const d = a.mesh.position.clone().sub(own).dot(fwd);
      return a.attractBehind ? d < 32 : d > -8;
    });
    if (busy) return;
    const junction = state.intersections
      .map(i => (i.centerZ - own.z) * Math.sign(fwd.z || 1))
      .filter(d => d > 0).sort((a, b) => a - b)[0];
    const oncomingStart = Math.min(130, junction === undefined ? 130 : junction - 24);
    // Oncoming cars need room this side of the next junction (its actors wait
    // for the player there); otherwise every car comes from behind.
    const fromBehind = oncomingStart < 80 ? true : (state.attractTurn = !state.attractTurn);
    state.attractClock = 0; state.attractNext = 5 + Math.random() * 4;
    const group = new THREE.Group(); scene.add(group); state.attractGroups.push(group);
    const kinds = [['car', 'Авто', '#2BC280'], ['car', 'Авто', '#6E86A6'], ['truck', 'Грузовик', '#9AA0A6'], ['motorcycle', 'Мото', '#8B5CF6'], ['bus', 'Автобус', '#FFA53C']];
    const [type, name, color] = kinds[Math.floor(Math.random() * kinds.length)];
    const cfg = { id: 'attract_' + Date.now(), type, name, color };
    let actor;
    if (fromBehind) {
      // Swings into the oncoming lane well before the parked player and back after it.
      // Ends short of the next junction, where the scenario's actors wait.
      const end = Math.min(160, junction === undefined ? 160 : junction - 26);
      const pts = [at('own', -80), at('own', -30), at('opp', -14), at('opp', 10), at('own', 26), at('own', Math.max(40, end))];
      actor = addRoadActor(group, cfg, pts[0], yaw, pts, 9);
      actor.signalPlan = [{ from: 36, to: 62, side: 'left' }, { from: 84, to: 104, side: 'right' }];
    } else {
      const pts = [at('opp', oncomingStart), at('opp', 20), at('opp', -90)];
      actor = addRoadActor(group, cfg, pts[0], yaw + Math.PI, pts, 10);
    }
    actor.waitsForPlayer = false; actor.attractBehind = fromBehind;
  }

  // --- Garage reveal: a new car rolls out of a closed garage ---
  // Rendered in its own scene while active; the main scene is paused.
  let reveal = null;
  function buildRevealScene(id, paint) {
    const sn = season(), dark = state.isDarkTheme;
    const rs = new THREE.Scene();
    rs.background = new THREE.Color(dark ? sn.skyDark : sn.sky);
    rs.fog = new THREE.FogExp2(dark ? sn.skyDark : sn.sky, 0.012);
    rs.add(new THREE.AmbientLight(0xFFFFFF, sn.ambient));
    const sun = new THREE.DirectionalLight(sn.sun, sn.sunIntensity + 0.2); sun.position.set(-8, 14, -10); rs.add(sun);
    const mat = c => new THREE.MeshLambertMaterial({ color: c });
    // The player's neighbourhood in the current season: lawn, a driveway,
    // a pavement strip with the road, trees, bushes, houses and a fence.
    const lawn = new THREE.Mesh(new THREE.PlaneGeometry(140, 140), mat(sn.ground)); lawn.rotation.x = -Math.PI / 2; rs.add(lawn);
    const drive = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 26), mat(sn.sidewalk)); drive.rotation.x = -Math.PI / 2; drive.position.set(0, 0.01, -13.6); rs.add(drive);
    const road = new THREE.Mesh(new THREE.PlaneGeometry(90, 8), mat(BRAND.asphalt)); road.rotation.x = -Math.PI / 2; road.position.set(0, 0.012, -30); rs.add(road);
    const kerb = new THREE.Mesh(new THREE.PlaneGeometry(90, 2.4), mat(sn.sidewalk)); kerb.rotation.x = -Math.PI / 2; kerb.position.set(0, 0.011, -24.8); rs.add(kerb);
    for (let x = -42; x <= 42; x += 6) { const dash = new THREE.Mesh(new THREE.PlaneGeometry(3, 0.16), mat(BRAND.asphaltMarking)); dash.rotation.x = -Math.PI / 2; dash.position.set(x, 0.013, -30); rs.add(dash); }
    [[-12, -6], [-15, 4], [13, -5], [16, 6], [-9, 10], [11, 12], [-20, -14], [21, -14]].forEach(([x, z]) => { const t = createTree(); t.position.set(x, 0, z); rs.add(t); });
    [[6.2, -16], [-7, -4], [7, -8], [9, -14]].forEach(([x, z]) => { const b = createBush(); b.position.set(x, 0, z); rs.add(b); });
    [[-19, 10, 1], [19, 10, 1]].forEach(([x, z, style]) => { const h = createBuilding(9, 6, 8, style); h.position.set(x, 0, z); rs.add(h); });
    [[-24, 2], [24, 2]].forEach(([x, z]) => { const f = createFence(30); f.position.set(x, 0, z); f.rotation.y = Math.PI / 2; rs.add(f); });
    const lamp = createLampPost(); lamp.position.set(-6.5, 0, -22.5); rs.add(lamp);
    // The garage: an open-fronted box the camera looks into from the side,
    // with a tool wall, shelves, a tyre stack and a strip light.
    const wall = mat(0x8F969E), inside = mat(0x6E757D), trim = mat(0x5A626A);
    const back = new THREE.Mesh(new THREE.BoxGeometry(9, 4.2, 0.3), inside); back.position.set(0, 2.1, 6.2); rs.add(back);
    [-1, 1].forEach(sx => {
      const side = new THREE.Mesh(new THREE.BoxGeometry(0.3, 4.2, 7), sx < 0 ? inside : wall); side.position.set(sx * 4.5, 2.1, 2.7); rs.add(side);
      const pier = new THREE.Mesh(new THREE.BoxGeometry(1.4, 4.6, 0.5), wall); pier.position.set(sx * 5.0, 2.3, -0.6); rs.add(pier);
    });
    const roofGeo = new THREE.ConeGeometry(Math.SQRT2 / 2, 1, 4); roofGeo.rotateY(Math.PI / 4);
    const roof = new THREE.Mesh(roofGeo, mat(sn.roof || 0x8C4A3C)); roof.scale.set(11.4, 2.2, 8.6); roof.position.set(0, 5.5, 2.7); rs.add(roof);
    const eave = new THREE.Mesh(new THREE.BoxGeometry(11.2, 0.35, 8.4), trim); eave.position.set(0, 4.55, 2.7); rs.add(eave);
    const lintel = new THREE.Mesh(new THREE.BoxGeometry(9, 0.7, 0.5), wall); lintel.position.set(0, 4.05, -0.6); rs.add(lintel);
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(8.4, 6.6), mat(0x4B525A)); floor.rotation.x = -Math.PI / 2; floor.position.set(0, 0.014, 2.7); rs.add(floor);
    // Furnishings along the back and the far wall.
    const shelf = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.08, 0.5), mat(0xB0895C)); [1.3, 2.2, 3.1].forEach(y => { const m = shelf.clone(); m.position.set(-2.4, y, 5.8); rs.add(m); });
    const cans = [0xF08A24, 0x317ED4, 0xE8C547, 0xF2F3F5, 0x2FA3A0];
    for (let i = 0; i < 9; i++) { const can = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.4, 0.3), mat(cans[i % cans.length])); can.position.set(-3.8 + (i % 5) * 0.7, (i < 5 ? 1.3 : 2.2) + 0.24, 5.78); rs.add(can); }
    const board = new THREE.Mesh(new THREE.BoxGeometry(2.4, 1.6, 0.06), mat(0x9E7A4E)); board.position.set(2.4, 2.4, 6.0); rs.add(board);
    [[-0.8, 0.4], [-0.3, 0.5], [0.3, 0.4], [0.8, 0.5], [0, -0.3]].forEach(([x, y]) => { const tool = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.7, 0.05), mat(0x3B4148)); tool.position.set(2.4 + x, 2.4 + y, 5.94); rs.add(tool); });
    for (let i = 0; i < 4; i++) { const tyre = new THREE.Mesh(new THREE.TorusGeometry(0.42, 0.16, 8, 14), mat(0x24282C)); tyre.rotation.x = Math.PI / 2; tyre.position.set(3.6, 0.18 + i * 0.34, 4.6); rs.add(tyre); }
    const bench = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.9, 2.2), mat(0x5B6169)); bench.position.set(-3.9, 0.45, 2.4); rs.add(bench);
    const benchTop = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.08, 2.3), mat(0xB0895C)); benchTop.position.set(-3.9, 0.94, 2.4); rs.add(benchTop);
    const strip = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.08, 0.2), mat(0xFFF4D6)); strip.position.set(0, 4.0, 2.6); rs.add(strip);
    const glow = new THREE.PointLight(0xFFE2B0, 0.7, 14); glow.position.set(0, 3.7, 2.6); rs.add(glow);
    // Door: a slatted panel that rolls up under the lintel.
    const door = new THREE.Group();
    for (let i = 0; i < 8; i++) {
      const slat = new THREE.Mesh(new THREE.BoxGeometry(8.4, 0.5, 0.12), mat(i % 2 ? 0xC9CFD4 : 0xBAC1C7));
      slat.position.y = 0.28 + i * 0.52; door.add(slat);
    }
    door.position.set(0, 0, -0.7); rs.add(door);
    const car = window.PDD_VEHICLES.create(id, paint);
    car.position.set(0, 0, 2.6); car.rotation.y = Math.PI; // nose towards the door
    rs.add(car);
    // Three-quarter view from the driveway: the whole garage front and the
    // spot where the car stops are in frame on a portrait screen.
    const cam = new THREE.PerspectiveCamera(50, 1, 0.1, 160);
    cam.position.set(-12, 5.6, -20); cam.lookAt(0.2, 1.0, -3);
    return { scene: rs, camera: cam, door, car, phase: 'closed', t: 0, yaw: 0, spin: 0 };
  }
  function updateReveal(dt) {
    const r = reveal; if (!r) return;
    const w = container.clientWidth || window.innerWidth, h = container.clientHeight || window.innerHeight;
    r.camera.aspect = w / h; r.camera.updateProjectionMatrix();
    if (r.phase === 'opening') {
      r.t += dt; const u = Math.min(1, r.t / 1.3);
      r.door.position.y = 4.3 * (1 - Math.pow(1 - u, 3));
      r.door.children.forEach(slat => { slat.visible = slat.position.y + r.door.position.y < 3.75; });
      if (u >= 1) { r.phase = 'driving'; r.t = 0; }
    } else if (r.phase === 'driving') {
      r.t += dt; const u = Math.min(1, r.t / 2.2), e = u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2;
      r.car.position.z = 2.6 - 9.2 * e;
      r.car.userData.wheels.forEach(wh => wh.rotateX(-dt * 6 * (1 - Math.abs(u - 0.5) * 2 + 0.2)));
      if (u >= 1) { r.phase = 'turning'; r.t = 0; }
    } else if (r.phase === 'turning') {
      r.t += dt; const u = Math.min(1, r.t / 1.1), e = 1 - Math.pow(1 - u, 3);
      r.car.rotation.y = Math.PI + (Math.PI / 2) * e; // nose towards the viewer
      if (u >= 1) { r.phase = 'shown'; r.yaw = r.car.rotation.y; sendToFlutter({ event: 'reveal_shown' }); }
    } else if (r.phase === 'shown') {
      // Free spin by finger; drifts slowly when idle.
      r.yaw += (r.spin + 0.15) * dt; r.spin *= Math.pow(0.05, dt);
      r.car.rotation.y = r.yaw;
    }
    renderer.render(r.scene, r.camera);
  }

  // Offscreen thumbnail of any model/paint, for the garage list.
  let thumbRenderer = null;
  function renderThumbnail(id, paint) {
    if (!thumbRenderer) { thumbRenderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true }); thumbRenderer.setSize(280, 180); thumbRenderer.setPixelRatio(1); }
    const ts = new THREE.Scene();
    ts.add(new THREE.AmbientLight(0xFFFFFF, 0.7));
    const key = new THREE.DirectionalLight(0xFFF4E0, 0.8); key.position.set(4, 8, 6); ts.add(key);
    const car = window.PDD_VEHICLES.create(id, paint); car.rotation.y = 0.5; ts.add(car);
    // Front three-quarter view, the car centred in the frame.
    const cam = new THREE.OrthographicCamera(-2.7, 2.7, 1.75, -1.75, 0.1, 50);
    cam.position.set(7, 3.4, 8); cam.lookAt(0, 0.65, 0);
    thumbRenderer.setClearColor(0x000000, 0);
    thumbRenderer.render(ts, cam);
    const url = thumbRenderer.domElement.toDataURL('image/png');
    car.traverse(o => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); });
    return url;
  }

  function clearOncoming() {
    state.oncomingSeconds = 0;
    state.oncomingPenalized = false;
    if (state.oncoming) {
      state.oncoming = false;
      sendToFlutter({ event: 'lane_changed', lane: 'right', oncoming: false });
    }
  }

  function updateLaneViolation(dt, oncoming = state.currentLaneOffset > -0.85) {
    if (oncoming !== state.oncoming) {
      state.oncoming = oncoming;
      state.oncomingSeconds = 0;
      state.oncomingPenalized = false;
      sendToFlutter({ event: 'lane_changed', lane: oncoming ? 'left' : 'right', oncoming });
      if (oncoming) state.oncomingEpisode = ++state.violationEpisode;
      return;
    }
    if (oncoming && !state.oncomingPenalized) {
      state.oncomingSeconds += dt;
      if (state.oncomingSeconds + 1e-9 < 3) return;
      state.oncomingPenalized = true;
      sendToFlutter({ event: 'violation', type: 'oncoming', episode: state.oncomingEpisode });
    }
  }

  let lastTime = null, telemetryElapsed = 0;
  function animate(time) {
    requestAnimationFrame(animate);
    const dt = lastTime === null ? 0 : Math.min((time - lastTime) / 1000, 0.05);
    lastTime = time;
    if (reveal) { updateReveal(dt); return; }
    if (state.paused) return;
    if (!state.paused) {
      updateAttract(dt);
      updateActors(dt);
      if (state.resolution) updateResolution(dt);
      else updatePlayerMovement(dt);
      updateRoadEvent(dt);
      updateWeather(dt);
      updateBlinkers(dt);
      gameAudio?.update(dt, time / 1000);
      state.roadSegments.forEach(seg => seg.traverse(obj => {
        if (obj.userData.beacons) obj.userData.beacons.forEach((lamp, i) => {
          lamp.visible = Math.floor(time / 180 + i) % 2 === 0;
        });
      }));
      terrainMesh.position.z = playerCarGroup.position.z + 500;
      updateCamera(dt);
      checkAndSpawnNext();
      telemetryElapsed += dt;
      if (telemetryElapsed >= 0.2) {
        telemetryElapsed = 0;
        sendToFlutter({ event: 'telemetry', speedKmH: Math.round(Math.abs(state.speed) * 3.6),
          distanceM: Math.round(state.distanceTraveled), limitKmH: effectiveLimitKmH() });
      }
    }
    renderer.render(scene, camera);
  }

  function updateBlinkers(dt) {
    playerCarGroup.userData.frontAxles?.forEach(axle => { axle.rotation.y = (state.steering || 0) * 0.4; });
    playerWheels.forEach(w => w.rotateX(state.speed * dt / 0.35));
    playerCarGroup.brakeLights.forEach(light => {
      light.material.color.setHex(state.isBraking || state.speed === 0 || !state.isAccelerating ? 0xF04438 : 0x7F1D1D);
    });
    const b = state.blinker;
    if (b) {
      b.remaining = state.steering ? 2.2 : b.remaining - dt;
      b.elapsed += dt;
      if (b.remaining <= 0) state.blinker = null;
    }
    playerCarGroup.blinkerL.visible = !!(state.blinker && b.side === 'left' && Math.floor(b.elapsed * 3) % 2 === 0);
    playerCarGroup.blinkerR.visible = !!(state.blinker && b.side === 'right' && Math.floor(b.elapsed * 3) % 2 === 0);
    const blinkerOn = playerCarGroup.blinkerL.visible || playerCarGroup.blinkerR.visible;
    if (blinkerOn && !gameAudio?.blinkerOn) gameAudio?.click();
    if (gameAudio) gameAudio.blinkerOn = blinkerOn;
  }

  function integrateDriving(dt, limit = state.maxSpeed) {
    // Brake: firm deceleration while moving; from a standstill it becomes
    // reverse gear (slow, negative speed). Gas is ignored while braking.
    if (state.isBraking) {
      if (state.speed > 0.05) state.speed = Math.max(0, state.speed - dt * 30);
      else state.speed = Math.max(-4, state.speed - dt * 5);
    } else if (state.speed < 0) {
      state.speed = Math.min(0, state.speed + dt * 12);
    } else if (state.speed > limit + 0.01) {
      // Above the limit in force (it just dropped): coast down, do not snap.
      state.speed = Math.max(limit, state.speed - dt * (state.isAccelerating ? 4 : 22));
    } else {
      state.speed = state.isAccelerating ? Math.min(limit, state.speed + dt * 9) : Math.max(0, state.speed - dt * 22);
    }
    const steps = Math.max(1, Math.ceil(Math.abs(state.speed) * dt / 0.15));
    let curbContact = false;
    for (let i = 0; i < steps; i++) {
      const before = playerCarGroup.position.clone(), oldYaw = playerCarGroup.rotation.y;
      const step = state.speed * dt / steps;
      // Slow steering remains available when the nose is pressed against a curb.
      // In reverse the rear swings the other way, as on a real car.
      playerCarGroup.rotation.y += (state.steering || 0) * Math.sign(state.speed || 1) *
        Math.min(1.8, Math.max(state.isAccelerating ? 1 : 0, Math.abs(state.speed)) * 0.32) * dt / steps;
      const desiredYaw = playerCarGroup.rotation.y;
      const dx = Math.sin(desiredYaw) * step, dz = Math.cos(desiredYaw) * step;
      playerCarGroup.position.x += dx; playerCarGroup.position.z += dz;
      if (!playerOnRoad()) {
        curbContact = true;
        // Resolve the blocked normal component while preserving tangential travel.
        const candidates = [[dx, 0, desiredYaw], [0, dz, desiredYaw]];
        // Small lateral separation permits steering AWAY from a curb at rest.
        const correction = Math.min(0.08, dt / steps * 1.8);
        candidates.push([correction, dz, desiredYaw], [-correction, dz, desiredYaw],
          [dx, correction, desiredYaw], [dx, -correction, desiredYaw],
          [dx, 0, oldYaw], [0, dz, oldYaw]);
        let supported = false;
        for (const [x, z, yaw] of candidates) {
          playerCarGroup.position.copy(before).add(new THREE.Vector3(x, 0, z));
          playerCarGroup.rotation.y = yaw;
          if (playerOnRoad()) { supported = true; break; }
        }
        if (!supported) { playerCarGroup.position.copy(before); playerCarGroup.rotation.y = oldYaw; }
      }
      const obstacle = Math.abs(step) > 0.0001
        ? state.actors.find(a => !a.done && !a.fall && footprintsOverlap(playerFootprint(), actorFootprint(a), 0.025))
        : null;
      if (obstacle) {
        const previousPlayer = { p: before, yaw: oldYaw,
          halfWidth: playerCarGroup.userData.halfWidth, halfLength: playerCarGroup.userData.halfLength };
        const other = actorFootprint(obstacle);
        const wasOverlapping = footprintsOverlap(previousPlayer, other, 0.025);
        const separating = playerCarGroup.position.distanceTo(other.p) > before.distanceTo(other.p) + 0.002;
        const stationary = obstacle.crashed;
        if (!wasOverlapping && !(stationary && Math.abs(state.speed) < 3)) {
          playerCarGroup.position.copy(before); playerCarGroup.rotation.y = oldYaw;
          handleCollision(obstacle, 'collision:' + obstacle.config.id);
          break;
        }
        if (!wasOverlapping || !separating) {
          // Touching a parked crash participant at walking pace, or pushing
          // deeper into an existing contact, is not a
          // new ДТП: the move is simply blocked (like a curb). Steering out of
          // it stays possible so the run never freezes.
          const blocked = [[0, 0, desiredYaw], [dx, 0, desiredYaw], [0, dz, desiredYaw]].every(([x, z, yaw]) => {
            playerCarGroup.position.copy(before).add(new THREE.Vector3(x, 0, z));
            playerCarGroup.rotation.y = yaw;
            return !playerOnRoad() || footprintsOverlap(playerFootprint(), other, 0.025) ||
              playerCarGroup.position.distanceTo(other.p) + 0.002 < before.distanceTo(other.p);
          });
          if (blocked) { playerCarGroup.position.copy(before); playerCarGroup.rotation.y = oldYaw; }
          if (wasOverlapping && obstacle.crashed && !obstacle.knock) separateCrashedActor(obstacle);
          state.speed = Math.sign(state.speed) * Math.min(Math.abs(state.speed), 1.5);
          break;
        }
      }
      if (state.speed > 0) state.distanceTraveled += playerCarGroup.position.distanceTo(before);
    }
    if (curbContact) {
      drivingFault('offroad', 'offroad');
      state.speed = Math.max(-2, Math.min(state.speed, 4));
      if (state.curbClearTime !== 0 && Math.abs(state.speed) > 1.5) gameAudio?.scrapeHit();
      state.curbClearTime = 0;
    } else {
      state.curbClearTime = (state.curbClearTime || 0) + dt;
      if (state.curbClearTime > 0.6) (state.resolution ? state.resolution.faults : state.driveFaults).delete('offroad');
    }
  }

  function refreshRoadBounds() {
    scene.updateMatrixWorld(true);
    state.roadBounds = [];
    state.roadSegments.forEach(seg => seg.traverse(obj => {
      if (obj.userData.surface === 'road') state.roadBounds.push({
        box: new THREE.Box3().setFromObject(obj), material: obj.material,
      });
    }));
  }

  function roadSupports(point) {
    return (state.roadBounds || []).some(({box, material}) =>
      point.x >= box.min.x - 0.1 && point.x <= box.max.x + 0.1 &&
      point.z >= box.min.z - 0.1 && point.z <= box.max.z + 0.1 &&
      (material.clippingPlanes || []).every(plane => plane.distanceToPoint(point) >= -0.01));
  }

  function playerOnRoad() {
    for (const x of [-playerCarGroup.userData.halfWidth, playerCarGroup.userData.halfWidth])
      for (const z of [-playerCarGroup.userData.halfLength, playerCarGroup.userData.halfLength]) {
        const corner = new THREE.Vector3(x, 0, z).applyAxisAngle(new THREE.Vector3(0, 1, 0), playerCarGroup.rotation.y).add(playerCarGroup.position);
        if (!roadSupports(corner)) return false;
      }
    return true;
  }

  function updatePlayerMovement(dt) {
    if (state.isAtSituation) { state.speed = 0; return; }
    if (state.driveRecovery > 0) {
      state.driveRecovery = Math.max(0, state.driveRecovery - dt);
      if (!state.driveRecovery) {
        state.driveFaults.clear();
        sendToFlutter({ event: 'maneuver_ready' });
      }
      return;
    }
    const active = state.intersections.find(it => it.stopZ + 3 > playerCarGroup.position.z);
    state.activeIntersection = active || null;
    let limit = state.maxSpeed;
    if (active && Math.cos(playerCarGroup.rotation.y) > 0.2) {
      const distance = active.stopZ - playerCarGroup.position.z;
      limit = Math.min(limit, Math.sqrt(Math.max(0, 2 * 8 * distance)));
    }
    if (Math.cos(playerCarGroup.rotation.y) > 0.2) limit = roadEventLimit(playerCarGroup.position.z, limit);
    const contactsBefore = playerContacts();
    integrateDriving(dt, limit);
    if (state.driveRecovery > 0) return;
    state.currentLaneOffset = playerCarGroup.position.x;
    const inOncomingLane = Math.cos(playerCarGroup.rotation.y) * playerCarGroup.position.x > 0.85;
    updateLaneViolation(dt, inOncomingLane && !roadOvertakeAllowedAt(playerCarGroup.position.z));
    for (const actor of state.actors) {
      if (actor.done || actor.fall) continue;
      if (footprintsOverlap(playerFootprint(), actorFootprint(actor))) {
        if (contactsBefore.has(actor)) { if (actor.crashed && !actor.knock) separateCrashedActor(actor); continue; }
        handleCollision(actor, 'collision:' + actor.config.id); return;
      }
    }
    if (Math.abs(Math.sin(playerCarGroup.rotation.y)) < 0.2 && Math.abs(playerCarGroup.position.x) < 2.5) {
      state.lastSafePosition.copy(playerCarGroup.position);
      state.lastSafeYaw = playerCarGroup.rotation.y;
    }
    const road = state.roadEvent;
    if (road && road.phase === 'approach' && road.stopZ !== undefined &&
        road.stopZ - playerCarGroup.position.z <= 0.18 && road.stopZ + 3 > playerCarGroup.position.z &&
        Math.cos(playerCarGroup.rotation.y) > 0.2) {
      startRoadQuestion();
      return;
    }
    if (active && active.stopZ - playerCarGroup.position.z <= 0.18) {
      state.speed = 0;
      state.isAccelerating = false;
      state.steering = 0;
      state.isAtSituation = true;
      sendToFlutter({ event: 'approach_situation', situation: active.situation });
    }
  }

  let cameraLook = new THREE.Vector3(0, 0, 14), cameraHeading = 0, cameraViewSize = 42;
  function updateCamera(dt) {
    const height = container.clientHeight || window.innerHeight;
    const width = container.clientWidth || window.innerWidth;
    if (width <= 0 || height <= 0) return;
    state.intersections.forEach(it => {
      it.guide.visible = it === state.activeIntersection && Math.abs(playerCarGroup.position.z - it.centerZ) < 55;
    });
    state.orbitYaw = state.attract ? (state.orbitYaw || 0) : (state.orbitYaw || 0) * Math.exp(-4 * dt);
    let desiredYaw = playerCarGroup.rotation.y + (state.orbitYaw || 0);
    let delta = Math.atan2(Math.sin(desiredYaw - cameraHeading), Math.cos(desiredYaw - cameraHeading));
    cameraHeading += delta * (1 - Math.exp(-3 * dt));
    const forward = new THREE.Vector3(Math.sin(cameraHeading), 0, Math.cos(cameraHeading));
    const focus = playerCarGroup.position.clone();
    let lookAhead = 10;
    let desiredViewSize = 42;
    const roadQuestion = state.roadEvent?.phase === 'question' ? state.roadEvent : null;
    if (roadQuestion) {
      // Frame the player, the signs and the traffic of this stretch, not the
      // junction 200 m ahead that state.activeIntersection already points at.
      const ev = roadQuestion;
      const boxes = ev.actors.map(a => new THREE.Box3().setFromObject(a.mesh));
      ev.group.children.filter(o => !o.userData.actor && o.position.y === 0).forEach(o => boxes.push(new THREE.Box3().setFromObject(o)));
      const minX = Math.min(-7, ...boxes.map(b => b.min.x)) - 1.5;
      const maxX = Math.max(7, ...boxes.map(b => b.max.x)) + 1.5;
      const minZ = playerCarGroup.position.z - 4;
      const maxZ = Math.min(ev.stopZ + 60, Math.max(ev.stopZ + 24, ...boxes.map(b => b.max.z + b.max.y * 1.05))) + 2;
      const visibleFraction = Math.max(0.25, (height - state.viewportInsets.top - state.viewportInsets.bottom) / height);
      desiredViewSize = Math.max(42, (maxX - minX) / (width / height), (maxZ - minZ) * 0.69 / visibleFraction);
      focus.set(0, 0, (minZ + maxZ) / 2);
      lookAhead = 0;
    } else if (state.isAtSituation && state.activeIntersection && state.resolution?.phase !== 'manual') {
      const intersection = state.activeIntersection;
      const bounds = intersection.actors.map(a => a.viewBounds);
      const minX = Math.min(-7, ...bounds.map(b => b.min.x)) - 1.5;
      const maxX = Math.max(7, ...bounds.map(b => b.max.x)) + 1.5;
      const minZ = Math.min(playerCarGroup.position.z - 2.5, intersection.centerZ - 8, ...bounds.map(b => b.min.z)) - 1.5;
      // At this camera elevation model/badge height contributes ~1m of forward
      // projection per metre of height. Reserve it above the roof, under the HUD.
      const maxZ = Math.max(intersection.centerZ + 8, ...bounds.map(b => b.max.z + b.max.y * 1.05)) + 2;
      const visibleFraction = Math.max(0.25, (height - state.viewportInsets.top - state.viewportInsets.bottom) / height);
      desiredViewSize = Math.max(42, (maxX - minX) / (width / height), (maxZ - minZ) * 0.69 / visibleFraction);
      focus.set((minX + maxX) / 2, 0, (minZ + maxZ) / 2);
      lookAhead = 0;
    }
    const alpha = 1 - Math.exp(-5 * dt);
    cameraViewSize += (desiredViewSize - cameraViewSize) * alpha;
    camera.left = -cameraViewSize * width / height / 2;
    camera.right = -camera.left;
    camera.top = cameraViewSize / 2; camera.bottom = -camera.top;
    camera.updateProjectionMatrix();
    // Place the scene at the centre of the ACTUAL uncovered viewport, including
    // large text / tall answer sheets, rather than the centre behind the sheet.
    const offset = (state.viewportInsets.bottom - state.viewportInsets.top) / height * cameraViewSize / (2 * 0.69);
    const desiredLook = focus.clone().addScaledVector(forward, lookAhead - offset);
    const desiredPos = desiredLook.clone().addScaledVector(forward, -44);
    desiredPos.y = 42;
    cameraLook.lerp(desiredLook, alpha);
    camera.position.lerp(desiredPos, alpha);
    camera.lookAt(cameraLook);
    // Free steering can put scenery between the camera and the car. Fade only
    // those buildings intersecting that sight line; never hide the road itself.
    const sight = playerCarGroup.position.clone().sub(camera.position);
    const sightLengthSq = sight.lengthSq();
    state.occluders.forEach(building => {
      if (!building.parent) return;
      const bounds = new THREE.Box3().setFromObject(building);
      const center = bounds.getCenter(new THREE.Vector3());
      const t = THREE.MathUtils.clamp(center.clone().sub(camera.position).dot(sight) / sightLengthSq, 0, 1);
      const closest = camera.position.clone().addScaledVector(sight, t);
      const radius = bounds.getSize(new THREE.Vector3()).length() * 0.28;
      const faded = t > 0.04 && t < 0.96 && center.distanceTo(closest) < radius;
      building.traverse(part => {
        if (!part.material) return;
        part.material.transparent = faded;
        part.material.opacity = faded ? 0.14 : 1;
        part.material.depthWrite = !faded;
      });
    });
    sunTarget.position.copy(cameraLook);
    dirLight.position.copy(cameraLook).add(new THREE.Vector3(12, 70, -7));
  }

  function onWindowResize() {
    const width = container.clientWidth || window.innerWidth;
    const height = container.clientHeight || window.innerHeight;
    if (width <= 0 || height <= 0) return;
    const aspect = width / height;
    const viewSize = 42;
    camera.left = -viewSize * aspect / 2;
    camera.right = viewSize * aspect / 2;
    camera.top = viewSize / 2;
    camera.bottom = -viewSize / 2;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
  }

  function resetGame() {
    state.roadSegments.forEach(disposeSegment);
    state.roadSegments = [];
    state.intersections = [];
    state.actors = [];
    state.ambient = [];
    state.occluders = [];
    state.district = 0;
    currentCorridor = null;
    state.exitRoad = null;
    state.driveFaults.clear();
    state.driveRecovery = 0;
    state.lastSafePosition.set(-1.8, 0, 0);
    state.lastSafeYaw = 0;
    state.resolution = null;
    state.activeIntersection = null;
    state.roadEvent = null;
    state.roadTurn = 0;
    state.busBays = [];
    state.sky = null; state.weatherOverride = null; state.rain = 0; state.overcast = 0;
    state.speedLimitKmH = null;
    state.speedingTime = 0;
    state.speedingPenalized = false;
    roadBag = [];
    state.currentSituation = null;
    state.speed = 0;
    state.distanceTraveled = 0;
    state.isAtSituation = false;
    state.isResolvingSituation = false;
    state.isAccelerating = false;
    state.isBraking = false;
    state.targetLane = 1;
    state.currentLaneOffset = state.targetLaneOffset = -1.8;
    state.violationEpisode = 0;
    state.steering = 0;
    state.blinker = null;
    clearOncoming();
    situationIndex = 0;
    situationBag = [];
    playerCarGroup.position.set(-1.8, 0, 0);
    playerCarGroup.rotation.set(0, 0, 0);
    camera.position.set(0, 42, -36);
    cameraLook.set(0, 0, 14);
    cameraHeading = 0;
    cameraViewSize = 42;
    buildInitialTrack();
    telemetryElapsed = 0;
  }

  window.game = {
    releaseTraffic,
    setGas(isPressed) {
      if (isPressed) gameAudio?.unlock();
      if (state.attract) { state.isAccelerating = false; return; }
      state.isAccelerating = !state.paused && !state.driveRecovery && (!state.isAtSituation || state.resolution?.phase === 'manual') && !state.resolution?.recovery && Boolean(isPressed);
    },
    setBrake(isPressed) {
      state.isBraking = !state.paused && !state.driveRecovery && (!state.isAtSituation || state.resolution?.phase === 'manual') && !state.resolution?.recovery && Boolean(isPressed);
    },
    // Signed-out visitors: a living street to look at (finger orbits the camera).
    setAttract(on) {
      state.attract = Boolean(on);
      if (!state.attract) {
        state.orbitYaw = 0;
        // The visitor is now a driver: clear the attract traffic before
        // the first metre so nothing is left sitting in the oncoming lane.
        state.actors.forEach(a => { if (a.config?.id?.startsWith('attract_')) { a.done = true; a.mesh.visible = false; } });
        (state.attractGroups || []).forEach(disposeSegment);
        state.attractGroups = [];
      }
    },
    // Garage reveal of a newly unlocked car; tap opens the door, finger spins.
    showReveal(id, paint) {
      if (!window.PDD_VEHICLES.specs[id]) return;
      reveal = buildRevealScene(id, paint || null);
      updateReveal(0);
    },
    openReveal() { if (reveal && reveal.phase === 'closed') { reveal.phase = 'opening'; reveal.t = 0; } },
    hideReveal() {
      if (!reveal) return;
      reveal.scene.traverse(o => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); });
      reveal = null;
      renderer.render(scene, camera);
    },
    thumbnail(id, paint) { try { return renderThumbnail(id, paint || null); } catch (_) { return ''; } },
    setSteering(direction) {
      state.steering = !state.paused && !state.driveRecovery && (!state.isAtSituation || state.resolution?.phase === 'manual') && !state.resolution?.recovery
        ? Math.max(-1, Math.min(1, Number(direction) || 0)) : 0;
      if (state.steering) {
        const side = state.steering > 0 ? 'left' : 'right';
        if (state.blinker?.side !== side) state.blinker = { side, remaining: 2.2, elapsed: 0 };
      }
    },
    switchLane,
    selectVehicle,
    proceedAfterAnswer: resolveSituationAnimation,
    setPaused(paused) {
      const next = Boolean(paused);
      if (next === state.paused) return;
      state.paused = next;
      if (next) { state.isAccelerating = false; state.isBraking = false; state.steering = 0; }
      gameAudio?.setPaused(next);
      lastTime = null;
    },
    setViewportInsets(insets) {
      state.viewportInsets = { top: Math.max(0, Number(insets.top) || 0), bottom: Math.max(0, Number(insets.bottom) || 0) };
    },
    configure(config) {
      state.nativeControls = true;
      if (config.labels) Object.assign(state.labels, config.labels);
      // A first-time player sees clear weather for the whole session.
      state.firstRun = Boolean(config.firstRun);
      gameAudio?.setEnabled(config.soundEnabled !== false);
    },
    setTheme(isDark) {
      state.isDarkTheme = Boolean(isDark);
      applyWeather();
      renderer.render(scene, camera);
    },
    // Debug/testing: 'summer' | 'autumn' | 'winter', or null for the calendar.
    // Existing scenery is re-tinted; trees keep their colour until rebuilt.
    setSeason(kind) {
      currentSeason = SEASONS[kind] || SEASONS[seasonFromDate()];
      const sn = currentSeason;
      scene.traverse(o => {
        const tag = o.material?.userData?.seasonal; if (!tag) return;
        if (tag === 'ground') o.material.color.setHex(sn.ground);
        else if (tag.startsWith('verge')) o.material.color.setHex(sn.verge[Number(tag[5])] || sn.ground);
        else if (tag === 'sidewalk') o.material.color.setHex(sn.sidewalk);
        else if (tag === 'roof') o.material.color.setHex(sn.roof || (Math.random() > 0.5 ? 0x8C4A3C : 0x5D6B75));
        else if (tag === 'canopy') o.material.color.setHex(sn.canopy[Math.floor(Math.random() * sn.canopy.length)]);
        else if (tag === 'birch') o.material.color.setHex(Math.random() < 0.7 ? sn.birch : sn.canopy[Math.floor(Math.random() * sn.canopy.length)]);
        else if (tag === 'water') o.material.color.setHex(sn.precipitation === 'snow' ? 0xD7E6EE : 0x6FA8C9);
      });
      state.weatherDirty = true;
    },
    // Debug/testing: force 'clear' | 'overcast' | 'rain', or null for the
    // automatic cycle.
    setWeather(kind) {
      state.weatherOverride = ['clear', 'overcast', 'rain'].includes(kind) ? kind : null;
      if (!state.sky) state.sky = { kind: 'clear', left: 0 };
      if (state.weatherOverride) { state.sky.kind = state.weatherOverride; state.sky.left = 1e9; }
      else state.sky.left = 0;
    },
    reset: resetGame
  };
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) window.game.setPaused(true);
  });

  // Run init on DOM ready
  window.addEventListener('error', () => sendToFlutter({ event: 'engine_error' }));
  window.addEventListener('unhandledrejection', () => sendToFlutter({ event: 'engine_error' }));
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
