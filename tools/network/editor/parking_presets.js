// A location is expanded into ordinary editable scene objects in one history step.
// No prefab reference survives placement: moving/deleting a pump never changes its neighbours.
const ParkingPresets = (() => {
  const round = n => Math.round(n * 1000) / 1000;
  const copy = value => JSON.parse(JSON.stringify(value));
  const list = catalog => catalog?.presets || [];
  const get = (catalog, id) => list(catalog).find(p => p.id === id) || list(catalog)[0] || null;
  function place(scene, preset, position, yaw = 0) {
    if (!preset) return [];
    const c = Math.cos(yaw), s = Math.sin(yaw);
    const point = p => [round(position[0] + p[0] * c + p[1] * s), round(position[1] + p[1] * c - p[0] * s)];
    const instances = new Set(['decor','roads','markings'].flatMap(key => (scene[key] || []).map(o => o.presetInstance)));
    let instance = 1;
    while (instances.has(`${preset.id}_${instance}`)) instance++;
    const presetInstance = `${preset.id}_${instance}`;
    const refs = [];
    for (const [key, type] of [['decor', 'decor'], ['roads', 'road'], ['markings', 'marking']]) {
      const items = preset[key] || [];
      if (!items.length) continue;
      const target = scene[key] ||= [], used = new Set(target.map(o => o.id));
      let serial = 1;
      for (const source of items) {
        const o = copy(source), prefix = `${preset.id}_${type}_`;
        while (used.has(prefix + serial)) serial++;
        o.id = prefix + serial++;
        o.presetInstance = presetInstance;
        used.add(o.id);
        delete o.auto;
        if (o.pos) o.pos = point(o.pos);
        if (type === 'decor') {
          o.yaw = round((o.yaw || 0) + yaw);
          o.scale ||= [1, 1, 1];
          o.tint ??= null;
        }
        if (o.outer) o.outer = o.outer.map(point);
        if (o.holes) o.holes = o.holes.map(ring => ring.map(point));
        if (o.points) o.points = o.points.map(point);
        if (o.polygons) o.polygons = o.polygons.map(poly => ({...poly, outer:poly.outer.map(point), holes:(poly.holes || []).map(ring => ring.map(point))}));
        target.push(o);
        refs.push({t:type, id:o.id});
      }
    }
    return refs;
  }
  return { list, get, place };
})();
if (typeof module !== 'undefined') module.exports = ParkingPresets;
