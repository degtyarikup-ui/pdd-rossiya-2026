// Shared read lifecycle for the admin only. Private records stay in tab memory;
// every endpoint still performs its own server-side authorization.
export const ADMIN_DATA_STYLES = `<style>
.admin-view-skeleton{width:100%;min-width:0;padding:6px 0 22px;box-sizing:border-box}
.admin-skeleton-cards{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px;margin:0 0 18px}
.admin-skeleton-card,.admin-skeleton-table{background:var(--card-bg,#fff);border-radius:20px;padding:24px;min-width:0}
.admin-skeleton-bar{height:12px;border-radius:6px;background:var(--surface-gray,#edf0f4);width:45%;animation:adminSkeletonPulse 1.6s ease-in-out infinite}
.admin-skeleton-card .admin-skeleton-bar+div{height:34px;width:62%;margin-top:25px}
.admin-skeleton-row{display:grid;grid-template-columns:1fr 2fr 1fr;gap:24px;padding:21px 0;border-bottom:1px solid var(--border,#edf0f3)}
.admin-skeleton-row:last-child{border:0}.admin-skeleton-row .admin-skeleton-bar{width:80%}.admin-skeleton-row .admin-skeleton-bar:last-child{width:55%;justify-self:end}
.admin-first-load>:not(style):not(.admin-view-skeleton):not(.admin-load-notice):not([data-admin-keep]){display:none!important}
.admin-load-notice{display:flex;align-items:center;justify-content:flex-end;gap:10px;min-height:18px;margin:0 0 10px;font-size:11px;line-height:1.5;color:var(--text-muted,#747b88)}
.admin-load-notice[hidden],.admin-view-skeleton[hidden]{display:none!important}
.admin-load-notice button{border:0;background:transparent;padding:4px;color:var(--primary,#0574f8);font:inherit;cursor:pointer}
.admin-load-notice[data-state=refreshing]:before{content:'';height:5px;width:5px;border-radius:50%;background:var(--primary,#0574f8);animation:adminSkeletonPulse 1.6s infinite}
.admin-load-notice[data-state=stale],.admin-load-notice[data-state=error]{color:#b25e27}
@keyframes adminSkeletonPulse{0%,100%{opacity:.45}50%{opacity:1}}
@media(max-width:600px){.admin-skeleton-cards{gap:8px}.admin-skeleton-card,.admin-skeleton-table{padding:16px}.admin-skeleton-row{gap:12px}.admin-skeleton-card .admin-skeleton-bar{width:70%}}
@media(prefers-reduced-motion:reduce){.admin-skeleton-bar,.admin-load-notice:before{animation:none!important}}
</style>`;

export const ADMIN_DATA_CLIENT_JS = String.raw`
(function(){
  var nativeFetch=window.fetch.bind(window), cache=new Map(), inflight=new Map(), views=new Map();
  var epoch=0, authEpoch=0, authenticated=false, checkedAt=0, sessionFlight=null, bytes=0;
  var writes=new Set(), TTL=45000, MAX_BYTES=8*1024*1024;
  function cancelled(){var e=new Error('Запрос отменён');e.name='AbortError';return e;}
  function copy(value){return typeof structuredClone==='function'?structuredClone(value):JSON.parse(JSON.stringify(value));}
  function keyFor(input){var u=new URL(typeof input==='string'?input:input.url,location.href);return u.origin===location.origin&&u.pathname.indexOf('/api/admin/')===0?u.pathname+u.search:null;}
  function invalidate(){
    epoch++;cache.clear();bytes=0;
    inflight.forEach(function(f){f.controller.abort();});inflight.clear();
    // The analytics snapshot is aggregate-only, but must not survive a write.
    try{Object.keys(localStorage).filter(function(k){return k.indexOf('pdd-admin-analytics-v1:')===0;}).forEach(function(k){localStorage.removeItem(k);});}catch(_){}
  }
  function reset(){
    authEpoch++;authenticated=false;checkedAt=0;sessionFlight=null;invalidate();
    views.forEach(function(v){v.hasData=false;v.cold=true;v.failed.clear();});
  }
  function authRequired(){
    reset();
    if(typeof anAuthRequired==='function')anAuthRequired();
    else {var app=document.getElementById('app'),login=document.getElementById('login-overlay');if(app)app.style.display='none';if(login)login.style.display='flex';}
  }
  async function ensureSession(){
    if(authenticated && Date.now()>=checkedAt && Date.now()-checkedAt<TTL)return;
    if(sessionFlight)return sessionFlight;
    var identity=authEpoch;
    var promise=(async function(){
      var controller=new AbortController(),timer=setTimeout(function(){controller.abort();},15000);
      try{
        var response=await nativeFetch('/api/admin/session',{cache:'no-store',signal:controller.signal});
        if(identity!==authEpoch)throw cancelled();
        if(response.status===401||response.status===403){authRequired();throw new Error('Требуется вход');}
        if(!response.ok)throw new Error('Не удалось проверить сессию');
        authenticated=true;checkedAt=Date.now();
      }finally{clearTimeout(timer);}
    })();
    sessionFlight=promise;
    try{return await promise;}finally{if(sessionFlight===promise)sessionFlight=null;}
  }
  function viewState(id){
    if(!id)return null;var el=typeof id==='string'?document.getElementById(id):id;if(!el)return null;
    var v=views.get(el);if(v)return v;
    var skeleton=document.createElement('div');skeleton.className='admin-view-skeleton';skeleton.setAttribute('role','status');skeleton.setAttribute('aria-label','Загрузка данных');skeleton.hidden=true;
    var card='<div class="admin-skeleton-card"><div class="admin-skeleton-bar"></div><div class="admin-skeleton-bar"></div></div>';
    var row='<div class="admin-skeleton-row"><i class="admin-skeleton-bar"></i><i class="admin-skeleton-bar"></i><i class="admin-skeleton-bar"></i></div>';
    skeleton.innerHTML='<div aria-hidden="true"><div class="admin-skeleton-cards">'+card.repeat(3)+'</div><div class="admin-skeleton-table">'+row.repeat(5)+'</div></div>';
    var notice=document.createElement('div');notice.className='admin-load-notice';notice.setAttribute('role','status');notice.setAttribute('aria-live','polite');notice.hidden=true;
    Array.from(el.children).forEach(function(child){if(child.matches('.ec-toolbar,.pb-intro,.pb-tabs,.pb-workspaces'))child.setAttribute('data-admin-keep','');});
    v={el:el,skeleton:skeleton,notice:notice,pending:0,hasData:false,cold:true,failed:new Set(),retries:new Map()};views.set(el,v);return v;
  }
  function paint(v){
    if(!v)return;
    if(v.notice.parentNode!==v.el){
      var keep=Array.from(v.el.children).filter(function(child){return child.hasAttribute('data-admin-keep');}).pop();
      if(keep)keep.after(v.notice);else v.el.prepend(v.notice);
    }
    if(v.skeleton.parentNode!==v.el)v.notice.after(v.skeleton);
    var state=v.pending?(v.cold?'loading':'refreshing'):(v.failed.size?(v.hasData?'stale':'error'):'ready');
    v.el.dataset.loadState=state;v.el.setAttribute('aria-busy',v.pending?'true':'false');
    v.el.classList.toggle('admin-first-load',state==='loading');v.skeleton.hidden=state!=='loading';
    v.notice.hidden=state==='ready'||state==='loading';v.notice.dataset.state=state;
    v.notice.textContent=state==='refreshing'?'Обновление…':(state==='stale'?'Не удалось обновить данные':'Не удалось загрузить данные');
    if(state==='stale'||state==='error'){
      var button=document.createElement('button');button.type='button';button.textContent='Повторить';button.onclick=function(){Array.from(v.failed).forEach(function(key){var retry=v.retries.get(key);if(retry)retry();});};v.notice.appendChild(button);
    }
  }
  function remember(key,data,at){
    var size=JSON.stringify(data).length*2;if(size>2*1024*1024)return;
    if(cache.has(key)){bytes-=cache.get(key).size;cache.delete(key);}
    cache.set(key,{data:copy(data),at:at,size:size});bytes+=size;
    while(cache.size>32||bytes>MAX_BYTES){var first=cache.keys().next().value;bytes-=cache.get(first).size;cache.delete(first);}
  }
  function request(key){
    var existing=inflight.get(key);if(existing)return existing.promise;
    var controller=new AbortController(),version=epoch,identity=authEpoch;
    var entry={controller:controller,promise:null};
    entry.promise=(async function(){
      var timer=setTimeout(function(){controller.abort();},150000);
      try{
        var response=await nativeFetch(key,{cache:'no-store',signal:controller.signal});
        if(identity!==authEpoch||version!==epoch)throw cancelled();
        if(response.status===401||response.status===403){authRequired();throw new Error('Требуется вход');}
        var data=await response.json();
        if(identity!==authEpoch||version!==epoch)throw cancelled();
        if(!response.ok||data.ok===false)throw new Error(data.error||('Ошибка сервера '+response.status));
        var at=Date.now();return {data:data,at:at,version:version};
      }finally{clearTimeout(timer);if(inflight.get(key)===entry)inflight.delete(key);}
    })();inflight.set(key,entry);return entry.promise;
  }
  // Consumers own their deadline/cancellation; one short call must not cancel
  // another section's shared request. The transport has a 150s upper bound.
  function forCaller(promise,signal,timeout){
    if(signal&&signal.aborted)return Promise.reject(cancelled());
    return new Promise(function(resolve,reject){
      function finish(fn,value){clearTimeout(timer);if(signal)signal.removeEventListener('abort',abort);fn(value);}
      function abort(){finish(reject,cancelled());}
      var timer=setTimeout(function(){var e=new Error('Сервер отвечает слишком долго');e.name='TimeoutError';finish(reject,e);},timeout);
      if(signal)signal.addEventListener('abort',abort,{once:true});
      promise.then(function(value){finish(resolve,value);},function(error){finish(reject,error);});
    });
  }
  async function load(url,options){
    var opts=options||{},key=keyFor(url);if(!key)throw new Error('Недопустимый адрес данных');
    var v=viewState(opts.view),identity=authEpoch,version=epoch;
    var stopped=function(){return identity!==authEpoch||(opts.signal&&opts.signal.aborted);};
    if(v){if(opts.hasData&&authenticated){v.hasData=true;v.cold=false;}v.pending++;v.failed.delete(key);v.retries.set(key,function(){load(url,Object.assign({},opts,{force:true})).catch(function(){});});paint(v);}
    try{
      await ensureSession();if(stopped())throw cancelled();
      while(writes.size){await Promise.allSettled(Array.from(writes));if(stopped())throw cancelled();}
      var saved=cache.get(key),ttl=Number.isFinite(opts.ttl)?Math.max(0,opts.ttl):TTL;
      if(saved){
        cache.delete(key);cache.set(key,saved);
        if(opts.onData)opts.onData(copy(saved.data),{cached:true,updatedAt:saved.at,refreshing:!!opts.force||(Date.now()<saved.at||Date.now()-saved.at>=ttl)});
        if(v){v.hasData=true;v.cold=false;paint(v);}
        if(!opts.force&&Date.now()>=saved.at&&Date.now()-saved.at<ttl)return copy(saved.data);
      }
      for(var attempt=0;attempt<4;attempt++){
        version=epoch;
        try{
          var result=await forCaller(request(key),opts.signal,opts.timeout||45000);
          if(stopped())throw cancelled();
          if(result.version!==epoch)throw cancelled();
          if(opts.onData)opts.onData(copy(result.data),{cached:false,updatedAt:result.at,refreshing:false});
          if(stopped()||result.version!==epoch)throw cancelled();
          remember(key,result.data,result.at);
          if(v){v.hasData=true;v.failed.delete(key);}return copy(result.data);
        }catch(error){
          if(stopped()||version===epoch||attempt===3)throw error;
          while(writes.size)await Promise.allSettled(Array.from(writes));
          await ensureSession();if(stopped())throw cancelled();
        }
      }
    }catch(error){if(v&&!stopped())v.failed.add(key);throw error;}
    finally{if(v){v.pending=Math.max(0,v.pending-1);if(!v.pending&&v.hasData)v.cold=false;paint(v);}}
  }
  // Observe only same-origin admin requests. POST bodies/responses are never cached.
  window.fetch=async function(input,options){
    var key=keyFor(input),method=String((options&&options.method)||(typeof input==='object'&&input.method)||'GET').toUpperCase();
    var mutation=!!key&&!['GET','HEAD','OPTIONS'].includes(method),authChange=key==='/api/admin/login'||key==='/api/admin/logout';
    if(authChange)reset();else if(mutation)invalidate();
    var pending=nativeFetch(input,options);if(mutation)writes.add(pending);
    try{
      var response=await pending;
      if(key&&(response.status===401||response.status===403)&&key!=='/api/admin/login')authRequired();
      return response;
    }finally{if(mutation){writes.delete(pending);invalidate();}}
  };
  document.addEventListener('visibilitychange',function(){if(!document.hidden)checkedAt=0;});
  window.AdminData={load:load,ensureSession:ensureSession,invalidate:invalidate,reset:reset};
})();
`;
