const EASE = 'cubic-bezier(.22, 1, .36, 1)';

export function createAnimationScope(enabled) {
  const running = new Map();

  function animate(element, frames, {duration = 320, delay = 0, easing = EASE, geometry = false, cleanup} = {}) {
    if (!element || !enabled()) { cleanup?.(); return; }
    const animation = element.animate(frames, {duration, delay, easing, fill: 'both'});
    let settled = false;
    const settle = () => {
      if (settled) return;
      settled = true;
      running.delete(animation);
      animation.cancel();
      cleanup?.();
    };
    running.set(animation, {settle, geometry});
    // Cancellation is an ordinary interaction, not an unhandled rejection.
    animation.finished.then(settle, settle);
    return animation;
  }

  function settle(geometryOnly = false) {
    for (const item of [...running.values()]) if (!geometryOnly || item.geometry) item.settle();
  }

  return {animate, settle};
}
