export const OFFERS_NAV = `
<button class="nav-item" data-feature="offers"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" aria-hidden="true"><path d="m3 12 9-9h8v8l-9 10Z"/><circle cx="16.5" cy="6.5" r="1"/></svg><span>Тарифы</span></button>`;

const storeForm = (store, title) => `
<form data-store="${store}">
  <h3>${title}</h3>
  <label>Подписка на 3 месяца <select name="mode">
    <option value="legacy">Текущий тариф</option><option value="standard">Новый тариф</option>
    <option value="promotion">Акция · прежний тариф</option>
  </select></label>
  <label><input type="checkbox" name="trial"> Предлагать 3 дня бесплатно</label>
  <button class="btn-action" type="submit">Применить в ${title}</button>
</form>`;

export const OFFERS_VIEW = `
<section id="offers-view" style="display:none">
<style>
#offers-view{max-width:780px}#offers-view fieldset{border:0;margin:0;padding:0}
#offers-view h3{margin:0 0 4px;font-size:18px}#offers-view p{color:var(--text-muted);margin:0 0 14px}
#offers-view form{display:flex;flex-wrap:wrap;align-items:center;gap:10px 14px;margin-bottom:18px}
#offers-view form h3{width:100%}#offers-view label{display:flex;align-items:center;flex-wrap:wrap;gap:8px}
#offers-view select,#offers-view input[type=number]{font:inherit;background:var(--card-bg);color:inherit;border:1px solid var(--border);border-radius:8px;padding:7px 9px}
#offers-view input[type=number]{width:84px}#offers-view section{margin:0 0 24px}
#offers-view #offers-state{margin:12px 0;min-height:1.3em}
</style>
<div id="offers-state" role="status"></div>
<fieldset id="offers-controls" disabled>
  <section><h3>СБП · 90 дней</h3>
    <p id="offers-sbp-current"></p>
    <form id="offers-discount"><label>Цена для акции, ₽ <input name="priceRub" type="number" min="1" max="369" step="1" required></label>
      <button type="submit" class="btn-action">Сохранить черновик</button></form>
    <form id="offers-sbp"><label>Цена для новых заказов <select name="mode"><option value="legacy">Прежняя · 290 ₽</option>
      <option value="standard">Новая · 370 ₽</option><option value="promotion">Акция</option></select></label>
      <button type="submit" class="btn-action">Применить цену СБП</button></form>
    <p>Старые версии приложения оформляют 90 дней за 290 ₽. Для открытого заказа действует сумма при создании.</p>
    <button class="btn-action" id="offers-sbp-trial" type="button">Проверить пробный период СБП</button>
    <p id="offers-sbp-trial-status" role="status"></p>
  </section>
  <section><p>Цены подписок и условия автопродления задаются в магазинах. Пробный период появится при доступном предложении с той же ценой продления, что у выбранного тарифа.</p>
    ${storeForm('appstore','App Store')}${storeForm('googleplay','Google Play')}
  </section>
</fieldset>
<button class="btn-action" id="offers-refresh" type="button">Обновить</button>
</section>`;

export const OFFERS_JS = `
(function() {
  const root = document.getElementById('offers-view');
  const controls = root.querySelector('#offers-controls');
  const refresh = root.querySelector('#offers-refresh');
  const state = root.querySelector('#offers-state');
  const sbp = root.querySelector('#offers-sbp');
  const discount = root.querySelector('#offers-discount');
  const stores = [...root.querySelectorAll('[data-store]')];
  const endpoint = '/api/admin/premium-offers';
  let revision = null, busy = false;
  function render(data) {
    const s = data.settings;
    revision = s.revision;
    sbp.elements.mode.value = s.sbpMode;
    discount.elements.priceRub.value = s.draftPriceRub;
    sbp.querySelector('[value="promotion"]').textContent = 'Акция · ' + s.draftPriceRub + ' ₽';
    root.querySelector('#offers-sbp-current').textContent = 'Сейчас ' + data.catalog.tariffs.threeMonths.priceRub + ' ₽' + (s.sbpMode === 'promotion' ? ' по акции.' : '.');
    for (const form of stores) {
      form.elements.mode.value = s.nativeQuarter[form.dataset.store];
      form.elements.trial.checked = s.storeTrials[form.dataset.store];
    }
  }
  async function update(change) {
    if (busy) return;
    busy = true;
    controls.disabled = refresh.disabled = true;
    state.textContent = change ? 'Сохранение…' : 'Загрузка…';
    try {
      const options = change ? {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...change,revision})} : {};
      render(await adminFetchJson(endpoint, options));
      state.textContent = change ? 'Сохранено' : '';
    } catch (error) {
      revision = null;
      state.textContent = error.message === 'offers_changed'
        ? 'Тарифы изменились в другой вкладке. Обновите данные.'
        : 'Не удалось получить подтверждение сервера. Обновите данные.';
    } finally {
      busy = false;
      controls.disabled = revision === null;
      refresh.disabled = false;
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
  discount.onsubmit = event => {
    event.preventDefault();
    update({operation:'save_promotion',priceRub:discount.elements.priceRub.valueAsNumber});
  };
  sbp.onsubmit = event => {
    event.preventDefault();
    update({operation:'activate_sbp',mode:sbp.elements.mode.value});
  };
  for (const form of stores) form.onsubmit = event => {
    event.preventDefault();
    update({operation:'set_store',store:form.dataset.store,mode:form.elements.mode.value,trial:form.elements.trial.checked});
  };
  refresh.onclick = window.loadPremiumOffers = () => update();
})();`;
