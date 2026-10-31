// Last successful aggregates render after a lightweight session check, while
// the expensive stats request refreshes them. Cache never authorizes access.
export const ANALYTICS_LOADER_JS = String.raw`
var anCachePrefix = 'pdd-admin-analytics-v1:';
var anActiveLoad = null;
var anAuthenticated = false;
function anClearCache() {
  try {
    Object.keys(localStorage).filter(function(k){return k.indexOf(anCachePrefix)===0;})
      .forEach(function(k){localStorage.removeItem(k);});
  } catch (_) {}
}
function anReadCache(key) {
  try {
    var saved=JSON.parse(localStorage.getItem(key));
    if(saved && Number.isFinite(saved.at) && saved.at<=Date.now() && Date.now()-saved.at<7*86400000
      && saved.data && saved.data.totals && Array.isArray(saved.data.timeline)) return saved;
  } catch (_) {}
  return null;
}
function anWriteCache(key, data, at) {
  // Exclude the legacy recent-event feed; persist dashboard aggregates only.
  var snapshot={};
  ['totals','previous','timeline','usage','storeReports','users','sources','targets','campaigns','platforms','apps','countries']
    .forEach(function(k){if(data[k]!==undefined)snapshot[k]=data[k];});
  try { localStorage.setItem(key,JSON.stringify({at:at,data:snapshot})); } catch (_) {}
}
function anUpdatedLabel(at) {
  return new Date(at).toLocaleString('ru-RU',{timeZone:'Europe/Moscow',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'})+' МСК';
}
function anAuthRequired() {
  anAuthenticated=false;
  anClearCache();
  window.__anData=null;
  document.getElementById('login-overlay').style.display='flex';
  document.getElementById('app').style.display='none';
}
async function checkAuthAndLoad() {
  var key=anCachePrefix+currentApp+':'+currentDays;
  if(anActiveLoad && anActiveLoad.key===key)return;
  if(anActiveLoad)anActiveLoad.controller.abort();
  var load={key:key,controller:new AbortController()};
  anActiveLoad=load;
  var requestId=++window.__analyticsRequestId;
  var state=document.getElementById('admin-data-state');
  var banner=document.getElementById('admin-error-banner');
  var refresh=document.getElementById('refresh-btn');
  var cached=null;
  var timeout=setTimeout(function(){load.controller.abort();},150000);
  if(refresh){refresh.disabled=true;refresh.setAttribute('aria-busy','true');refresh.setAttribute('aria-label','Обновление аналитики');}
  if(state){state.className='admin-data-state loading';state.textContent='Обновление…';}
  if(banner)banner.classList.remove('visible');
  try {
    if(!anAuthenticated){
      var session=await fetch('/api/admin/session',{cache:'no-store',signal:load.controller.signal});
      if(requestId!==window.__analyticsRequestId)return;
      if(session.status===401 || session.status===403){anAuthRequired();return;}
      if(!session.ok)throw new Error('Не удалось проверить сессию');
      anAuthenticated=true;
    }
    document.getElementById('login-overlay').style.display='none';
    document.getElementById('app').style.display='flex';
    cached=anReadCache(key);
    if(cached){
      renderDashboard(cached.data);
      if(state)state.textContent='Данные на '+anUpdatedLabel(cached.at)+' · обновление…';
    } else if(window.__anCacheKey!==key){
      // Do not label another period's numbers as the newly selected period.
      renderDashboard({totals:{},timeline:[],sources:[]});
    }
    window.__anCacheKey=key;
    var response=await fetch('/api/admin/stats?days='+currentDays+'&app='+currentApp,{cache:'no-store',signal:load.controller.signal});
    if(requestId!==window.__analyticsRequestId)return;
    if(response.status===401 || response.status===403){anAuthRequired();return;}
    if(!response.ok)throw new Error('Сервер вернул ошибку '+response.status);
    var data=await response.json();
    if(requestId!==window.__analyticsRequestId)return;
    renderDashboard(data);
    var at=Date.now();
    // A missing users block indicates an incomplete server refresh. Keep the
    // previous complete snapshot available for the next visit.
    if(data.users)anWriteCache(key,data,at);
    window.__analyticsUpdatedAt=new Date(at);
    if(state){state.className='admin-data-state ready';state.textContent='Обновлено '+anUpdatedLabel(at);}
  } catch(err) {
    if(requestId!==window.__analyticsRequestId)return;
    if(state){state.className='admin-data-state error';state.textContent=cached?'Данные на '+anUpdatedLabel(cached.at):'Нет обновления';}
    var errorText=document.getElementById('admin-error-text');
    if(errorText)errorText.textContent=cached?'Не удалось обновить данные. Показаны сохранённые значения.':'Не удалось загрузить данные. Попробуйте обновить ещё раз.';
    if(banner)banner.classList.add('visible');
    console.error('checkAuthAndLoad error:',err);
  } finally {
    clearTimeout(timeout);
    if(requestId===window.__analyticsRequestId){
      anActiveLoad=null;
      if(refresh){refresh.disabled=false;refresh.setAttribute('aria-busy','false');refresh.setAttribute('aria-label','Обновить аналитику');}
    }
  }
}
`;
