// All dimensions are edited in the graph. Each pointer gesture is one undo step.
App.terrainEditor = (() => {
  const left = 30, right = 294, top = 10, bottom = 128;
  const clamp = (v, min, max) => Math.min(max, Math.max(min, v));
  const round = v => Math.round(v * 10) / 10;
  const bounds = sc => sc.terrain?.profile?.length ? sc.terrain.profile : [[-(sc.crop || 90),0],[sc.crop || 90,0]];
  const options = {rebuild:false, surfaces:true};
  const fmt = v => Number(v.toFixed(2)).toLocaleString('ru-RU');
  let lastScene, selected = -1, bumpIndex = -1, active = null;

  function icon(action, x, y, title, path) {
    return `<g data-command="${action}" class="graph-icon" transform="translate(${x} ${y})"><title>${title}</title>
      <rect x="-9" y="-8" width="18" height="16" rx="3"/><path d="${path}"/></g>`;
  }

  function profileGraph(sc) {
    const pts = bounds(sc), crop = sc.crop || 90;
    const x = z => left + (z + crop) / (2*crop) * (right-left);
    const y = h => bottom - h / 30 * (bottom-top);
    let curve = `M ${x(pts[0][0])} ${y(pts[0][1])}`;
    for (let i = 1; i < pts.length; i++) {
      const [az,ah] = pts[i-1], [bz,bh] = pts[i];
      curve += ` C ${x(az+(bz-az)/3)} ${y(ah)} ${x(bz-(bz-az)/3)} ${y(bh)} ${x(bz)} ${y(bh)}`;
    }
    const grid = [0,10,20,30].map(h => `<path class="grid" d="M${left} ${y(h)}H${right}"/><text x="2" y="${y(h)+3}">${h} м</text>`).join('');
    const dots = pts.map(([z,h],i) => {
      const fixed = i === 0 || i === pts.length-1;
      return `<g data-point="${i}" class="${fixed ? 'fixed' : selected === i ? 'selected' : ''}">
        <title>${fmt(z)} м · высота ${fmt(h)} м</title><circle class="hit" cx="${x(z)}" cy="${y(h)}" r="8"/>
        <circle cx="${x(z)}" cy="${y(h)}" r="${fixed ? 3 : 5}"/></g>`;
    }).join('');
    const bumps = (sc.terrain?.bumps || []).map((b,i) => `<g class="bump-mark" data-bump="${i}" transform="translate(${x(b.centre[1])} 135)">
      <title>Неровность ${i+1} · ${fmt(b.height*100)} см</title><rect x="-8" y="-6" width="16" height="13" fill="transparent"/>
      <path d="M-6 2 Q0 -8 6 2 Z"/></g>`).join('');
    let remove = '';
    if (selected > 0 && selected < pts.length-1) {
      const [z,h] = pts[selected];
      remove = icon('delete', x(z) > right-20 ? x(z)-15 : x(z)+15, y(h)<22 ? y(h)+12 : y(h)-12, 'Удалить точку', 'M-3 -3L3 3M3 -3L-3 3');
    }
    return grid + `<path class="area" d="${curve} V${bottom} H${left}Z"/><path class="profile" d="${curve}"/>`
      + dots + bumps + remove + `<text x="${left}" y="148">−${crop} м</text><text x="${right}" text-anchor="end" y="148">+${crop} м</text>`
      + icon('menu',13,143,'Действия графика','M-5 0h.1 M0 0h.1 M5 0h.1');
  }

  // Left: plan of the scene. Right: side profile and a separate width dimension.
  const plan = {left:12, top:26, size:100};
  const shape = {centre:223, base:93, scale:4.4, rise:65};
  function bumpGraph(b, crop) {
    const {left,top,size} = plan;
    const px = left + (b.centre[0]+crop)*size/(2*crop), py = top + (crop-b.centre[1])*size/(2*crop);
    const width = b.width*size/(2*crop), length = b.length*size/(2*crop);
    const {centre,base,scale,rise} = shape;
    const end = centre + b.length*scale/2, side = centre + b.width*scale/2, peak = base-b.height/.2*rise;
    const handle = (key,x,y,title) => `<g data-handle="${key}"><title>${title}</title>
      <circle class="hit" cx="${x}" cy="${y}" r="9"/><circle cx="${x}" cy="${y}" r="4"/></g>`;
    return icon('back',13,12,'Вернуться к профилю','M4 0H-4M0 -4L-4 0L0 4')
      + `<text x="30" y="15">Неровность ${bumpIndex+1}</text>
         <rect class="plan" x="${left}" y="${top}" width="${size}" height="${size}"/>
         <path class="grid" d="M${left} ${top+size/2}h${size} M${left+size/2} ${top}v${size}"/>
         <rect class="footprint" x="${px-width/2}" y="${py-length/2}" width="${width}" height="${length}"/>
         <text x="12" y="143">X ${fmt(b.centre[0])} · Z ${fmt(b.centre[1])} м</text>
         <path class="grid" d="M150 ${base}H296"/>
         <path class="bump-shape" d="M${2*centre-end} ${base} C${2*centre-end+(end-centre)/2} ${base} ${centre-(end-centre)/2} ${peak} ${centre} ${peak} S${end-(end-centre)/2} ${base} ${end} ${base}Z"/>
         <text x="150" y="15">Высота ${fmt(b.height*100)} см</text>
         <path class="grid" d="M${2*centre-end} ${base+8}H${end}"/><text x="150" y="115">Длина ${fmt(b.length)} м</text>
         <path class="profile" d="M${2*centre-side} 123H${side}"/><text x="150" y="144">Ширина ${fmt(b.width)} м</text>`
      + handle('position',px,py,'Положение на плане') + handle('height',centre,peak,'Высота')
      + handle('length',end,base+8,'Длина') + handle('width',side,123,'Ширина')
      + icon('delete',293,12,'Удалить неровность','M-3 -3L3 3M3 -3L-3 3');
  }

  function draw(sc) {
    const bump = sc.terrain?.bumps?.[bumpIndex];
    if (bump) return bumpGraph(bump,sc.crop || 90);
    bumpIndex = -1;
    if (selected >= bounds(sc).length-1) selected = -1;
    return profileGraph(sc);
  }

  function html(sc) {
    if (sc.id !== lastScene) { selected = bumpIndex = -1; lastScene = sc.id; }
    return `<div class="terrain-editor"><svg data-terrain-graph tabindex="0" viewBox="0 0 306 152" aria-label="График рельефа">${draw(sc)}</svg></div>`;
  }

  function mount(pane,sc) {
    const root = pane.querySelector('.terrain-editor');
    if (!root) return;
    const svg = root.querySelector('svg'), crop = sc.crop || 90;
    const locked = () => App.state.locked.has('roads') || sc !== App.S;
    const refresh = () => { svg.innerHTML = draw(sc); };
    const focus = () => svg.focus({preventScroll:true});
    let gesture = null, menu = null;

    function fitBump(b) {
      b.centre[0] = clamp(b.centre[0],-crop+b.width/2,crop-b.width/2);
      b.centre[1] = clamp(b.centre[1],-crop+b.length/2+.1,crop-b.length/2-.1);
    }
    function edit(fn) {
      if (locked()) return;
      App.edit(() => {
        fn();
        if (!sc.terrain?.profile?.length && !sc.terrain?.bumps?.length) delete sc.terrain;
      },options);
    }
    function remove() {
      if (bumpIndex >= 0) {
        edit(() => { sc.terrain.bumps.splice(bumpIndex,1); bumpIndex = -1; });
      } else if (selected > 0 && selected < bounds(sc).length-1) {
        edit(() => {
          sc.terrain.profile.splice(selected,1);
          if (sc.terrain.profile.length === 2) delete sc.terrain.profile;
          selected = -1;
        });
      }
    }
    const local = e => new DOMPoint(e.clientX,e.clientY).matrixTransform(svg.getScreenCTM().inverse());
    const zAt = x => round((x-left)/(right-left)*2*crop-crop);
    const heightAt = y => round(clamp((bottom-y)/(bottom-top)*30,0,30));

    function closeMenu() {
      if (!menu) return;
      menu.remove(); menu = null; active = null;
    }
    function openMenu(at, z) {
      closeMenu();
      menu = document.createElement('div');
      menu.className = 'terrain-menu'; menu.setAttribute('role','group');
      const action = (label,fn) => {
        const button = document.createElement('button');
        button.type = 'button'; button.textContent = label;
        button.onclick = () => { closeMenu(); focus(); if (!locked()) fn(); };
        menu.append(button);
      };
      if ((sc.terrain?.bumps?.length || 0) < 16) action('Добавить неровность', () => edit(() => {
        const b = {centre:[sc.stop?.x || 0, z],width:7,length:3.5,height:.08};
        fitBump(b); sc.terrain ||= {}; (sc.terrain.bumps ||= []).push(b);
        selected = -1; bumpIndex = sc.terrain.bumps.length-1;
      }));
      if (sc.terrain?.profile) action('Выровнять профиль', () => edit(() => { delete sc.terrain.profile; selected = -1; }));
      if (!menu.childElementCount) { closeMenu(); return; }
      root.append(menu);
      const box = root.getBoundingClientRect();
      menu.style.left = clamp(at.x-box.left,0,box.width-menu.offsetWidth)+'px';
      menu.style.top = clamp(at.y-box.top,0,box.height-menu.offsetHeight)+'px';
      active = {svg,sc};
      menu.firstElementChild.focus({preventScroll:true});
    }
    root.onfocusout = e => { if (menu && !root.contains(e.relatedTarget)) closeMenu(); };
    root.onkeydown = e => {
      if (e.key === 'Delete' || e.key === 'Backspace') {
        e.preventDefault(); e.stopPropagation();
        if (!locked() && !gesture && !menu && !e.repeat) remove();
      } else if (e.key.startsWith('Arrow') && !e.ctrlKey && !e.metaKey && !e.altKey) {
        e.stopPropagation();
        if (menu || gesture || locked()) return;
        e.preventDefault();
        const step = e.shiftKey ? 1 : .1;
        const dz = (Number(e.key === 'ArrowRight') - Number(e.key === 'ArrowLeft')) * step;
        const dh = (Number(e.key === 'ArrowUp') - Number(e.key === 'ArrowDown')) * step;
        if (bumpIndex >= 0) edit(() => {
          const b = sc.terrain.bumps[bumpIndex];
          b.centre = [round(b.centre[0]+dz),round(b.centre[1]+dh)];
          fitBump(b);
        });
        else if (selected > 0 && selected < bounds(sc).length-1) edit(() => {
          const pts = sc.terrain.profile, [z,h] = pts[selected], next = round(z+dz);
          const inGap = next-pts[selected-1][0] > .1 && pts[selected+1][0]-next > .1;
          pts[selected] = [dz && inGap ? next : z,clamp(round(h+dh),0,30)];
        });
      } else if (e.key === 'Enter' && e.target === svg && bumpIndex < 0 && !gesture && !locked()) {
        e.preventDefault(); e.stopPropagation();
        const box = svg.getBoundingClientRect();
        openMenu(new DOMPoint(box.left,box.bottom),sc.stop?.z || 0);
      } else if (e.key === 'Escape' && (menu || gesture || bumpIndex >= 0)) {
        e.preventDefault(); e.stopPropagation();
        if (gesture) finish(true);
        else if (menu) { closeMenu(); focus(); }
        else { bumpIndex = -1; refresh(); }
      }
    };
    svg.oncontextmenu = e => {
      e.preventDefault();
      if (locked() || gesture) return;
      focus(); closeMenu();
      const point = e.target.closest('[data-point]'), bump = e.target.closest('[data-bump]');
      if (point) { selected = Number(point.dataset.point); remove(); }
      else if (bump) { bumpIndex = Number(bump.dataset.bump); remove(); }
      else if (bumpIndex < 0) openMenu(new DOMPoint(e.clientX,e.clientY),zAt(local(e).x));
    };
    svg.onpointerdown = e => {
      if (e.button !== 0 || e.ctrlKey || locked() || gesture) return;
      focus();
      if (menu) { closeMenu(); return; }
      const p = local(e), command = e.target.closest('[data-command]')?.dataset.command;
      if (command) {
        if (command === 'delete') remove();
        if (command === 'back') { bumpIndex = -1; refresh(); }
        if (command === 'menu') openMenu(new DOMPoint(e.clientX,e.clientY),sc.stop?.z || 0);
        return;
      }
      const marker = e.target.closest('[data-bump]');
      if (marker) { selected = -1; bumpIndex = Number(marker.dataset.bump); refresh(); return; }
      const handle = e.target.closest('[data-handle]')?.dataset.handle;
      const point = e.target.closest('[data-point]');
      const z = zAt(p.x), pts = bounds(sc);
      if (bumpIndex >= 0 && !handle) return;
      if (bumpIndex < 0) {
        if (point) {
          selected = Number(point.dataset.point);
          if (selected === 0 || selected === pts.length-1) { selected = -1; refresh(); return; }
        } else {
          if (p.y < top || p.y > bottom || z <= -crop+.1 || z >= crop-.1 || pts.length >= 64 || pts.some(a => Math.abs(a[0]-z) <= .1)) return;
          selected = pts.findIndex(a => a[0] > z);
        }
      }
      gesture = {id:e.pointerId,handle,start:p,bump:handle && structuredClone(sc.terrain.bumps[bumpIndex])};
      svg.setPointerCapture(e.pointerId); active = {svg,sc}; App.beginDrag();
      if (!point && !handle) App.dragMove(() => {
        sc.terrain ||= {}; (sc.terrain.profile ||= pts).splice(selected,0,[z,heightAt(p.y)]);
      },options);
      refresh();
    };
    svg.onpointermove = e => {
      if (e.pointerId !== gesture?.id) return;
      if (locked()) { finish(true); return; }
      const p = local(e);
      if (gesture.handle) {
        const b = sc.terrain.bumps[bumpIndex], start = gesture.bump;
        const dx = p.x-gesture.start.x, dy = p.y-gesture.start.y;
        App.dragMove(() => {
          switch (gesture.handle) {
            case 'position':
              b.centre = [round(start.centre[0]+dx*2*crop/plan.size),round(start.centre[1]-dy*2*crop/plan.size)];
              break;
            case 'height': b.height = clamp(Math.round(start.height*100-dy*20/shape.rise),1,20)/100; break;
            case 'width':
            case 'length': b[gesture.handle] = clamp(round(start[gesture.handle]+dx*2/shape.scale),.5,30); break;
          }
          fitBump(b);
        },options);
      } else {
        const pts = bounds(sc), min = pts[selected-1][0]+.11, max = pts[selected+1][0]-.11;
        const z = min <= max ? Math.round(clamp(zAt(p.x),min,max)*100)/100 : pts[selected][0];
        const h = heightAt(p.y);
        if (pts[selected][0] === z && pts[selected][1] === h) return;
        App.dragMove(() => { pts[selected] = [z,h]; },options);
      }
      refresh();
    };
    function finish(cancel) {
      gesture = null; active = null;
      if (sc !== App.S) return;
      if (cancel) App.cancelDrag(); else App.endDrag(options);
      if (svg.isConnected) refresh();
    }
    svg.onpointerup = e => { if (e.pointerId === gesture?.id) finish(false); };
    svg.onpointercancel = svg.onlostpointercapture = e => { if (e.pointerId === gesture?.id) finish(true); };
  }
  function resize(terrain, oldCrop, crop) {
    if (terrain.profile?.length) {
      const profile = [[-crop,0]];
      for (const [z,h] of terrain.profile.slice(1,-1)) {
        const at = round(z * crop / oldCrop);
        if (at-profile.at(-1)[0] > .1 && crop-at > .1) profile.push([at,h]);
      }
      terrain.profile = [...profile,[crop,0]];
    }
    for (const b of terrain.bumps || []) {
      b.centre = [clamp(b.centre[0]*crop/oldCrop,-crop+b.width/2,crop-b.width/2),
        clamp(b.centre[1]*crop/oldCrop,-crop+b.length/2+.1,crop-b.length/2-.1)];
    }
  }
  return {html,mount,resize,editing:() => active?.sc === App.S && !!active?.svg.isConnected};
})();
