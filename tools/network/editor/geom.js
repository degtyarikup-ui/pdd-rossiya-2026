// Road geometry laid along a centreline (x, z in metres): the carriageway outline, and the strips beside
// it. The road tool (ui.js) turns one drawn line into the items of the scene: a road, lawns where a
// pavement is not wanted, a centre marking. The builder makes the pavements itself (3.2 m beside
// every road), so a strip of lawn over that pavement is what "no pavement" means.
const RoadGeom = (() => {
  const PAVEMENT = 3.2;          // the builder's pavement width beside the carriageway (build.py SIDEWALK)
  const round = (p) => [Math.round(p[0] * 1000) / 1000, Math.round(p[1] * 1000) / 1000];

  // The line without repeated points (a double click adds one).
  function clean(points) {
    return points.filter((p, i) => i === 0 || Math.hypot(p[0] - points[i - 1][0], p[1] - points[i - 1][1]) > 0.02);
  }

  // The centreline moved `d` metres to its left (negative: to the right). Corners are mitred: the two
  // offset edges meet on the bisector, so the road keeps its width round a bend (clamped at sharp turns).
  function offset(points, d) {
    const n = points.length, out = [];
    const normal = (a, b) => {
      const dx = b[0] - a[0], dz = b[1] - a[1], l = Math.hypot(dx, dz) || 1;
      return [-dz / l, dx / l];
    };
    for (let i = 0; i < n; i++) {
      const ns = [];
      if (i > 0) ns.push(normal(points[i - 1], points[i]));
      if (i < n - 1) ns.push(normal(points[i], points[i + 1]));
      let nx = 0, nz = 0;
      for (const v of ns) { nx += v[0]; nz += v[1]; }
      const l = Math.hypot(nx, nz) || 1;
      nx /= l; nz /= l;
      const k = ns.length === 2 ? Math.min(3, 1 / Math.max(nx * ns[0][0] + nz * ns[0][1], 0.3)) : 1;
      out.push([points[i][0] + nx * d * k, points[i][1] + nz * d * k]);
    }
    return out;
  }

  // The carriageway: its left edge forward, the right edge back.
  function outline(points, width) {
    const left = offset(points, width / 2);
    const right = offset(points, -width / 2).reverse();
    return [...left, ...right].map(round);
  }

  // The strip beside the carriageway on one side (1 = left, -1 = right), as wide as the pavement.
  function strip(points, width, side) {
    const inner = offset(points, (side * width) / 2);
    const outer = offset(points, (side * (width / 2 + PAVEMENT))).reverse();
    return [...inner, ...outer].map(round);
  }

  return { clean, offset, outline, strip, PAVEMENT };
})();
