// The checkout confirms the amount again before creating a charge. When payments
// are unavailable, the optional email form records the same price shown here.
(function () {
  const api = 'https://pdd-install-notifier.sergei-pdd.workers.dev';
  const buttons = [...document.querySelectorAll('.plan-buy')];
  const dialog = document.getElementById('pay-dialog');
  const form = document.getElementById('pay-form');
  const email = document.getElementById('pay-email');
  const heading = document.getElementById('pay-title');
  const error = document.getElementById('pay-error');
  const status = document.getElementById('tariff-status');
  const fallback = document.getElementById('tariff-fallback');
  const schema = document.getElementById('tariff-schema');
  const productPage = JSON.parse(schema.textContent);
  const legacy = {version:1, tariffs:{weekly:{days:7,priceRub:99},threeMonths:{days:90,priceRub:290}}};
  let catalog, live, selected, loading = false, sending = false;

  function valid(value) {
    return value?.version === 1 && buttons.every(button => {
      const plan = value.tariffs?.[button.dataset.tier];
      return plan?.days === (button.dataset.tier === 'weekly' ? 7 : 90) &&
        Number.isSafeInteger(plan.priceRub) && plan.priceRub > 0;
    });
  }
  function showCatalog(value) {
    catalog = value;
    const offers = [];
    for (const button of buttons) {
      const plan = catalog?.tariffs[button.dataset.tier];
      const card = button.closest('.plan');
      const price = plan ? plan.priceRub + ' ₽' : '—';
      card.querySelector('.plan-price').textContent = price;
      if (button.dataset.tier === 'threeMonths') {
        card.querySelector('.plan-note').textContent = 'Доступ на 90 дней' +
          (plan ? ' — около ' + Math.round(plan.priceRub / 3) + ' ₽ в месяц' : '');
      }
      button.disabled = !plan;
      button.textContent = plan ? 'Оплатить ' + price : 'Выбрать тариф';
      if (plan) offers.push({'@type':'Offer', name:button.dataset.title, price:String(plan.priceRub),
        priceCurrency:'RUB', url:'https://pdd-drive.app/tarify/'});
    }
    if (offers.length) productPage.mainEntity.offers = offers;
    else delete productPage.mainEntity.offers;
    schema.textContent = JSON.stringify(productPage);
  }
  async function read(path) {
    const response = await fetch(api + path, {cache:'no-store',signal:AbortSignal.timeout(10000)});
    if (!response.ok) throw new Error('unavailable');
    const raw = await response.text();
    // A deployed legacy Worker uses this exact health body for unknown routes.
    if (path === '/api/pay/catalog' && raw.trim() === 'pdd-install-notifier: ok') return legacy;
    return JSON.parse(raw);
  }
  async function load() {
    if (loading) return;
    loading = true;
    showCatalog(null);
    fallback.hidden = true;
    status.textContent = 'Загружаем цены…';
    document.getElementById('pay-soon-note').hidden = true;
    try {
      const [value, availability] = await Promise.all([read('/api/pay/catalog'), read('/api/pay/status')]);
      if (!valid(value) || typeof availability?.available !== 'boolean') throw new Error('invalid_catalog');
      live = availability.available;
      showCatalog(value);
      document.getElementById('pay-soon-note').hidden = live;
      status.textContent = '';
    } catch {
      status.textContent = 'Не удалось загрузить цены.';
      fallback.hidden = false;
    } finally { loading = false; }
  }
  function show(id) {
    for (const name of ['pay-soon','pay-done','pay-live']) document.getElementById(name).hidden = name !== id;
  }
  function quote(button) {
    const priceRub = catalog.tariffs[button.dataset.tier].priceRub;
    selected = {tier:button.dataset.tier, expectedPriceRub:priceRub, catalogVersion:1};
    heading.textContent = button.dataset.title + ' — ' + priceRub + ' ₽';
  }
  function paymentUrl(tier) { return '/app/?checkout=sbp&tier=' + encodeURIComponent(tier); }
  for (const button of buttons) {
    button.onclick = () => {
      if (!catalog || sending) return;
      const tier = button.dataset.tier;
      if (typeof ym === 'function') ym(111960332, 'reachGoal', 'tariff_click', {tier});
      if (live) { location.assign(paymentUrl(tier)); return; }
      quote(button);
      error.textContent = '';
      show('pay-soon');
      dialog.showModal();
      email.focus();
    };
  }
  document.getElementById('tariff-retry').onclick = load;
  dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
  form.onsubmit = async event => {
    event.preventDefault();
    if (!selected || sending) return;
    const value = email.value.trim();
    if (!email.validity.valid || !value) { error.textContent = 'Проверьте адрес почты'; return; }
    const button = form.querySelector('button[type=submit]');
    sending = button.disabled = true;
    error.textContent = '';
    try {
      const response = await fetch(api + '/api/pay/lead', {
        method:'POST', headers:{'content-type':'application/json'}, signal:AbortSignal.timeout(12000),
        body:JSON.stringify({...selected, email:value, website:form.website.value}),
      });
      const result = await response.json();
      if (response.status === 409 && result.code === 'price_changed' && valid(result.catalog)) {
        showCatalog(result.catalog);
        quote(buttons.find(plan => plan.dataset.tier === selected.tier));
        error.textContent = 'Цена изменилась. Проверьте новую сумму и подтвердите выбор.';
      } else if (!response.ok || result.ok !== true) {
        throw new Error('unavailable');
      } else if (result.available === true) {
        live = true;
        document.getElementById('pay-soon-note').hidden = true;
        document.querySelector('#pay-live a').href = paymentUrl(selected.tier);
        show('pay-live');
      } else {
        document.getElementById('pay-done-email').textContent = value;
        show('pay-done');
      }
    } catch {
      error.textContent = 'Не удалось отправить, попробуйте ещё раз';
    } finally { sending = button.disabled = false; }
  };
  window.addEventListener('pageshow', event => { if (event.persisted && !dialog.open) load(); });
  load();
})();
