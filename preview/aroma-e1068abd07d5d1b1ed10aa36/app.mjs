import { getMatches, getAvailableNotes, getPerfumesForGender, removeNoteAt, isCompleteSelection } from './game-model.mjs';
import { noteArtwork } from './note-art.mjs';
import { createGameMotion } from './motion.mjs';

const root = document.querySelector('#game');
const announcement = document.querySelector('#announcement');
const audienceSwitch = document.querySelector('.audience-switch');
const motion = createGameMotion(root);
const imageCache = [];
const warmedImages = new Set();
const icons = {
  arrow:'<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4 12h15m-6-6 6 6-6 6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  back:'<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M20 12H5m6-6-6 6 6 6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  reset:'<svg viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M4.2 6.5A6.4 6.4 0 1 1 3.6 12M4 2v5h5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  close:'<svg viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="m6 6 8 8M14 6l-8 8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
};
const preferred = ['Грейпфрут','Ирис','Ваниль','Чёрная смородина','Жасмин','Кедр','Замша'];
const familyGroups = [
  { label:'Все', value:'all' },
  { label:'Цитрусы', value:'citrus', families:['Цитрусовые'] },
  { label:'Цветы', value:'floral', families:['Цветы'] },
  { label:'Тёплые', value:'warm', families:['Тёплые аккорды','Дерево и смолы','Пряности'] },
  { label:'Свежие', value:'fresh', families:['Фрукты и ягоды','Зелень и свежесть'] }
];
let catalog;
let gender = 'women';
const drafts = new Map();
let choices = [];
let family = 'all';
let view = 'game';
let resultIndex = 0;
let lastPointerAction;
const escape = s => String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const ordinal = ['Первая нота','Вторая нота','Третья нота'];

function ingredient(name) {
  const art = noteArtwork[name];
  if (!art) throw new Error(`Missing note artwork: ${name}`);
  const x = art.columns === 1 ? 50 : art.column / (art.columns - 1) * 100;
  const y = art.rows === 1 ? 50 : art.row / (art.rows - 1) * 100;
  return `<span class="ingredient" data-art="${escape(name)}" style="background-image:url('${art.file}');background-size:${art.columns*100}% ${art.rows*100}%;background-position:${x}% ${y}%" aria-hidden="true"></span>`;
}
function resetPalette() {family='all';}
function activePerfumes() {return getPerfumesForGender(catalog.perfumes, gender);}
function say(message) {announcement.textContent=message;}
function warmResults() {
  const sources = [...getMatches(activePerfumes(), choices).map(perfume => perfume.image), './public/assets/perfume-light-backdrop.webp'];
  for (const source of sources) {
    if (warmedImages.has(source)) continue;
    warmedImages.add(source);
    const image = new Image();
    image.fetchPriority = 'low';
    image.decoding = 'async';
    image.src = source;
    imageCache.push(image);
    image.decode().catch(() => {});
  }
}
function focusHeading() {root.querySelector('h2')?.focus({preventScroll:true});}
function focusAfterChange(event, removed) {
  if (event.detail === 0 && view === 'game') {
    const options = [...root.querySelectorAll('.note-choice')];
    const target = options.find(button => button.dataset.note === removed) || options[0];
    target?.focus({preventScroll:true});
    // Keep keyboard focus visible inside the list without moving the page.
    const grid=root.querySelector('.note-grid');
    if(target && grid){
      const item=target.getBoundingClientRect(), bounds=grid.getBoundingClientRect();
      const fade=parseFloat(getComputedStyle(grid).getPropertyValue('--scroll-fade')) || 0;
      if(item.top<bounds.top+fade)grid.scrollTop+=item.top-bounds.top-fade-4;
      else if(item.bottom>bounds.bottom)grid.scrollTop+=item.bottom-bounds.bottom+4;
    }
  } else focusHeading();
}
function removeMark() {return `<span class="remove-note" aria-hidden="true">${icons.close}</span>`;}
function composition() {
  return `<aside class="composition" aria-label="Ваша комбинация"><div class="composition-heading"><h3>Ваша комбинация</h3><span class="selection-count" aria-label="Выбрано ${choices.length} из 3 нот"><b>${choices.length}</b><span aria-hidden="true">/</span>3</span></div><div class="mix-notes">${ordinal.map((label,i)=>`<button class="mix-slot ${choices[i]?'filled':''} ${i===choices.length?'current':''}" data-remove="${i}" ${!choices[i]?'disabled':''} aria-label="${choices[i]?`Убрать ноту ${escape(choices[i])}`:escape(label)+' — ещё не выбрана'}"><span class="slot-art">${choices[i]?ingredient(choices[i])+removeMark():`<span class="slot-number">0${i+1}</span>`}</span>${choices[i]?`<span class="slot-label">${escape(choices[i])}</span>`:''}</button>`).join('')}</div></aside>`;
}
function noteOptions() {
  const available = getAvailableNotes(activePerfumes(), choices);
  const group = familyGroups.find(x=>x.value===family);
  let filtered = available.filter(name=>(!group.families||group.families.includes(catalog.notes.find(n=>n.name===name)?.family)));
  filtered.sort((a,b)=>{
    const ia=preferred.indexOf(a),ib=preferred.indexOf(b);
    return (ia<0?99:ia)-(ib<0?99:ib)||a.localeCompare(b,'ru');
  });
  return {available,displayed:filtered};
}
function palette() {
  const {available,displayed}=noteOptions();
  return `<div class="palette"><h2 class="sr-only" tabindex="-1">Выберите ноту · ${choices.length} из 3 выбрано</h2><div class="filters"><div class="filter-scroll" role="group" aria-label="Группы нот">${familyGroups.map(g=>`<button class="filter" data-family="${g.value}" aria-pressed="${family===g.value}" ${g.families&&!available.some(name=>g.families.includes(catalog.notes.find(n=>n.name===name)?.family))?'disabled':''}>${g.label}</button>`).join('')}</div></div><div class="note-grid" aria-label="Доступные ноты">${displayed.length?displayed.map(name=>`<button class="note-choice" data-note="${escape(name)}" aria-label="Выбрать ноту ${escape(name)}">${ingredient(name)}<span class="note-label">${escape(name)}</span><span class="add-note" aria-hidden="true">+</span></button>`).join(''):`<div class="empty-search">Нет подходящих нот<button data-action="clear-filter">Сбросить фильтр</button></div>`}</div></div>`;
}
function result() {
  const matches = getMatches(activePerfumes(),choices);
  const perfume = matches[resultIndex];
  if(!perfume) {view='game';choices=[];resetPalette();render();return;}
  root.className='game-shell result-shell';
  root.innerHTML=`<div class="result-content scene-enter"><div class="product-art" data-perfume="${escape(perfume.id)}"><span class="result-bloom" aria-hidden="true"></span><div class="product-bottle"><img src="${escape(perfume.image)}" alt="${escape(perfume.brand+' '+perfume.name)}"><span class="bottle-glint" style="--bottle-mask:url('${escape(perfume.image)}')" aria-hidden="true"><span class="bottle-glint-beam"></span></span></div></div><div class="result-copy"><p class="product-brand">${escape(perfume.brand)}</p><h2 tabindex="-1">${escape(perfume.name)}</h2><p class="product-description">${escape(perfume.description)}</p><div class="result-notes" aria-label="Ваши ноты">${choices.map((n,i)=>`<button class="result-note" data-remove="${i}" aria-label="Убрать ноту ${escape(n)}"><span class="result-note-art">${ingredient(n)}${removeMark()}</span><span>${escape(n)}</span></button>`).join('')}</div><div class="result-actions"><button class="gold-button" data-action="reset">${icons.reset}Собрать ещё</button>${matches.length>1?`<div class="result-paging" aria-label="Подходящие ароматы"><button class="paging-button" data-page="-1" aria-label="Предыдущий аромат">${icons.back}</button><span>${resultIndex+1} / ${matches.length}</span><button class="paging-button" data-page="1" aria-label="Следующий аромат">${icons.arrow}</button></div>`:''}</div></div></div>`;
}
function render() {
  root.setAttribute('aria-busy','false');
  root.dataset.gender=gender;
  if(view==='result')return result();
  root.className='game-shell';
  root.innerHTML=`<div class="game-body">${palette()}${composition()}</div>`;
}
audienceSwitch.addEventListener('click', event => {
  const button = event.target.closest('button[data-gender]');
  if (!catalog || !button || button.disabled || button.dataset.gender === gender) return;
  const before = motion.capture();
  drafts.set(gender, {choices: [...choices], family, view, resultIndex,
    noteScroll: root.querySelector('.note-grid')?.scrollTop || 0,
    filterScroll: root.querySelector('.filter-scroll')?.scrollLeft || 0});
  gender = button.dataset.gender;
  const saved = drafts.get(gender);
  choices = saved ? [...saved.choices] : [];
  family = saved?.family || 'all';
  view = saved?.view || 'game';
  resultIndex = saved?.resultIndex || 0;
  lastPointerAction = undefined;
  audienceSwitch.dataset.gender = gender;
  audienceSwitch.querySelectorAll('button').forEach(option => option.setAttribute('aria-pressed', String(option.dataset.gender === gender)));
  render();
  const grid = root.querySelector('.note-grid');
  if (grid) grid.scrollTop = saved?.noteScroll || 0;
  if (choices.length) warmResults();
  motion.play(before, {kind: 'gender', pointer: event.detail > 0, filterScroll: saved?.filterScroll || 0});
  const label = gender === 'women' ? 'Женские ароматы' : 'Мужские ароматы';
  say(view === 'result' ? `${label}. Ваш аромат — ${getMatches(activePerfumes(),choices)[resultIndex].name}` : `${label}. Выбрано ${choices.length} из 3 нот.`);
});
root.addEventListener('keydown', event => {
  if(event.repeat && ['Enter',' '].includes(event.key)) event.preventDefault();
});
root.addEventListener('click', event => {
  const button=event.target.closest('button');
  if(!button||button.disabled)return;
  if(event.detail>0 && (button.dataset.note || button.dataset.remove!==undefined || button.dataset.action==='reset')){
    const now=performance.now();
    if(lastPointerAction && now-lastPointerAction.time<220 && Math.hypot(event.clientX-lastPointerAction.x,event.clientY-lastPointerAction.y)<14)return;
    lastPointerAction={time:now,x:event.clientX,y:event.clientY};
  }
  if(button.dataset.note){
    const note=button.dataset.note;
    if(!getAvailableNotes(activePerfumes(),choices).includes(note))return;
    const before=motion.capture(button);
    choices.push(note);resetPalette();
    warmResults();
    if(isCompleteSelection(choices)){view='result';resultIndex=0;}
    render();focusAfterChange(event);
    const needsScroll=view==='result'&&root.getBoundingClientRect().top<0;
    motion.play(before,{kind:'select',note,pointer:event.detail>0,skipTravel:needsScroll});
    if(needsScroll)root.scrollIntoView({block:'start',behavior:motion.reduced()?'instant':'smooth'});
    say(choices.length<3?`${note}. Выбрано ${choices.length} из 3 нот.`:`Ваш аромат — ${getMatches(activePerfumes(),choices)[0].name}`);
    return;
  }
  if(button.dataset.remove!==undefined){
    const index=Number(button.dataset.remove);
    if(index>=choices.length)return;
    const removed=choices[index];
    const before=motion.capture();
    choices=removeNoteAt(choices,index);view='game';resetPalette();render();focusAfterChange(event,removed);
    motion.play(before,{kind:'remove',note:removed,pointer:event.detail>0});
    say(`${removed} — нота удалена. Выбрано ${choices.length} из 3.`);return;
  }
  if(button.dataset.family){
    if(family===button.dataset.family)return;
    const before=motion.capture();family=button.dataset.family;render();
    root.querySelector(`[data-family="${family}"]`)?.focus({preventScroll:true});
    motion.play(before,{kind:'filter',pointer:event.detail>0});return;
  }
  if(button.dataset.page){const before=motion.capture();const matches=getMatches(activePerfumes(),choices);resultIndex=(resultIndex+Number(button.dataset.page)+matches.length)%matches.length;render();focusHeading();motion.play(before,{kind:'page'});say(matches[resultIndex].name);return;}
  const action=button.dataset.action;
  if(action==='reset'){const before=motion.capture();choices=[];view='game';resultIndex=0;resetPalette();render();focusAfterChange(event);motion.play(before,{kind:'reset',pointer:event.detail>0});say('Новая комбинация. Выберите первую ноту.');}
  if(action==='clear-filter'){const before=motion.capture();resetPalette();render();focusAfterChange(event);motion.play(before,{kind:'filter'});}
  if(action==='retry')load();
});
async function load(){
  try{
    root.setAttribute('aria-busy','true');
    const response=await fetch('./data/runtime-catalog.json');if(!response.ok)throw new Error('Catalog unavailable');
    catalog=await response.json();
    for (const value of ['women','men']) if (!getPerfumesForGender(catalog.perfumes,value).length) throw new Error(`Empty fragrance category: ${value}`);
    for(const note of catalog.notes)if(!noteArtwork[note.name])throw new Error(`Missing note artwork: ${note.name}`);
    // Product images warm after the first choice so they do not compete with notes.
    render();motion.play(null);
    audienceSwitch.querySelectorAll('button').forEach(button => {button.disabled=false;});
  }catch(error){root.setAttribute('aria-busy','false');root.innerHTML='<div class="palette"><h2>Не удалось открыть коллекцию</h2><p>Попробуйте загрузить её ещё раз.</p><button class="gold-button" data-action="retry">Повторить</button></div>';console.error(error);}
}
load();
