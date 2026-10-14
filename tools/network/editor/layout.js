// The road plan of a scene, the way a city builder has it: junction points (nodes) joined by streets.
// Everything on the ground follows from it: the road outlines, the centre lines, stop lines and
// zebras, the player's stop, the approach and every manoeuvre, the exit widths. ui.js keeps the plan
// in scene.layout and calls apply() after each edit; build.py and the game read the generated items.
//
// Frame (as in every scene): metres, the junction at (0, 0), the player drives along +z, +x is the
// driver's LEFT. So for a direction t = (tx, tz): left = (tz, -tx), right = (-tz, tx).
// A heading (yaw) is atan2(tx, tz): 0 = +z. Right-hand traffic: a car keeps to the right of the centre.
const Layout = (() => {
  // Street kinds: width of the carriageway, the lane centres to the right of the centre line.
  const KINDS = {
    yard: { width: 5.0, lanes: [1.25], title: "Проезд" },
    street: { width: 8.4, lanes: [1.8], title: "Улица" },
    avenue: { width: 14.0, lanes: [1.75, 5.25], title: "Проспект" },
  };
  const KERB_R = 5.0;
  const CAR_BACK = 2.4;        // the player's car centre behind its stop line (half a car and a gap)          // the kerb radius the builder rounds every inner corner with (build.py CURB_RADIUS)
  const ZEBRA_LEN = 4.0;       // zebra bars along the traffic (build.py ZEBRA_LENGTH)
  const PORT_SNAP = 8.0;       // an end within this of a side's middle snaps to it (the game's street goes on there)
  const NODE_SNAP = 4.0;
  const STREET_SNAP = 3.0;
  const r3 = (v) => Math.round(v * 1000) / 1000;
  const P = (p) => [r3(p[0]), r3(p[1])];
  const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
  const mul = (a, k) => [a[0] * k, a[1] * k];
  const len = (a) => Math.hypot(a[0], a[1]);
  const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const unit = (a) => { const l = len(a) || 1; return [a[0] / l, a[1] / l]; };
  const left = (t) => [t[1], -t[0]];
  const right = (t) => [-t[1], t[0]];
  const heading = (t) => Math.atan2(t[0], t[1]);
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1];
  // Positive: the second direction turns to the driver's left of the first.
  const turnAngle = (tin, tout) => Math.atan2(-(tin[0] * tout[1] - tin[1] * tout[0]), dot(tin, tout));
  const wrap = (a) => { while (a > Math.PI) a -= 2 * Math.PI; while (a <= -Math.PI) a += 2 * Math.PI; return a; };

  const kindOf = (st) => KINDS[st.kind] || KINDS.street;
  // A street with a dividing strip (median, m) is that much wider: the strip in the middle, the lanes beside it.
  const medianOf = (st) => (st.kind === "yard" ? 0 : Number(st.median) || 0);
  const widthOf = (st) => kindOf(st).width + medianOf(st);

  // ---- the plan as a graph ------------------------------------------------------------
  function nodeOf(L, id) { return L.nodes.find((n) => n.id === id); }
  function streetOf(L, id) { return L.streets.find((s) => s.id === id); }
  function streetsAt(L, nid) { return L.streets.filter((s) => s.a === nid || s.b === nid); }
  const otherEnd = (st, nid) => (st.a === nid ? st.b : st.a);
  const endOf = (st, nid) => (st.a === nid ? "a" : "b");

  // The centre line of a street from a to b: straight, or a curve through its bend handle.
  function centreline(L, st, samples = 24) {
    const A = xy(nodeOf(L, st.a)), B = xy(nodeOf(L, st.b));
    if (!st.bend) return [A, B];
    const C = st.bend, out = [];
    for (let i = 0; i <= samples; i++) {
      const t = i / samples, u = 1 - t;
      out.push([u * u * A[0] + 2 * u * t * C[0] + t * t * B[0], u * u * A[1] + 2 * u * t * C[1] + t * t * B[1]]);
    }
    return out;
  }
  const xy = (n) => [n.x, n.z];

  // The centre line leaving node `nid` (its first point is the node).
  function lineFrom(L, st, nid) {
    const pts = centreline(L, st);
    return st.a === nid ? pts : pts.slice().reverse();
  }

  // Point and direction at distance d along a polyline (clamped to its ends; beyond the end it goes straight on).
  function along(pts, d) {
    let acc = 0;
    for (let i = 0; i + 1 < pts.length; i++) {
      const seg = dist(pts[i], pts[i + 1]);
      if (acc + seg >= d || i + 2 === pts.length) {
        const t = unit(sub(pts[i + 1], pts[i]));
        return { p: add(pts[i], mul(t, d - acc)), t };
      }
      acc += seg;
    }
    return { p: pts[0], t: [0, 1] };
  }
  const polyLen = (pts) => pts.slice(1).reduce((s, p, i) => s + dist(pts[i], p), 0);

  // The part of a polyline between distances d0 and d1 (d1 may be the end).
  function cut(pts, d0, d1) {
    const total = polyLen(pts);
    d1 = Math.min(d1, total);
    if (d1 - d0 < 0.05) return [];
    const out = [along(pts, d0).p];
    let acc = 0;
    for (let i = 0; i + 1 < pts.length; i++) {
      acc += dist(pts[i], pts[i + 1]);
      if (acc > d0 + 1e-6 && acc < d1 - 1e-6) out.push(pts[i + 1]);
    }
    out.push(along(pts, d1).p);
    return out;
  }

  // A polyline moved `d` metres to the right of its direction (mitred corners).
  function offsetRight(pts, d) {
    const n = pts.length, out = [];
    for (let i = 0; i < n; i++) {
      const ns = [];
      if (i > 0) ns.push(right(unit(sub(pts[i], pts[i - 1]))));
      if (i < n - 1) ns.push(right(unit(sub(pts[i + 1], pts[i]))));
      let m = ns.reduce((s, v) => add(s, v), [0, 0]);
      m = unit(m);
      const k = ns.length === 2 ? Math.min(3, 1 / Math.max(dot(m, ns[0]), 0.3)) : 1;
      out.push(add(pts[i], mul(m, d * k)));
    }
    return out;
  }

  function circle(c, r, n = 40) {
    const out = [];
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2;
      out.push(P([c[0] + Math.cos(a) * r, c[1] + Math.sin(a) * r]));
    }
    return out;
  }

  function outline(pts, w) {
    const l = offsetRight(pts, -w / 2), r = offsetRight(pts, w / 2).reverse();
    return [...l, ...r].map(P);
  }

  const onBorder = (L, n, crop) => Math.abs(Math.abs(n.x) - crop) < 0.05 || Math.abs(Math.abs(n.z) - crop) < 0.05;

  // What each node is: a junction (3 streets or more, or a roundabout), a joint (2), a border end or a dead end.
  function nodeKind(L, n, crop) {
    const deg = streetsAt(L, n.id).length;
    if (n.ring) return "ring";
    if (deg >= 3) return "junction";
    if (deg === 2) return "joint";
    return onBorder(L, n, crop) ? "border" : "dead";
  }

  // How far from a node a street's paint stops: the cross street, then the kerb rounding.
  function gapAt(L, st, nid, crop) {
    const n = nodeOf(L, nid);
    const kind = nodeKind(L, n, crop);
    if (kind === "ring") return n.ring.r + 1.0;
    if (kind === "joint") return 0;
    if (kind === "border") return -1.0;           // beyond the border: the builder cuts it at the square
    if (kind === "dead") return widthOf(st) / 2;
    const others = streetsAt(L, nid).filter((s) => s !== st).map(widthOf);
    return Math.max(...others) / 2 + KERB_R;
  }

  // Where the stop line of a street end lies (from the node), with or without a zebra before it.
  function stopDistance(L, st, nid, crop) {
    // The player's stop moved by hand (dragging the car in the editor): metres from the junction.
    if (L.player && L.player.street === st.id && L.player.toward === nid && L.player.stopAt) return L.player.stopAt + endOffset(L, st, nid, crop);
    const end = (st.ends || {})[endOf(st, nid)] || {};
    const n = nodeOf(L, nid);
    const gap = gapAt(L, st, nid, crop);
    if (nodeKind(L, n, crop) === "ring") return gap + (end.zebra ? ZEBRA_LEN + 1.0 : 0.0) + 0.5;
    return Math.max(gap, 4) + (end.zebra ? ZEBRA_LEN + 1.5 : 0) + 1.5 + endOffset(L, st, nid, crop);
  }

  // Move an approach's island nose and paint together, leaving the junction and border fixed.
  // Five metres removes the kerb-rounding setback while keeping the zebra outside cross traffic.
  function endOffsetLimits(L, st, nid, crop) {
    const total = polyLen(centreline(L, st));
    const far = otherEnd(st, nid), farKind = nodeKind(L, nodeOf(L, far), crop);
    const otherGap = medianOf(st) && farKind === "border" ? 30 : Math.max(0, gapAt(L, st, far, crop));
    const end = (st.ends || {})[endOf(st, nid)] || {};
    const player = L.player?.street === st.id && L.player.toward === nid ? L.player : null;
    const base = player?.stopAt || Math.max(gapAt(L, st, nid, crop), 4) + (end.zebra ? ZEBRA_LEN + 1.5 : 0) + 1.5;
    // Two junction ends share the strip; each may shorten its own half, leaving a visible island.
    const available = medianOf(st) && farKind === "junction" ? total / 2 : total - otherGap;
    return { min: -5, max: Math.max(0, Math.min(60, available - base - 5)) };
  }
  function endOffset(L, st, nid, crop) {
    if (nodeKind(L, nodeOf(L, nid), crop) !== "junction") return 0;
    const limits = endOffsetLimits(L, st, nid, crop);
    const value = Number((st.ends || {})[endOf(st, nid)]?.approachOffset) || 0;
    return Math.max(limits.min, Math.min(limits.max, value));
  }
  function setEndOffset(scene, streetId, nid, value) {
    const st = streetOf(scene.layout, streetId), crop = scene.crop || 90;
    if (!st || ![st.a, st.b].includes(nid) || !Number.isFinite(value)) return false;
    const before = endOffset(scene.layout, st, nid, crop);
    const key = endOf(st, nid);
    st.ends = st.ends || {};
    st.ends[key] = { ...(st.ends[key] || {}), approachOffset: value };
    const after = endOffset(scene.layout, st, nid, crop);
    if (after) st.ends[key].approachOffset = r3(after); else delete st.ends[key].approachOffset;
    const pl = scene.layout.player;
    // Preserve the author's chosen distance before the line; a free question pose stays fixed.
    if (pl?.street === st.id && pl.toward === nid && pl.mode !== "free" && pl.questionAt != null) pl.questionAt = r3(pl.questionAt + after - before);
    return true;
  }

  // ---- generation ---------------------------------------------------------------------
  // The items the plan makes, each marked auto: true (the user's own items stay as they are).
  function generate(scene) {
    const L = scene.layout, crop = Number(scene.crop || 90);
    const roads = [], markings = [], lawns = [];
    let mid = 0;
    let streetId = null;
    const mark = (m) => markings.push({ id: `auto_mark_${++mid}`, auto: true, colour: "white", street: streetId, ...m });

    for (const st of L.streets) {
      streetId = st.id;
      const w = widthOf(st);
      let pts = centreline(L, st);
      // A border end reaches a metre past the square (the builder cuts it there); others end at the node.
      const ext = (nid, at0) => {
        const n = nodeOf(L, nid);
        if (nodeKind(L, n, crop) !== "border") return;
        const t = at0 ? unit(sub(pts[0], pts[1])) : unit(sub(pts.at(-1), pts.at(-2)));
        if (at0) pts = [add(pts[0], t), ...pts]; else pts = [...pts, add(pts.at(-1), t)];
      };
      ext(st.a, true);
      ext(st.b, false);
      // With a dividing strip the street meets the game's own street (no strip) at the sides of the
      // scene: its last metres there narrow back to the plain width (the builder rounds the step).
      const borderA = nodeKind(L, nodeOf(L, st.a), crop) === "border", borderB = nodeKind(L, nodeOf(L, st.b), crop) === "border";
      const plainEnds = medianOf(st) > 0 && (borderA || borderB);
      const lenAll = polyLen(pts);
      const wide = plainEnds ? cut(pts, borderA ? 22 : 0, lenAll - (borderB ? 22 : 0)) : pts;
      const roadItem = { id: `road_${st.id}`, auto: true, outer: outline(wide.length >= 2 ? wide : pts, w), holes: [], walk: st.walk !== false && st.surface !== "sand", edge: st.edge !== false && st.surface !== "sand", surface: st.surface || "asphalt" };
      roads.push(roadItem);
      if (plainEnds) roads.push({ id: `road_${st.id}_plain`, auto: true, outer: outline(pts, kindOf(st).width), holes: [] });
      if (st.walk === false || st.surface === "sand") {
        for (const side of [1, -1]) {
          const inner = offsetRight(pts, side * w / 2), outer = offsetRight(pts, side * (w / 2 + 3.4)).reverse();
          lawns.push({ id: `auto_lawn_${st.id}_${side > 0 ? "r" : "l"}`, auto: true, outer: [...inner, ...outer].map(P), holes: [] });
        }
      }

      // Centre lines: from the stop line (or the junction's edge) at one end to the other.
      const line = centreline(L, st);
      const total = polyLen(line);
      const startD = (nid) => {
        const n = nodeOf(L, nid), kind = nodeKind(L, n, crop);
        if (kind === "junction") return stopDistance(L, st, nid, crop) - 1.5 + 0.2;
        if (kind === "border") return -1.0;
        return Math.max(0, gapAt(L, st, nid, crop));
      };
      let d0 = startD(st.a), d1 = total - startD(st.b);
      const ext0 = d0 < 0 ? -d0 : 0, ext1 = d1 > total ? d1 - total : 0;
      const body = cut(line, Math.max(0, d0), Math.min(total, d1));
      // The dividing strip: a raised island of grass along the middle, ending a little before the stop
      // lines (cars turn round its nose); signs and lights can stand on it.
      if (medianOf(st) > 0 && body.length >= 2) {
        const m = medianOf(st);
        const a0 = d0 > 0 ? d0 + 1.0 : (borderA ? 30 : 0), a1 = d1 < total ? d1 - 1.0 : total - (borderB ? 30 : 0);
        const strip = cut(line, Math.max(0, a0), Math.min(total, a1));
        if (strip.length >= 2) {
          roadItem.holes.push(outline(strip, m));
          roadItem.green = true;
        }
        if (st.kind === "avenue") for (const side of [1, -1]) mark({ type: "dashed", points: offsetRight(body, side * (m / 2 + 3.5)).map(P) });
        // Where the strip has ended (towards the side of the scene) the plain street's centre line goes on.
        if (borderA) mark({ type: "dashed", points: cut(line, 0, 26).map(P) });
        if (borderB) mark({ type: "dashed", points: cut(line, total - 26, total).map(P) });
      }
      if (body.length >= 2 && !medianOf(st)) {
        if (ext0) body[0] = add(body[0], mul(unit(sub(body[0], body[1])), ext0));
        if (ext1) body[body.length - 1] = add(body.at(-1), mul(unit(sub(body.at(-1), body.at(-2))), ext1));
        const c = st.manualMarks || st.surface === "sand" ? "none" : st.centre || (st.kind === "yard" ? "none" : st.kind === "avenue" ? "double" : "dashed");
        if (c === "dashed") mark({ type: "dashed", points: body.map(P) });
        else if (c === "solid") mark({ type: "solid", points: body.map(P) });
        else if (c === "double") {
          mark({ type: "solid", points: offsetRight(body, 0.15).map(P) });
          mark({ type: "solid", points: offsetRight(body, -0.15).map(P) });
        }
        if (st.kind === "avenue" && !st.manualMarks && st.surface !== "sand") {
          mark({ type: "dashed", points: offsetRight(body, 3.5).map(P) });
          mark({ type: "dashed", points: offsetRight(body, -3.5).map(P) });
        }
      }

      // Stop lines and zebras at the ends (set per end in the inspector).
      for (const nid of [st.a, st.b]) {
        const end = (st.ends || {})[endOf(st, nid)] || {};
        const n = nodeOf(L, nid), kind = nodeKind(L, n, crop);
        if (kind === "border" || kind === "joint") continue;
        const from = lineFrom(L, st, nid);
        const tin = mul(along(from, 1).t, -1);              // driving toward the node
        if (end.stop) {
          const s = along(from, stopDistance(L, st, nid, crop)).p;
          mark({ type: "stop", width: 0.4, points: [P(s), P(add(s, mul(right(tin), w / 2)))] });
        }
        if (end.zebra) {
          const at = kind === "ring" ? gapAt(L, st, nid, crop) + ZEBRA_LEN / 2 : Math.max(gapAt(L, st, nid, crop), 4) + 0.5 + ZEBRA_LEN / 2 + endOffset(L, st, nid, crop);
          const c = along(from, at).p;
          mark({ type: "zebra", length: ZEBRA_LEN, points: [P(add(c, mul(right(tin), -w / 2))), P(add(c, mul(right(tin), w / 2)))] });
        }
      }
    }

    // Nodes: a disc fills every junction, joint and dead end (no notch where streets meet at an angle);
    // a roundabout is its ring with the island cut out.
    for (const n of L.nodes) {
      const kind = nodeKind(L, n, crop);
      const at = streetsAt(L, n.id);
      if (!at.length) continue;
      if (kind === "ring") {
        roads.push({ id: `road_${n.id}`, auto: true, outer: circle(xy(n), n.ring.r, 64), holes: [circle(xy(n), n.ring.island, 48).reverse()] });
      } else if (kind !== "border") {
        roads.push({ id: `road_${n.id}`, auto: true, outer: circle(xy(n), Math.max(...at.map(widthOf)) / 2, 40), holes: [] });
      }
    }
    return { roads, markings, lawns };
  }

  // ---- routes -------------------------------------------------------------------------
  // The lane (a polyline in the direction of travel) of a street driven away from node `nid`.
  function laneAway(L, st, nid, offset, crop) {
    const pts = lineFrom(L, st, nid);
    const far = nodeOf(L, otherEnd(st, nid));
    if (nodeKind(L, far, crop) === "border") pts.push(add(pts.at(-1), mul(unit(sub(pts.at(-1), pts.at(-2))), 1)));
    return offsetRight(pts, offset);
  }

  function laneOffsets(st) { return kindOf(st).lanes.map((x) => x + medianOf(st) / 2); }

  // Classifies every way out of a junction for a car coming in on street `inSt`: straight, left, right, uturn.
  function exitsOf(L, inSt, nid) {
    const tin = mul(along(lineFrom(L, inSt, nid), 1).t, -1);
    const found = {};
    for (const st of streetsAt(L, nid)) {
      if (st === inSt) continue;
      const tout = along(lineFrom(L, st, nid), 1).t;
      const a = turnAngle(tin, tout);
      const key = Math.abs(a) < 0.6 ? "straight" : Math.abs(a) > 2.6 ? null : a > 0 ? "left" : "right";
      if (!key) continue;
      const ideal = key === "straight" ? 0 : key === "left" ? Math.PI / 2 : -Math.PI / 2;
      if (!found[key] || Math.abs(a - ideal) < found[key].miss) found[key] = { street: st, angle: a, miss: Math.abs(a - ideal) };
    }
    found.uturn = { street: inSt, angle: Math.PI, miss: 0 };
    return found;
  }

  function bezier(p0, t0, p1, t1, n = 10) {
    const k = dist(p0, p1) * 0.5;
    const c0 = add(p0, mul(t0, k)), c1 = sub(p1, mul(t1, k)), out = [];
    for (let i = 1; i < n; i++) {
      const t = i / n, u = 1 - t;
      out.push([u * u * u * p0[0] + 3 * u * u * t * c0[0] + 3 * u * t * t * c1[0] + t * t * t * p1[0],
        u * u * u * p0[1] + 3 * u * u * t * c0[1] + 3 * u * t * t * c1[1] + t * t * t * p1[1]]);
    }
    return out;
  }

  // The path through node `nid` for a car on street `inSt` (lane offset `loIn`), out by `exit` (an exitsOf entry),
  // as points: the start (already on the lane), the junction, then `tail` metres along the way out.
  function through(L, inSt, nid, exitKey, exit, start, loIn, crop, tail = 20, inLaneIdx = null) {
    const n = nodeOf(L, nid), C = xy(n);
    const inLine = lineFrom(L, inSt, nid);
    const tin = mul(along(inLine, 1).t, -1);
    const outSt = exit.street;
    const outLanes = laneOffsets(outSt);
    const inLanes = laneOffsets(inSt);
    const resolvedInIdx = (inLaneIdx !== null && inLaneIdx !== undefined)
      ? inLaneIdx
      : Math.max(0, inLanes.findIndex((l) => Math.abs(l - loIn) < 0.05));
    const loOut = exitKey === "right" ? outLanes.at(-1)
      : (exitKey === "straight" && outLanes.length > 1 && resolvedInIdx > 0)
        ? outLanes[Math.min(outLanes.length - 1, resolvedInIdx)]
        : outLanes[0];
    const ring = n.ring;
    const pts = [start];
    if (ring) {
      // Round the island keeping it on the left: the angle around the centre goes down.
      const rl = (ring.r + ring.island) / 2;
      const inPt = sub(add(along(inLine, ring.r).p, mul(right(tin), loIn)), C);
      const aIn = Math.atan2(inPt[1], inPt[0]);
      const outLine = laneAway(L, outSt, nid, loOut, crop);
      const exitPt = along(outLine, ring.r).p;
      let aOut = Math.atan2(exitPt[1] - C[1], exitPt[0] - C[0]);
      const entry = add(along(inLine, ring.r + 3).p, mul(right(tin), loIn));
      pts.push(entry);
      let sweep = aIn - aOut;
      while (sweep <= 0.3) sweep += 2 * Math.PI;
      const steps = Math.max(4, Math.round(sweep / 0.25));
      for (let i = 0; i <= steps; i++) {
        const a = aIn - (sweep * i) / steps;
        pts.push([C[0] + Math.cos(a) * rl, C[1] + Math.sin(a) * rl]);
      }
      const dOut = ring.r + 3;
      for (const p of cut(outLine, dOut, dOut + tail)) pts.push(p);
      return { points: pts, outLanes: loOut };
    }
    const gapIn = Math.max(...streetsAt(L, nid).filter((s) => s !== inSt).map(widthOf)) / 2 + 0.5;
    const entry = add(along(inLine, gapIn).p, mul(right(tin), loIn));
    if (exitKey === "uturn") {
      const R = Math.max(2.6, loIn + 0.8);
      pts.push(entry);
      const c = add(C, mul(tin, -1.7));
      for (let i = 0; i <= 8; i++) {
        const a = (i / 8) * Math.PI;
        pts.push(add(c, add(mul(right(tin), R * Math.cos(a)), mul(tin, R * Math.sin(a)))));
      }
      const back = laneAway(L, inSt, nid, loOut, crop);
      for (const p of cut(back, gapIn + 3, gapIn + 3 + tail)) pts.push(p);
      return { points: pts };
    }
    const outLine = laneAway(L, outSt, nid, loOut, crop);
    const gapOut = widthOf(inSt) / 2 + 0.5;
    const ex = along(outLine, gapOut);
    pts.push(entry);
    if (exitKey !== "straight") pts.push(...bezier(entry, tin, ex.p, ex.t, 8));
    pts.push(ex.p);
    for (const p of cut(outLine, gapOut + 0.5, gapOut + tail)) pts.push(p);
    return { points: pts };
  }

  // Free question pose is separate from the entry street: roads/paint and the connector to the
  // continuous city stay unchanged. The pose is persisted in the layout, never inferred from a route.
  const isFreePlayer = (scene) => scene.layout?.player?.mode === "free";
  function playerPose(scene) {
    const pose = isFreePlayer(scene) && scene.layout.player.pose;
    return pose ? { x: Number(pose.x), z: Number(pose.z), yaw: Number(pose.yaw) || 0 }
      : { ...scene.stop, yaw: Number(scene.stop?.yaw) || 0 };
  }
  function setPlayerMode(scene, mode) {
    if (!scene.layout) return false;
    const plan = streetPlayerPlan(scene);
    if (!plan) return false;
    const pl = scene.layout.player = { ...(scene.layout.player || {}), street: plan.st.id, toward: plan.nid };
    if (mode === "free") {
      pl.pose = playerPose(scene);
      pl.mode = "free";
    } else {
      delete pl.mode;
      delete pl.pose;
    }
    return true;
  }
  // Explicit route edits are distinct from regenerated copies. Free-mode paths have their own
  // authored source, so moving the question never overwrites the street-mode author's route.
  function editPlayerRoute(scene, route) {
    if (!route) return;
    route.manual = true;
    delete route.auto;
    if (isFreePlayer(scene) && route.kind === "manoeuvre") route.playerFreeEdited = true;
  }
  function setPlayerRouteManual(scene, route, manual) {
    if (!route) return;
    if (manual) return editPlayerRoute(scene, route);
    if (scene.layout && route.kind === "manoeuvre") {
      if (isFreePlayer(scene)) (scene.layout.freePaths = scene.layout.freePaths || {})[route.exit] = null;
      else if (scene.layout.paths) delete scene.layout.paths[route.exit];
    }
    delete route.manual;
    delete route.playerFreeEdited;
    route.auto = true;
  }
  function pointInPolygon(p, poly) {
    let inside = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const a = poly[i], b = poly[j];
      if ((a[1] > p[1]) !== (b[1] > p[1]) && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
    }
    return inside;
  }
  function drivingArea(scene) {
    const generated = scene.layout ? generate(scene).roads : [];
    const roads = [...generated, ...(scene.roads || []).filter(r => !r.auto)];
    // build.py cuts islands out of the union, including the roads that enter a roundabout.
    const holes = roads.flatMap(r => r.holes || []);
    return (p) => !holes.some(h => pointInPolygon(p, h)) && roads.some(r => pointInPolygon(p, r.outer));
  }
  function footprintSupported(at, pose, halfWidth = 0.95, halfLength = 2.4) {
    const c = Math.cos(pose.yaw), n = Math.sin(pose.yaw);
    for (const u of [-halfWidth, 0, halfWidth]) for (const v of [-halfLength, 0, halfLength]) {
      if (!at([pose.x + u * c + v * n, pose.z - u * n + v * c])) return false;
    }
    return true;
  }
  function freePlayerSupported(scene, pose) { return footprintSupported(drivingArea(scene), pose); }
  function movePlayer(scene, point) {
    if (!isFreePlayer(scene)) return false;
    const next = { ...playerPose(scene), x: r3(point[0]), z: r3(point[1]) };
    if (!freePlayerSupported(scene, next)) return false;
    scene.layout.player.pose = next;
    return true;
  }
  function rotatePlayer(scene, yaw) {
    if (!isFreePlayer(scene)) return false;
    const next = { ...playerPose(scene), yaw: r3(wrap(yaw)) };
    if (!freePlayerSupported(scene, next)) return false;
    scene.layout.player.pose = next;
    return true;
  }
  function playerPlan(scene) {
    const plan = streetPlayerPlan(scene);
    if (!plan || !isFreePlayer(scene)) return plan;
    const p = playerPose(scene);
    return { ...plan, free: true, stop: [p.x, p.z], tin: [Math.sin(p.yaw), Math.cos(p.yaw)] };
  }

  // Polyline routes on the actual road area. Ring arcs use its legal direction; the small grid
  // search is a fallback for arbitrary junction/bend poses, never a change to authored geometry.
  const densePath = (pts, step = 1) => {
    const out = [pts[0]];
    for (let i = 1; i < pts.length; i++) {
      const count = Math.max(1, Math.ceil(dist(pts[i - 1], pts[i]) / step));
      for (let j = 1; j <= count; j++) out.push(add(pts[i - 1], mul(sub(pts[i], pts[i - 1]), j / count)));
    }
    return out.map(P).filter((p, i, a) => !i || dist(p, a[i - 1]) > 0.001);
  };
  function freeRoutes(scene, original) {
    const pose = playerPose(scene), stop = [pose.x, pose.z], toward = [Math.sin(pose.yaw), Math.cos(pose.yaw)];
    const at = drivingArea(scene);
    const radiusOK = (p, radius = 1.03) => {
      if (!at(p)) return false;
      for (let i = 0; i < 8; i++) if (!at(add(p, [Math.cos(i * Math.PI / 4) * radius, Math.sin(i * Math.PI / 4) * radius]))) return false;
      return true;
    };
    const clearLine = (a, b) => {
      const n = Math.max(1, Math.ceil(dist(a, b) / 0.65));
      for (let i = 0; i <= n; i++) if (!radiusOK(add(a, mul(sub(b, a), i / n)))) return false;
      return true;
    };
    const rings = scene.layout.nodes.filter(n => n.ring);
    const ringFor = (p) => rings.find(n => { const d = dist(p, xy(n)); return d > n.ring.island && d < n.ring.r + 0.1; });
    const sameRing = ringFor(stop);
    function ringPath(from, to) {
      const ring = sameRing;
      if (!ring) return null;
      const C = xy(ring), middle = (ring.ring.r + ring.ring.island) / 2;
      const near = (p) => { const v = sub(p, C), d = len(v); return add(C, mul(unit(v), d < ring.ring.r ? d : middle)); };
      const enter = near(from), leave = near(to);
      const a = Math.atan2(enter[1] - C[1], enter[0] - C[0]), b = Math.atan2(leave[1] - C[1], leave[0] - C[0]);
      let sweep = a - b;
      while (sweep < -0.001) sweep += 2 * Math.PI;
      const steps = Math.max(1, Math.ceil(sweep * middle));
      const arc = [];
      for (let i = 0; i <= steps; i++) {
        const t = i / steps, angle = a - sweep * t;
        const radius = len(sub(enter, C)) * (1 - t) + len(sub(leave, C)) * t;
        arc.push(add(C, [Math.cos(angle) * radius, Math.sin(angle) * radius]));
      }
      const path = densePath([from, ...arc, to]);
      return path.every(p => radiusOK(p)) ? path : null;
    }
    // A* on a one-and-a-half metre lattice. It is cached within a regeneration for every exit,
    // and stops early at the goal. Direction on a ring is constrained to keep the island on the left.
    const STEP = 1.5, cache = new Map();
    const pass = (x, z) => {
      const key = `${x},${z}`;
      if (!cache.has(key)) cache.set(key, radiusOK([x * STEP, z * STEP]));
      return cache.get(key);
    };
    function navigate(from, to) {
      if (dist(from, to) < 0.02) return [from, to];
      if (!ringFor(from) && !ringFor(to) && clearLine(from, to)) return densePath([from, to]);
      const around = (p) => {
        const cx = Math.round(p[0] / STEP), cz = Math.round(p[1] / STEP), found = [];
        for (let dx = -3; dx <= 3; dx++) for (let dz = -3; dz <= 3; dz++) if (pass(cx + dx, cz + dz)) {
          const q = [(cx + dx) * STEP, (cz + dz) * STEP];
          if (clearLine(p, q)) found.push({ x: cx + dx, z: cz + dz, d: dist(p, q) });
        }
        return found.sort((a, b) => a.d - b.d)[0];
      };
      const start = around(from), goal = around(to);
      if (!start || !goal) return null;
      const key = (x, z) => `${x},${z}`, goalKey = key(goal.x, goal.z), startKey = key(start.x, start.z);
      const open = [], records = new Map(), closed = new Set();
      const push = (v) => { let i = open.length; open.push(v); while (i) { const p = (i - 1) >> 1; if (open[p].f <= v.f) break; open[i] = open[p]; i = p; } open[i] = v; };
      const pop = () => { const v = open[0], end = open.pop(); if (open.length) { let i = 0; while (i * 2 + 1 < open.length) { let j = i * 2 + 1; if (j + 1 < open.length && open[j + 1].f < open[j].f) j++; if (open[j].f >= end.f) break; open[i] = open[j]; i = j; } open[i] = end; } return v; };
      const heuristic = (x, z) => Math.hypot(x - goal.x, z - goal.z);
      const first = { x: start.x, z: start.z, g: 0, f: heuristic(start.x, start.z), parent: null, key: startKey };
      records.set(startKey, first); push(first);
      let result = null, iterations = 0;
      while (open.length && iterations++ < 30000) {
        const node = pop();
        if (closed.has(node.key)) continue;
        if (node.key === goalKey) { result = node; break; }
        closed.add(node.key);
        const here = [node.x * STEP, node.z * STEP], ring = ringFor(here);
        for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) {
          if (!dx && !dz) continue;
          const x = node.x + dx, z = node.z + dz, k = key(x, z);
          if (closed.has(k) || !pass(x, z) || (dx && dz && (!pass(node.x + dx, node.z) || !pass(node.x, node.z + dz)))) continue;
          // a decreasing polar angle is the right-hand circulation used by through().
          if (ring) { const v = sub(here, xy(ring)); if (v[0] * dz - v[1] * dx > 0.1) continue; }
          const g = node.g + Math.hypot(dx, dz);
          if (records.has(k) && records.get(k).g <= g) continue;
          const next = { x, z, key: k, g, f: g + heuristic(x, z), parent: node };
          records.set(k, next); push(next);
        }
      }
      if (!result) return null;
      const points = [to];
      for (let n = result; n; n = n.parent) points.push([n.x * STEP, n.z * STEP]);
      points.push(from); points.reverse();
      const simple = [points[0]];
      for (let i = 0; i < points.length - 1;) {
        let j = Math.min(points.length - 1, i + 16);
        while (j > i + 1 && (!clearLine(points[i], points[j]) || (ringFor(points[i]) && j > i + 3))) j--;
        simple.push(points[j]); i = j;
      }
      return densePath(simple);
    }
    const errors = [];
    const ap = original.routes.find(r => r.kind === "approach");
    let back = add(stop, mul(toward, -3));
    if (!clearLine(back, stop)) back = add(stop, mul(toward, -0.4));
    let approach = null;
    if (sameRing) {
      // Original entry stop to the circulating lane, then round the island to the free pose.
      const ordinary = original.routes.find(r => r.kind === "manoeuvre");
      const firstRing = ordinary?.points.findIndex(p => ringFor(p) === sameRing);
      if (firstRing >= 0) {
        const arc = ringPath(ordinary.points[firstRing], back);
        if (arc) approach = [...ap.points, ...ordinary.points.slice(1, firstRing), ...arc, stop];
      }
    }
    if (!approach) {
      const enter = along(ap.points, Math.min(3.0, polyLen(ap.points) * 0.5)).p;
      const route = navigate(enter, back);
      approach = route ? [ap.points[0], ...route, stop] : null;
    }
    if (!approach) errors.push("Не удалось построить подъезд к месту игрока. Переместите машину или измените угол.");
    const routes = approach ? [{ ...ap, points: densePath(approach), playerFree: true }] : [];
    const entryPlan = streetPlayerPlan(scene);
    const exits = ["junction", "ring"].includes(entryPlan.kind) ? exitsOf(scene.layout, entryPlan.st, entryPlan.nid) : {};
    const freePaths = scene.layout.freePaths || {};
    const automatic = Object.values(freePaths).some(p => p === null)
      ? streetRoutes({ ...scene, layout: { ...scene.layout, paths: {} } }).routes : [];
    for (const source of original.routes.filter(r => r.kind === "manoeuvre")) {
      const freeOwn = freePaths[source.exit];
      const reset = Object.hasOwn(freePaths, source.exit) && freeOwn === null;
      const basis = reset ? (automatic.find(r => r.exit === source.exit) || source) : source;
      const r = { ...basis, points: basis.points.slice() };
      if (Array.isArray(freeOwn)) { r.points = freeOwn.map(P); r.manual = true; delete r.auto; }
      // A pose may be further along an exit than the old 20 m teaching arrow. Its new route
      // continues towards the border, instead of driving backwards to the arrow's former end.
      const out = exits[r.exit];
      if (out && !r.manual) {
        const line = lineFrom(scene.layout, out.street, entryPlan.nid);
        const centred = along(line, projectOn(line, r.points.at(-1)));
        const lateral = dot(sub(r.points.at(-1), centred.p), right(centred.t));
        const lane = laneAway(scene.layout, out.street, entryPlan.nid, lateral, scene.crop || 90);
        const former = projectOn(lane, r.points.at(-1));
        const tail = cut(lane, former + 0.1, polyLen(lane) - 3.3);
        if (tail.length) r.points.push(...tail);
      } else if (!r.manual && polyLen(r.points) > 3.4) {
        // A street without a junction already runs to its border. Keep the routing goal a car
        // length inside it; the world appends the continuous city after that border itself.
        r.points = cut(r.points, 0, polyLen(r.points) - 3.3);
      }
      const end = r.points.at(-1);
      let path = null;
      if (sameRing && !r.manual) {
        const lastRing = r.points.findLastIndex(p => ringFor(p) === sameRing);
        if (lastRing >= 0) {
          const arc = ringPath(stop, r.points[lastRing]);
          if (arc) path = [...arc, ...r.points.slice(lastRing + 1)];
        }
      }
      if (r.manual) {
        // Keep both author sources intact: street paths and explicit free-mode paths. A move
        // reanchors only the displayed/exported copy; an unchanged pose keeps edited vertices.
        if (dist(stop, r.points[0]) < 0.002) path = r.points.slice();
        else {
          let nearest = 0;
          for (let i = 1; i < r.points.length; i++) if (dist(stop, r.points[i]) < dist(stop, r.points[nearest])) nearest = i;
          const join = navigate(stop, r.points[nearest]);
          if (join) path = [...join, ...r.points.slice(nearest + 1)];
        }
      }
      if (!path && !r.manual) path = navigate(stop, end);
      if (path) routes.push({ ...r, points: densePath(path), playerFree: true });
      else errors.push(`Не удалось построить путь игрока: ${r.exit}. Переместите машину или измените угол.`);
    }
    return { ...original, routes, errors, stop: { x: r3(pose.x), z: r3(pose.z), yaw: r3(pose.yaw) } };
  }

  // The player's way: the street and the junction it leads to (past joints), the lane, the stop.
  function streetPlayerPlan(scene) {
    const L = scene.layout, crop = Number(scene.crop || 90);
    const pl = L.player && streetOf(L, L.player.street) ? L.player : defaultPlayer(L, crop);
    if (!pl) return null;
    const st = streetOf(L, pl.street);
    const nid = pl.toward;
    const n = nodeOf(L, nid);
    const q = (scene.question || {}).maneuver;
    const lanes = laneOffsets(st);
    const defaultLane = q === "right" ? lanes.length - 1 : 0;
    const laneIdx = (pl.lane !== undefined && pl.lane !== null) ? Number(pl.lane) : defaultLane;
    const safeLaneIdx = Math.max(0, Math.min(lanes.length - 1, laneIdx));
    const lo = lanes[safeLaneIdx] ?? lanes[0];
    const kind = nodeKind(L, n, crop);
    const inLine = lineFrom(L, st, nid);
    const total = polyLen(inLine);
    // Without a junction ahead the stop stands 10.7 m before the point of the road nearest to the centre
    // (the scene's middle, where the game lays the junction), as on a junction scene.
    const sd = kind === "junction" || kind === "ring" ? stopDistance(L, st, nid, crop)
      : Math.min(total - 2, projectOn(inLine, [0, 0]) + 10.7);
    // The car stands with its front at the stop line, not on it (the game puts its centre at the stop).
    const carD = Math.max(sd + CAR_BACK, Math.min(total - 1, Number(pl.questionAt) || sd + CAR_BACK));
    const s = along(inLine, carD);
    const tin = mul(s.t, -1);
    const stop = add(s.p, mul(right(tin), lo));
    return { st, nid, kind, lo, stop, tin, sd: carD, stopLineDistance: sd, total, lanes, laneIndex: safeLaneIdx };
  }

  // Without a choice: the street that comes in from the south side, driven north.
  function defaultPlayer(L, crop) {
    let best = null;
    for (const st of L.streets) {
      for (const nid of [st.a, st.b]) {
        const n = nodeOf(L, nid);
        if (Math.abs(n.z + crop) < 0.05) {
          const score = Math.abs(n.x);
          if (!best || score < best.score) best = { street: st.id, toward: otherEnd(st, nid), score };
        }
      }
    }
    if (!best && L.streets.length) {
      const st = L.streets[0];
      return { street: st.id, toward: st.b };
    }
    return best && { street: best.street, toward: best.toward };
  }

  function streetRoutes(scene) {
    const L = scene.layout, crop = Number(scene.crop || 90);
    const plan = streetPlayerPlan(scene);
    if (!plan) return { routes: [], stop: null, exitWidths: {}, approachWidth: 8.4 };
    const { st, nid, kind, lo, stop, tin, sd } = plan;
    const lane = offsetRight(lineFrom(L, st, otherEnd(st, nid)), lo);   // driving toward nid
    const laneTotal = polyLen(lane);
    const approach = cut(lane, Math.max(0, laneTotal - sd - 80), laneTotal - sd);
    const startNode = nodeOf(L, otherEnd(st, nid));
    if (nodeKind(L, startNode, crop) === "border" && approach.length) approach[0] = add(approach[0], mul(tin, -1));
    approach[approach.length - 1] = stop;
    const routes = [{ id: "approach", kind: "approach", auto: true, points: approach.map(P) }];
    const exitWidths = {};
    if (kind === "junction" || kind === "ring") {
      const exits = exitsOf(L, st, nid);
      for (const [key, ex] of Object.entries(exits)) {
        const r = through(L, st, nid, key, ex, stop, lo, crop, 20, plan.laneIndex);
        const tout = key === "uturn" ? mul(tin, -1) : along(lineFrom(L, ex.street, nid), 1).t;
        const own = (L.paths || {})[key];
        routes.push({ id: `manoeuvre_${key}`, kind: "manoeuvre", auto: !own, manual: !!own, exit: key, points: own ? own.map(P) : r.points.map(P),
          exitYaw: r3(key === "uturn" ? Math.PI : wrap(heading(tout) - heading(tin))) });
        exitWidths[key] = widthOf(ex.street);
      }
    } else {
      // No junction ahead: the road goes on (a bend or a straight). One way, called by its turn.
      const ahead = [stop];
      const inLine = lineFrom(L, st, nid);
      for (const p of offsetRight(cut(inLine, 0, plan.sd).reverse(), lo).slice(1)) ahead.push(p);
      let cur = st, at = nid, guard = 0;
      while (guard++ < 20 && nodeKind(L, nodeOf(L, at), crop) === "joint") {
        const nxt = streetsAt(L, at).find((s) => s !== cur);
        if (!nxt) break;
        for (const p of laneAway(L, nxt, at, lo, crop).slice(1)) ahead.push(p);
        cur = nxt;
        at = otherEnd(nxt, at);
      }
      const tout = unit(sub(ahead.at(-1), ahead.at(-2) || ahead[0]));
      const a = turnAngle(tin, tout);
      const key = Math.abs(a) < 0.6 ? "straight" : a > 0 ? "left" : "right";
      routes.push({ id: `manoeuvre_${key}`, kind: "manoeuvre", auto: true, exit: key, points: ahead.map(P), exitYaw: r3(wrap(heading(tout) - heading(tin))) });
      exitWidths[key] = widthOf(cur);
    }
    return {
      routes, exitWidths, approachWidth: widthOf(st),
      stop: { x: r3(stop[0]), z: r3(stop[1]), yaw: r3(heading(tin)) },
    };
  }

  function generateRoutes(scene) {
    const ordinary = streetRoutes(scene);
    return isFreePlayer(scene) && ordinary.stop ? freeRoutes(scene, ordinary) : ordinary;
  }

  // Replaces the generated items of a scene by the plan's (the user's own roads, marks, routes stay).
  function apply(scene) {
    if (!scene.layout) return scene;
    if (!scene.layout.streets.length) {
      // Every street removed: what the plan made goes too (the stop stays where it was).
      for (const key of ["roads", "markings", "lawns", "routes"]) scene[key] = (scene[key] || []).filter((x) => !x.auto);
      return scene;
    }
    // A manoeuvre edited by hand keeps its points (layout.paths): its drawn route is the source.
    for (const x of scene.routes || []) {
      if (x.kind !== "manoeuvre" || !x.manual) continue;
      if (!x.playerFree) (scene.layout.paths = scene.layout.paths || {})[x.exit] = x.points.map(P);
      else if (isFreePlayer(scene) && x.playerFreeEdited) (scene.layout.freePaths = scene.layout.freePaths || {})[x.exit] = x.points.map(P);
    }
    const g = generate(scene);
    const r = generateRoutes(scene);
    const mine = (list) => (list || []).filter((x) => !x.auto);
    scene.roads = [...g.roads, ...mine(scene.roads)];
    scene.markings = [...g.markings, ...mine(scene.markings)];
    scene.lawns = [...g.lawns, ...mine(scene.lawns)];
    const userRoutes = (scene.routes || []).filter((x) => !(x.auto || x.kind === "approach" || x.kind === "manoeuvre"));
    scene.routes = [...r.routes, ...userRoutes];
    if (r.stop) scene.stop = r.stop;
    if (r.errors?.length) scene.playerRouteErrors = r.errors; else delete scene.playerRouteErrors;
    scene.exitWidths = r.exitWidths;
    scene.approachWidth = r.approachWidth;
    // The question's manoeuvre must be one the plan has.
    const ways = r.routes.filter((x) => x.kind === "manoeuvre").map((x) => x.exit);
    if (!isFreePlayer(scene) && scene.question && ways.length && !ways.includes(scene.question.maneuver)) scene.question.maneuver = ways.includes("straight") ? "straight" : ways[0];
    return applyActors(scene);
  }

  // A participant follows the plan: its path is rebuilt from its place and the way it was asked to go.
  // `plan`: a scene with a layout to find the lanes in (a traced scene lends its detected plan).
  function applyActors(scene, plan = scene) {
    if (!plan.layout || !plan.layout.streets.length) return scene;
    for (const a of scene.actors || []) {
      if (!a.way) continue;
      const rid = `actor_${a.id}`;
      const existing = (scene.routes || []).find((x) => x.id === rid);
      if (existing && existing.manual) continue;
      const path = pathFrom(plan, a.pos, a.yaw, a.way);
      if (!path) continue;
      scene.routes = scene.routes.filter((x) => x.id !== rid);
      scene.routes.push({ id: rid, kind: "actor", auto: true, points: path.map(P) });
      a.route = rid;
      a.pos = P(path[0]);
    }
    return scene;
  }

  // ---- lanes: where a car dropped on the road stands and where it can go ---------------------
  // The nearest lane to a point: the street, the node it drives to, the point on the lane and the heading.
  function nearestLane(scene, p, preferYaw = null) {
    const L = scene.layout;
    if (!L) return null;
    let best = null;
    for (const st of L.streets) {
      for (const nid of [st.a, st.b]) {
        for (const lo of laneOffsets(st)) {
          const lane = offsetRight(lineFrom(L, st, otherEnd(st, nid)), lo);   // toward nid
          for (let i = 0; i + 1 < lane.length; i++) {
            const a = lane[i], b = lane[i + 1], ab = sub(b, a), l2 = dot(ab, ab) || 1;
            const t = Math.max(0, Math.min(1, dot(sub(p, a), ab) / l2));
            const q = add(a, mul(ab, t));
            const t1 = unit(ab);
            let d = dist(p, q);
            if (preferYaw !== null && Math.cos(heading(t1) - preferYaw) < 0) d += 6;
            if (!best || d < best.d) best = { d, street: st, toward: nid, point: q, t: t1, lo, yaw: heading(t1) };
          }
        }
      }
    }
    return best;
  }

  // The ways a car on that lane can take at the junction ahead.
  function waysFrom(scene, p, yaw) {
    const hit = nearestLane(scene, p, yaw);
    if (!hit) return [];
    const L = scene.layout, crop = Number(scene.crop || 90);
    const n = nodeOf(L, hit.toward), kind = nodeKind(L, n, crop);
    if (kind !== "junction" && kind !== "ring") return ["straight"];
    return Object.keys(exitsOf(L, hit.street, hit.toward));
  }

  // A participant's path from where it stands, through the junction ahead, the given way.
  function pathFrom(scene, p, yaw, way) {
    const hit = nearestLane(scene, p, yaw);
    if (!hit || hit.d > 6) return null;
    const L = scene.layout, crop = Number(scene.crop || 90);
    const n = nodeOf(L, hit.toward), kind = nodeKind(L, n, crop);
    if (kind !== "junction" && kind !== "ring") {
      const lane = laneAway(L, hit.street, otherEnd(hit.street, hit.toward), hit.lo, crop);
      const at = projectOn(lane, hit.point);
      return [hit.point, ...cut(lane, at + 0.5, at + 60)];
    }
    const exits = exitsOf(L, hit.street, hit.toward);
    const ex = exits[way] || exits.straight || Object.values(exits)[0];
    const key = exits[way] ? way : Object.keys(exits).find((k) => exits[k] === ex);
    return through(L, hit.street, hit.toward, key, ex, hit.point, hit.lo, crop, 40).points;
  }

  function projectOn(pts, p) {
    let acc = 0, best = { d: Infinity, at: 0 };
    for (let i = 0; i + 1 < pts.length; i++) {
      const a = pts[i], b = pts[i + 1], ab = sub(b, a), l = len(ab) || 1;
      const t = Math.max(0, Math.min(1, dot(sub(p, a), ab) / (l * l)));
      const d = dist(p, add(a, mul(ab, t)));
      if (d < best.d) best = { d, at: acc + t * l };
      acc += l;
    }
    return best.at;
  }

  // A point on a dividing strip (signs and lights stand there where they are put).
  function onMedian(scene, p) {
    for (const r of scene.roads || []) {
      if (!r.green) continue;
      for (const h of r.holes || []) {
        let c = false;
        for (let i = 0, j = h.length - 1; i < h.length; j = i++) {
          const [xi, zi] = h[i], [xj, zj] = h[j];
          if ((zi > p[1]) !== (zj > p[1]) && p[0] < ((xj - xi) * (p[1] - zi)) / (zj - zi) + xi) c = !c;
        }
        if (c) return true;
      }
    }
    return false;
  }

  // ---- pedestrians: across the road by the nearest zebra --------------------------------------
  // From where the person stands to the near end of the zebra, over it, and a few steps on.
  function zebraPath(scene, p) {
    let best = null;
    for (const m of scene.markings || []) {
      if (m.type !== "zebra" || !m.points || m.points.length < 2) continue;
      const [a, b] = m.points;
      const near = dist(p, a) < dist(p, b) ? [a, b] : [b, a];
      const d = dist(p, near[0]);
      if (!best || d < best.d) best = { d, from: near[0], to: near[1] };
    }
    if (!best || best.d > 40) return null;
    const t = unit(sub(best.to, best.from));
    const start = sub(best.from, mul(t, 1.5)), end = add(best.to, mul(t, 1.5));
    return [P(p), P(start), P(end), P(add(end, mul(t, 4)))];
  }

  // ---- editing the plan ---------------------------------------------------------------
  let counter = 0;
  function newId(L, prefix) {
    const taken = new Set([...L.nodes.map((n) => n.id), ...L.streets.map((s) => s.id)]);
    let id;
    do { id = `${prefix}${++counter}`; } while (taken.has(id));
    return id;
  }

  // Snaps a point the way a city builder does: to a node, onto a street, to the middle of a side, to the border.
  function snapPoint(scene, p, opts = {}) {
    const L = scene.layout, crop = Number(scene.crop || 90);
    for (const n of L.nodes) if (n.id !== opts.except && dist(p, xy(n)) < NODE_SNAP) return { p: xy(n), node: n.id };
    const ports = [[0, crop], [0, -crop], [crop, 0], [-crop, 0]];
    for (const q of ports) if (dist(p, q) < PORT_SNAP) return { p: q, port: true };
    for (const st of L.streets) {
      if (opts.exceptStreet && st.id === opts.exceptStreet) continue;
      const line = centreline(L, st);
      const at = projectOn(line, p);
      const q = along(line, at).p;
      const total = polyLen(line);
      if (dist(p, q) < STREET_SNAP + widthOf(st) / 2 && at > 3 && at < total - 3) return { p: q, street: st.id, at };
    }
    let q = [...p];
    if (Math.abs(Math.abs(q[0]) - crop) < 3) q[0] = Math.sign(q[0]) * crop;
    if (Math.abs(Math.abs(q[1]) - crop) < 3) q[1] = Math.sign(q[1]) * crop;
    q = [Math.max(-crop, Math.min(crop, q[0])), Math.max(-crop, Math.min(crop, q[1]))];
    return { p: q };
  }

  // Splits a street at distance `at` along it: a new node there, two streets in its place.
  function splitStreet(L, sid, at) {
    const st = streetOf(L, sid);
    const line = centreline(L, st);
    const q = along(line, at).p;
    const nid = newId(L, "n");
    L.nodes.push({ id: nid, x: r3(q[0]), z: r3(q[1]) });
    const second = { ...JSON.parse(JSON.stringify(st)), id: newId(L, "s"), a: nid, b: st.b, bend: null };
    st.b = nid;
    st.bend = null;
    const ends = st.ends || {};
    st.ends = { a: ends.a || {} };
    second.ends = { b: ends.b || {} };
    L.streets.push(second);
    if (L.player && L.player.street === st.id && L.player.toward === second.b) L.player = { street: second.id, toward: second.b };
    return nid;
  }

  // A node at a snapped point (made, found, or split into a street).
  function nodeAt(L, snapped) {
    if (snapped.node) return snapped.node;
    if (snapped.street) return splitStreet(L, snapped.street, snapped.at);
    const nid = newId(L, "n");
    L.nodes.push({ id: nid, x: r3(snapped.p[0]), z: r3(snapped.p[1]) });
    return nid;
  }

  // Lays a street from a to b (points), crossing the streets on its way: each crossing becomes a junction.
  function addStreet(scene, a, b, kind = "street") {
    const L = scene.layout;
    const sa = snapPoint(scene, a), sb = snapPoint(scene, b);
    if (dist(sa.p, sb.p) < 3) return null;
    // Crossings with straight streets along the new one (not at its ends).
    const hits = [];
    for (const st of L.streets) {
      if (st.bend) continue;
      const A = xy(nodeOf(L, st.a)), B = xy(nodeOf(L, st.b));
      const x = segCross(sa.p, sb.p, A, B);
      if (x && x.t > 0.04 && x.t < 0.96 && x.u > 0.02 && x.u < 0.98) hits.push({ st, t: x.t, u: x.u, len: dist(A, B) });
    }
    const na = nodeAt(L, sa);
    const nb = nodeAt(L, sb);
    const chain = [na];
    hits.sort((x, y) => x.t - y.t);
    for (const h of hits) {
      const cur = L.streets.find((s) => s.id === h.st.id);
      chain.push(splitStreet(L, cur.id, h.u * h.len));
    }
    chain.push(nb);
    const made = [];
    for (let i = 0; i + 1 < chain.length; i++) {
      if (chain[i] === chain[i + 1]) continue;
      const exists = L.streets.find((s) => (s.a === chain[i] && s.b === chain[i + 1]) || (s.b === chain[i] && s.a === chain[i + 1]));
      if (exists) continue;
      const st = { id: newId(L, "s"), a: chain[i], b: chain[i + 1], kind, ends: {} };
      L.streets.push(st);
      made.push(st.id);
    }
    tidy(L);
    return made;
  }

  function segCross(p, q, a, b) {
    const r = sub(q, p), s = sub(b, a), d = r[0] * s[1] - r[1] * s[0];
    if (Math.abs(d) < 1e-9) return null;
    const ap = sub(a, p);
    const t = (ap[0] * s[1] - ap[1] * s[0]) / d, u = (ap[0] * r[1] - ap[1] * r[0]) / d;
    return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? { t, u } : null;
  }

  // Removes a street; nodes left without streets go too, and a joint between two straight streets is healed.
  function removeStreet(scene, sid) {
    const L = scene.layout;
    L.streets = L.streets.filter((s) => s.id !== sid);
    tidy(L);
  }

  function removeNode(scene, nid) {
    const L = scene.layout;
    L.streets = L.streets.filter((s) => s.a !== nid && s.b !== nid);
    tidy(L);
  }

  function tidy(L) {
    L.nodes = L.nodes.filter((n) => L.streets.some((s) => s.a === n.id || s.b === n.id));
    if (L.player && !streetOf(L, L.player.street)) delete L.player;
  }

  // Moves a node (snapped to the border's middle or the border when near it).
  function moveNode(scene, nid, p) {
    const L = scene.layout, crop = Number(scene.crop || 90);
    const n = nodeOf(L, nid);
    const s = snapPoint(scene, p, { except: nid, exceptStreet: "__none" });
    let q = s.node ? p : s.p;
    q = [Math.max(-crop, Math.min(crop, q[0])), Math.max(-crop, Math.min(crop, q[1]))];
    // Bends move with their streets' ends: half of the node's move.
    const d = sub(q, xy(n));
    for (const st of streetsAt(L, nid)) if (st.bend) st.bend = P(add(st.bend, mul(d, 0.5)));
    n.x = r3(q[0]);
    n.z = r3(q[1]);
  }

  // Joins two nodes into one (the dragged node dropped on another).
  function mergeNodes(scene, from, into) {
    const L = scene.layout;
    if (from === into) return;
    for (const st of L.streets) {
      if (st.a === from) st.a = into;
      if (st.b === from) st.b = into;
    }
    L.streets = L.streets.filter((s) => s.a !== s.b);
    if (L.player && L.player.toward === from) L.player.toward = into;
    tidy(L);
  }

  // ---- ready-made plans -----------------------------------------------------------------
  function template(kind, crop = 90) {
    const N = (id, x, z) => ({ id, x, z });
    const S = (id, a, b, extra = {}) => ({ id, a, b, kind: "street", ends: {}, ...extra });
    const c = N("c", 0, 0), s = N("s", 0, -crop), n = N("n", 0, crop), e = N("e", crop, 0), w = N("w", -crop, 0);
    const stopEnd = { b: { stop: true } };
    let L;
    if (kind === "cross") L = { nodes: [c, s, n, e, w], streets: [S("s1", "s", "c", { ends: stopEnd }), S("s2", "c", "n"), S("s3", "c", "e"), S("s4", "c", "w")] };
    else if (kind === "tee-left") L = { nodes: [c, s, n, e], streets: [S("s1", "s", "c", { ends: stopEnd }), S("s2", "c", "n"), S("s3", "c", "e")] };
    else if (kind === "tee-right") L = { nodes: [c, s, n, w], streets: [S("s1", "s", "c", { ends: stopEnd }), S("s2", "c", "n"), S("s4", "c", "w")] };
    else if (kind === "tee") L = { nodes: [c, s, e, w], streets: [S("s1", "s", "c", { ends: stopEnd }), S("s3", "c", "e"), S("s4", "c", "w")] };
    else if (kind === "ring") L = { nodes: [{ ...c, ring: { r: 20, island: 9 } }, s, n, e, w], streets: [S("s1", "s", "c"), S("s2", "c", "n"), S("s3", "c", "e"), S("s4", "c", "w")] };
    else if (kind === "bend-left") L = { nodes: [s, e], streets: [S("s1", "s", "e", { bend: [0, 0] })] };
    else if (kind === "bend-right") L = { nodes: [s, w], streets: [S("s1", "s", "w", { bend: [0, 0] })] };
    else if (kind === "straight") L = { nodes: [s, n], streets: [S("s1", "s", "n")] };
    else if (kind === "yard-left") L = { nodes: [c, s, n, e], streets: [S("s1", "s", "c", { ends: stopEnd }), S("s2", "c", "n"), S("s3", "c", "e", { kind: "yard" })] };
    else if (kind === "yard-right") L = { nodes: [c, s, n, w], streets: [S("s1", "s", "c", { ends: stopEnd }), S("s2", "c", "n"), S("s4", "c", "w", { kind: "yard" })] };
    else if (kind === "median") L = { nodes: [c, s, n, e, w], streets: [S("s1", "s", "c", { ends: stopEnd, median: 3 }), S("s2", "c", "n", { median: 3 }), S("s3", "c", "e"), S("s4", "c", "w")] };
    else if (kind === "avenue") L = { nodes: [c, s, n, e, w], streets: [S("s1", "s", "c", { ends: stopEnd }), S("s2", "c", "n"), S("s3", "c", "e", { kind: "avenue" }), S("s4", "c", "w", { kind: "avenue" })] };
    else return null;
    L.player = { street: "s1", toward: L.streets[0].b };
    return JSON.parse(JSON.stringify(L));
  }

  const TEMPLATES = [
    { id: "cross", title: "Перекрёсток" },
    { id: "tee", title: "Т-образный" },
    { id: "tee-left", title: "Примыкание слева" },
    { id: "tee-right", title: "Примыкание справа" },
    { id: "ring", title: "Кольцо" },
    { id: "avenue", title: "С проспектом" },
    { id: "median", title: "С разделительной полосой" },
    { id: "yard-left", title: "Выезд со двора слева" },
    { id: "yard-right", title: "Выезд со двора справа" },
    { id: "bend-left", title: "Поворот налево" },
    { id: "bend-right", title: "Поворот направо" },
    { id: "straight", title: "Прямая" },
  ];

  // A small picture of a plan (SVG, the player's side at the bottom), for the template gallery and cards.
  function svg(L, crop = 90, size = 96) {
    const k = size / (2 * crop);
    // Plan view as in the editor: +z up, +x (driver's left) to the left.
    const X = (x) => (size / 2 - x * k).toFixed(1), Y = (z) => (size / 2 - z * k).toFixed(1);
    const parts = [];
    for (const st of L.streets) {
      const pts = centreline(L, st, 12);
      const d = pts.map((p, i) => `${i ? "L" : "M"}${X(p[0])} ${Y(p[1])}`).join(" ");
      parts.push(`<path d="${d}" stroke="#2c2f36" stroke-width="${(widthOf(st) * k * 1.6).toFixed(1)}" fill="none" stroke-linecap="butt"/>`);
    }
    for (const n of L.nodes) {
      const deg = L.streets.filter((s) => s.a === n.id || s.b === n.id).length;
      if (n.ring) {
        parts.push(`<circle cx="${X(n.x)}" cy="${Y(n.z)}" r="${(n.ring.r * k * 1.2).toFixed(1)}" fill="#2c2f36"/>`);
        parts.push(`<circle cx="${X(n.x)}" cy="${Y(n.z)}" r="${(n.ring.island * k * 1.2).toFixed(1)}" fill="#86a97a"/>`);
      } else if (deg >= 2) {
        const w = Math.max(...L.streets.filter((s) => s.a === n.id || s.b === n.id).map(widthOf));
        parts.push(`<circle cx="${X(n.x)}" cy="${Y(n.z)}" r="${(w * k * 0.8).toFixed(1)}" fill="#2c2f36"/>`);
      }
    }
    if (L.player) {
      const st = L.streets.find((s) => s.id === L.player.street);
      if (st) {
        const line = lineFrom(L, st, otherEnd(st, L.player.toward));
        const lane = offsetRight(line, 1.8 * 1.6);
        const a = along(lane, Math.max(4, polyLen(lane) * 0.25)).p, b = along(lane, polyLen(lane) * 0.62).p;
        parts.push(`<path d="M${X(a[0])} ${Y(a[1])} L${X(b[0])} ${Y(b[1])}" stroke="#ffa53c" stroke-width="${(size / 28).toFixed(1)}" stroke-linecap="round" marker-end="url(#ah)"/>`);
      }
    }
    return `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg"><defs><marker id="ah" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="3" markerHeight="3" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="#ffa53c"/></marker></defs><rect width="${size}" height="${size}" rx="${size / 8}" fill="#cfe0c3"/>${parts.join("")}</svg>`;
  }

  return {
    medianOf, onMedian, KINDS, TEMPLATES, generate, generateRoutes, apply, template, svg, centreline, nodeKind, widthOf,
    applyActors, nearestLane, waysFrom, pathFrom, zebraPath, stopDistance, endOffset, endOffsetLimits, setEndOffset, snapPoint, addStreet, removeStreet, removeNode, moveNode, mergeNodes,
    splitStreet, streetsAt, nodeOf, streetOf, playerPlan, lineFrom, along, polyLen, offsetRight, heading, laneOffsets,
    isFreePlayer, playerPose, setPlayerMode, movePlayer, rotatePlayer, freePlayerSupported, editPlayerRoute, setPlayerRouteManual,
  };
})();

if (typeof module !== "undefined" && module.exports) module.exports = Layout;
