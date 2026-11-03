// Pictures of the models for the library and the inspector: each prop, participant type and the
// traffic light rendered once from above at an angle, on a small offscreen canvas. Kept in the browser
// (localStorage) so the next visit shows them at once.
const Thumbs = (() => {
  const SIZE = 160;
  const VERSION = "t5";
  // Trees and bushes are white in their files: the game paints them (the season's colour).
  const TINT = Catalog.PROP_TINTS;
  const cache = new Map();
  const waiting = new Map();      // URL -> elements waiting for this render
  const observers = new WeakMap();
  let renderer = null, scene = null, camera = null, queue = Promise.resolve();
  const loader = new THREE.GLTFLoader();

  function urlOf(kind, id) {
    if(kind==='motorcycle')return `/asset/models/road/motorcycle.glb?sidecar=${id==='sidecar'?1:0}`;
    if (kind === "prop") return id === "parked" ? "/asset/models/vehicles/sedan.glb" : `/asset/scenery/${id}.glb`;
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
    if (waiting.has(url)) { waiting.get(url).add(el); return; }
    const targets = new Set([el]);
    waiting.set(url, targets);
    queue = queue.then(async () => {
      if (![...targets].some(target => target.isConnected)) return;
      const src = await render(url, kind === "prop" ? TINT[id] : null);
      cache.set(url, src);
      try { localStorage.setItem(`thumb:${VERSION}:${url}`, src); } catch (_) { /* Optional cache. */ }
      for (const target of targets) if (target.isConnected) target.src = src;
    }).catch(() => { /* A missing model must not stop the rest of the catalogue. */ })
      .finally(() => waiting.delete(url));
  }
  function stored(url) {
    try { return localStorage.getItem(`thumb:${VERSION}:${url}`); } catch (e) { return null; }
  }
  function fillAll(root = document) {
    const images = root.querySelectorAll("img[data-thumb]:not([src])");
    if (typeof IntersectionObserver === "undefined") { images.forEach(fill); return; }
    let observer = observers.get(root);
    if (!observer) {
      observer = new IntersectionObserver(entries => {
        for (const entry of entries) if (entry.isIntersecting) {
          observer.unobserve(entry.target);
          fill(entry.target);
        }
      }, { root: root === document ? null : root, rootMargin: "120px" });
      observers.set(root, observer);
    }
    observer.disconnect();
    images.forEach(img => observer.observe(img));
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

  async function render(url, tint) {
    if (!renderer) setup();
    let root = (await loader.loadAsync(url)).scene;
    if (url.includes("?sidecar=")) {
      const bundle = new THREE.Group();
      if (url.endsWith("=1")) {
        root.position.x = .37;
        const passenger = await loader.loadAsync("/asset/models/road/sidecar.glb").catch(() => null);
        if (passenger) { passenger.scene.position.x = -.56; bundle.add(passenger.scene); }
      }
      bundle.add(root);
      root = bundle;
      ActorAppearance.paint(root, "#4D7768");
    }
    if (tint) root.traverse(m => {
      if (m.isMesh && m.material?.color) { m.material = m.material.clone(); m.material.color.set(tint); }
    });
    scene.add(root);
    try {
      const box = new THREE.Box3().setFromObject(root);
      const size = box.getSize(new THREE.Vector3()), centre = box.getCenter(new THREE.Vector3());
      const r = Math.max(size.x, size.y, size.z) || 1;
      const dir = new THREE.Vector3(-0.9, 0.75, 1.1).normalize();
      camera.position.copy(centre).addScaledVector(dir, r * 2.2);
      camera.lookAt(centre);
      renderer.render(scene, camera);
      return renderer.domElement.toDataURL("image/png");
    } finally {
      scene.remove(root);
      root.traverse(node => {
        node.geometry?.dispose();
        for (const material of [].concat(node.material || [])) {
          for (const value of Object.values(material)) if (value?.isTexture) value.dispose();
          material.dispose();
        }
      });
    }
  }

  return { img, fill, fillAll };
})();
