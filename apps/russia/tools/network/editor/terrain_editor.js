// Longitudinal road profile. A gesture changes one history entry.
App.terrainEditor = (() => {
  const left = 30, right = 294, top = 10, bottom = 128;
  const clamp = (v, min, max) => Math.min(max, Math.max(min, v));
  const round = v => Math.round(v * 10) / 10;
  const bounds = sc => sc.terrain?.profile?.length ? sc.terrain.profile : [[-(sc.crop || 90),0],[sc.crop || 90,0]];
  let lastScene, selected = -1, activeGraph = null;

  function graph(points, crop) {
    const x = z => left + (z + crop) / (2*crop) * (right-left);
    const y = h => bottom - h / 30 * (bottom-top);
    let curve = `M ${x(points[0][0])} ${y(points[0][1])}`;
    for (let i=1; i<points.length; i++) {
      const [az,ah] = points[i-1], [bz,bh] = points[i];
      // Smoothstep interpolation, expressed as a cubic Bézier in screen space.
      curve += ` C ${x(az+(bz-az)/3)} ${y(ah)} ${x(bz-(bz-az)/3)} ${y(bh)} ${x(bz)} ${y(bh)}`;
    }
    const grid = [0,10,20,30].map(h=>`<path class="grid" d="M${left} ${y(h)}H${right}"/><text x="2" y="${y(h)+3}">${h} м</text>`).join('');
    const dots = points.map(([z,h],i)=>{
      const fixed = i===0 || i===points.length-1;
      return `<circle data-point="${i}" cx="${x(z)}" cy="${y(h)}" r="${fixed?3:5}" class="${fixed?'fixed':i===selected?'selected':''}"><title>${z} м · высота ${h} м</title></circle>`;
    }).join('');
    return grid + `<path class="area" d="${curve} V${bottom} H${left}Z"/><path class="profile" d="${curve}"/>` + dots
      + `<text x="${left}" y="145">−${crop} м</text><text x="${right}" text-anchor="end" y="145">+${crop} м</text>`;
  }

  function html(sc) {
    if (sc.id !== lastScene) { selected=-1; lastScene=sc.id; }
    const pts=bounds(sc), crop=sc.crop||90, bumps=sc.terrain?.bumps||[];
    if (selected >= pts.length-1 || selected < 1) selected = pts.length>2 ? 1 : -1;
    const point = pts[selected];
    const button = (key,label,disabled=false) => `<button class="btn ghost small" data-terrain-action="${key}" ${disabled?'disabled':''}>${label}</button>`;
    function slider(key,title,value,min,max,step,index,unit='м') {
      return `<label class="terrain-slider">${title}<output>${value} ${unit}</output><input type="range" data-terrain-slider="${key}" data-index="${index}" min="${min}" max="${max}" step="${step}" value="${value}" aria-label="${title}"></label>`;
    }
    return `<div class="terrain-editor"><p>Нажмите на график, чтобы добавить точку. Потяните её, чтобы изменить склон.</p>
      <svg viewBox="0 0 306 150" aria-label="Профиль высоты вдоль оси Z">${graph(pts,crop)}</svg>
      ${point ? slider('height','Высота точки',point[1],0,30,.1,selected) : ''}
      <div class="selection-actions">${button('add','Добавить точку',pts.length>=64)}${button('remove','Удалить точку',!point)}${button('flat','Выровнять',!sc.terrain?.profile)}</div>
      ${bumps.map((b,i)=>`<details class="terrain-bump" open><summary>Неровность ${i+1}</summary>
        ${slider('x','Поперёк дороги',b.centre[0],-crop+b.width/2,crop-b.width/2,.1,i)}
        ${slider('z','Вдоль дороги',b.centre[1],-crop+b.length/2+.1,crop-b.length/2-.1,.1,i)}
        ${slider('width','Ширина',b.width,.5,30,.1,i)}${slider('length','Длина',b.length,.5,30,.1,i)}
        ${slider('bumpHeight','Высота неровности',Math.round(b.height*100),1,20,1,i,'см')}
        <button class="btn ghost small" data-terrain-action="remove-bump" data-index="${i}">Удалить неровность</button></details>`).join('')}
      ${button('add-bump','Добавить неровность',bumps.length>=16)}</div>`;
  }

  function mount(pane,sc) {
    const root=pane.querySelector('.terrain-editor');
    if (!root) return;
    if (App.state.locked.has('roads')) {
      root.querySelectorAll('button,input').forEach(el=>el.disabled=true);
      return;
    }
    const crop=sc.crop||90, svg=root.querySelector('svg'), options={rebuild:false,surfaces:true};
    const profile=()=>{sc.terrain ||= {}; return sc.terrain.profile ||= bounds(sc);};
    function fitBump(b) {
      b.centre[0]=clamp(b.centre[0],-crop+b.width/2,crop-b.width/2);
      b.centre[1]=clamp(b.centre[1],-crop+b.length/2+.1,crop-b.length/2-.1);
    }
    const edit=fn=>App.edit(()=>{fn(); if(sc.terrain && !sc.terrain.profile?.length && !sc.terrain.bumps?.length) delete sc.terrain;},options);
    root.onclick=e=>{
      const btn=e.target.closest('[data-terrain-action]');
      if (!btn || btn.disabled) return;
      edit(()=>{
        switch(btn.dataset.terrainAction) {
          case 'add': {
            const pts=profile(); let gap=0;
            for(let i=1;i<pts.length-1;i++) if(pts[i+1][0]-pts[i][0]>pts[gap+1][0]-pts[gap][0]) gap=i;
            const [a,b]=pts.slice(gap,gap+2); selected=gap+1;
            pts.splice(selected,0,[round((a[0]+b[0])/2),round((a[1]+b[1])/2)]); break;
          }
          case 'remove': profile().splice(selected,1); if(profile().length===2) delete sc.terrain.profile; selected=-1; break;
          case 'flat': delete sc.terrain.profile; selected=-1; break;
          case 'add-bump': {
            const b={centre:[sc.stop.x,sc.stop.z+8],width:7,length:3.5,height:.08};
            fitBump(b); sc.terrain ||= {}; (sc.terrain.bumps ||= []).push(b); break;
          }
          case 'remove-bump': sc.terrain.bumps.splice(Number(btn.dataset.index),1); break;
        }
      });
    };
    root.oninput=e=>{
      const input=e.target.closest('[data-terrain-slider]');
      if(input) input.previousElementSibling.textContent=input.value+(input.dataset.terrainSlider==='bumpHeight'?' см':' м');
    };
    root.onchange=e=>{
      const input=e.target.closest('[data-terrain-slider]');
      if(!input) return;
      const key=input.dataset.terrainSlider,i=Number(input.dataset.index),v=Number(input.value);
      edit(()=>{
        if(key==='height') profile()[i][1]=v;
        else {
          const b=sc.terrain.bumps[i];
          if(key==='x'||key==='z') b.centre[key==='x'?0:1]=v;
          else if(key==='bumpHeight') b.height=v/100;
          else b[key]=v;
          fitBump(b);
        }
      });
    };
    const position=e=>{
      const p=new DOMPoint(e.clientX,e.clientY).matrixTransform(svg.getScreenCTM().inverse());
      return [round((p.x-left)/(right-left)*2*crop-crop),round(clamp((bottom-p.y)/(bottom-top)*30,0,30))];
    };
    let gesture=null;
    svg.onpointerdown=e=>{
      if(e.button!==0 || gesture) return;
      const pts=bounds(sc), [z,h]=position(e);
      let i=e.target.closest('[data-point]')?.dataset.point;
      if(i!==undefined && (+i===0 || +i===pts.length-1)) return;
      if(i===undefined && (pts.length>=64 || z<=-crop+.1 || z>=crop-.1 || pts.some(p=>Math.abs(p[0]-z)<=.1))) return;
      svg.setPointerCapture(e.pointerId); activeGraph=svg; App.beginDrag();
      if(i===undefined) {
        i=pts.findIndex(p=>p[0]>z);
        App.dragMove(()=>profile().splice(i,0,[z,h]),options);
      }
      selected=Number(i);gesture=e.pointerId;
      svg.innerHTML=graph(profile(),crop);
    };
    svg.onpointermove=e=>{
      if(e.pointerId!==gesture) return;
      const pts=profile(), [z,h]=position(e);
      const min=pts[selected-1][0]+.11, max=pts[selected+1][0]-.11;
      const at=min<=max ? Math.round(clamp(z,min,max)*100)/100 : pts[selected][0];
      if (pts[selected][0]===at && pts[selected][1]===h) return;
      App.dragMove(()=>{pts[selected]=[at,h];},options);
      const slider=root.querySelector('[data-terrain-slider="height"]');
      if (slider) { slider.value=h; slider.previousElementSibling.textContent=h+' м'; }
      svg.innerHTML=graph(pts,crop);
    };
    function finish(e,cancel) {
      if(e.pointerId!==gesture) return;
      gesture=null;activeGraph=null;
      if(cancel) App.cancelDrag(); else App.endDrag(options);
      App.renderInspector();
    }
    svg.onpointerup=e=>finish(e,false);
    svg.onpointercancel=e=>finish(e,true);
    svg.onlostpointercapture=e=>finish(e,true);
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
  return {html,mount,resize,editing:()=>!!activeGraph?.isConnected || !!document.activeElement?.matches('.terrain-slider input:active')};
})();
