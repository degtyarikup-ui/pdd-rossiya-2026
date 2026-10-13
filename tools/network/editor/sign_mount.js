// The object's position is always the roadside support; reach locates the board over the road.
const SignMount = (() => {
  const number = (value, fallback, min, max) => Number.isFinite(Number(value)) ? Math.max(min, Math.min(max, Number(value))) : fallback;
  function layout(o, boardHeight = 3) {
    const overhead = o.mount === 'cantilever';
    const reach = number(o.reach ?? 4.5, 4.5, 0.5, 15);
    const bottom = overhead ? number(o.clearance ?? 5.5, 5.5, 5, 8) : 2.2;
    const side = o.armSide === 'right' ? -1 : 1;
    return { overhead, reach, bottom, side, x: overhead ? side * reach : 0,
      postHeight: overhead ? bottom + boardHeight + 0.3 : bottom + boardHeight * 0.5,
      armLength: reach + 1.7 };
  }
  return { layout };
})();
if (typeof module !== 'undefined') module.exports = SignMount;
