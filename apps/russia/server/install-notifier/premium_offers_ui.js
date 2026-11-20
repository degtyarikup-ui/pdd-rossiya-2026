export const OFFERS_NAV = `
<button class="nav-item" data-feature="offers"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="m3 12 9-9h8v8l-9 10Z"/><circle cx="16.5" cy="6.5" r="1"/></svg><span>Тарифы</span></button>`;

const icon = (path) => `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${path}"/></svg>`;
const pencil = icon('m15 5 4 4M4 20l4-1 12-12a2.8 2.8 0 0 0-4-4L4 15z');
const refreshIcon = icon('M20 4v5h-5M4 20v-5h5M5 9a7.5 7.5 0 0 1 13-4l2 4M4 15l2 4a7.5 7.5 0 0 0 13-4');
const channels = [
  ['sbp', 'СБП', 'Разовая оплата · 90 дней'],
  ['appstore', 'App Store', 'Подписка · 3 месяца'],
  ['googleplay', 'Google Play', 'Подписка · 3 месяца'],
];
const editButton = (key, label) => `<button type="button" class="btn-action of-edit" data-edit="${key}" aria-label="${label}" title="${label}">${pencil}</button>`;

export const OFFERS_VIEW = `
<section id="offers-view" style="display:none">
<style>
#offers-view [hidden]{display:none!important}
#offers-view fieldset{border:0;padding:0;margin:0;min-width:0}
#offers-view .of-head,#offers-view .of-draft,.of-actions,.of-trial{display:flex;align-items:center;justify-content:space-between;gap:12px}
#offers-view .of-head{margin-bottom:16px}
#offers-view .card-title{margin:0}
.of-tools{display:flex;align-items:center;gap:8px}
#offers-state,#offers-sbp-trial-status,.of-note{color:var(--text-muted);font-size:var(--admin-type-control);line-height:1.45}
#offers-state[data-error]{color:var(--danger)}
#offers-state:empty,#offers-sbp-trial-status:empty{display:none}
#offers-view .of-edit,#offers-refresh{display:inline-grid;place-items:center;width:40px;height:40px;padding:0;color:var(--text-muted);background:transparent}
#offers-view .of-edit:hover,#offers-refresh:hover{background:var(--surface-gray);color:var(--text)}
.of-table{width:100%;border-collapse:collapse;text-align:left;table-layout:fixed}
.of-table .of-channel-col{width:35%}.of-table .of-rate-col{width:29%}.of-table .of-action-col{width:44px}
#offers-view .of-table th,#offers-view .of-table td{border:0;padding:13px 12px 13px 0;text-align:left;background:transparent}
#offers-view .of-table thead th{font-size:var(--admin-type-control);color:var(--text-muted);text-transform:none;letter-spacing:0;font-weight:var(--admin-weight-medium);padding-top:0;padding-bottom:10px}
#offers-view .of-table tbody tr{border-top:1px solid var(--admin-divider)}
#offers-view .of-table .of-channel{font-size:var(--admin-type-title);color:var(--text);font-weight:var(--admin-weight-semibold);letter-spacing:normal;text-transform:none}
.of-sub{display:block;color:var(--text-muted);font-size:var(--admin-type-control);font-weight:400;margin-top:2px}
#offers-view .of-table td{font-size:var(--admin-type-body);font-weight:var(--admin-weight-medium)}
#offers-view .of-table .of-action{text-align:right;padding-right:0}
.of-trial-value{color:var(--text-muted)}.of-trial-value[data-on]{color:var(--text)}
.of-mobile-label{display:none}
#offers-view .of-draft{padding:16px 24px 0;justify-content:flex-start;gap:12px}
.of-draft strong{font-size:var(--admin-type-body);font-weight:var(--admin-weight-semibold)}
.of-draft output{font-variant-numeric:tabular-nums;white-space:nowrap}
#offers-view .of-draft .of-edit{margin-left:-8px}
#offers-view .card{margin:0}
#offers-dialog{border:0;border-radius:var(--admin-radius);padding:24px;width:min(420px,calc(100% - 24px));max-height:calc(100dvh - 24px);overflow:auto;margin:auto;color:var(--text);background:var(--card-bg);box-sizing:border-box}
#offers-dialog::backdrop{background:#17223655}
#offers-dialog h2{font-size:var(--admin-type-dialog);line-height:var(--admin-leading-title);letter-spacing:-.025em;margin:0 0 20px}
.of-label{display:block;color:var(--text-muted);font-size:var(--admin-type-control);font-weight:var(--admin-weight-medium);margin-bottom:8px}
.of-choice{display:flex;align-items:center;gap:10px;min-height:44px;cursor:pointer}
.of-choice input,.of-trial input{width:17px;height:17px;margin:0;flex-shrink:0}
.of-choice strong{font-size:var(--admin-type-body);font-weight:var(--admin-weight-semibold)}
.of-choice small{font-size:var(--admin-type-control);color:var(--text-muted);margin-left:auto;text-align:right}
.of-trial,#offers-probe{border-top:1px solid var(--admin-divider);padding-top:14px;margin-top:14px}
.of-trial{cursor:pointer;min-height:36px}
.of-note{margin:9px 0 0}
#offers-dialog input[type=number]{width:100%;box-sizing:border-box;padding:10px 12px}
#offers-sbp-trial{border:0;background:transparent;color:var(--primary);padding:5px 0;font:inherit;cursor:pointer}
#offers-sbp-trial-status{margin:6px 0 0}
.of-actions{justify-content:flex-end;margin-top:22px}
@media(max-width:620px){
 #offers-view .of-head{margin-bottom:10px}
 #offers-view .of-table,#offers-view .of-table tbody{display:block}
 .of-table colgroup,.of-table thead{position:absolute;clip-path:inset(50%);width:1px;height:1px;overflow:hidden}
 #offers-view .of-table tbody tr{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:4px 8px;padding:14px 0}
 #offers-view .of-table tbody tr:last-child{padding-bottom:0}
 #offers-view .of-table td,#offers-view .of-table .of-channel{padding:0}
 .of-channel{grid-column:1;grid-row:1}.of-sub{display:inline;margin-left:8px}
 .of-rate{grid-row:2;grid-column:1}.of-trial-value{grid-row:3;grid-column:1}
 .of-action{grid-column:2;grid-row:1/4;align-self:center}
 .of-mobile-label{display:inline;color:var(--text-muted);font-weight:400}
 .of-trial-value[data-once]{display:none}
 #offers-view .of-draft{padding:10px 6px 0;gap:8px}
 #offers-view .of-draft .of-edit{margin-left:0}
 .of-tools{gap:0}
}
@media(max-width:420px){.of-sub{display:block;margin:1px 0 4px}#offers-view .of-head{align-items:flex-start}.of-tools{align-items:flex-start}#offers-state{max-width:120px}}
</style>
<div class="card">
  <div class="of-head"><h2 class="card-title">Премиум на 3 месяца</h2><div class="of-tools"><span id="offers-state" role="status"></span><button id="offers-refresh" type="button" class="btn-action" aria-label="Обновить" title="Обновить">${refreshIcon}</button></div></div>
  <fieldset id="offers-controls" disabled aria-label="Настройки тарифов">
    <table class="of-table" aria-label="Тарифы для новых покупок">
      <colgroup><col class="of-channel-col"><col class="of-rate-col"><col><col class="of-action-col"></colgroup>
      <thead><tr><th scope="col">Способ оплаты</th><th scope="col">Тариф</th><th scope="col">Пробный период</th><th scope="col" aria-label="Редактирование"></th></tr></thead>
      <tbody>${channels.map(([key, name, term]) => `<tr>
        <th scope="row" class="of-channel">${name}<span class="of-sub">${term}</span></th>
        <td class="of-rate"><span class="of-mobile-label">Тариф · </span><span id="offers-${key}-current">—</span></td>
        <td class="of-trial-value" ${key === 'sbp' ? 'data-once' : ''}><span class="of-mobile-label">Пробный период · </span><span id="offers-${key}-trial-value">${key === 'sbp' ? 'Нет' : '—'}</span></td>
        <td class="of-action">${editButton(key, 'Изменить тариф ' + name)}</td></tr>`).join('')}</tbody>
    </table>
  </fieldset>
</div>
<div class="of-draft"><strong>Черновик акции СБП</strong><output id="offers-draft-price">—</output>${editButton('draft', 'Изменить черновик акции СБП')}</div>
<dialog id="offers-dialog" aria-labelledby="offers-dialog-title">
 <form id="offers-form">
  <h2 id="offers-dialog-title"></h2>
  <fieldset id="offers-fields">
   <fieldset id="offers-modes"><legend class="of-label">Тариф для новых покупок</legend>
    ${['legacy','standard','promotion'].map(mode => `<label class="of-choice"><input type="radio" name="mode" value="${mode}"><strong></strong><small></small></label>`).join('')}
   </fieldset>
   <div id="offers-discount" hidden><label class="of-label" for="offers-draft-input">Акционная цена, ₽</label><input id="offers-draft-input" name="priceRub" type="number" min="1" max="369" step="1" required></div>
   <label class="of-trial" id="offers-trial"><span>3 дня бесплатно</span><input type="checkbox" name="trial"></label>
   <p class="of-note" id="offers-renewal" hidden>Подписка будет продлеваться по акционной цене.</p>
   <div id="offers-probe" hidden><button id="offers-sbp-trial" type="button">Проверить пробный период СБП</button><p id="offers-sbp-trial-status" role="status"></p></div>
  </fieldset>
  <div class="of-actions"><button id="offers-cancel" class="btn-action" type="button">Отмена</button><button id="offers-submit" class="btn-action btn-primary" type="submit">Применить</button></div>
 </form>
</dialog>
</section>`;

export const OFFERS_JS = `
(function() {
  const root = document.getElementById('offers-view');
  const el = id => root.querySelector('#offers-' + id);
  const controls = el('controls'), refresh = el('refresh'), state = el('state');
  const dialog = el('dialog'), form = el('form'), submit = el('submit');
  const draftButton = root.querySelector('[data-edit="draft"]');
  const price = form.elements.priceRub;
  const names = {sbp:'СБП', appstore:'App Store', googleplay:'Google Play', draft:'Черновик акции СБП'};
  const modeNames = {legacy:'Прежний тариф', standard:'Новый тариф', promotion:'Акция'};
  const endpoint = '/api/admin/premium-offers';
  let data = null, editing = null, busy = false;
  const rub = value => value.toLocaleString('ru-RU') + ' ₽';
  function modeOf(key) {
    return key === 'sbp' ? data.settings.sbpMode : data.settings.nativeQuarter[key];
  }
  const appleRate = mode => rub(mode === 'standard' ? 370 : 290);
  function render() {
    const s = data.settings;
    el('sbp-current').textContent = rub(data.catalog.tariffs.threeMonths.priceRub) + (s.sbpMode === 'promotion' ? ' по акции' : '');
    el('draft-price').textContent = rub(s.draftPriceRub);
    for (const key of ['appstore','googleplay']) {
      const mode = modeOf(key);
      el(key + '-current').textContent = key === 'appstore' ? appleRate(mode) + (mode === 'promotion' ? ' по акции' : ' в РФ') : modeNames[mode];
      const trial = el(key + '-trial-value');
      trial.textContent = s.storeTrials[key] ? '3 дня бесплатно' : 'Выключен';
      trial.parentElement.toggleAttribute('data-on', s.storeTrials[key]);
    }
  }
  function syncEditor() {
    if (!data || !editing) return;
    const s = data.settings, mode = form.elements.mode.value;
    const draft = editing === 'draft', sbp = editing === 'sbp', store = !draft && !sbp;
    const changed = draft ? price.validity.valid && price.valueAsNumber !== s.draftPriceRub
      : mode !== modeOf(editing) || (store && form.elements.trial.checked !== s.storeTrials[editing]) ||
        (sbp && mode === 'promotion' && s.promotionPriceRub !== s.draftPriceRub);
    submit.disabled = busy || !changed;
    el('renewal').hidden = !store || mode !== 'promotion';
  }
  function openEditor(key) {
    if (!data || busy) return;
    editing = key;
    const s = data.settings;
    const draft = key === 'draft', sbp = key === 'sbp';
    el('dialog-title').textContent = names[key];
    el('modes').hidden = el('modes').disabled = draft;
    el('discount').hidden = price.disabled = !draft;
    el('trial').hidden = form.elements.trial.disabled = draft || sbp;
    el('probe').hidden = !sbp;
    el('sbp-trial-status').textContent = '';
    price.value = s.draftPriceRub;
    if (!draft) {
      const amounts = {legacy:290,standard:370,promotion:s.draftPriceRub};
      const captions = {legacy:'Прежняя цена',standard:'Новая цена',promotion:'По акции'};
      for (const row of form.querySelectorAll('.of-choice')) {
        const input = row.querySelector('input'), mode = input.value;
        input.checked = mode === modeOf(key);
        row.querySelector('strong').textContent = sbp ? rub(amounts[mode]) : modeNames[mode];
        row.querySelector('small').textContent = sbp ? captions[mode] : key === 'appstore' ? appleRate(mode) + ' в РФ' : mode === 'promotion' ? 'По прежней цене' : '';
      }
    }
    form.elements.trial.checked = s.storeTrials[key] === true;
    submit.textContent = draft ? 'Сохранить черновик' : 'Применить';
    syncEditor();
    dialog.showModal();
    if (draft) price.focus();
    else form.querySelector('input:checked').focus();
  }
  async function update(change) {
    if (busy) return;
    busy = true;
    controls.disabled = draftButton.disabled = el('fields').disabled = refresh.disabled = true;
    submit.disabled = true;
    el('cancel').disabled = !!change;
    state.removeAttribute('data-error');
    state.textContent = change ? '' : 'Загрузка…';
    if (change) submit.textContent = 'Сохранение…';
    try {
      const options = change ? {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...change,revision:data.settings.revision})} : {};
      data = await adminFetchJson(endpoint, options);
      render();
      if (dialog.open) dialog.close();
      state.textContent = change ? 'Сохранено' : '';
    } catch (error) {
      data = null;
      if (dialog.open) dialog.close();
      state.setAttribute('data-error', '');
      state.textContent = error.message === 'offers_changed' ? 'Изменено в другой вкладке. Обновите.' : (change ? 'Сохранение не подтверждено. Обновите.' : 'Не удалось загрузить тарифы. Обновите.');
    } finally {
      busy = false;
      el('fields').disabled = el('cancel').disabled = refresh.disabled = false;
      controls.disabled = draftButton.disabled = !data;
      if (change && data) root.querySelector('[data-edit="' + editing + '"]').focus();
      if (!data) refresh.focus();
    }
  }
  const trialCheck = root.querySelector('#offers-sbp-trial');
  const trialStatus = root.querySelector('#offers-sbp-trial-status');
  trialCheck.onclick = async () => {
    if (trialCheck.disabled) return;
    trialCheck.disabled = true;
    trialStatus.textContent = 'Проверяем условия Platega…';
    try {
      const terms = await adminFetchJson(endpoint + '/sbp-trial');
      if (!terms.trialSupported) {
        trialStatus.textContent = 'Platega не разрешает пробный период для этого магазина.';
      } else if (terms.minTrialAmount === 0 && terms.maxTrialPeriodDays >= 3) {
        trialStatus.textContent = 'Platega разрешает 3 дня за 0 ₽. Оформление подписки через СБП пока не подключено.';
      } else {
        const amount = terms.minTrialAmount.toLocaleString('ru-RU', { maximumFractionDigits: 2 });
        trialStatus.textContent = 'Три бесплатных дня недоступны. Минимальная сумма — ' + amount +
          ' ₽. Максимальный срок — ' + terms.maxTrialPeriodDays + ' дн.';
      }
    } catch (_) {
      trialStatus.textContent = 'Не удалось проверить условия Platega. Попробуйте ещё раз.';
    } finally {
      trialCheck.disabled = false;
    }
  };

  root.querySelectorAll('[data-edit]').forEach(button => {
    button.onclick = () => openEditor(button.dataset.edit);
  });
  draftButton.disabled = true;
  form.oninput = syncEditor;
  el('cancel').onclick = () => dialog.close();
  dialog.addEventListener('cancel', event => { if (busy) event.preventDefault(); });
  form.onsubmit = event => {
    event.preventDefault();
    if (submit.disabled || !data) return;
    if (editing === 'draft') return update({operation:'save_promotion',priceRub:price.valueAsNumber});
    const mode = form.elements.mode.value;
    if (editing === 'sbp') return update({operation:'activate_sbp',mode});
    return update({operation:'set_store',store:editing,mode,trial:form.elements.trial.checked});
  };
  refresh.onclick = window.loadPremiumOffers = () => { if (!dialog.open) return update(); };
})();`;
