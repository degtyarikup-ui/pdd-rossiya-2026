// Shared polygons describe the painted 1.18 arrows in both thumbnails and the
// surface builder. The two authored points are the tail and forward end of the axis.
const DirectionMark = (() => {
  const variants = [
    ['straight', 'Прямо'], ['left', 'Налево'], ['right', 'Направо'],
    ['straight_left', 'Прямо и налево'], ['straight_right', 'Прямо и направо'],
    ['left_right', 'Налево и направо'], ['all', 'Все направления'],
  ];
  let shapes = {};
  async function load() {
    const response = await fetch('/static/direction_arrows.json');
    if (!response.ok) throw new Error('Не удалось загрузить стрелки разметки');
    shapes = await response.json();
  }
  function polygons(mark) {
    const [a, b] = mark.points || [];
    if (!a || !b) return [];
    const dx = b[0] - a[0], dz = b[1] - a[1], length = Math.hypot(dx, dz);
    if (length < .01) return [];
    const width = mark.width ?? 2.6;
    // The driver's right is -X when driving along +Z.
    return (shapes[mark.direction || 'straight'] || []).map(ring => ring.map(([x, z]) => [
      a[0] + dx * z - dz / length * x * width,
      a[1] + dz * z + dx / length * x * width,
    ]));
  }
  function svg(direction = 'straight') {
    return `<svg class="direction-mark-pic" viewBox="-0.6 -0.08 1.2 1.16" aria-hidden="true"><g transform="translate(0 1) scale(1 -1)" fill="currentColor">${(shapes[direction] || []).map(ring => `<polygon points="${ring.map(p => p.join(',')).join(' ')}"/>`).join('')}</g></svg>`;
  }
  return { variants, load, polygons, svg };
})();
