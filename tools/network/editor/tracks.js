// Tram tracks of a scene (scene.tracks: [{ id, points, depot }]): drawn with the «Рельсы» tool, built by
// build.py as two rails (and a paved bed where they leave the road, so the kerb opens for them). A tram
// rides a track (actor.track, actor.trackDir) and may turn onto a branch ahead (actor.branch), e.g. into
// its depot, so it is off the road once it has passed. Its path is rebuilt from that on every edit.
const Tracks = (() => {
  const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const r3 = (v) => Math.round(v * 1000) / 1000;
  const SNAP = 3.5;

  const of = (s, id) => (s.tracks || []).find((t) => t.id === id);

  // Where p falls on a polyline: distance along it, the point, how far off it is.
  function project(pts, p) {
    let acc = 0, best = { d: Infinity, at: 0, q: pts[0] };
    for (let i = 0; i + 1 < pts.length; i++) {
      const a = pts[i], b = pts[i + 1], dx = b[0] - a[0], dz = b[1] - a[1], l = Math.hypot(dx, dz) || 1;
      const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / (l * l)));
      const q = [a[0] + dx * t, a[1] + dz * t], d = dist(p, q);
      if (d < best.d) best = { d, at: acc + t * l, q };
      acc += l;
    }
    return best;
  }
  const length = (pts) => pts.slice(1).reduce((s, p, i) => s + dist(pts[i], p), 0);
  // The part of a polyline between distances a and b (b < a: backwards).
  function part(pts, a, b) {
    if (b < a) return part(pts.slice().reverse(), length(pts) - a, length(pts) - b);
    const out = [];
    let acc = 0;
    const at = (d) => {
      let s = 0;
      for (let i = 0; i + 1 < pts.length; i++) {
        const l = dist(pts[i], pts[i + 1]);
        if (s + l >= d || i + 2 === pts.length) { const t = l ? Math.min(1, (d - s) / l) : 0; return [pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t]; }
        s += l;
      }
      return pts[0];
    };
    out.push(at(a));
    for (let i = 1; i < pts.length; i++) {
      acc += dist(pts[i - 1], pts[i]);
      if (acc > a + 1e-6 && acc < b - 1e-6) out.push(pts[i]);
    }
    out.push(at(b));
    return out;
  }

  // The branches that leave a track ahead of distance `from` in direction `dir`.
  function branchesAhead(s, track, from, dir) {
    const out = [];
    for (const t of s.tracks || []) {
      if (t === track || t.points.length < 2) continue;
      for (const [end, other] of [[t.points[0], false], [t.points.at(-1), true]]) {
        const pr = project(track.points, end);
        if (pr.d < SNAP && (pr.at - from) * dir > 1) out.push({ track: t, at: pr.at, reversed: other });
      }
    }
    return out;
  }

  // The path of a tram: along its track from where it stands, then onto its branch if one is set.
  function pathFor(s, a) {
    const track = of(s, a.track);
    if (!track || track.points.length < 2) return null;
    const dir = a.trackDir === -1 ? -1 : 1;
    const pr = project(track.points, a.pos);
    const total = length(track.points);
    const branch = a.branch && branchesAhead(s, track, pr.at, dir).find((b) => b.track.id === a.branch);
    if (branch) {
      const main = part(track.points, pr.at, branch.at);
      const spur = branch.reversed ? branch.track.points.slice().reverse() : branch.track.points;
      return [...main, ...spur.slice(1)];
    }
    return part(track.points, pr.at, dir > 0 ? total : 0);
  }

  // Every tram on a track: its place on the rails, its heading and its path.
  function apply(s) {
    for (const a of s.actors || []) {
      if (a.type !== "tram" || !a.track) continue;
      // Editing route points is an explicit choice, just as for the road planner.
      // A later unrelated edit must not replace that path with the old rail line.
      const existing = (s.routes || []).find((r) => r.id === a.route);
      if (existing?.manual) continue;
      const path = pathFor(s, a);
      if (!path || path.length < 2) continue;
      a.pos = [r3(path[0][0]), r3(path[0][1])];
      a.yaw = r3(Math.atan2(path[1][0] - path[0][0], path[1][1] - path[0][1]));
      const rid = `actor_${a.id}`;
      s.routes = (s.routes || []).filter((r) => r.id !== rid);
      s.routes.push({ id: rid, kind: "actor", auto: true, points: path.map((p) => [r3(p[0]), r3(p[1])]) });
      a.route = rid;
    }
    return s;
  }

  // A point of a new track snaps onto the rails already there (a branch starts on its main line).
  function snap(s, p) {
    let best = null;
    for (const t of s.tracks || []) {
      for (const q of [t.points[0], t.points.at(-1)]) if (dist(p, q) < SNAP && (!best || dist(p, q) < best.d)) best = { d: dist(p, q), q };
      const pr = project(t.points, p);
      if (pr.d < SNAP && (!best || pr.d < best.d)) best = { d: pr.d, q: pr.q };
    }
    return best ? [r3(best.q[0]), r3(best.q[1])] : p;
  }

  // The nearest track to a point (a tram put down on the rails takes it).
  function nearest(s, p) {
    let best = null;
    for (const t of s.tracks || []) {
      const pr = project(t.points, p);
      if (!best || pr.d < best.d) best = { ...pr, track: t };
    }
    return best;
  }

  // The old baked ground contains rails in two specific vertex colours. Limit
  // removal to all three matching ground vertices so grey props stay intact.
  const railColours = [[142, 153, 156], [146, 154, 156]].map(c => c.map(v => v / 255));
  const linear = v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  const bakedRailColours = [...railColours, ...railColours.map(c => c.map(linear))];
  function isBakedRailTriangle(heights, colours) {
    return heights.length === 3 && colours.length === 3
      && heights.every(y => y >= -0.005 && y <= 0.16)
      && colours.every(c => bakedRailColours.some(target => target.every((v, k) => Math.abs(c[k] - v) <= 1.5 / 255)));
  }

  return { pathFor, apply, snap, nearest, branchesAhead, project, of, isBakedRailTriangle };
})();
if (typeof module !== "undefined") module.exports = Tracks;
