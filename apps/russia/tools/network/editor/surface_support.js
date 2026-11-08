// Ground beneath a participant, using the same triangulated surfaces as the game.
// Paint and rails are overlays, not supporting surfaces. Holes stay holes.
const SurfaceSupport = (() => {
  const cache = new WeakMap();
  function triangles(build) {
    if (!build) return [];
    if (!cache.has(build)) {
      const out = [];
      for (const s of build.surfaces || []) {
        if (!s.layer && !s.support) continue;
        for (let i = 0; i < s.idx.length; i += 3) {
          const p = s.idx.slice(i, i + 3).map(j => [s.verts[j * 2], s.verts[j * 2 + 1]]);
          out.push({p, h:s.idx.slice(i,i+3).map(j=>s.heights?.[j] ?? s.y), id:s.id, y:s.y, minX:Math.min(...p.map(q=>q[0])), maxX:Math.max(...p.map(q=>q[0])),
            minZ:Math.min(...p.map(q=>q[1])), maxZ:Math.max(...p.map(q=>q[1]))});
        }
      }
      cache.set(build, out.sort((a,b)=>b.y-a.y));
    }
    return cache.get(build);
  }
  function at(build, x, z) {
    let best = {y:build ? -0.15 : 0,id:null};
    for (const t of triangles(build)) {
      if (x < t.minX || x > t.maxX || z < t.minZ || z > t.maxZ) continue;
      const [a,b,c] = t.p;
      const cross = (p,q) => (q[0]-p[0])*(z-p[1])-(q[1]-p[1])*(x-p[0]);
      const signs = [cross(a,b),cross(b,c),cross(c,a)];
      if (signs.every(v=>v >= -1e-8) || signs.every(v=>v <= 1e-8)) {
        const det = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);
        if (Math.abs(det) < 1e-12) continue;
        const u = ((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(z-c[1]))/det;
        const v = ((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(z-c[1]))/det;
        const y = t.h[0] === t.h[1] && t.h[1] === t.h[2] ? t.h[0] : t.h[0]*u+t.h[1]*v+t.h[2]*(1-u-v);
        if (y > best.y) best = {y,id:t.id};
      }
    }
    return best;
  }
  return {at};
})();
if (typeof module !== "undefined") module.exports = SurfaceSupport;
