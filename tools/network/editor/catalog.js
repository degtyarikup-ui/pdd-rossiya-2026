// What the things of a scene are called and how the library shows them: groups of props
// (scenery/index.json keys), participant types, the tints a prop can take. Names only: the models
// come from the server's catalog (/api/catalog).
const Catalog = (() => {
  // Library groups, in order. match: which prop ids belong to the group.
  const PROP_GROUPS = [
    { id: "trees", title: "Деревья и кусты", icon: "tree", match: (p) => p.startsWith("trees/") || p === "street/bush" },
    { id: "homes", title: "Дома", icon: "home", match: (p) => p.startsWith("buildings/home") },
    { id: "blocks", title: "Многоэтажки", icon: "building", match: (p) => p.startsWith("buildings/block") || p.startsWith("buildings/tower") },
    { id: "street", title: "Улица", icon: "lamp", match: (p) => p.startsWith("street/") && p !== "street/bush" },
    { id: "parked", title: "Стоящие машины", icon: "parked", match: (p) => p === "parked" },
  ];
  const PROP_NAMES = {
    "trees/pine_0": "Ель", "trees/round_0": "Дерево", "trees/birch_0": "Берёза", "street/bush": "Куст",
    "street/fence_12": "Забор 12 м", "street/fence_14": "Забор 14 м", "street/lamp": "Фонарь",
    "street/kiosk_0": "Киоск", "street/kiosk_1": "Киоск", "street/kiosk_2": "Киоск", parked: "Машина у обочины",
  };
  function propName(id) {
    if (PROP_NAMES[id]) return PROP_NAMES[id];
    const m = id.match(/^buildings\/(home|block|tower)_(\d+)$/);
    if (m) return { home: "Дом", block: "Жилой дом", tower: "Высотка" }[m[1]] + " " + (Number(m[2]) + 1);
    return id;
  }
  const groupOf = (id) => PROP_GROUPS.find((g) => g.match(id)) || PROP_GROUPS[0];

  // Participants: name, icon, how fast they go by default (m/s) and whether they drive on lanes.
  const ACTORS = {
    car: { name: "Легковая", icon: "car", lane: true },
    truck: { name: "Грузовик", icon: "car", lane: true },
    bus: { name: "Автобус", icon: "car", lane: true },
    tram: { name: "Трамвай", icon: "car", lane: true },
    van: { name: "Фургон", icon: "car", lane: true },
    special: { name: "Спецмашина", icon: "car", lane: true },
    tanker: { name: "Цистерна", icon: "car", lane: true },
    motorcycle: { name: "Мотоцикл", icon: "car", lane: true },
    cyclist: { name: "Велосипедист", icon: "person", lane: false },
    pedestrian: { name: "Пешеход", icon: "person", lane: false },
    cart: { name: "Повозка", icon: "car", lane: false },
  };
  const ACTOR_ORDER = ["car", "truck", "bus", "van", "special", "tanker", "motorcycle", "tram", "cyclist", "pedestrian", "cart"];
  // Speeds people think in, and the metres per second the game takes.
  const SPEEDS = [
    { id: "slow", title: "Медленно", v: 5 },
    { id: "normal", title: "Обычно", v: 10 },
    { id: "fast", title: "Быстро", v: 15 },
  ];
  const speedOf = (v) => SPEEDS.reduce((b, s) => (Math.abs(s.v - v) < Math.abs(b.v - v) ? s : b), SPEEDS[1]);

  // Tints: the scenes' own most used colours, so a new prop matches the rest.
  const TINTS = {
    trees: [null, "#3e7c42", "#467e3c", "#9a8a3e", "#c7a24a", "#e0b33c", "#d98a2b", "#c94f2b"],
    homes: [null, "#f3e3c3", "#e9d5cc", "#e8cfa8", "#d9b99b", "#c8d9c0", "#e8e8e8", "#b86a2a"],
    blocks: [null, "#f3e3c3", "#e9d5cc", "#e8cfa8", "#d9b99b", "#c8d9c0", "#e8e8e8"],
    street: [null, "#e8e8e8", "#b86a2a", "#3e7c42"],
    parked: [null, "#e8e8e8", "#c94f2b", "#3e63dd", "#2b2f36", "#e0b33c"],
  };

  const EXITS = {
    left: { title: "Налево", icon: "arrow-left" },
    straight: { title: "Прямо", icon: "arrow-up" },
    right: { title: "Направо", icon: "arrow-right" },
    uturn: { title: "Разворот", icon: "arrow-uturn" },
  };
  const LETTERS = ["А", "Б", "В", "Г"];
  const LETTER_COLOUR = { "А": "#e0533d", "Б": "#8b5cf6", "В": "#0891b2", "Г": "#d98e04", "Д": "#16a34a" };
  const LIGHTS = [
    { id: "red", title: "Красный", colour: "#ff3b30" },
    { id: "yellow", title: "Жёлтый", colour: "#ffcc00" },
    { id: "green", title: "Зелёный", colour: "#34c759" },
    { id: "flashing_yellow", title: "Мигает жёлтый", colour: "#ffcc00" },
  ];
  const MARKS = {
    dashed: { title: "Прерывистая", icon: "marking" },
    solid: { title: "Сплошная", icon: "road" },
    stop: { title: "Стоп-линия", icon: "stopline" },
    zebra: { title: "Зебра", icon: "zebra" },
  };

  return { PROP_GROUPS, propName, groupOf, ACTORS, ACTOR_ORDER, SPEEDS, speedOf, TINTS, EXITS, LETTERS, LETTER_COLOUR, LIGHTS, MARKS };
})();
