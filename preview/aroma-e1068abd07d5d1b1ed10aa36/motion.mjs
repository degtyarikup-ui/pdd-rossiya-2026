import { createAnimationScope } from './motion-scope.mjs';

// Motion follows committed state. No animation delays a choice or a result.
const rect = element => {
  const {left, top, width, height} = element.getBoundingClientRect();
  return {left, top, width, height};
};
const inViewport = box => box.width > 0 && box.height > 0 && box.top < innerHeight && box.top + box.height > 0 && box.left < innerWidth && box.left + box.width > 0;
const intersects = (a, b) => a.left < b.left + b.width && a.left + a.width > b.left && a.top < b.top + b.height && a.top + a.height > b.top;

export function createGameMotion(root) {
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const flights = new Map();
  let onScreen = true;
  const enabled = () => !reduced.matches && !document.hidden && onScreen && typeof root.animate === 'function';
  const {animate, settle} = createAnimationScope(enabled);
  function snapshotArt(element) {
    const art = element.querySelector('.ingredient');
    if (!art) return null;
    const label = element.querySelector('.slot-label') || element.querySelector(':scope > span:last-child');
    return {box: rect(art), clone: art.cloneNode(true), label: label ? rect(label) : null};
  }
  function capture(source) {
    const grid = root.querySelector('.note-grid');
    const gridBox = grid ? rect(grid) : null;
    const notes = new Map();
    root.querySelectorAll('.note-choice').forEach(element => {
      const box = rect(element);
      if (inViewport(box) && intersects(box, gridBox)) notes.set(element.dataset.note, box);
    });
    const selected = new Map();
    root.querySelectorAll('.mix-slot.filled, .result-note').forEach(element => {
      const item = snapshotArt(element);
      selected.set(element.querySelector('.ingredient').dataset.art, item);
    });
    // Continue an interrupted flight from its visible position.
    for (const [name, flight] of flights) if (selected.has(name)) selected.get(name).box = rect(flight);
    const activeFilter = root.querySelector('.filter-indicator') || root.querySelector('.filter[aria-pressed=true]');
    const snapshot = {
      notes, selected,
      source: source ? snapshotArt(source) : null,
      filter: activeFilter ? rect(activeFilter) : null,
      filterScroll: root.querySelector('.filter-scroll')?.scrollLeft || 0,
      height: root.getBoundingClientRect().height,
      result: root.classList.contains('result-shell')
    };
    settle();
    return snapshot;
  }
  function flip(element, from, options = {}) {
    if (!from || !element) return;
    const to = rect(element);
    if (!inViewport(from) || !inViewport(to) || !to.width || !to.height) return;
    const x = from.left - to.left, y = from.top - to.top;
    const sx = from.width / to.width, sy = from.height / to.height;
    if (Math.abs(x) + Math.abs(y) < 1 && Math.abs(sx - 1) + Math.abs(sy - 1) < .01) return;
    const origin = element.style.transformOrigin;
    element.style.transformOrigin = '0 0';
    animate(element, [
      {transform: `translate(${x}px,${y}px) scale(${sx},${sy})`},
      {transform: 'translate(0,0) scale(1)'}
    ], {...options, geometry: true, cleanup: () => {element.style.transformOrigin = origin;}});
  }
  function syncFilterEdges(container) {
    container.style.setProperty('--filter-fade-start', container.scrollLeft > 2 ? '16px' : '0px');
    container.style.setProperty('--filter-fade-end', container.scrollWidth - container.clientWidth - container.scrollLeft > 2 ? '20px' : '0px');
  }
  function syncNoteFade(grid) {
    if (!grid) return;
    const distance = parseFloat(getComputedStyle(grid).getPropertyValue('--scroll-fade')) || 38;
    grid.style.setProperty('--note-fade-alpha', 1 - Math.min(1, Math.max(0, grid.scrollTop) / distance));
  }
  function placeIndicator(previous, {scrollLeft, revealActive = false} = {}) {
    const container = root.querySelector('.filter-scroll');
    const active = container?.querySelector('[aria-pressed=true]');
    if (!active) return;
    // The strip is recreated with each state change. Keep the user's position
    // when filtering, and bring a newly active category fully into view.
    if (scrollLeft !== undefined) container.scrollLeft = scrollLeft;
    if (revealActive && container.scrollWidth > container.clientWidth) {
      const item = rect(active), bounds = rect(container);
      if (item.left < bounds.left + 18) container.scrollLeft += item.left - bounds.left - 18;
      else if (item.left + item.width > bounds.left + bounds.width - 22) container.scrollLeft += item.left + item.width - bounds.left - bounds.width + 22;
    }
    syncFilterEdges(container);
    const position = rect(active), parent = rect(container);
    const indicator = document.createElement('span');
    indicator.className = 'filter-indicator';
    indicator.setAttribute('aria-hidden', 'true');
    Object.assign(indicator.style, {
      left: `${position.left - parent.left + container.scrollLeft}px`, top: `${position.top - parent.top}px`,
      width: `${position.width}px`, height: `${position.height}px`
    });
    container.classList.add('has-filter-indicator');
    container.prepend(indicator);
    if (previous) flip(indicator, previous, {duration: 260});
  }
  function floatingArt(item) {
    const ghost = document.createElement('span');
    ghost.className = 'note-flight';
    ghost.setAttribute('aria-hidden', 'true');
    Object.assign(ghost.style, {
      left: `${item.box.left}px`, top: `${item.box.top}px`,
      width: `${item.box.width}px`, height: `${item.box.height}px`
    });
    const art = item.clone.cloneNode(true);
    Object.assign(art.style, {width: '100%', height: '100%', visibility: 'visible'});
    ghost.append(art);
    document.body.append(ghost);
    return ghost;
  }
  function fly(name, item, target) {
    if (!item || !target || !enabled()) return false;
    const to = rect(target);
    if (!inViewport(item.box) || !inViewport(to)) return false;
    const ghost = floatingArt(item);
    flights.set(name, ghost);
    const wrapper = target.parentElement;
    const visibility = wrapper.style.visibility;
    wrapper.style.visibility = 'hidden';
    const dx = to.left - item.box.left, dy = to.top - item.box.top;
    const scale = to.width / item.box.width;
    const distance = Math.hypot(dx, dy);
    const duration = Math.min(440, 280 + distance * .2);
    animate(ghost, [
      {transform: 'translate(0,0) scale(1) rotate(0deg)', opacity: 1},
      {transform: `translate(${dx * .55}px,${dy * .55 - Math.min(38, distance * .07)}px) scale(${1 + (scale - 1) * .55}) rotate(-3deg)`, offset: .55, opacity: 1},
      {transform: `translate(${dx}px,${dy}px) scale(${scale}) rotate(0deg)`, opacity: 1}
    ], {duration, geometry: true, cleanup: () => {
      wrapper.style.visibility = visibility;
      ghost.remove();
      if (flights.get(name) === ghost) flights.delete(name);
    }});
    return true;
  }
  function remove(item) {
    if (!item || !enabled() || !inViewport(item.box)) return;
    const ghost = floatingArt(item);
    animate(ghost, [
      {opacity: .85, transform: 'translate(0,0) scale(1)'},
      {opacity: 0, transform: 'translate(0,12px) scale(.8)'}
    ], {duration: 180, geometry: true, cleanup: () => ghost.remove()});
  }
  function converge(name, item, destination, index) {
    if (!item || !enabled() || !inViewport(item.box)) return;
    if (!inViewport(destination)) return;
    const ghost = floatingArt(item);
    flights.set(name, ghost);
    const scale = .12;
    const dx = destination.left + destination.width * .5 - item.box.left - item.box.width * scale / 2;
    const dy = destination.top + destination.height * .54 - item.box.top - item.box.height * scale / 2;
    animate(ghost, [
      {transform: 'translate(0,0) scale(1) rotate(0deg)', opacity: 1},
      {transform: `translate(${dx * .78}px,${dy * .78 - 20}px) scale(.52) rotate(${(index-1)*9}deg)`, opacity: .88, offset: .58},
      {transform: `translate(${dx}px,${dy}px) scale(${scale}) rotate(0deg)`, opacity: 0}
    ], {duration: 470, delay: index * 22, easing: 'cubic-bezier(.32, 0, .2, 1)', geometry: true, cleanup: () => {
      ghost.remove();
      if (flights.get(name) === ghost) flights.delete(name);
    }});
  }
  function reveal(element, delay = 0, distance = 10, duration = 340) {
    animate(element, [
      {opacity: 0, transform: `translateY(${distance}px)`},
      {opacity: 1, transform: 'translateY(0)'}
    ], {delay, duration});
  }
  function play(previous, {kind = 'initial', note, pointer = false, skipTravel = false, filterScroll} = {}) {
    syncVisibility();
    syncNoteFade(root.querySelector('.note-grid'));
    placeIndicator(kind === 'gender' ? null : previous?.filter, {scrollLeft: filterScroll ?? (kind === 'filter' ? previous?.filterScroll : 0), revealActive: true});
    if (pointer) root.classList.add('motion-no-hover');
    if (!enabled()) return;
    const isResult = root.classList.contains('result-shell');
    const newHeight = root.getBoundingClientRect().height;
    if (previous && Math.abs(previous.height - newHeight) > 2) {
      animate(root, [{height: `${previous.height}px`}, {height: `${newHeight}px`}], {duration: 360, geometry: true});
    }
    if (kind === 'gender') {
      reveal(root.querySelector('.game-body, .result-content'), 0, 0, 240);
      return;
    }
    if (isResult) {
      const art = root.querySelector('.product-art');
      const bottle = art.querySelector('.product-bottle');
      const focalPoint = rect(bottle);
      const discovery = kind === 'select';
      reveal(art, 0, 0, discovery ? 280 : 360);
      if (discovery) {
        // The three choices become one fragrance: convergence, light, glass.
        animate(art.querySelector('.result-bloom'), [
          {opacity: 0, transform: 'scale(.18)'},
          {opacity: .92, transform: 'scale(.9)', offset: .32},
          {opacity: .48, transform: 'scale(1.15)', offset: .65},
          {opacity: 0, transform: 'scale(1.35)'}
        ], {duration: 1050, delay: 70, easing: 'cubic-bezier(.4, 0, .2, 1)'});
        animate(bottle, [
          {opacity: 0, transform: 'perspective(850px) translateY(26px) rotateY(-13deg) scale(.84)', filter: 'blur(7px) brightness(1.45)'},
          {opacity: 1, transform: 'perspective(850px) translateY(-4px) rotateY(2deg) scale(1.025)', filter: 'blur(0px) brightness(1.08)', offset: .72},
          {opacity: 1, transform: 'perspective(850px) translateY(0) rotateY(0deg) scale(1)', filter: 'blur(0px) brightness(1)'}
        ], {duration: 930, delay: 200});
        animate(art.querySelector('.bottle-glint-beam'), [
          {opacity: 0, transform: 'translateX(-110%)'},
          {opacity: .52, transform: 'translateX(-26%)', offset: .32},
          {opacity: .38, transform: 'translateX(30%)', offset: .65},
          {opacity: 0, transform: 'translateX(110%)'}
        ], {duration: 650, delay: 600, easing: 'linear'});
      } else {
        animate(bottle, [{opacity: 0, transform: 'translateY(14px) scale(.96)'}, {opacity: 1, transform: 'translateY(0) scale(1)'}], {duration: 440});
      }
      ['.product-brand','.result-copy h2','.product-description','.result-actions'].forEach((selector, index) => reveal(root.querySelector(selector), (discovery ? 390 : 60) + index * (discovery ? 85 : 45), 10, 380));
      root.querySelectorAll('.result-note').forEach((element, index) => {
        const target = element.querySelector('.ingredient');
        const name = target.dataset.art;
        const source = name === note ? previous?.source : previous?.selected.get(name);
        if (discovery && !skipTravel) converge(name, source, focalPoint, index);
        reveal(element.querySelector('.result-note-art'), (discovery ? 540 : 150) + index * 35, 8);
        reveal(element.lastElementChild, (discovery ? 600 : 190) + index * 35, 5);
      });
      return;
    }
    const grid = root.querySelector('.note-grid');
    const gridBox = rect(grid);
    let stagger = 0;
    grid.querySelectorAll('.note-choice').forEach(element => {
      const box = rect(element);
      if (!inViewport(box) || !intersects(box, gridBox)) return;
      // Keep the keyboard target and its focus ring steady at a scroll edge.
      if (element === document.activeElement) return;
      const from = previous?.notes.get(element.dataset.note);
      if (from && kind !== 'filter') flip(element, from, {duration: 310});
      else reveal(element, Math.min(stagger++ * 22, 110), 10, 280);
    });
    root.querySelectorAll('.mix-slot.filled').forEach(element => {
      const target = element.querySelector('.ingredient');
      const name = target.dataset.art;
      const item = name === note && kind === 'select' ? previous?.source : previous?.selected.get(name);
      const travelling = !skipTravel && item && (name === note && kind === 'select' || previous?.result) && fly(name, item, target);
      if (!travelling && item) flip(target, item.box, {duration: 340});
      const label = element.querySelector('.slot-label');
      if (travelling) reveal(label, 220, 4, 220);
      else if (item?.label) flip(label, item.label, {duration: 340});
    });
    if (kind === 'remove') remove(previous?.selected.get(note));
    if (kind !== 'filter') {
      animate(root.querySelector('.selection-count b'), [
        {opacity: .3, transform: 'translateY(5px)'}, {opacity: 1, transform: 'translateY(0)'}
      ], {duration: 240});
      const current = root.querySelector('.mix-slot.current .slot-art');
      animate(current, [{opacity: .45, transform: 'scale(.93)'}, {opacity: 1, transform: 'scale(1)'}], {duration: 340, delay: 100});
    }
  }
  function syncVisibility() {
    root.classList.toggle('motion-paused', document.hidden || !onScreen);
    if (document.hidden || !onScreen) settle();
  }
  const observer = new IntersectionObserver(entries => {
    onScreen = entries[0].isIntersecting;
    syncVisibility();
  });
  observer.observe(root);
  document.addEventListener('visibilitychange', syncVisibility);
  reduced.addEventListener('change', () => {if (reduced.matches) settle();});
  // Geometry effects stop at the correct committed state if the viewport moves.
  addEventListener('scroll', event => {
    settle(true);
    if (event.target.classList?.contains('filter-scroll')) syncFilterEdges(event.target);
    if (event.target.classList?.contains('note-grid')) syncNoteFade(event.target);
  }, {capture: true, passive: true});
  addEventListener('resize', () => {settle(true); root.querySelector('.filter-indicator')?.remove(); placeIndicator(); syncNoteFade(root.querySelector('.note-grid'));}, {passive: true});
  root.addEventListener('pointermove', () => root.classList.remove('motion-no-hover'), {passive: true});
  root.addEventListener('keydown', () => root.classList.remove('motion-no-hover'));
  return {capture, play, reduced: () => reduced.matches};
}
