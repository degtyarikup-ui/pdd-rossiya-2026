// Shared framing math, kept independent of Three.js so authoring can be checked without a renderer.
// centre is the horizontal centre of the picture ABOVE the card; elevation is its world height.
const QuestionCamera = (() => {
  const PHONE_H = 844, DEFAULT_PITCH = Math.atan2(42, 44), DISTANCE = Math.hypot(42, 44);
  const MIN_PITCH = Math.PI / 18, MAX_PITCH = 85 * Math.PI / 180;
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const finite = (v, fallback) => Number.isFinite(v) ? v : fallback;
  const wrap = v => Math.atan2(Math.sin(v), Math.cos(v));
  function normalize(view = {}) {
    return { ...view, centre: [finite(view.centre?.[0], 0), finite(view.centre?.[1], 0)],
      height: Math.max(1.5, finite(view.height, 24)), card: clamp(finite(view.card, 280), 0, 560),
      yaw: wrap(finite(view.yaw, 0)), pitch: clamp(finite(view.pitch, DEFAULT_PITCH), MIN_PITCH, MAX_PITCH),
      elevation: clamp(finite(view.elevation, 0), 0, 30) };
  }
  function pose(view) {
    const q = normalize(view), sy = Math.sin(q.yaw), cy = Math.cos(q.yaw), sp = Math.sin(q.pitch), cp = Math.cos(q.pitch);
    const free = Math.max(0.3, 1 - q.card / PHONE_H), size = q.height / free;
    const shift = (1 - free) * size * 0.5 / sp;
    const look = [q.centre[0] - sy * shift, q.elevation, q.centre[1] - cy * shift];
    return { size, free, look, position: [look[0] - sy * cp * DISTANCE, look[1] + sp * DISTANCE, look[2] - cy * cp * DISTANCE] };
  }
  function pan(view, dx, dy, pixelsHigh) {
    const q = normalize(view), k = pose(q).size / Math.max(1, pixelsHigh), sy = Math.sin(q.yaw), cy = Math.cos(q.yaw);
    const along = dy * k / Math.sin(q.pitch);
    return { ...q, centre: [q.centre[0] + cy * dx * k + sy * along, q.centre[1] - sy * dx * k + cy * along] };
  }
  function orbit(view, dx, dy) {
    const q = normalize(view);
    return normalize({ ...q, yaw: q.yaw - dx * 0.008, pitch: q.pitch + dy * 0.008 });
  }
  function zoom(view, factor) { const q = normalize(view); return { ...q, height: clamp(q.height * factor, 1.5, 140) }; }
  function viewport(view, width, height, rect) {
    const vertical = pose(view).size * height / rect.h, horizontal = vertical * width / height;
    const x = (width / 2 - rect.x - rect.w / 2) * vertical / height;
    const y = (rect.y + rect.h / 2 - height / 2) * vertical / height;
    return { left: -horizontal / 2 + x, right: horizontal / 2 + x, top: vertical / 2 + y, bottom: -vertical / 2 + y };
  }
  return { PHONE_H, DEFAULT_PITCH, DISTANCE, MIN_PITCH, MAX_PITCH, normalize, pose, pan, orbit, zoom, viewport };
})();
if (typeof module !== "undefined") module.exports = QuestionCamera;
