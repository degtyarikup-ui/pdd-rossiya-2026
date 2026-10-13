// The object's position is always the roadside support; reach locates the board over the road.
const SignMount = (() => {
  const number = (value, fallback, min, max) => Number.isFinite(Number(value)) ? Math.max(min, Math.min(max, Number(value))) : fallback;
  const FACE_KEYS = ['code', 'plate', 'plateSign', 'mainRoad', 'roads', 'laneDirections'];
  // Saved order is explicit: the primary face is at the top, secondSign below it.
  const faces = o => [o, o.secondSign].filter(face => face && typeof face.code === 'string' && face.code);
  const faceCopy = face => Object.fromEntries(FACE_KEYS.filter(key => face[key] !== undefined).map(key => [key, JSON.parse(JSON.stringify(face[key]))]));
  function replaceFace(target, source) {
    for (const key of FACE_KEYS) delete target[key];
    Object.assign(target, faceCopy(source));
  }
  function swapFaces(o) {
    if (!o.secondSign) return;
    const top = faceCopy(o), bottom = faceCopy(o.secondSign);
    replaceFace(o, bottom); o.secondSign = top;
  }
  function layout(o, boardHeight = 3, topFaceHeight = boardHeight) {
    const overhead = o.mount === 'cantilever';
    const reach = number(o.reach ?? 4.5, 4.5, 0.5, 15);
    const bottom = overhead ? number(o.clearance ?? 5.5, 5.5, 5, 8) : 2.2;
    const side = o.armSide === 'right' ? -1 : 1;
    return { overhead, reach, bottom, side, x: overhead ? side * reach : 0,
      postHeight: overhead ? bottom + boardHeight + 0.3 : bottom + boardHeight - topFaceHeight * 0.5,
      armLength: reach + 1.7 };
  }
  return { layout, faces, faceCopy, replaceFace, swapFaces };
})();
if (typeof module !== 'undefined') module.exports = SignMount;
