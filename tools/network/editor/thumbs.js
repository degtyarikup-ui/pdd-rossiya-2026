// Pictures of the models for the library and the inspector: each prop, participant type and the
// traffic light rendered once from above at an angle, on a small offscreen canvas. Kept in the browser
// (localStorage) so the next visit shows them at once.
const Thumbs = (() => {
  const SIZE = 160;
  const VERSION = "t3";
  // Trees and bushes are white in their files: the game paints them (the season's colour).
  const TINT = { "trees/pine_0": "#3e7c42", "trees/round_0": "#5f8f3e", "trees/birch_0": "#7fa34a", "street/bush": "#467e3c" };
  const cache = new Map();
  const waiting = new Map();      // url -> [img]
  let renderer = null, scene = null, camera = null, queue = Promise.resolve();
  const loader = new THREE.GLTFLoader();

  function urlOf(kind, id) {
    if (kind === "prop") return id === "parked" ? "/asset/models/traffic/sedan.glb" : `/asset/scenery/${id}.glb`;
    if (kind === "actor") {
      const tpl = App.state.catalog?.actorTypes[id];
      return tpl ? `/asset/scene/${tpl.asset}` : null;
    }
    if (kind === "light") {
      if (id === "light_tram" || id === "tram") {
        const tr = App.state.catalog?.lightTramAsset || App.state.catalog?.lightAssets?.tram;
        if (tr) return `/asset/scene/${tr}`;
      }
      return App.state.catalog?.lightAsset ? `/asset/scene/${App.state.catalog.lightAsset}` : null;
    }
    return null;
  }

  // An <img> placeholder; fill() gives it its picture when it is in the page.
  function img(kind, id, cls = "") {
    const url = urlOf(kind, id);
    const src = url && cache.get(url);
    return `<img class="thumb ${cls}" data-thumb="${kind}|${id}" ${src ? `src="${src}"` : ""} alt="" draggable="false">`;
  }

  function fill(el) {
    const [kind, id] = el.dataset.thumb.split("|");
    const url = urlOf(kind, id);
    if (!url) return;
    const have = cache.get(url) || stored(url);
    if (have) { cache.set(url, have); el.src = have; return; }
    if (waiting.has(url)) { waiting.get(url).push(el); return; }
    waiting.set(url, [el]);
    queue = queue.then(() => render(url, kind === "prop" ? TINT[id] : null)).then((src) => {
      if (src) {
        cache.set(url, src);
        try { localStorage.setItem(`thumb:${VERSION}:${url}`, src); } catch (e) { /* full: drawn again next time */ }
      }
      for (const x of waiting.get(url) || []) if (src) x.src = src;
      waiting.delete(url);
      document.querySelectorAll(`img[data-thumb="${kind}|${id}"]`).forEach((x) => { if (src) x.src = src; });
    });
  }
  function stored(url) {
    try { return localStorage.getItem(`thumb:${VERSION}:${url}`); } catch (e) { return null; }
  }
  function fillAll(root = document) {
    root.querySelectorAll("img[data-thumb]:not([src])").forEach(fill);
  }

  function setup() {
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    renderer.setPixelRatio(1);
    renderer.setSize(SIZE, SIZE);
    renderer.setClearColor(0x000000, 0);
    scene = new THREE.Scene();
    scene.add(new THREE.HemisphereLight(0xffffff, 0x8a8f78, 1.0));
    const sun = new THREE.DirectionalLight(0xffffff, 0.6);
    sun.position.set(-3, 6, 4);
    scene.add(sun);
    camera = new THREE.PerspectiveCamera(30, 1, 0.1, 1000);
  }

  function render(url, tint) {
    return new Promise((resolve) => {
      if (!renderer) setup();
      loader.load(url, (g) => {
        const root = g.scene;
        if (tint) root.traverse((m) => { if (m.isMesh && m.material && m.material.color) { m.material = m.material.clone(); m.material.color.set(tint); } });
        scene.add(root);
        const box = new THREE.Box3().setFromObject(root);
        const size = box.getSize(new THREE.Vector3()), centre = box.getCenter(new THREE.Vector3());
        const r = Math.max(size.x, size.y, size.z) || 1;
        const dir = new THREE.Vector3(-0.9, 0.75, 1.1).normalize();
        camera.position.copy(centre).addScaledVector(dir, r * 2.2);
        camera.lookAt(centre);
        renderer.render(scene, camera);
        const src = renderer.domElement.toDataURL("image/png");
        scene.remove(root);
        resolve(src);
      }, undefined, () => resolve(null));
    });
  }

  return { img, fill, fillAll };
})();
