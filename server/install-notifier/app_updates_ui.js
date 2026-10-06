export const APP_UPDATES_VIEW_HTML = `
<form id="up-form" class="nt-card" style="margin-bottom:20px">
<h3>Обновления приложения</h3>
<p class="nt-hint" style="margin:0 0 16px">Предложение «Обновить / Позже» при входе в приложение. Повтор — не чаще раза в сутки. Android проверяет доступность через Google Play, iOS сверяет версию с App Store. Включайте только после публикации; версия и сборка должны совпадать с релизом. Пустая конфигурация Android использует автоматическую проверку Google Play.</p>
<div class="nt-row">
<label class="nt-field"><span>Приложение</span><select id="up-app"><option value="ru">Россия</option><option value="by">Беларусь</option><option value="rs">Сербия</option></select></label>
<label class="nt-field"><span>Магазин</span><select id="up-platform"><option value="android">Google Play</option><option value="ios">App Store</option></select></label>
</div>
<label class="nt-check"><input id="up-enabled" type="checkbox">Показывать предложение об обновлении для этой страны и платформы</label>
<div class="nt-row">
<label class="nt-field"><span>Версия (versionName)</span><input id="up-version" placeholder="2.1.9" maxlength="40" required></label>
<label class="nt-field"><span>Номер сборки (versionCode / build)</span><input id="up-build" type="number" min="1" max="2147483647" step="1" required></label>
</div>
<label class="nt-field"><span>applicationId / bundle ID опубликованного приложения</span><input id="up-package" maxlength="160" required></label>
<label class="nt-field"><span>Прямая ссылка магазина</span><input id="up-url" type="url" maxlength="500" placeholder="https://…" required></label>
<label class="nt-field"><span>Что нового — на языке выбранного приложения (необязательно)</span><textarea id="up-notes" maxlength="1000"></textarea></label>
<div class="nt-actions"><button type="submit" id="up-save" class="btn-action primary">Сохранить</button><button type="button" id="up-refresh" class="btn-action">Обновить данные</button><span id="up-status" role="status"></span></div>
<div id="up-error" class="nt-error" role="alert"></div>
</form>`;
export const APP_UPDATES_CLIENT_JS = `
(function(){
var records=[],busy=false;
var el=function(id){return document.getElementById('up-'+id);};
async function api(body){var r=await fetch('/api/admin/app-updates',{method:body?'POST':'GET',headers:body?{'content-type':'application/json'}:{},body:body?JSON.stringify(body):undefined});var d=await r.json();if(!r.ok)throw new Error(r.status===401?'Войдите в админку заново':d.error||'Не удалось загрузить настройки');return d;}
function fill(){var app=el('app').value,platform=el('platform').value;var item=records.find(function(x){return x.app===app&&x.platform===platform;});el('enabled').checked=!!(item&&item.enabled);el('version').value=item?item.version:'';el('build').value=item?item.build:'';el('package').value=item?item.packageId:platform==='android'?app+'.pdd.pdd_app':'';el('url').value=item?item.storeUrl:platform==='android'?'https://play.google.com/store/apps/details?id='+el('package').value:'';el('notes').value=item?item.notes:'';el('status').textContent=item?(item.enabled?'Показ включён':'Показ отключён'):'Релиз ещё не настроен';el('error').textContent='';}
async function load(){if(busy)return;busy=true;el('save').disabled=true;try{records=(await api()).releases||[];fill();}catch(e){el('error').textContent=e.message;}finally{busy=false;el('save').disabled=false;}}
el('app').onchange=fill;el('platform').onchange=fill;el('refresh').onclick=load;
el('form').onsubmit=async function(e){e.preventDefault();if(busy)return;busy=true;el('save').disabled=true;el('error').textContent='';var body={app:el('app').value,platform:el('platform').value,enabled:el('enabled').checked,version:el('version').value.trim(),build:Number(el('build').value),packageId:el('package').value.trim(),storeUrl:el('url').value.trim(),notes:el('notes').value.trim()};try{var saved=(await api(body)).release;records=records.filter(function(x){return x.app!==saved.app||x.platform!==saved.platform;});records.push(saved);fill();el('status').textContent='Сохранено';}catch(error){el('error').textContent=error.message;}finally{busy=false;el('save').disabled=false;}};
document.querySelectorAll('.sidebar-menu .nav-item').forEach(function(btn){btn.addEventListener('click',function(){if(btn.dataset.feature==='notifications')load();});});
fill();
})();
`;
