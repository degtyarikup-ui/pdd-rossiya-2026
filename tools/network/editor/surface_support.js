// Ground beneath a participant, using the same triangulated surfaces as the game.
// Paint and rails are overlays, not supporting surfaces. Holes stay holes.
const SurfaceSupport = (() => {
  const cache = new WeakMap();
  function triangles(build) {
    if (!build) return [];
    if (!cache.has(build)) {
      const out = [];
      for (const s of build.surfaces || []) {
        if (!s.layer) continue;
        for (let i = 0; i < s.idx.length; i += 3) {
          const p = s.idx.slice(i, i + 3).map(j => [s.verts[j * 2], s.verts[j * 2 + 1]]);
          out.push({p, id:s.id, y:s.y, minX:Math.min(...p.map(q=>q[0])), maxX:Math.max(...p.map(q=>q[0])),
            minZ:Math.min(...p.map(q=>q[1])), maxZ:Math.max(...p.map(q=>q[1]))});
        }
      }
      cache.set(build, out.sort((a,b)=>b.y-a.y));
    }
    return cache.get(build);
  }
  function at(build, x, z) {
    for (const t of triangles(build)) {
      if (x < t.minX || x > t.maxX || z < t.minZ || z > t.maxZ) continue;
      const [a,b,c] = t.p;
      const cross = (p,q) => (q[0]-p[0])*(z-p[1])-(q[1]-p[1])*(x-p[0]);
      const signs = [cross(a,b),cross(b,c),cross(c,a)];
      if (signs.every(v=>v >= -1e-8) || signs.every(v=>v <= 1e-8)) return {y:t.y,id:t.id};
    }
    return {y:build ? -0.15 : 0,id:null};
  }
  return {at};
})();
if (typeof module !== "undefined") module.exports = SurfaceSupport;
