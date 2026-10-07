// Единый редакционный план. Существующие редакторы встраиваются в рабочие вкладки.
import { PUBLICATIONS_DATA_CLIENT_JS } from './publications_data.js';

export const PUBLICATIONS_VIEW_HTML = String.raw`
<section id="publications-view" style="display:none">
<style>
#publications-view{--pb-line:#edf0f3;--pb-muted:#747b88;--pb-blue:#0574f8;--pb-bg:#f4f5f7;font-size:14px;line-height:1.5;color:#17191e}
#publications-view [hidden]{display:none!important}
.pb-intro{display:flex;align-items:center;justify-content:space-between;gap:16px;margin:-6px 0 22px}
.pb-intro p{color:var(--pb-muted);font-size:12px;margin:0}
.pb-actions{display:flex;gap:12px;align-items:center;flex-shrink:0}
.pb-tabs{display:flex;gap:5px;margin:0 0 26px;overflow:auto;padding:0 0 2px}
.pb-tabs button{background:none;border:0;border-radius:22px;padding:10px 17px;font:inherit;font-size:13px;font-weight:650;white-space:nowrap;color:var(--pb-muted);cursor:pointer;transition:background .15s,color .15s}
.pb-tabs button:hover{background:#e9ecf1;color:#17191e}
.pb-tabs button.active{color:#fff;background:#17191e}
.pb-summary{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;margin-bottom:24px}
.pb-stat{border:0;border-radius:20px;padding:20px 24px;background:#fff;text-align:left;cursor:pointer;transition:background .15s}
.pb-stat:hover{background:#ebf3ff}
.pb-stat span{display:block;color:var(--pb-muted);font-size:12px;font-weight:550}
.pb-stat strong{font-size:36px;line-height:1.15;letter-spacing:-1.3px;display:block;margin-top:13px;font-weight:650;color:#17191e;font-variant-numeric:tabular-nums}
.pb-stat small{display:none}
.pb-stat:first-child{background:#0574f8}.pb-stat:first-child:hover{background:#0069e7}.pb-stat:first-child span{color:#d5e7ff}.pb-stat:first-child strong{color:#fff}
.pb-stat.attention strong{color:#cb4927}
.pb-panel{border:0;border-radius:22px;background:#fff;overflow:hidden}
.pb-panel-head{padding:24px 26px 18px;display:flex;gap:16px;justify-content:space-between;align-items:center;flex-wrap:wrap}
.pb-month-nav{display:flex;gap:10px;align-items:center}
.pb-month-title{font-size:20px;font-weight:650;letter-spacing:-.4px;min-width:176px}
.pb-icon-btn{border:0;border-radius:50%;background:var(--pb-bg);height:34px;width:34px;color:#747b88;cursor:pointer;font-size:23px;line-height:1;display:inline-flex;align-items:center;justify-content:center;flex-shrink:0}
.pb-icon-btn:hover{background:#e8ebf1;color:#17191e}
.pb-icon-btn:disabled{opacity:.35;cursor:default}
.pb-view-toggle{display:flex;gap:2px;background:var(--pb-bg);border-radius:22px;padding:4px}
.pb-view-toggle button{border:0;border-radius:18px;padding:7px 14px;background:none;color:var(--pb-muted);font-size:12px;font-weight:650;cursor:pointer}
.pb-view-toggle button.active{background:#fff;color:#17191e}
.pb-tools{padding:0 26px 16px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.pb-search{flex:1;min-width:180px;background:var(--pb-bg);border:0;border-radius:12px;padding:12px 15px;font:inherit;font-size:13px}
.pb-tools select{border:0;background:var(--pb-bg);border-radius:12px;padding:12px 15px;font:inherit;font-size:12px;color:#17191e;min-height:42px}
.pb-channels{display:flex;gap:8px;flex-wrap:wrap;padding:0 26px 22px}
.pb-channel{border:0;background:var(--pb-bg);border-radius:20px;font-size:12px;font-weight:550;cursor:pointer;padding:8px 13px;color:#747b88;display:flex;gap:7px;align-items:center;transition:background .15s,color .15s}
.pb-channel:hover{background:#e9ecf1;color:#17191e}
.pb-channel.active{background:#e8f2ff;color:#0574f8}
.pb-dot{height:7px;width:7px;border-radius:50%;display:inline-block;flex-shrink:0}
.pb-status{display:inline-flex;align-items:center;gap:5px;border-radius:16px;padding:5px 9px;font-size:11px;font-weight:550;background:#f0f2f5;color:#747b88;white-space:nowrap}
.pb-status.scheduled{color:#0574f8;background:#e8f2ff}
.pb-status.published{color:#168253;background:#eaf8f0}
.pb-status.failed,.pb-status.overdue{color:#c34527;background:#fff0ec}
.pb-status.processing{color:#a66b0e;background:#fff7e5}
.pb-legend{display:flex;gap:16px;flex-wrap:wrap;color:var(--pb-muted);font-size:11px;padding:16px 26px}
.pb-legend span{display:flex;gap:6px;align-items:center}
.pb-feedback{padding:14px 18px;background:#fff7e9;color:#966314;border:0;border-radius:14px;margin-bottom:18px;font-size:12px}
.pb-feedback:empty{display:none}
.pb-load-state{font-size:11px;color:var(--pb-muted)}
.pb-weekdays{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));border-bottom:1px solid var(--pb-line);background:#fafbfc}
.pb-weekdays span{padding:12px;font-size:11px;font-weight:550;color:var(--pb-muted)}
.pb-calendar{display:grid;grid-template-columns:repeat(7,minmax(0,1fr))}
.pb-day{min-height:156px;border-right:1px solid var(--pb-line);border-bottom:1px solid var(--pb-line);padding:12px 9px;min-width:0}
.pb-day:nth-child(7n){border-right:0}
.pb-day.outside{background:#fafbfc}
.pb-day.today{background:#f6faff}
.pb-day-top{display:flex;justify-content:space-between;align-items:center;margin-bottom:9px;color:var(--pb-muted);font-size:11px}
.pb-day-number{border:0;background:none;border-radius:50%;width:28px;height:28px;font-weight:550;font-size:12px;color:#17191e;cursor:pointer}
.pb-day.today .pb-day-number{background:#0574f8;color:#fff}
.pb-calendar-item{display:block;width:100%;text-align:left;border:0;border-radius:8px;background:#eef4fc;border-left:2px solid #0574f8;padding:7px 8px;margin:6px 0;cursor:pointer;font:inherit;min-width:0}
.pb-calendar-item:hover{filter:brightness(.97)}
.pb-calendar-item small{font-size:10px;color:#747b88;display:block}
.pb-calendar-item strong{font-weight:550;font-size:11px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;line-height:1.4}
.pb-more{background:none;border:0;color:#0574f8;cursor:pointer;font-size:11px;padding:4px}
.pb-date-heading{padding:12px 26px;background:#f8f9fb;font-size:12px;font-weight:550;display:flex;justify-content:space-between;color:#747b88}
.pb-date-heading span:first-child::first-letter{text-transform:uppercase}
.pb-date-heading span:last-child{font-variant-numeric:tabular-nums;color:#9ba1ac}
.pb-plan-row{display:grid;grid-template-columns:68px minmax(0,1fr) 160px 140px 20px;align-items:center;gap:18px;padding:20px 26px;border-bottom:1px solid #f0f2f5;cursor:pointer;outline-offset:-3px}
.pb-plan-row:hover{background:#fafbfc}
.pb-thumb{width:68px;height:50px;border-radius:10px;background:#f0f2f5;object-fit:cover;display:flex;align-items:center;justify-content:center;color:#8f97a4;font-size:20px;font-weight:550}
.pb-row-title{font-size:14px;font-weight:600;color:#17191e;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;line-height:1.5}
.pb-row-meta{font-size:11px;color:var(--pb-muted);margin-top:5px}
.pb-row-platforms{display:flex;gap:6px;flex-wrap:wrap;align-items:center}
.pb-platform-tag{display:inline-flex;align-items:center;gap:6px;font-size:11px;color:#747b88;white-space:nowrap}
.pb-row-arrow{color:#a6adb9;font-size:22px}
.pb-empty{padding:64px 24px;text-align:center;color:var(--pb-muted);font-size:13px;line-height:1.8}
.pb-empty strong{display:block;color:#17191e;font-size:16px;font-weight:600;margin-bottom:6px}
.pb-empty button{margin-top:16px}
.pb-list-foot{display:flex;justify-content:center;gap:14px;align-items:center;padding:20px;color:var(--pb-muted);font-size:12px}
.pb-drawer-backdrop{position:fixed;inset:0;background:#17191e55;z-index:10010;display:flex;justify-content:flex-end;backdrop-filter:blur(3px)}
.pb-drawer{--pb-line:#edf0f3;--pb-muted:#747b88;--pb-bg:#f4f5f7;background:#fff;color:#17191e;width:480px;max-width:100%;height:100%;padding:30px;overflow:auto;display:flex;flex-direction:column;gap:24px;box-shadow:-8px 0 36px #17191e0a}
.pb-drawer-head{display:flex;justify-content:space-between;align-items:center}
.pb-drawer-head h3{font-size:13px;font-weight:550;color:var(--pb-muted);margin:0}
.pb-drawer h4{font-size:24px;letter-spacing:-.6px;font-weight:650;line-height:1.4;margin:0}
.pb-drawer-preview{width:100%;max-height:210px;object-fit:cover;border-radius:16px}
.pb-detail-text{white-space:pre-wrap;color:#747b88;line-height:1.7;font-size:13px;max-height:250px;overflow:auto}
.pb-field{display:flex;flex-direction:column;gap:10px;font-size:12px;font-weight:550}
.pb-field input{background:var(--pb-bg);border:0;padding:13px 15px;border-radius:12px;font:inherit;font-size:14px;color:#17191e;min-height:46px}
.pb-drawer-note{color:var(--pb-muted);font-size:12px;line-height:1.7}
.pb-drawer-info{margin:12px 0 18px;font-size:12px;color:var(--pb-muted)}
.pb-drawer-info summary{cursor:pointer;list-style:none;display:inline-flex;align-items:center;gap:6px}
.pb-drawer-info summary::before{content:'i';width:16px;height:16px;border-radius:50%;background:#f0f2f5;display:inline-flex;align-items:center;justify-content:center;font-size:10px;font-weight:650}
.pb-drawer-info summary::-webkit-details-marker{display:none}
.pb-drawer-info p{margin-top:10px}
.pb-drawer-buttons{display:flex;gap:10px;flex-wrap:wrap}
.pb-drawer-error{color:#c34527;font-size:12px}
.pb-drawer-footer{border-top:1px solid var(--pb-line);padding-top:24px;margin-top:auto}
.pb-loading{padding:70px 24px;text-align:center;color:var(--pb-muted)}
#publications-view button:focus-visible,#publications-view input:focus-visible,#publications-view select:focus-visible,.pb-drawer button:focus-visible,.pb-drawer input:focus-visible,.pb-drawer a:focus-visible{outline:2px solid #0574f8;outline-offset:3px}
#publications-view .card{border:0;border-radius:20px;padding:24px;margin-bottom:20px;box-shadow:none}
#publications-view .card-head{flex-wrap:wrap;gap:12px}
@media(max-width:1050px){.pb-plan-row{grid-template-columns:58px minmax(0,1fr) 120px 110px 16px;gap:14px}.pb-day{min-height:130px}.pb-calendar-item strong{font-size:10px}.pb-calendar-item{padding:6px}.pb-thumb{width:58px;height:46px}.pb-month-title{min-width:150px;font-size:18px}.pb-stat{padding:20px}}
@media(max-width:760px){.pb-intro{gap:10px;margin-bottom:18px}.pb-summary{grid-template-columns:repeat(2,minmax(0,1fr));gap:12px;margin-bottom:20px}.pb-stat{padding:18px}.pb-tabs{gap:4px;margin-bottom:20px}.pb-tabs button{padding:9px 13px;font-size:12px}.pb-stat strong{font-size:30px}.pb-stat span{font-size:11px}.pb-month-title{font-size:16px;min-width:125px}.pb-panel-head{padding:20px 18px 16px;gap:14px}.pb-panel-head>.pb-view-toggle{margin-left:auto}.pb-month-nav{gap:7px}.pb-month-nav .btn-action{padding:8px 10px}.pb-tools{padding:0 18px 14px}.pb-channels{padding:0 18px 18px;gap:6px}.pb-channel{padding:7px 10px;font-size:11px}.pb-calendar{min-width:700px}.pb-weekdays{min-width:700px}.pb-calendar-scroll{overflow:auto}.pb-plan-row{grid-template-columns:52px minmax(0,1fr) 18px;gap:6px 12px;padding:18px}.pb-row-platforms{grid-column:2;grid-row:2}.pb-plan-row>.pb-status{grid-column:2;grid-row:3;justify-self:start;margin-top:3px}.pb-row-arrow{grid-column:3;grid-row:1}.pb-thumb{width:52px;height:44px;align-self:start}.pb-row-title{font-size:13px}.pb-drawer{padding:24px}.pb-drawer h4{font-size:21px}.pb-tools select{flex:1}.pb-search{width:100%;flex-basis:100%}.pb-load-state{display:none}.pb-date-heading,.pb-legend{padding:14px 18px}#publications-view .card{padding:20px}#threads-view .sc-row{flex-wrap:wrap;width:100%;min-width:0;max-width:100%}#th-list{min-width:0;grid-template-columns:minmax(0,1fr)}#threads-view .sc-row>div:last-child{width:100%;min-width:0;flex-direction:row!important;flex-wrap:wrap;justify-content:flex-end}}
@media(prefers-reduced-motion:reduce){#publications-view *{transition:none!important}}
</style>
<div class="pb-intro"><p>Время · МСК</p><div class="pb-actions"><span id="pb-updated" class="pb-load-state" aria-live="polite"></span><button type="button" class="btn-action" id="pb-refresh">Обновить</button></div></div>
<div class="pb-tabs" role="tablist" aria-label="Публикации"><button type="button" role="tab" data-pb-workspace="plan" class="active">Контент-план</button><button type="button" role="tab" data-pb-workspace="blog">Блог</button><button type="button" role="tab" data-pb-workspace="threads">Threads</button><button type="button" role="tab" data-pb-workspace="videos">Видео</button></div>
<div id="pb-plan-workspace" role="tabpanel">
 <div id="pb-feedback" class="pb-feedback" role="status"></div>
 <div id="pb-summary" class="pb-summary"></div>
 <div class="pb-panel">
  <div class="pb-panel-head"><div class="pb-month-nav"><button type="button" class="pb-icon-btn" id="pb-prev" aria-label="Предыдущий месяц">‹</button><div class="pb-month-title" id="pb-month"></div><button type="button" class="pb-icon-btn" id="pb-next" aria-label="Следующий месяц">›</button><button type="button" class="btn-action" id="pb-today">Сегодня</button></div><div class="pb-view-toggle" aria-label="Вид плана"><button type="button" data-pb-mode="list" class="active" aria-pressed="true">Список</button><button type="button" data-pb-mode="calendar" aria-pressed="false">Календарь</button></div></div>
  <div class="pb-tools"><input type="search" class="pb-search" id="pb-search" placeholder="Найти публикацию" aria-label="Поиск публикаций"><select id="pb-status" aria-label="Статус публикаций"><option value="upcoming">Предстоящие</option><option value="all">Все статусы</option><option value="failed">Требуют внимания</option><option value="undated">Без отдельной даты</option><option value="published">Опубликованные</option><option value="dated">Прошедшие даты блога</option></select><button type="button" class="btn-action" id="pb-reset" hidden>Сбросить фильтры</button></div>
  <div class="pb-channels" id="pb-channels"></div>
  <div id="pb-plan-content" aria-live="polite"><div class="pb-loading">Загружаем контент-план…</div></div>
  <div class="pb-legend"><span><i class="pb-dot" style="background:#0574F8"></i>Блог</span><span><i class="pb-dot" style="background:#374151"></i>Threads</span><span><i class="pb-dot" style="background:#cc3887"></i>Instagram</span><span><i class="pb-dot" style="background:#e34a3e"></i>YouTube</span></div>
 </div>
</div>
<div id="pb-workspace-mount" role="tabpanel"></div>
</section>`;

export function enhancePublicationsHtml(html) {
  return html
    .replace(/<button class="nav-item" data-feature="blog">[\s\S]*?<\/button>/, '<button class="nav-item" data-feature="publications"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 11h18M8 15h2M14 15h2"/></svg><span>Публикации</span></button>')
    .replace(/<button class="nav-item" data-feature="threads">[\s\S]*?<\/button>/, '')
    .replace(/<button class="nav-item" data-feature="social">[\s\S]*?<\/button>/, '');
}

const CLIENT = String.raw`
var PB_DAY=publicationDay, PB_NORMALIZE=normalizePublications, PB_FILTER=filterPublications, PB_MSK_TO_ISO=publicationMskToIso;
var pbState={blog:[],threads:{posts:[]},social:{posts:[],accounts:[]}}, pbItems=[], pbLoaded=false, pbLoading=false, pbWorkspace='plan', pbMode=localStorage.getItem('pdd-publications-mode')||'list', pbChannel='all', pbPage=0, pbMonth=PB_DAY(Date.now()).slice(0,7), pbFocusDate='', pbRange='', pbOpenId='', pbLoadId=0;
var PB_CHANNELS={blog:{name:'Блог',color:'#0574F8'},threads:{name:'Threads',color:'#374151'},instagram:{name:'Instagram',color:'#cc3887'},youtube:{name:'YouTube',color:'#e34a3e'}};
var PB_STATUS={scheduled:'Запланировано',queued:'Без отдельной даты',processing:'Публикуется',published:'Опубликовано',failed:'Ошибка',draft:'Черновик',dated:'Дата статьи'};
function pbEsc(v){return adminEsc(v);}
function pbDate(date,full){return new Date(date+'T12:00:00Z').toLocaleDateString('ru-RU',{day:'numeric',month:full?'long':'short',weekday:full?'long':undefined,timeZone:'Europe/Moscow'});}
function pbTags(item){return item.channels.map(function(k){var c=PB_CHANNELS[k];return '<span class="pb-platform-tag" title="'+pbEsc(PB_STATUS[(item.channelStatuses||{})[k]]||c.name)+'"><i class="pb-dot" style="background:'+c.color+'"></i>'+c.name+((item.channelStatuses||{})[k]==='published'?' ✓':(item.channelStatuses||{})[k]==='failed'?' !':'')+'</span>';}).join('');}
function pbStatus(item){var label=item.overdue?'Дата прошла':item.status==='queued'&&item.scheduleMode==='automatic'?(item.paused?'Канал на паузе':'По расписанию'):PB_STATUS[item.status]||item.status;return '<span class="pb-status '+(item.overdue?'overdue':item.status)+'">'+pbEsc(label)+'</span>';}
function pbRouteWorkspace(){var route=location.hash.slice(1).split('/');return route[0]==='publications'&&['blog','threads','videos'].indexOf(route[1])!==-1?route[1]:'plan';}
window.pubOpen=function(workspace,updateHistory){
 pbWorkspace=['plan','blog','threads','videos'].indexOf(workspace)!==-1?workspace:'plan';
 document.getElementById('publications-view').style.display=currentFeature==='publications'?'block':'none';
 document.getElementById('current-view-title').textContent='Публикации';
 document.getElementById('pb-plan-workspace').hidden=pbWorkspace!=='plan';
 document.getElementById('pb-workspace-mount').hidden=pbWorkspace==='plan';
 ['blog','threads','social'].forEach(function(k){var el=document.getElementById(k+'-view');if(el)el.style.display=(pbWorkspace===(k==='social'?'videos':k))?'block':'none';});
 document.querySelectorAll('[data-pb-workspace]').forEach(function(btn){var active=btn.dataset.pbWorkspace===pbWorkspace;btn.classList.toggle('active',active);btn.setAttribute('aria-selected',String(active));btn.tabIndex=active?0:-1;});
 if(updateHistory){var hash='#publications'+(pbWorkspace==='plan'?'':'/'+pbWorkspace);if(location.hash!==hash)history.pushState(null,'',hash);}
 if(pbWorkspace==='plan'){if(!pbLoaded&&!pbLoading)loadPublications();else pbRender();}
 else if(pbWorkspace==='blog')loadBlogArticles();else if(pbWorkspace==='threads')loadThreads();else loadSocial();
};
async function loadPublications(){
 var id=++pbLoadId;pbLoading=true;document.getElementById('pb-refresh').disabled=true;document.getElementById('pb-updated').textContent='Обновление…';
 var urls=['/api/admin/blog','/api/admin/threads/state','/api/admin/social/state'];
 var results=await Promise.allSettled(urls.map(async function(url){var res=await fetch(url,{signal:AbortSignal.timeout(15000)});if(res.status===401||res.status===403){checkAuthAndLoad();throw new Error('Нужно войти в админку');}var data=await res.json();if(!res.ok)throw new Error(data.error||'Ошибка '+res.status);return data;}));
 if(id!==pbLoadId)return;
 var names=['Блог','Threads','Видео'],keys=['blog','threads','social'],errors=[];
 results.forEach(function(r,i){if(r.status==='fulfilled')pbState[keys[i]]=r.value;else errors.push(names[i]+': '+r.reason.message);});
 pbLoaded=results.some(function(r){return r.status==='fulfilled';});pbLoading=false;pbItems=PB_NORMALIZE(pbState);document.getElementById('pb-refresh').disabled=false;
 document.getElementById('pb-feedback').textContent=errors.length?'Не удалось обновить '+errors.join('; ')+'. Если данные уже были загружены, показана последняя версия.':'';
 document.getElementById('pb-updated').textContent=errors.length?'Частичные данные':'Обновлено '+new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'});
 pbRender();
}
function pbSummary(){
 var today=PB_DAY(Date.now()),weekEnd=PB_DAY(Date.now()+6*86400000);
 var next=pbItems.filter(function(i){return i.date>=today&&i.date<=weekEnd&&['scheduled','processing'].indexOf(i.status)!==-1;}), attention=pbItems.filter(function(i){return i.status==='failed'||i.overdue;}), undated=pbItems.filter(function(i){return !i.date&&['queued','draft'].indexOf(i.status)!==-1;}),queue=pbItems.filter(function(i){return ['scheduled','queued','processing','failed','draft'].indexOf(i.status)!==-1;});
 document.getElementById('pb-summary').innerHTML=[['В ближайшие 7 дней',next.length,'С назначенной датой','upcoming'],['Требуют внимания',attention.length,'Ошибки и прошедшие даты','failed'],['Без отдельной даты',undated.length,'Проверьте расписание каналов','undated'],['В работе',queue.length,'Статьи, посты и ролики','all']].map(function(m){return '<button type="button" class="pb-stat '+(m[3]==='failed'&&m[1]?'attention':'')+'" data-pb-summary="'+m[3]+'" title="'+pbEsc(m[2])+'"><span>'+m[0]+'</span><strong>'+m[1]+'</strong><small>'+m[2]+'</small></button>';}).join('');
}
function pbFiltered(){
 var query=document.getElementById('pb-search').value.trim(), status=document.getElementById('pb-status').value;
 var items=PB_FILTER(pbItems,{channel:pbChannel,query:query});
 if(status==='upcoming')items=items.filter(function(i){return ['scheduled','queued','processing','draft'].indexOf(i.status)!==-1;});
 else if(status==='failed')items=items.filter(function(i){return i.status==='failed'||i.overdue;});
 else if(status==='undated')items=items.filter(function(i){return !i.date&&['queued','draft'].indexOf(i.status)!==-1;});
 else if(status!=='all')items=items.filter(function(i){return i.status===status;});
 var ignoreMonth=!!pbRange||['failed','undated'].indexOf(status)!==-1;
 if(pbRange==='week'){var today=PB_DAY(Date.now()),end=PB_DAY(Date.now()+6*86400000);items=items.filter(function(i){return i.date>=today&&i.date<=end&&['scheduled','processing'].indexOf(i.status)!==-1;});}
 if(!ignoreMonth)items=items.filter(function(i){return !i.date||i.date.slice(0,7)===pbMonth;});
 if(pbFocusDate)items=items.filter(function(i){return i.date===pbFocusDate;});
 return items;
}
function pbRender(){
 if(!document.getElementById('publications-view'))return;
 pbSummary();
 document.getElementById('pb-month').textContent=new Date(pbMonth+'-15T12:00:00Z').toLocaleDateString('ru-RU',{month:'long',year:'numeric',timeZone:'Europe/Moscow'});
 if(pbRange==='all')document.getElementById('pb-month').textContent='Все даты';
 if(pbRange==='week')document.getElementById('pb-month').textContent=pbDate(PB_DAY(Date.now()))+' — '+pbDate(PB_DAY(Date.now()+6*86400000));
 document.getElementById('pb-channels').innerHTML='<button type="button" class="pb-channel '+(pbChannel==='all'?'active':'')+'" data-pb-channel="all" aria-pressed="'+(pbChannel==='all')+'">Все площадки</button>'+Object.keys(PB_CHANNELS).map(function(k){var c=PB_CHANNELS[k];return '<button type="button" class="pb-channel '+(pbChannel===k?'active':'')+'" data-pb-channel="'+k+'" aria-pressed="'+(pbChannel===k)+'"><i class="pb-dot" style="background:'+c.color+'"></i>'+c.name+'</button>';}).join('');
 document.querySelectorAll('[data-pb-mode]').forEach(function(b){b.classList.toggle('active',b.dataset.pbMode===pbMode);b.setAttribute('aria-pressed',String(b.dataset.pbMode===pbMode));});
 document.getElementById('pb-reset').hidden=!pbRange&&!pbFocusDate&&pbChannel==='all'&&!document.getElementById('pb-search').value&&document.getElementById('pb-status').value==='upcoming';
 if(!pbLoaded){if(!pbLoading)document.getElementById('pb-plan-content').innerHTML='<div class="pb-empty"><strong>План не загрузился</strong>Нажмите «Обновить», чтобы повторить.</div>';return;}
 var items=pbFiltered();
 if(pbMode==='calendar')pbCalendar(items);else pbList(items);
}
function pbRow(item){
 var symbol=item.sourceType==='blog'?'A':item.sourceType==='threads'?'@':'▶';
 return '<div class="pb-plan-row" tabindex="0" role="button" data-pb-item="'+pbEsc(item.id)+'" aria-label="'+pbEsc('Открыть: '+item.title)+'">'+(item.thumbnail?'<img class="pb-thumb" src="'+pbEsc(item.thumbnail)+'" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'https://pdd-drive.ru/assets/og-image.png\';">':'<span class="pb-thumb" aria-hidden="true">'+symbol+'</span>')+'<div><div class="pb-row-title">'+pbEsc(item.title)+'</div><div class="pb-row-meta">'+pbEsc(item.time?item.time+' МСК':item.scheduleMode==='automatic'?'Расписание канала · '+(item.autoTime||'время не задано')+' МСК':item.date?'Дата статьи':item.sourceType==='threads'?'Назначьте дату для публикации':'Без даты')+'</div></div><div class="pb-row-platforms">'+pbTags(item)+'</div>'+pbStatus(item)+'<span class="pb-row-arrow" aria-hidden="true">›</span></div>';
}
function pbList(items){
 var el=document.getElementById('pb-plan-content');
 if(!items.length){el.innerHTML='<div class="pb-empty"><strong>В этом периоде публикаций нет</strong>Выберите другой месяц или измените фильтры.<br><button class="btn-action" type="button" data-pb-clear>Сбросить фильтры</button></div>';return;}
 var sorted=items.slice().sort(function(a,b){return String(a.date||'9999').localeCompare(String(b.date||'9999'))||String(a.time||'').localeCompare(String(b.time||''));});
 var pages=Math.ceil(sorted.length/30);pbPage=Math.min(pbPage,pages-1);var page=sorted.slice(pbPage*30,(pbPage+1)*30), html='',prev='';
 page.forEach(function(item){var date=item.date||'undated';if(prev!==date){var count=sorted.filter(function(i){return (i.date||'undated')===date;}).length;html+='<div class="pb-date-heading"><span>'+pbEsc(date==='undated'?'Без отдельной даты':pbDate(date,true))+'</span><span>'+count+'</span></div>';prev=date;}html+=pbRow(item);});
 html+='<div class="pb-list-foot"><span>'+Math.min(sorted.length,pbPage*30+1)+'–'+Math.min(sorted.length,(pbPage+1)*30)+' из '+sorted.length+'</span>'+(pages>1?'<button type="button" class="pb-icon-btn" data-pb-page="-1" aria-label="Предыдущая страница" '+(pbPage?'':'disabled')+'>‹</button><button type="button" class="pb-icon-btn" data-pb-page="1" aria-label="Следующая страница" '+(pbPage===pages-1?'disabled':'')+'>›</button>':'')+'</div>';el.innerHTML=html;
}
function pbCalendar(items){
 var first=new Date(pbMonth+'-01T12:00:00Z'),offset=(first.getUTCDay()+6)%7,start=first.getTime()-offset*86400000, count=new Date(first.getUTCFullYear(),first.getUTCMonth()+1,0).getDate(),cells=Math.ceil((offset+count)/7)*7, today=PB_DAY(Date.now()),html='<div class="pb-calendar-scroll"><div class="pb-weekdays">'+['Пн','Вт','Ср','Чт','Пт','Сб','Вс'].map(function(d){return '<span>'+d+'</span>';}).join('')+'</div><div class="pb-calendar">';
 for(var n=0;n<cells;n++){var date=new Date(start+n*86400000).toISOString().slice(0,10), dayItems=items.filter(function(i){return i.date===date;});html+='<div class="pb-day '+(date.slice(0,7)!==pbMonth?'outside':'')+' '+(date===today?'today':'')+'"><div class="pb-day-top"><button type="button" class="pb-day-number" data-pb-date="'+date+'" aria-label="'+pbEsc(pbDate(date,true))+'">'+Number(date.slice(8))+'</button><span>'+(dayItems.length||'')+'</span></div>'+dayItems.slice(0,3).map(function(i){var c=PB_CHANNELS[i.channels[0]];return '<button type="button" class="pb-calendar-item" style="border-color:'+c.color+'" data-pb-item="'+pbEsc(i.id)+'"><small>'+pbEsc(i.time||c.name)+'</small><strong>'+pbEsc(i.title)+'</strong></button>';}).join('')+(dayItems.length>3?'<button type="button" class="pb-more" data-pb-date="'+date+'">Ещё '+(dayItems.length-3)+'</button>':'')+'</div>';}
 html+='</div></div>';var undated=items.filter(function(i){return !i.date;});if(undated.length)html+='<div class="pb-date-heading"><span>Без отдельной даты</span><span>'+undated.length+'</span></div>'+undated.slice(0,5).map(pbRow).join('')+(undated.length>5?'<div class="pb-list-foot"><button type="button" class="btn-action" data-pb-undated>Показать все '+undated.length+'</button></div>':'');document.getElementById('pb-plan-content').innerHTML=html;
}
function pbCloseDrawer(){var el=document.getElementById('pb-drawer-bg');if(el)el.remove();pbOpenId='';if(window.__pbPreviousFocus&&window.__pbPreviousFocus.isConnected)window.__pbPreviousFocus.focus();}
function pbOpenDrawer(id){
 var item=pbItems.find(function(i){return i.id===id;});if(!item)return;
 pbCloseDrawer();window.__pbPreviousFocus=document.activeElement;pbOpenId=id;
 var bg=document.createElement('div');bg.id='pb-drawer-bg';bg.className='pb-drawer-backdrop';
 var editable=['published','processing','dated'].indexOf(item.status)===-1||item.sourceType==='blog';
 var dateValue=item.sourceType==='blog'?(item.date||''):(item.date?item.date+'T'+(item.time||'10:00'):'');
 var note=item.sourceType==='blog'?'Дата в контент-плане статьи. Публикация текста на сайте выполняется через редактор блога.':item.scheduleMode==='automatic'?'Без отдельной даты ролик может выйти по расписанию канала в '+(item.autoTime||'заданное время')+' МСК. Назначьте точную дату, чтобы управлять временем выхода.':item.sourceType==='threads'?'Без даты пост остаётся в очереди. После назначения даты он публикуется автоматически.':'Время публикации — по Москве.';
 if(item.sourceType==='threads'&&item.status==='failed')note+=' Смена даты сохраняет ошибку; повторную отправку можно запустить в редакторе Threads.';
 bg.innerHTML='<aside class="pb-drawer" role="dialog" aria-modal="true" aria-labelledby="pb-drawer-title"><div class="pb-drawer-head"><h3 id="pb-drawer-title">Публикация</h3><button type="button" class="pb-icon-btn" id="pb-drawer-close" aria-label="Закрыть">×</button></div><div class="pb-row-platforms">'+pbTags(item)+pbStatus(item)+'</div>'+(item.previewUrl?'<video class="pb-drawer-preview" style="max-height:300px;background:#172236" controls playsinline preload="none" src="'+pbEsc(item.previewUrl)+'"'+(item.thumbnail?' poster="'+pbEsc(item.thumbnail)+'"':'')+'></video>':item.thumbnail?'<img class="pb-drawer-preview" src="'+pbEsc(item.thumbnail)+'" alt="">':'')+'<h4>'+pbEsc(item.title)+'</h4>'+(item.text?'<div class="pb-detail-text">'+pbEsc(item.text)+'</div>':'')+(item.error?'<div class="pb-drawer-error">'+pbEsc(item.error)+'</div>':'')+(item.paused?'<div class="pb-feedback">Канал на паузе. Автоматическая публикация выключена в настройках.</div>':'')+'<form id="pb-date-form"><label class="pb-field">'+(item.sourceType==='blog'?'Дата статьи':'Дата и время · МСК')+'<input id="pb-date-input" type="'+(item.sourceType==='blog'?'date':'datetime-local')+'" value="'+dateValue+'" '+(editable?'':'disabled')+' required></label><details class="pb-drawer-info"><summary>О расписании</summary><p class="pb-drawer-note">'+pbEsc(note)+'</p></details><div class="pb-drawer-error" id="pb-date-error" role="alert"></div>'+(editable?'<div class="pb-drawer-buttons"><button type="submit" class="btn-action btn-primary" id="pb-date-save">Сохранить дату</button>'+(item.sourceType!=='blog'&&item.date?'<button type="button" class="btn-action" id="pb-date-clear">'+(item.sourceType==='social'?'Вернуть к расписанию канала':'Снять дату')+'</button>':'')+'</div>':'')+'</form><div class="pb-drawer-footer"><div class="pb-drawer-buttons"><button type="button" class="btn-action" id="pb-open-editor">Открыть в '+(item.sourceType==='blog'?'блоге':item.sourceType==='threads'?'Threads':'видео')+'</button>'+(item.permalink&&/^https?:\/\//.test(item.permalink)?'<a class="btn-action" href="'+pbEsc(item.permalink)+'" target="_blank" rel="noopener">Открыть публикацию ↗</a>':'')+'</div></div></aside>';
 document.body.appendChild(bg);bg.addEventListener('click',function(e){if(e.target===bg)pbCloseDrawer();});document.getElementById('pb-drawer-close').onclick=pbCloseDrawer;
 document.getElementById('pb-open-editor').onclick=function(){pbCloseDrawer();pubOpen(item.sourceType==='social'?'videos':item.sourceType,true);};
 document.getElementById('pb-date-form').onsubmit=function(e){e.preventDefault();pbSaveDate(item,false);};var clear=document.getElementById('pb-date-clear');if(clear)clear.onclick=function(){pbSaveDate(item,true);};document.getElementById('pb-drawer-close').focus();
 bg.addEventListener('keydown',function(e){if(e.key==='Tab'){var focusable=Array.from(bg.querySelectorAll('button:not([disabled]),input:not([disabled]),a[href]'));var first=focusable[0],last=focusable[focusable.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}});
}
async function pbSaveDate(item,clear){
 var save=document.getElementById('pb-date-save');if(!save||save.disabled)return;
 if(clear&&item.sourceType==='social'&&!confirm('Ролик вернётся к расписанию канала и сможет выйти в ближайшее окно. Продолжить?'))return;
 var value=document.getElementById('pb-date-input').value;if(!clear&&!value)return;
 var scheduledAt=null;try{if(!clear&&item.sourceType!=='blog'){scheduledAt=PB_MSK_TO_ISO(value);if(!scheduledAt)throw new Error('invalid date');}}catch(e){document.getElementById('pb-date-error').textContent='Укажите корректную дату';return;}
 if(scheduledAt&&scheduledAt<=new Date().toISOString()){document.getElementById('pb-date-error').textContent='Выберите время в будущем';return;}
 save.disabled=true;save.textContent='Сохранение…';var clearBtn=document.getElementById('pb-date-clear');if(clearBtn)clearBtn.disabled=true;
 try{
  if(item.sourceType==='blog')await adminFetchJson('/api/admin/blog/'+encodeURIComponent(item.sourceId),{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({datePublished:value})});
  else if(item.sourceType==='threads')await thApi('update',{id:item.sourceId,scheduledAt:scheduledAt});
  else await scApi('posts/update',{id:item.sourceId,scheduledAt:scheduledAt});
  pbCloseDrawer();adminToast('Дата сохранена');await loadPublications();
 }catch(e){var error=document.getElementById('pb-date-error');if(error)error.textContent='Не удалось сохранить: '+e.message;if(save.isConnected){save.disabled=false;save.textContent='Сохранить дату';if(clearBtn)clearBtn.disabled=false;}}
}
function pbClearFilters(){pbRange='';pbChannel='all';pbFocusDate='';pbPage=0;document.getElementById('pb-search').value='';document.getElementById('pb-status').value='upcoming';pbRender();}
(function(){
 var mount=document.getElementById('pb-workspace-mount');['blog','threads','social'].forEach(function(k){var el=document.getElementById(k+'-view');if(el)mount.appendChild(el);});
 VIEW_TITLES.publications='Публикации';
 document.querySelectorAll('.sidebar-menu .nav-item').forEach(function(btn){btn.addEventListener('click',function(){var active=btn.dataset.feature==='publications';document.getElementById('publications-view').style.display=active?'block':'none';if(active)pubOpen(pbRouteWorkspace(),false);else pbCloseDrawer();});});
 document.querySelectorAll('[data-pb-workspace]').forEach(function(btn){btn.onclick=function(){pubOpen(btn.dataset.pbWorkspace,true);};btn.onkeydown=function(e){if(['ArrowLeft','ArrowRight'].indexOf(e.key)===-1)return;e.preventDefault();var buttons=Array.from(document.querySelectorAll('[data-pb-workspace]')),index=buttons.indexOf(btn);var next=buttons[(index+(e.key==='ArrowRight'?1:-1)+buttons.length)%buttons.length];next.click();next.focus();};});
 document.querySelectorAll('[data-pb-mode]').forEach(function(btn){btn.onclick=function(){pbMode=btn.dataset.pbMode;pbFocusDate='';pbPage=0;localStorage.setItem('pdd-publications-mode',pbMode);pbRender();};});
 document.getElementById('pb-refresh').onclick=function(){if(pbWorkspace==='plan')loadPublications();else pubOpen(pbWorkspace,false);};
 document.getElementById('pb-search').oninput=function(){pbPage=0;pbRender();};document.getElementById('pb-status').onchange=function(){pbRange='';pbFocusDate='';pbPage=0;pbRender();};document.getElementById('pb-reset').onclick=pbClearFilters;
 document.getElementById('pb-channels').onclick=function(e){var b=e.target.closest('[data-pb-channel]');if(b){pbChannel=b.dataset.pbChannel;pbPage=0;pbRender();}};
 document.getElementById('pb-summary').onclick=function(e){var b=e.target.closest('[data-pb-summary]');if(b){document.getElementById('pb-status').value=b.dataset.pbSummary;pbMonth=PB_DAY(Date.now()).slice(0,7);pbRange=b.dataset.pbSummary==='upcoming'?'week':b.dataset.pbSummary==='all'?'all':'';pbFocusDate='';pbPage=0;pbMode='list';pbRender();}};
 function shiftMonth(amount){var d=new Date(pbMonth+'-15T12:00:00Z');d.setUTCMonth(d.getUTCMonth()+amount);pbMonth=d.toISOString().slice(0,7);pbRange='';pbFocusDate='';pbPage=0;pbRender();}
 document.getElementById('pb-prev').onclick=function(){shiftMonth(-1);};document.getElementById('pb-next').onclick=function(){shiftMonth(1);};document.getElementById('pb-today').onclick=function(){pbMonth=PB_DAY(Date.now()).slice(0,7);pbRange='';pbFocusDate='';pbPage=0;pbRender();};
 var content=document.getElementById('pb-plan-content');content.onclick=function(e){var item=e.target.closest('[data-pb-item]'),date=e.target.closest('[data-pb-date]'),page=e.target.closest('[data-pb-page]');if(item)pbOpenDrawer(item.dataset.pbItem);else if(date){pbRange='';pbMonth=date.dataset.pbDate.slice(0,7);pbFocusDate=date.dataset.pbDate;pbMode='list';pbPage=0;pbRender();}else if(page){pbPage+=Number(page.dataset.pbPage);pbRender();}else if(e.target.closest('[data-pb-clear]'))pbClearFilters();else if(e.target.closest('[data-pb-undated]')){document.getElementById('pb-status').value='undated';pbMode='list';pbPage=0;pbRender();}};
 content.onkeydown=function(e){if((e.key==='Enter'||e.key===' ')&&e.target.matches('[data-pb-item][role="button"]')){e.preventDefault();pbOpenDrawer(e.target.dataset.pbItem);}};
 document.addEventListener('keydown',function(e){if(e.key==='Escape')pbCloseDrawer();});
 document.addEventListener('pdd:publications-changed',function(){pbLoaded=false;});
 function route(){if(location.hash.split('/')[0]==='#publications'&&currentFeature==='publications')pubOpen(pbRouteWorkspace(),false);}
 window.addEventListener('popstate',route);window.addEventListener('hashchange',route);
})();
`;
export const PUBLICATIONS_CLIENT_JS = PUBLICATIONS_DATA_CLIENT_JS + '\n' + CLIENT;
