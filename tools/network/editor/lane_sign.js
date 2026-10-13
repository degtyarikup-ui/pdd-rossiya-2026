// Editable 5.15.1 face. Each lane has its own permitted directions, left to right
// as the approaching driver sees them. Kept in parity with scripts/lane_sign.gd.
const LaneSign = (() => {
  const DIRECTIONS = Object.freeze(['left', 'straight', 'right']);
  const DEFAULT_LANES = Object.freeze([
    Object.freeze(['left', 'straight']), Object.freeze(['straight']), Object.freeze(['straight', 'right']),
  ]);
  const LANE_WIDTH = 48, MARGIN = 8, HEIGHT = 100, SCALE = 3 / 160;
  const BLUE = '#0D69E1';

  function normalize(lanes) {
    const source = Array.isArray(lanes) && lanes.length ? lanes.slice(0, 6) : DEFAULT_LANES;
    return source.map(lane => {
      const selected = Array.isArray(lane) ? lane : typeof lane === 'string' ? [lane] : [];
      const valid = DIRECTIONS.filter(direction => selected.includes(direction));
      return valid.length ? valid : ['straight'];
    });
  }

  function dimensions(lanes) {
    return { width: (normalize(lanes).length * LANE_WIDTH + MARGIN * 2) * SCALE, height: HEIGHT * SCALE };
  }

  function geometry(lanes) {
    lanes = normalize(lanes);
    const width = lanes.length * LANE_WIDTH + MARGIN * 2, paths = [], heads = [], separators = [];
    for (let i = 0; i < lanes.length; i++) {
      const cx = MARGIN + LANE_WIDTH * (i + 0.5), directions = lanes[i];
      if (directions.includes('straight')) {
        paths.push(`M${cx} 87V29`);
        heads.push([[cx, 13], [cx - 9, 30], [cx + 9, 30]]);
      }
      for (const [direction, side] of [['left', -1], ['right', 1]]) {
        if (!directions.includes(direction)) continue;
        paths.push(`M${cx} 87V57Q${cx} 47 ${cx + side * 10} 47H${cx + side * 12}`);
        heads.push([[cx + side * 22, 47], [cx + side * 10, 40], [cx + side * 10, 54]]);
      }
      if (i > 0) for (let y = 43; y <= 84; y += 9) separators.push([MARGIN + LANE_WIDTH * i - 1, y, 2, 6]);
    }
    return { width, height: HEIGHT, paths, heads, separators };
  }

  function svg(lanes) {
    const g = geometry(lanes);
    const rects = g.separators.map(([x, y, w, h]) => `<rect x="${x}" y="${y}" width="${w}" height="${h}"/>`).join('');
    const paths = g.paths.map(path => `<path d="${path}"/>`).join('');
    const heads = g.heads.map(points => `<polygon points="${points.map(point => point.join(',')).join(' ')}"/>`).join('');
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${g.width * 4}" height="${g.height * 4}" viewBox="0 0 ${g.width} ${g.height}"><rect width="${g.width}" height="${g.height}" rx="5" fill="#fff"/><rect x="3" y="3" width="${g.width - 6}" height="${g.height - 6}" rx="3" fill="${BLUE}"/><g fill="#fff">${rects}${heads}</g><g stroke="#fff" stroke-width="6" stroke-linejoin="round" fill="none">${paths}</g></svg>`;
  }

  // Synchronous canvas texture: editing a checkbox immediately replaces the face
  // and does not wait on an SVG image request or a previous asynchronous load.
  function canvas(lanes) {
    const g = geometry(lanes), result = document.createElement('canvas');
    result.width = g.width * 4; result.height = g.height * 4;
    const context = result.getContext('2d');
    context.scale(4, 4);
    context.fillStyle = '#fff'; context.beginPath(); context.roundRect(0, 0, g.width, g.height, 5); context.fill();
    context.fillStyle = BLUE; context.beginPath(); context.roundRect(3, 3, g.width - 6, g.height - 6, 3); context.fill();
    context.fillStyle = '#fff';
    for (const rectangle of g.separators) context.fillRect(...rectangle);
    for (const points of g.heads) {
      context.beginPath(); context.moveTo(...points[0]);
      for (const point of points.slice(1)) context.lineTo(...point);
      context.closePath(); context.fill();
    }
    context.strokeStyle = '#fff'; context.lineWidth = 6; context.lineJoin = 'round';
    for (const path of g.paths) context.stroke(new Path2D(path));
    return result;
  }

  return { DIRECTIONS, DEFAULT_LANES, normalize, dimensions, geometry, svg, canvas };
})();
if (typeof module !== 'undefined') module.exports = LaneSign;
