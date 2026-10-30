// The object's position is always the roadside support; reach locates the board over the road.
const SignMount = (() => {
  const number = (value, fallback, min, max) => Number.isFinite(Number(value)) ? Math.max(min, Math.min(max, Number(value))) : fallback;
  const NUMBER_SPECS = {"3.24":{"rect":[27,33,46,34],"default":50,"unit":"км/ч","size":[100.0,86.0],"angle":0},"3.25":{"rect":[27,33,46,34],"default":50,"unit":"км/ч","size":[100.0,86.0],"angle":0},"3.11":{"rect":[28,31,29,42],"default":7,"unit":"т","size":[100.0,86.0],"angle":0},"3.12":{"rect":[35,20,22,29],"default":6,"unit":"т","size":[100.0,86.0],"angle":0},"3.13":{"rect":[29,24,42,35],"default":4.5,"unit":"м","size":[100.0,86.0],"angle":0},"3.14":{"rect":[28,28,44,34],"default":2.7,"unit":"м","size":[100.0,86.0],"angle":0},"3.15":{"rect":[37,57,26,19],"default":10,"unit":"м","size":[100.0,86.0],"angle":0},"3.16":{"rect":[34,20,27,19],"default":70,"unit":"м","size":[100.0,86.0],"angle":0},"4.6":{"rect":[26,30,48,37],"default":50,"unit":"км/ч","size":[100.0,86.0],"angle":0},"4.7":{"rect":[26,30,48,37],"default":50,"unit":"км/ч","size":[100.0,86.0],"angle":0},"6.2":{"rect":[23,29,54,43],"default":50,"unit":"км/ч","size":[100.0,86.0],"angle":0},"6.3.2":{"rect":[20,38,18,17],"default":15,"unit":"м","size":[100.0,86.0],"angle":0},"8.1.1":{"rect":[12,29,55,42],"default":300,"unit":"м","size":[115.0,86.0],"angle":0},"8.1.2":{"rect":[13,52,54,32],"default":250,"unit":"м","size":[115.0,120.0],"angle":0},"8.1.3":{"rect":[7,29,37,43],"default":100,"unit":"м","size":[115.0,71.0],"angle":0},"8.1.4":{"rect":[36,27,41,46],"default":300,"unit":"м","size":[115.0,71.0],"angle":0},"8.2.1":{"rect":[23,25,36,46],"default":100,"unit":"м","size":[102.0,52.0],"angle":0},"8.2.2":{"rect":[22,50,57,24],"default":10,"unit":"м","size":[52.0,102.0],"angle":0},"8.2.5":{"rect":[6,27,29,46],"default":30,"unit":"м","size":[102.0,52.0],"angle":0},"8.2.6":{"rect":[50,27,28,46],"default":25,"unit":"м","size":[102.0,52.0],"angle":0},"1.13":{"rect":[35,47,22,18],"default":12,"unit":"%","size":[100.0,86.0],"angle":22},"1.14":{"rect":[31,52,22,18],"default":10,"unit":"%","size":[100.0,86.0],"angle":-22}};
  const FACE_KEYS = ['code', 'plate', 'plateSign', 'mainRoad', 'roads', 'laneDirections', 'zoneVariant', 'number'];
  const numeric = code => !!NUMBER_SPECS[code];
  const numberSpec = code => NUMBER_SPECS[code];
  const validNumber = (value, code='3.24') => Number.isFinite(value) && value > 0 && value <= (['3.24','3.25','4.6','4.7','6.2'].includes(code)?150:99999) && (['3.24','3.25','4.6','4.7','6.2'].includes(code)?Number.isInteger(value):Number.isInteger(Math.round(value*100000)/1000));
  const textureCode = face => numeric(face.code) && validNumber(face.number,face.code) ? `${face.code}_${face.number}` : face.code==='5.33' && face.zoneVariant==='plain' ? '5.33_plain' : face.code;
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
  const plateWidth = (main, plate) => Math.min(main[0] * .8 / plate[0], main[1] * .95 / plate[1]);
  return { numberSpec, numeric, validNumber, layout, plateWidth, faces, faceCopy, replaceFace, swapFaces, textureCode };
})();
if (typeof module !== 'undefined') module.exports = SignMount;
