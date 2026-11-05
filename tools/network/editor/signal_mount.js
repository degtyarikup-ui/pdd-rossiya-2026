/* Signal faces point towards +Z. Positions remain anchored at the roadside pole. */
const SignalMount = (() => {
  const states = [
    {value:"off",title:"Выкл.",glyph:"× ↓"},
    {value:"red",title:"Закрыто",glyph:"×",colour:"#ff3838"},
    {value:"green",title:"Открыто",glyph:"↓",colour:"#36ff88"},
    {value:"yellow_left",title:"Перестроиться влево",glyph:"↙",colour:"#ffd52a"},
    {value:"yellow_right",title:"Перестроиться вправо",glyph:"↘",colour:"#ffd52a"},
  ];
  function layout(o) {
    const overhead = o.mount === "cantilever", reverse = !!o.reversible;
    const info = !reverse && !o.tram && Object.values(o.pedestrianSections || {}).some(v => ["off","on","flashing"].includes(v));
    const minY = info ? 1.745 : !reverse && o.tram ? 1.91 : 2.6;
    const maxY = reverse ? 3.5 : o.tram ? 5.30 : 4.2;
    const reach = Math.max(.5, Math.min(15, o.reach ?? 4.5));
    const bottom = overhead ? Math.max(5, Math.min(8, o.clearance ?? 5.5)) : minY;
    const side = o.armSide === "right" ? 1 : -1;
    return {overhead, minY, maxY, reach, side, bottom, x: overhead ? side*reach : 0,
      lift: bottom-minY, top: overhead ? bottom+maxY-minY+.3 : maxY+.1, armLength: reach+1.7};
  }
  return {states, layout};
})();
