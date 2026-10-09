// Раздел «Экономика» админки: точный стиль страницы Аналитики.
// Крупные числа, карточки .an-card, подсказки под значками «i», чеки по премиумам,
// Cloudflare $5, домен, ИИ, фонд развития (15%), доли Сергея (93.3%) и Никиты (6.7%).

export const ECONOMY_NAV_HTML = String.raw`
      <button class="nav-item" data-feature="economy">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <line x1="12" y1="1" x2="12" y2="23"/>
          <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>
        </svg>
        <span>Экономика</span>
      </button>`;

export const ECONOMY_VIEW_HTML = String.raw`
<div id="economy-view" style="display:none;">
<style>
#economy-view{--an-accent:#0574F8;--an-green:#22a875;--an-text:#17191E;--an-muted:#747B88;--an-gray:#F4F5F7;color:var(--an-text)}
.ec-top-row{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:16px;flex-wrap:wrap}
.ec-tabs{display:flex;gap:3px;padding:4px;background:#F4F5F7;border-radius:999px;width:fit-content}
.ec-tabs button{border:0;background:transparent;color:var(--an-muted);padding:7px 14px;border-radius:999px;font-size:11.5px;font-weight:600;cursor:pointer;min-height:30px}
.ec-tabs button.active{background:var(--an-text);color:#fff}
.ec-badge{display:inline-flex;align-items:center;gap:4px;padding:3px 8px;border-radius:6px;font-size:11px;font-weight:600}
.ec-badge-green{background:#E8F8F0;color:#22a875}
.ec-badge-blue{background:#E8F2FE;color:#0574F8}
.ec-badge-amber{background:#FEF3C7;color:#D97706}
.ec-badge-gray{background:#F4F5F7;color:var(--an-muted)}
.ec-split-bar{height:8px;border-radius:999px;background:#F4F5F7;overflow:hidden;display:flex;margin:12px 0 6px}
.ec-split-sergey{background:var(--an-accent);height:100%}
.ec-split-nikita{background:var(--an-green);height:100%}
.ec-partners{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:14px}
.ec-partner{background:#F8FAFC;border-radius:14px;padding:16px;display:flex;flex-direction:column;gap:6px}
.ec-partner-title{display:flex;justify-content:space-between;align-items:center;font-size:12px;font-weight:600;color:var(--an-muted)}
.ec-partner-val{font-size:24px;font-weight:650;letter-spacing:-.8px;color:var(--an-text);font-variant-numeric:tabular-nums}
.ec-calc-input{border:0;background:#F4F5F7;border-radius:10px;padding:9px 12px;font-size:18px;font-weight:700;color:var(--an-text);width:160px;text-align:right}
.ec-calc-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-top:16px}
.ec-calc-item{background:#F8FAFC;border-radius:12px;padding:14px}
.ec-calc-item-label{font-size:11px;color:var(--an-muted);font-weight:500;margin-bottom:4px}
.ec-calc-item-val{font-size:18px;font-weight:650;letter-spacing:-.4px;font-variant-numeric:tabular-nums}
.ec-search{border:0;border-radius:10px;padding:9px 12px;font-size:12px;background:#F4F5F7;color:var(--an-text);min-height:34px;flex:1}
@media(max-width:900px){.ec-partners{grid-template-columns:1fr}.ec-calc-grid{grid-template-columns:1fr 1fr}}
@media(max-width:600px){.ec-calc-grid{grid-template-columns:1fr}}
</style>

<!-- Панель периодов -->
<div class="ec-top-row">
  <div class="ec-tabs" id="ec-period-tabs">
    <button type="button" data-period="month" class="active">Этот месяц</button>
    <button type="button" data-period="30d">30 дней</button>
    <button type="button" data-period="all">Всё время</button>
  </div>
  <div style="display:flex; align-items:center; gap:10px;">
    <span class="admin-data-state ready" id="ec-data-state">Готово</span>
    <button class="btn-action" id="ec-refresh-btn" title="Обновить данные">
      <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
      <span>Обновить</span>
    </button>
  </div>
</div>

<!-- Верхний ряд: KPI карточки (стиль Аналитики) -->
<div class="an-grid">
  <div class="an-card an-kpi">
    <div class="an-kpi-top"><span>Выручка с премиумов</span></div>
    <div class="an-big" id="ec-gross-val">0 ₽</div>
    <div class="an-caption" id="ec-gross-sub" style="margin-top:6px;">0 оплат · реальный доход</div>
  </div>

  <div class="an-card an-kpi">
    <div class="an-kpi-top"><span>Расходы проекта</span></div>
    <div class="an-big" id="ec-costs-val">0 ₽</div>
    <div class="an-caption" id="ec-costs-sub" style="margin-top:6px;">Cloudflare $5 · Домен · ИИ</div>
  </div>

  <div class="an-card an-kpi">
    <div class="an-kpi-top"><span>Фонд развития</span></div>
    <div class="an-big" id="ec-reinvest-val">0 ₽</div>
    <div class="an-caption" id="ec-reinvest-sub" style="margin-top:6px;">15% реинвестиций в продукт</div>
  </div>

  <div class="an-card an-kpi is-primary">
    <div class="an-kpi-top"><span>Чистая прибыль</span></div>
    <div class="an-big" id="ec-net-val">0 ₽</div>
    <div class="an-caption" id="ec-net-sub" style="margin-top:6px; color:rgba(255,255,255,0.8);">К выплате основателям</div>
  </div>
</div>

<!-- Ряд 1: Партнеры (93.3% / 6.7%) и Расходы (Cloudflare $5, Домен, ИИ) -->
<div class="an-charts-grid">
  <!-- Карточка 1: Выплаты участникам -->
  <div class="an-card">
    <div class="an-head">
      <div class="an-title">Выплаты создателям</div>
      <details class="an-help">
        <summary aria-label="О долях">i</summary>
        <div>Расчёт от чистой распределяемой прибыли (после покрытия $5 Cloudflare, домена, ИИ и отчисления 15% в фонд развития проекта). Сергей — 93,3%, Никита — 6,7%.</div>
      </details>
    </div>

    <!-- Прогресс-бар долей -->
    <div style="display:flex; justify-content:space-between; font-size:11px; font-weight:600; color:var(--an-muted);">
      <span style="color:var(--an-accent);">Сергей 93,3%</span>
      <span style="color:var(--an-green);">Никита 6,7%</span>
    </div>
    <div class="ec-split-bar">
      <div class="ec-split-sergey" id="ec-bar-s" style="width:93.3%"></div>
      <div class="ec-split-nikita" id="ec-bar-n" style="width:6.7%"></div>
    </div>

    <!-- Карточки партнеров -->
    <div class="ec-partners">
      <div class="ec-partner">
        <div class="ec-partner-title">
          <span>Сергей</span>
          <span class="ec-badge ec-badge-blue">93,3%</span>
        </div>
        <div class="ec-partner-val" id="ec-payout-s">0 ₽</div>
        <div style="font-size:11px; color:var(--an-muted);">Основатель / разработка</div>
      </div>

      <div class="ec-partner">
        <div class="ec-partner-title">
          <span>Никита</span>
          <span class="ec-badge ec-badge-green">6,7%</span>
        </div>
        <div class="ec-partner-val" style="color:var(--an-green);" id="ec-payout-n">0 ₽</div>
        <div style="font-size:11px; color:var(--an-muted);">Партнёр / развитие</div>
      </div>
    </div>
  </div>

  <!-- Карточка 2: Расходы проекта -->
  <div class="an-card">
    <div class="an-head">
      <div class="an-title">Расходы проекта</div>
      <details class="an-help">
        <summary aria-label="О расходах">i</summary>
        <div>Ежемесячные инфраструктурные затраты: подписка Cloudflare $5, доменное имя pdd-drive.ru (~800 ₽/год = 67 ₽/мес) и Google Gemini по фактическому расходу токенов.</div>
      </details>
    </div>

    <table class="an-table">
      <thead>
        <tr>
          <th>Статья</th>
          <th>Тариф</th>
          <th>Сумма в рублях</th>
        </tr>
      </thead>
      <tbody id="ec-costs-tbody">
        <tr>
          <td><strong>Подписка Cloudflare</strong></td>
          <td><span class="code-badge">$5.00 / мес</span></td>
          <td><span id="ec-cost-cf-rub">~475.00 ₽</span></td>
        </tr>
        <tr>
          <td><strong>Домен pdd-drive.ru</strong></td>
          <td><span class="code-badge">~800 ₽ / год</span></td>
          <td><span id="ec-cost-domain-rub">67.00 ₽ / мес</span></td>
        </tr>
        <tr>
          <td><strong>Google Gemini ИИ</strong></td>
          <td><span class="code-badge" id="ec-cost-ai-usd">$0.00</span></td>
          <td><span id="ec-cost-ai-rub">0.00 ₽</span></td>
        </tr>
      </tbody>
    </table>
  </div>
</div>

<!-- Ряд 2: Точка безубыточности и Планер целей -->
<div class="an-charts-grid">
  <!-- Точка безубыточности -->
  <div class="an-card">
    <div class="an-head">
      <div class="an-title">Точка безубыточности</div>
      <details class="an-help">
        <summary aria-label="О безубыточности">i</summary>
        <div>Сколько подписок нужно продавать в месяц, чтобы 100% окупать расходы на Cloudflare, домен и встроенный ИИ.</div>
      </details>
    </div>

    <div style="margin:4px 0 16px;">
      <div style="font-size:11px; color:var(--an-muted); font-weight:500;">Для полной окупаемости проекта:</div>
      <div class="an-big" style="margin:6px 0 10px;" id="ec-be-sum">~542 ₽ / мес</div>
    </div>

    <div style="display:flex; gap:12px; margin-bottom:14px; flex-wrap:wrap;">
      <div style="background:#F8FAFC; border-radius:12px; padding:12px 14px; flex:1; min-width:130px;">
        <div style="font-size:11px; color:var(--an-muted);">НЕДЕЛЬНЫХ (99 ₽)</div>
        <div style="font-size:20px; font-weight:700; color:var(--an-accent); margin-top:2px;" id="ec-be-w">6 шт</div>
      </div>
      <div style="background:#F8FAFC; border-radius:12px; padding:12px 14px; flex:1; min-width:130px;">
        <div style="font-size:11px; color:var(--an-muted);">НА 3 МЕСЯЦА (290 ₽)</div>
        <div style="font-size:20px; font-weight:700; color:var(--an-green); margin-top:2px;" id="ec-be-3m">2 шт</div>
      </div>
    </div>
    <div style="font-size:12px; font-weight:600; color:var(--an-muted);" id="ec-be-status">Окупаемость считается в реальном времени.</div>
  </div>

  <!-- Интерактивный планер целей -->
  <div class="an-card">
    <div class="an-head">
      <div class="an-title">План продаж</div>
      <details class="an-help">
        <summary aria-label="О калькуляторе">i</summary>
        <div>Расчёт темпа продаж и выплат для достижения цели по чистой прибыли. Учитывает 15% фонд развития и конверсию от текущей базы 6 595 аккаунтов.</div>
      </details>
    </div>

    <div style="display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap; margin-bottom:12px;">
      <div class="ec-tabs" id="ec-calc-presets">
        <button type="button" data-val="10000">10k</button>
        <button type="button" data-val="50000" class="active">50k</button>
        <button type="button" data-val="100000">100k</button>
        <button type="button" data-val="300000">300k</button>
      </div>
      <div style="display:flex; align-items:center; gap:6px;">
        <input type="number" id="ec-calc-input" class="ec-calc-input" value="50000" step="5000" min="1000">
        <span style="font-size:14px; font-weight:600; color:var(--an-text);">₽ / мес</span>
      </div>
    </div>

    <div class="ec-calc-grid">
      <div class="ec-calc-item">
        <div class="ec-calc-item-label">Нужно продаж в месяц</div>
        <div class="ec-calc-item-val" style="color:var(--an-accent);" id="ec-plan-sales-m">~310 шт</div>
        <div style="font-size:11px; color:var(--an-muted);" id="ec-plan-sales-d">~10 в день</div>
      </div>
      <div class="ec-calc-item">
        <div class="ec-calc-item-label">Сергею (93,3%)</div>
        <div class="ec-calc-item-val" style="color:var(--an-accent);" id="ec-plan-s-rub">46 650 ₽</div>
        <div style="font-size:11px; color:var(--an-muted);">Никите: <span id="ec-plan-n-rub">3 350 ₽</span></div>
      </div>
      <div class="ec-calc-item">
        <div class="ec-calc-item-label">В развитие (15%)</div>
        <div class="ec-calc-item-val" style="color:#D97706;" id="ec-plan-dev-rub">8 820 ₽</div>
        <div style="font-size:11px; color:var(--an-muted);" id="ec-plan-cr-val">CR: ~4.7%</div>
      </div>
    </div>
  </div>
</div>

<!-- Ряд 3: Чеки и покупки премиумов -->
<div class="an-card">
  <div class="an-head">
    <div style="display:flex; align-items:center; gap:12px;">
      <div class="an-title">Чеки и покупки премиумов</div>
      <span class="an-caption" id="ec-receipts-count" style="margin:0;">0 записей</span>
      <details class="an-help">
        <summary aria-label="О чеках">i</summary>
        <div>Список всех подтверждённых оплат через СБП (Platega), App Store, Google Play и ручных выплат. Тестовые платежи разработчика исключены из выручки.</div>
      </details>
    </div>
    <div style="display:flex; align-items:center; gap:8px;">
      <label style="display:flex; align-items:center; gap:6px; font-size:12px; color:var(--an-muted); cursor:pointer;">
        <input type="checkbox" id="ec-hide-test-chk" checked>
        <span>Без тестов</span>
      </label>
      <button class="btn-action" id="ec-add-payout-btn">+ Выплата стора</button>
    </div>
  </div>

  <div style="margin-bottom:12px;">
    <input type="search" id="ec-receipts-search" class="ec-search" placeholder="Поиск по чекам (email, имя, транзакция…)">
  </div>

  <div class="an-table-wrap">
    <table class="an-table">
      <thead>
        <tr>
          <th>Дата (МСК)</th>
          <th>Покупатель</th>
          <th>Источник</th>
          <th>Тариф</th>
          <th>Сумма</th>
          <th>ID заказа / Чек</th>
          <th>Статус</th>
        </tr>
      </thead>
      <tbody id="ec-receipts-tbody">
        <tr><td colspan="7" class="an-empty">Загрузка чеков…</td></tr>
      </tbody>
    </table>
  </div>
</div>

<!-- Настройки и коэффициенты под спойлером -->
<div class="an-card" style="padding:18px 24px;">
  <details class="an-day-details">
    <summary>Параметры и коэффициенты (курс доллара, домен, доли)</summary>
    <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(180px, 1fr)); gap:14px; margin-top:16px; align-items:flex-end;">
      <div>
        <label class="form-label">Курс USD/RUB:</label>
        <input type="number" id="ec-cfg-usd" class="form-input" style="width:100%;" value="95" step="0.5">
      </div>
      <div>
        <label class="form-label">Cloudflare в месяц ($):</label>
        <input type="number" id="ec-cfg-cf" class="form-input" style="width:100%;" value="5" step="1">
      </div>
      <div>
        <label class="form-label">Домен pdd-drive.ru (₽/мес):</label>
        <input type="number" id="ec-cfg-domain" class="form-input" style="width:100%;" value="67" step="5">
      </div>
      <div>
        <label class="form-label">Фонд развития (%):</label>
        <input type="number" id="ec-cfg-reinvest" class="form-input" style="width:100%;" value="15" step="0.5">
      </div>
      <div>
        <label class="form-label">Доля Никиты (%):</label>
        <input type="number" id="ec-cfg-nikita" class="form-input" style="width:100%;" value="6.7" step="0.1">
      </div>
      <div>
        <button class="btn-action btn-primary" id="ec-save-cfg-btn" style="width:100%; height:38px; justify-content:center;">Сохранить</button>
      </div>
    </div>
  </details>
</div>

</div>
`;

export const ECONOMY_CLIENT_JS = String.raw`
// ────────────────────── Economy Module Client JS ──────────────────────
if (typeof VIEW_TITLES !== 'undefined') {
  VIEW_TITLES.economy = 'Экономика';
}

(function() {
  var ecStats = null;
  var ecPeriod = 'month';
  var ecReceipts = [];

  function fmtRub(val) {
    var n = Math.round(Number(val) || 0);
    return n.toLocaleString('ru-RU') + ' ₽';
  }

  function fmtDecRub(val) {
    var n = Number(val) || 0;
    return n.toLocaleString('ru-RU', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' ₽';
  }

  function fmtDate(iso) {
    if (!iso) return '—';
    try {
      var d = new Date(iso);
      return d.toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' }) + ' ' +
             d.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
    } catch (_) {
      return String(iso);
    }
  }

  async function loadEconomy() {
    var state = document.getElementById('ec-data-state');
    if (state) {
      state.className = 'admin-data-state loading';
      state.innerText = 'Загрузка…';
    }

    try {
      var res = await fetch('/api/admin/economy/stats?period=' + ecPeriod);
      if (res.status === 401) {
        if (typeof checkAuthAndLoad === 'function') checkAuthAndLoad();
        return;
      }
      if (!res.ok) throw new Error('Ошибка ' + res.status);
      var data = await res.json();
      ecStats = data;
      ecReceipts = data.receipts || [];
      renderEconomy(data);
      renderReceipts();
      if (state) {
        state.className = 'admin-data-state ready';
        state.innerText = 'Обновлено ' + new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
      }
    } catch (err) {
      console.error('loadEconomy error:', err);
      if (state) {
        state.className = 'admin-data-state error';
        state.innerText = 'Ошибка';
      }
    }
  }

  function renderEconomy(data) {
    if (!data) return;
    var rev = data.revenue || {};
    var exp = data.expenses || {};
    var prof = data.profit || {};
    var partners = data.partners || {};
    var be = data.breakEven || {};
    var cfg = data.config || {};

    // 1. KPI карточки
    var elGross = document.getElementById('ec-gross-val');
    if (elGross) elGross.innerText = fmtRub(rev.grossRub);
    var elGrossSub = document.getElementById('ec-gross-sub');
    if (elGrossSub) elGrossSub.innerText = (rev.ordersCount || 0) + ' оплат · без тестов';

    var elCosts = document.getElementById('ec-costs-val');
    if (elCosts) elCosts.innerText = fmtRub(exp.totalRub);

    var elReinvest = document.getElementById('ec-reinvest-val');
    if (elReinvest) elReinvest.innerText = fmtRub(prof.reinvestRub);

    var elNet = document.getElementById('ec-net-val');
    if (elNet) elNet.innerText = fmtRub(prof.distributableNetRub);

    // 2. Партнеры
    var sergey = partners.sergey || {};
    var nikita = partners.nikita || {};
    var elPayoutS = document.getElementById('ec-payout-s');
    if (elPayoutS) elPayoutS.innerText = fmtRub(sergey.payoutRub);
    var elPayoutN = document.getElementById('ec-payout-n');
    if (elPayoutN) elPayoutN.innerText = fmtRub(nikita.payoutRub);

    // 3. Таблица расходов
    var elCfRub = document.getElementById('ec-cost-cf-rub');
    if (elCfRub) elCfRub.innerText = fmtDecRub(exp.cloudflare?.rub);
    var elDomRub = document.getElementById('ec-cost-domain-rub');
    if (elDomRub) elDomRub.innerText = fmtDecRub(exp.domain?.rub || 67);
    var elAiUsd = document.getElementById('ec-cost-ai-usd');
    if (elAiUsd) elAiUsd.innerText = '$' + (exp.ai?.usd || 0).toFixed(4);
    var elAiRub = document.getElementById('ec-cost-ai-rub');
    if (elAiRub) elAiRub.innerText = fmtDecRub(exp.ai?.rub);

    // 4. Точка безубыточности
    var elBeSum = document.getElementById('ec-be-sum');
    if (elBeSum) elBeSum.innerText = fmtRub(be.targetRub) + ' / мес';
    var elBeW = document.getElementById('ec-be-w');
    if (elBeW) elBeW.innerText = (be.weeklySubsNeeded || 6) + ' шт';
    var elBe3m = document.getElementById('ec-be-3m');
    if (elBe3m) elBe3m.innerText = (be.threeMonthSubsNeeded || 2) + ' шт';

    var elBeStat = document.getElementById('ec-be-status');
    if (elBeStat) {
      if (be.isProfitable) {
        elBeStat.innerHTML = '<span style="color:var(--an-green);font-weight:600;">✓ Проект окупается на ' + be.coveragePercent + '% и приносит чистую прибыль.</span>';
      } else {
        elBeStat.innerHTML = '<span style="color:#D97706;font-weight:600;">Покрытие расходов: ' + be.coveragePercent + '%. Нужно ещё ' + Math.max(1, (be.weeklySubsNeeded || 6) - (rev.ordersCount || 0)) + ' подписок.</span>';
      }
    }

    // 5. Конфиг
    var elUsd = document.getElementById('ec-cfg-usd');
    if (elUsd) elUsd.value = cfg.usdRate || 95;
    var elCf = document.getElementById('ec-cfg-cf');
    if (elCf) elCf.value = cfg.cloudflareMonthlyUsd || 5;
    var elDom = document.getElementById('ec-cfg-domain');
    if (elDom) elDom.value = cfg.domainMonthlyRub || 67;
    var elReinv = document.getElementById('ec-cfg-reinvest');
    if (elReinv) elReinv.value = cfg.reinvestPercent || 15;
    var elNik = document.getElementById('ec-cfg-nikita');
    if (elNik) elNik.value = cfg.nikitaSharePercent || 6.7;

    updatePlanner();
  }

  function renderReceipts() {
    var tbody = document.getElementById('ec-receipts-tbody');
    var countEl = document.getElementById('ec-receipts-count');
    if (!tbody) return;

    var hideTest = document.getElementById('ec-hide-test-chk')?.checked ?? true;
    var q = (document.getElementById('ec-receipts-search')?.value || '').toLowerCase().trim();

    var testCount = 0;
    var filtered = ecReceipts.filter(function(r) {
      if (r.isTest) testCount++;
      if (hideTest && r.isTest) return false;
      if (q) {
        var str = (r.customer + ' ' + r.email + ' ' + r.txId + ' ' + r.id + ' ' + r.store).toLowerCase();
        if (str.indexOf(q) === -1) return false;
      }
      return true;
    });

    if (countEl) {
      countEl.innerText = filtered.length + ' чеков' + (hideTest && testCount > 0 ? ' (' + testCount + ' тест скрыт)' : '');
    }

    if (!filtered.length) {
      var emptyMsg = hideTest && testCount > 0
        ? 'Скрыт 1 тестовый чек (снимите галочку «Без тестов», чтобы увидеть)'
        : 'Нет подтверждённых чеков за выбранный период';
      tbody.innerHTML = '<tr><td colspan="7" class="an-empty">' + emptyMsg + '</td></tr>';
      return;
    }

    tbody.innerHTML = filtered.map(function(r) {
      var badge = r.isTest
        ? '<span class="ec-badge ec-badge-amber">Тест</span>'
        : '<span class="ec-badge ec-badge-green">Оплачен</span>';
      var storeIcon = '';
      if (typeof BRAND_SVGS !== 'undefined' && BRAND_SVGS) {
        if (r.storeKey === 'web') storeIcon = BRAND_SVGS.sbp;
        else if (r.storeKey === 'appstore' || r.storeKey === 'apple') storeIcon = BRAND_SVGS.appstore;
        else if (r.storeKey === 'gplay' || r.storeKey === 'googleplay') storeIcon = BRAND_SVGS.gplay;
        else if (r.storeKey === 'rustore') storeIcon = BRAND_SVGS.rustore;
      }
      var storeBadge = r.storeKey === 'web'
        ? '<span class="ec-badge ec-badge-blue" style="display:inline-flex;align-items:center;gap:6px;">' + (storeIcon || '') + '<span>СБП</span></span>'
        : '<span class="ec-badge ec-badge-gray" style="display:inline-flex;align-items:center;gap:6px;">' + (storeIcon || '') + '<span>' + (r.store || 'Стор') + '</span></span>';

      return '<tr>' +
        '<td>' + fmtDate(r.date) + '</td>' +
        '<td><strong>' + (typeof adminEsc === 'function' ? adminEsc(r.customer) : r.customer) + '</strong>' +
          (r.email ? '<br><small style="color:var(--an-muted);">' + (typeof adminEsc === 'function' ? adminEsc(r.email) : r.email) + '</small>' : '') + '</td>' +
        '<td>' + storeBadge + '</td>' +
        '<td>' + (r.tier || 'Премиум') + '</td>' +
        '<td><strong>' + fmtRub(r.amountRub) + '</strong></td>' +
        '<td><span class="code-badge" style="font-size:10.5px;">' + (r.txId ? String(r.txId).slice(0, 16) + '…' : '—') + '</span></td>' +
        '<td>' + badge + '</td>' +
      '</tr>';
    }).join('');
  }

  function updatePlanner() {
    var input = document.getElementById('ec-calc-input');
    var targetNet = Math.max(1000, Number(input ? input.value : 50000) || 50000);

    var reinvestPct = ecStats?.config?.reinvestPercent || 15;
    var nikitaPct = ecStats?.config?.nikitaSharePercent || 6.7;
    var sergeyPct = 100 - nikitaPct;

    var factor = Math.max(0.1, 1 - (reinvestPct / 100));
    var reqOperating = targetNet / factor;
    var reinvestAmount = reqOperating - targetNet;

    var avgCheck = 190;
    var reqSales = Math.ceil(reqOperating / avgCheck);
    var dailySales = Math.max(1, Math.round(reqSales / 30));

    var sergeyPayout = (targetNet * sergeyPct) / 100;
    var nikitaPayout = (targetNet * nikitaPct) / 100;

    var totalUsers = ecStats?.unitEconomics?.totalUsersCount || 6595;
    var reqCR = totalUsers > 0 ? ((reqSales / totalUsers) * 100).toFixed(1) : '4.7';

    var elSalesM = document.getElementById('ec-plan-sales-m');
    if (elSalesM) elSalesM.innerText = '~' + reqSales.toLocaleString('ru-RU') + ' шт';
    var elSalesD = document.getElementById('ec-plan-sales-d');
    if (elSalesD) elSalesD.innerText = '~' + dailySales + ' в день';

    var elS = document.getElementById('ec-plan-s-rub');
    if (elS) elS.innerText = fmtRub(sergeyPayout);
    var elN = document.getElementById('ec-plan-n-rub');
    if (elN) elN.innerText = fmtRub(nikitaPayout);

    var elDev = document.getElementById('ec-plan-dev-rub');
    if (elDev) elDev.innerText = fmtRub(reinvestAmount);

    var elCr = document.getElementById('ec-plan-cr-val');
    if (elCr) elCr.innerText = 'CR: ~' + reqCR + '%';
  }

  function initListeners() {
    // Периоды
    var periodTabs = document.querySelectorAll('#ec-period-tabs button');
    periodTabs.forEach(function(btn) {
      btn.addEventListener('click', function() {
        periodTabs.forEach(function(b) { b.classList.remove('active'); });
        btn.classList.add('active');
        ecPeriod = btn.dataset.period || 'month';
        loadEconomy();
      });
    });

    // Обновить
    var refBtn = document.getElementById('ec-refresh-btn');
    if (refBtn) refBtn.addEventListener('click', loadEconomy);

    // Фильтр и поиск чеков
    var chkHide = document.getElementById('ec-hide-test-chk');
    if (chkHide) chkHide.addEventListener('change', renderReceipts);
    var searchInput = document.getElementById('ec-receipts-search');
    if (searchInput) searchInput.addEventListener('input', renderReceipts);

    // Калькулятор
    var calcInput = document.getElementById('ec-calc-input');
    if (calcInput) calcInput.addEventListener('input', updatePlanner);

    var presetBtns = document.querySelectorAll('#ec-calc-presets button');
    presetBtns.forEach(function(btn) {
      btn.addEventListener('click', function() {
        presetBtns.forEach(function(b) { b.classList.remove('active'); });
        btn.classList.add('active');
        if (calcInput) {
          calcInput.value = btn.dataset.val;
          updatePlanner();
        }
      });
    });

    // Сохранить параметры
    var saveCfgBtn = document.getElementById('ec-save-cfg-btn');
    if (saveCfgBtn) {
      saveCfgBtn.addEventListener('click', async function() {
        var usdRate = parseFloat(document.getElementById('ec-cfg-usd').value);
        var cloudflareMonthlyUsd = parseFloat(document.getElementById('ec-cfg-cf').value);
        var domainMonthlyRub = parseFloat(document.getElementById('ec-cfg-domain').value);
        var reinvestPercent = parseFloat(document.getElementById('ec-cfg-reinvest').value);
        var nikitaSharePercent = parseFloat(document.getElementById('ec-cfg-nikita').value);

        saveCfgBtn.innerText = 'Сохранение…';
        saveCfgBtn.disabled = true;

        try {
          var res = await fetch('/api/admin/economy/settings', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ usdRate, cloudflareMonthlyUsd, domainMonthlyRub, reinvestPercent, nikitaSharePercent })
          });
          var data = await res.json();
          if (data.ok) {
            saveCfgBtn.innerText = 'Сохранено!';
            setTimeout(function() { saveCfgBtn.innerText = 'Сохранить'; saveCfgBtn.disabled = false; }, 1800);
            loadEconomy();
          } else {
            alert('Ошибка: ' + (data.error || 'не удалось сохранить'));
            saveCfgBtn.innerText = 'Сохранить';
            saveCfgBtn.disabled = false;
          }
        } catch (e) {
          alert('Ошибка сети: ' + e);
          saveCfgBtn.innerText = 'Сохранить';
          saveCfgBtn.disabled = false;
        }
      });
    }

    // Выплата стора
    var payoutBtn = document.getElementById('ec-add-payout-btn');
    if (payoutBtn) {
      payoutBtn.addEventListener('click', async function() {
        var store = prompt('Магазин (appstore / googleplay / rustore / other):', 'appstore');
        if (!store) return;
        var title = prompt('Описание (например: Выплата от Apple за прошлый месяц):');
        if (!title) return;
        var amt = parseFloat(prompt('Сумма в рублях:'));
        if (!amt || amt <= 0) return;

        try {
          var res = await fetch('/api/admin/economy/revenues/add', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ store, title, amountRub: amt })
          });
          var data = await res.json();
          if (data.ok) loadEconomy();
          else alert('Ошибка: ' + (data.error || 'не удалось добавить'));
        } catch (e) {
          alert('Ошибка сети: ' + e);
        }
      });
    }

    // Слушатель сайдбара
    document.querySelectorAll('.sidebar-menu .nav-item').forEach(function(btn) {
      btn.addEventListener('click', function() {
        var isEconomy = btn.dataset.feature === 'economy';
        var viewEl = document.getElementById('economy-view');
        if (viewEl) viewEl.style.display = isEconomy ? 'block' : 'none';
        if (isEconomy) {
          var titleEl = document.getElementById('current-view-title');
          if (titleEl) titleEl.innerText = 'Экономика';
          loadEconomy();
        }
      });
    });
    window.loadEconomy = loadEconomy;
  }

  window.loadEconomy = loadEconomy;
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initListeners);
  } else {
    initListeners();
  }

  // Немедленный запуск при открытии вкладки «Экономика»
  if (location.hash.split('/')[0] === '#economy' || localStorage.getItem('pdd-admin-feature') === 'economy') {
    var viewEl = document.getElementById('economy-view');
    if (viewEl) viewEl.style.display = 'block';
    loadEconomy();
  }
})();
`;
