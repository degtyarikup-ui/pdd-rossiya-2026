// Экономика: фактические поступления, календарь расходов и распределение прибыли.
// Разметка и клиентский код подключаются оболочкой admin_ui.js.
export const ECONOMY_NAV_HTML = String.raw`
<button class="nav-item" data-feature="economy"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg><span>Экономика</span></button>`;

export const ECONOMY_VIEW_HTML = String.raw`
<div id="economy-view" style="display:none">
<style>
#economy-view{color:var(--text,#17191E);--ec-muted:#747B88;--ec-blue:#0574F8;--ec-green:#15966B;--ec-red:#C54C35;--ec-soft:#F4F6F9}
#economy-view [hidden]{display:none!important}
#economy-view button{cursor:pointer}#economy-view button:disabled{cursor:default}
.ec-toolbar,.ec-actions,.ec-head,.ec-inline{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.ec-toolbar{justify-content:space-between;margin-bottom:18px}.ec-actions{gap:8px}.ec-period-note{font-size:11px;color:var(--ec-muted);margin:0 0 16px}
.ec-seg{display:flex;gap:3px;padding:4px;background:#E9ECF1;border-radius:11px;max-width:100%;width:fit-content}
#economy-view .ec-seg button{border:0;padding:8px 13px;min-height:32px;border-radius:8px;background:transparent;color:var(--ec-muted);font-size:11.5px;font-weight:550;white-space:nowrap}
#economy-view .ec-seg button.active{background:#17191E;color:#fff}
#economy-view .ec-seg.ec-small{background:var(--ec-soft);padding:3px}#economy-view .ec-seg.ec-small button{padding:6px 10px;min-height:28px;font-size:11px}
#economy-view .ec-seg.ec-small button.active{background:#fff;color:#17191E}
.ec-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;margin-bottom:16px}
#economy-view .ec-card{background:#fff;padding:22px 24px;border-radius:20px;min-width:0}
.ec-kpi-label{font-size:12px;color:var(--ec-muted);font-weight:500;display:flex;align-items:center;gap:7px}
.ec-value{font-size:34px;font-weight:580;letter-spacing:-1.2px;line-height:1.15;margin:18px 0 10px;font-variant-numeric:tabular-nums;overflow-wrap:anywhere}
.ec-caption{font-size:11px;color:var(--ec-muted);line-height:1.5}.ec-caption:empty{display:none}
#economy-view .ec-net{background:var(--ec-blue);color:#fff}.ec-net .ec-kpi-label,.ec-net .ec-caption{color:#D8E8FF}
#economy-view .ec-net.is-loss{background:#FCEDE8;color:var(--ec-red)}.ec-net.is-loss .ec-kpi-label,.ec-net.is-loss .ec-caption{color:#A35A4B}
.ec-main-grid{display:grid;grid-template-columns:minmax(0,1.4fr) minmax(310px,1fr);gap:16px;align-items:start;margin-bottom:16px}
.ec-head{justify-content:space-between;margin-bottom:18px;min-height:34px}.ec-head h2,.ec-head h3{margin:0;font-size:15px;letter-spacing:-.3px;font-weight:600}
.ec-head-title{display:flex;align-items:center;gap:8px}.ec-head .ec-caption{margin-left:auto}
.ec-table-wrap{overflow:auto;max-width:100%}.ec-table{border-collapse:collapse;width:100%;font-size:12px;line-height:1.5}
#economy-view .ec-table th{font-size:10px;color:#89919F;font-weight:500;letter-spacing:.3px;text-align:left;padding:0 10px 11px 0;white-space:nowrap}
#economy-view .ec-table td{border-top:1px solid #EDF0F3;padding:13px 10px 13px 0;vertical-align:middle;font-weight:450}
#economy-view .ec-table th:last-child,#economy-view .ec-table td:last-child{padding-right:0}
.ec-table strong{font-weight:550}.ec-table .ec-money{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums;font-weight:600}.ec-table .ec-cell-action{width:30px;text-align:right}
.ec-sub{display:block;color:var(--ec-muted);font-size:10.5px;font-weight:400;margin-top:3px}.ec-name{min-width:120px;max-width:240px;overflow-wrap:anywhere}
.ec-pill{display:inline-flex;align-items:center;gap:5px;padding:4px 7px;border-radius:6px;font-size:10px;font-weight:500;white-space:nowrap;background:#F0F2F6;color:#737C8C}
.ec-pill.blue{background:#E8F1FF;color:var(--ec-blue)}.ec-pill.green{background:#E9F6EF;color:var(--ec-green)}.ec-pill.amber{background:#FFF3DC;color:#A66A12}
#economy-view .ec-edit{display:inline-flex;align-items:center;justify-content:center;border:0;background:#F3F5F8;color:#717D90;width:30px;height:30px;border-radius:8px;padding:6px;flex-shrink:0}
#economy-view .ec-edit:hover{background:#E8F1FF;color:var(--ec-blue)}.ec-edit svg{width:14px;height:14px}
.ec-row-actions{display:flex;align-items:center;justify-content:flex-end;gap:6px}
#economy-view .ec-remove{color:var(--ec-red);background:#FCF1EE}#economy-view .ec-remove:hover{color:#A93A25;background:#F9DFD7}
.ec-delete-summary{grid-column:1/-1;background:#F4F6F9;border-radius:12px;padding:15px;overflow-wrap:anywhere}.ec-delete-summary strong{font-size:14px;font-weight:550;display:block}.ec-delete-summary span{display:block;font-size:12px;color:#747B88;margin-top:5px}
.ec-expense-foot{display:flex;gap:14px;justify-content:space-between;flex-wrap:wrap;border-top:1px solid #EDF0F3;padding-top:14px;margin-top:2px;font-size:11px;color:var(--ec-muted)}.ec-expense-foot b{color:#343B49;font-weight:550;margin-left:5px}
.ec-ai-note{display:flex;align-items:center;justify-content:space-between;gap:10px;font-size:11px;margin-top:16px;background:var(--ec-soft);border-radius:10px;padding:11px 12px;color:var(--ec-muted)}.ec-ai-note strong{color:#424C5B;font-weight:550}
.ec-split{display:flex;overflow:hidden;height:8px;border-radius:10px;margin:0 0 20px;background:#EDF0F4}.ec-split i{display:block;background:var(--ec-blue);transition:width .2s}.ec-split i+i{background:var(--ec-green)}
.ec-partner{display:flex;align-items:center;gap:11px;padding:14px 0}.ec-partner+.ec-partner{border-top:1px solid #EDF0F3}.ec-avatar{width:36px;height:36px;display:grid;place-items:center;border-radius:12px;background:#E8F1FF;color:var(--ec-blue);font-weight:600;font-size:13px;flex:none}.ec-avatar.green{background:#E9F6EF;color:var(--ec-green)}
.ec-partner-info{flex:1;min-width:0}.ec-partner-info strong{font-size:13px;font-weight:550}.ec-partner-amount{font-size:21px;font-weight:580;letter-spacing:-.5px;white-space:nowrap;font-variant-numeric:tabular-nums}.ec-partner-percent{font-size:11px;color:var(--ec-muted);margin-left:7px}
.ec-distribution-foot{margin-top:15px;padding:14px;background:var(--ec-soft);border-radius:12px;display:flex;align-items:center;justify-content:space-between;gap:12px;font-size:11px;color:var(--ec-muted)}.ec-distribution-foot b{font-size:14px;font-weight:600;color:#343B49;white-space:nowrap}
.ec-profit-path{font-size:10.5px;color:#8B94A2;margin-top:14px;text-align:center}.ec-empty{padding:28px 10px!important;text-align:center;color:var(--ec-muted);font-size:12px}
.ec-feedback{display:flex;justify-content:space-between;gap:14px;padding:12px 16px;border-radius:12px;background:#E9F6EF;color:#16774F;font-size:12px;margin-bottom:16px}.ec-feedback.error{background:#FCEDE8;color:#B1432D}.ec-feedback button{border:0;background:none;color:inherit;padding:0;font-size:18px;line-height:1}
.ec-ledger-tools{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-bottom:16px}.ec-search{flex:1;min-width:180px;padding:9px 12px}.ec-ledger-tools select{padding:9px 11px;max-width:170px}.ec-check{display:flex;align-items:center;gap:6px;font-size:11px;color:var(--ec-muted);cursor:pointer;white-space:nowrap}
.ec-ledger-tools input[type=checkbox]{margin:0}.ec-ledger-top{margin-bottom:14px}.ec-receipt-id{border:0;background:none;padding:3px 0;font-size:10px;color:#8791A0;max-width:150px;text-align:left;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;display:block;font-family:monospace}
.ec-pager{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:15px;font-size:11px;color:var(--ec-muted)}.ec-pager .ec-actions{gap:6px}
.ec-planning{background:#fff;border-radius:20px;margin-top:16px}.ec-planning>summary{display:flex;align-items:center;justify-content:space-between;list-style:none;cursor:pointer;padding:19px 24px;font-weight:550;font-size:13px}.ec-planning>summary::-webkit-details-marker{display:none}.ec-planning>summary:after{content:'+';font-size:20px;font-weight:400;color:var(--ec-muted)}.ec-planning[open]>summary:after{content:'−'}
.ec-plan-grid{display:grid;grid-template-columns:1fr 1.3fr;gap:24px;padding:0 24px 24px}.ec-plan-block+.ec-plan-block{border-left:1px solid #EDF0F3;padding-left:24px}.ec-plan-title{font-size:12px;font-weight:550;margin-bottom:13px}.ec-plan-amount{font-size:26px;letter-spacing:-.8px;font-weight:580;margin:8px 0}.ec-progress{height:5px;background:#EDF0F3;border-radius:9px;margin:14px 0 8px;overflow:hidden}.ec-progress i{height:100%;display:block;background:var(--ec-green)}.ec-plan-numbers{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:16px}.ec-plan-numbers strong{display:block;font-size:17px;font-weight:600;color:#343B49;margin-top:5px}.ec-plan-controls{display:grid;grid-template-columns:1fr 1fr;gap:12px}.ec-plan-controls label{font-size:11px;color:var(--ec-muted);display:flex;flex-direction:column;gap:6px}.ec-plan-controls input{padding:9px 12px;width:100%;box-sizing:border-box}
#ec-dialog{margin:auto;padding:0;border:0;border-radius:22px;width:min(460px,calc(100% - 32px));max-height:calc(100svh - 40px);overflow:auto;color:#17191E;background:#fff;box-shadow:0 20px 80px #17223622}
#ec-dialog::backdrop{background:#17223655;backdrop-filter:blur(3px)}#ec-form{padding:26px}#ec-dialog h2{font-size:21px;font-weight:600;letter-spacing:-.6px;margin:0 0 22px}.ec-form-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}.ec-field{display:flex;flex-direction:column;gap:7px;min-width:0;font-size:11px;font-weight:500;color:#6D7583}.ec-field.full{grid-column:1/-1}.ec-field input,.ec-field select{box-sizing:border-box;width:100%;padding:11px 12px;font-weight:450}.ec-field input[type=checkbox]{width:auto;min-height:auto}.ec-form-check{display:flex;align-items:center;gap:8px;grid-column:1/-1;font-size:12px;color:#555E6E}.ec-form-preview{grid-column:1/-1;background:#F4F6F9;border-radius:10px;padding:12px;font-size:11px;color:#747B88;min-height:16px}.ec-form-preview b{font-weight:600;color:#343B49}
.ec-form-actions{display:flex;align-items:center;justify-content:flex-end;gap:8px;margin-top:24px;flex-wrap:wrap}.ec-form-actions #ec-delete{margin-right:auto}.ec-form-error{font-size:12px;color:#B1432D;background:#FCEDE8;padding:11px 12px;border-radius:10px;margin-top:16px}.ec-form-note{font-size:11px;color:#747B88;margin:16px 0 0;line-height:1.5}
@media(max-width:1150px){.ec-main-grid{grid-template-columns:minmax(0,1fr)}.ec-value{font-size:29px}#economy-view .ec-card{padding:20px}.ec-partner-amount{font-size:23px}}
@media(max-width:1050px){.ec-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:850px){.ec-plan-grid{grid-template-columns:1fr}.ec-plan-block+.ec-plan-block{border-left:0;border-top:1px solid #EDF0F3;padding:22px 0 0}}
@media(max-width:600px){
 #economy-view .ec-table{display:block}#economy-view .ec-table tbody{display:block}
 #economy-view .ec-table thead{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}
 #economy-view .ec-table tr{display:grid;grid-template-columns:minmax(0,1fr) auto 30px;gap:5px 10px;padding:14px 0;border-top:1px solid #EDF0F3;align-items:center}
 #economy-view .ec-table td{border:0;padding:0;min-width:0}
 #economy-view .ec-table td.ec-empty{grid-column:1/-1;padding:20px 0!important}
 #economy-view .ec-table .ec-name{min-width:0;max-width:none}
 #economy-view .ec-table .ec-money{white-space:normal;overflow-wrap:anywhere;font-size:12px;max-width:105px}
 #economy-view #ec-expenses-body td:first-child{grid-column:1;grid-row:1}
 #economy-view #ec-expenses-body td:nth-child(2){grid-column:1;grid-row:2;display:flex;align-items:center;gap:7px;flex-wrap:wrap}
 #economy-view #ec-expenses-body td:nth-child(2) .ec-sub{margin:0}
 #economy-view #ec-expenses-body td:nth-child(3){grid-column:2;grid-row:1/3}
 #economy-view #ec-expenses-body td:nth-child(4){grid-column:3;grid-row:1/3}#economy-view #ec-expenses-body .ec-row-actions{flex-direction:column}
 #economy-view #ec-receipts-body tr{grid-template-columns:minmax(0,1fr) auto;gap:7px 10px}
 #economy-view #ec-receipts-body td:nth-child(2){grid-column:1;grid-row:1}
 #economy-view #ec-receipts-body td:nth-child(5){grid-column:2;grid-row:1;align-self:start;padding-top:1px}
 #economy-view #ec-receipts-body td:nth-child(1){grid-column:1;grid-row:2;font-size:10.5px;color:var(--ec-muted)}
 #economy-view #ec-receipts-body td:nth-child(6){grid-column:2;grid-row:2;text-align:right;width:auto}
 #economy-view #ec-receipts-body td:nth-child(3){grid-column:1;grid-row:3}
 #economy-view #ec-receipts-body td:nth-child(4){grid-column:2;grid-row:3;text-align:right}
}
@media(max-width:480px){.ec-kpis{gap:10px}.ec-value{font-size:27px;margin-top:14px}#economy-view .ec-card{padding:17px}.ec-kpi-label{font-size:11px}.ec-caption{font-size:10.5px}.ec-toolbar{gap:13px}.ec-toolbar>.ec-actions{width:100%;justify-content:flex-end}.ec-toolbar .admin-data-state{display:inline;margin-right:auto;padding-left:0}.ec-head{gap:10px}.ec-ledger-tools select{flex:1;max-width:none}.ec-search{flex-basis:100%}.ec-form-grid{gap:14px 10px}#ec-form{padding:22px}.ec-partner-amount{font-size:21px}.ec-plan-grid{padding:0 17px 20px}.ec-planning>summary{padding:18px 17px}}
</style>

<div class="ec-toolbar">
 <div class="ec-seg" id="ec-period-tabs" aria-label="Период"><button type="button" data-period="month" class="active" aria-pressed="true">Этот месяц</button><button type="button" data-period="30d" aria-pressed="false">30 дней</button><button type="button" data-period="all" aria-pressed="false">Всё время</button></div>
 <div class="ec-actions"><span class="admin-data-state loading" id="ec-data-state" role="status">Загрузка…</span><button type="button" class="btn-action" id="ec-refresh">Обновить</button><button type="button" class="btn-action" id="ec-settings" disabled>Параметры</button></div>
</div>
<div id="ec-feedback" class="ec-feedback" role="status" hidden><span></span><button type="button" aria-label="Закрыть сообщение">×</button></div>
<p class="ec-period-note" id="ec-period-note">&nbsp;</p>
<div class="ec-kpis" aria-label="Итоги периода">
 <div class="ec-card"><div class="ec-kpi-label">Поступления</div><div class="ec-value" id="ec-gross-val">—</div><div class="ec-caption" id="ec-gross-sub">Все источники · продажи магазинов по тарифу</div></div>
 <div class="ec-card"><div class="ec-kpi-label">Расходы</div><div class="ec-value" id="ec-costs-val">—</div><div class="ec-caption" id="ec-costs-sub">За выбранный период</div></div>
 <div class="ec-card"><div class="ec-kpi-label">В развитие</div><div class="ec-value" id="ec-reinvest-val">—</div><div class="ec-caption" id="ec-reinvest-sub">От прибыли после расходов</div></div>
 <div class="ec-card ec-net" id="ec-net-card"><div class="ec-kpi-label" id="ec-net-label">К распределению</div><div class="ec-value" id="ec-net-val">—</div><div class="ec-caption" id="ec-net-sub">Сергей и Никита</div></div>
</div>
<div class="ec-main-grid">
 <section class="ec-card" aria-labelledby="ec-expenses-title">
  <div class="ec-head"><h2 id="ec-expenses-title">Расходы проекта</h2><button type="button" class="btn-action btn-primary" id="ec-add-expense" disabled>+ Расход</button></div>
  <div class="ec-head"><div class="ec-seg ec-small" id="ec-expense-filter" aria-label="Вид расходов"><button type="button" class="active" data-filter="all" aria-pressed="true">Все</button><button type="button" data-filter="recurring" aria-pressed="false">Постоянные</button><button type="button" data-filter="once" aria-pressed="false">Разовые</button></div><span class="ec-caption">В периоде, ₽</span></div>
  <div class="ec-table-wrap"><table class="ec-table"><thead><tr><th>Статья</th><th>Периодичность</th><th class="ec-money">Сумма</th><th aria-label="Действия"></th></tr></thead><tbody id="ec-expenses-body"><tr><td colspan="4" class="ec-empty">Загрузка расходов…</td></tr></tbody></table></div>
  <div class="ec-expense-foot"><span>Постоянные <b id="ec-recurring-total">—</b></span><span>Разовые <b id="ec-once-total">—</b></span></div>
  <div class="ec-ai-note" id="ec-ai-note" hidden><span>Gemini · за всё время <strong id="ec-ai-total"></strong></span><span class="ec-pill" id="ec-ai-scope">Вне периода</span></div>
 </section>
 <section class="ec-card" aria-labelledby="ec-partners-title">
  <div class="ec-head"><h2 id="ec-partners-title">Распределение прибыли</h2><button type="button" class="btn-action" id="ec-edit-shares" disabled>Изменить</button></div>
  <div class="ec-split" aria-hidden="true"><i id="ec-bar-s" style="width:93.3%"></i><i id="ec-bar-n" style="width:6.7%"></i></div>
  <div class="ec-partner"><div class="ec-avatar">С</div><div class="ec-partner-info"><strong>Сергей</strong><span class="ec-partner-percent" id="ec-share-s">—</span><span class="ec-sub">Разработка</span></div><div class="ec-partner-amount" id="ec-payout-s">—</div></div>
  <div class="ec-partner"><div class="ec-avatar green">Н</div><div class="ec-partner-info"><strong>Никита</strong><span class="ec-partner-percent" id="ec-share-n">—</span><span class="ec-sub">Развитие</span></div><div class="ec-partner-amount" id="ec-payout-n">—</div></div>
  <div class="ec-distribution-foot"><span>Фонд развития <span id="ec-fund-pct">—</span></span><b id="ec-fund-total">—</b></div>
  <div class="ec-profit-path">Поступления → Расходы → Развитие → Доли</div>
 </section>
</div>
<section class="ec-card" aria-labelledby="ec-income-title">
 <div class="ec-head ec-ledger-top"><div class="ec-head-title"><h2 id="ec-income-title">Поступления и покупки</h2><span class="ec-caption" id="ec-receipts-count"></span></div><button type="button" class="btn-action btn-primary" id="ec-add-revenue" disabled>+ Поступление</button></div>
 <div class="ec-head"><div class="ec-seg ec-small" id="ec-receipt-mode" aria-label="Тип записей"><button type="button" class="active" data-mode="actual" aria-pressed="true">Поступления</button><button type="button" data-mode="estimated" aria-pressed="false">Покупки в сторах</button></div><span class="ec-caption" id="ec-ledger-note">Учтены в доходе</span></div>
 <div class="ec-ledger-tools"><input type="search" class="ec-search" id="ec-search" placeholder="Имя, email или номер заказа" aria-label="Поиск поступлений"><select id="ec-store-filter" aria-label="Источник поступления"><option value="all">Все источники</option><option value="web">СБП</option><option value="appstore">App Store</option><option value="googleplay">Google Play</option><option value="rustore">RuStore</option><option value="other">Другие</option></select><label class="ec-check"><input type="checkbox" id="ec-show-tests">Тестовые</label></div>
 <div class="ec-table-wrap"><table class="ec-table"><thead><tr><th>Дата · МСК</th><th>Описание</th><th>Источник</th><th>Статус</th><th class="ec-money">Сумма</th><th aria-label="Действия"></th></tr></thead><tbody id="ec-receipts-body"><tr><td colspan="6" class="ec-empty">Загрузка поступлений…</td></tr></tbody></table></div>
 <div class="ec-pager"><span id="ec-page-info"></span><div class="ec-actions"><button type="button" class="btn-action" id="ec-prev" aria-label="Предыдущая страница" disabled>←</button><button type="button" class="btn-action" id="ec-next" aria-label="Следующая страница" disabled>→</button></div></div>
</section>
<details class="ec-planning"><summary>Планирование <span class="ec-caption">Окупаемость и цель на месяц</span></summary><div class="ec-plan-grid">
 <div class="ec-plan-block"><div class="ec-plan-title">Постоянные расходы в месяц</div><div class="ec-plan-amount" id="ec-monthly-cost">—</div><div class="ec-caption">Без разовых расходов и ИИ</div><div class="ec-progress"><i id="ec-coverage-bar" style="width:0"></i></div><div class="ec-caption" id="ec-coverage">—</div><div class="ec-plan-numbers"><span class="ec-caption">По 99 ₽<strong id="ec-be-week">—</strong></span><span class="ec-caption">По 290 ₽<strong id="ec-be-quarter">—</strong></span></div></div>
 <div class="ec-plan-block"><div class="ec-plan-title">Цель к распределению</div><div class="ec-plan-controls"><label>Прибыль, ₽ / мес<input type="number" id="ec-plan-target" min="0" max="100000000" step="1000" value="50000"></label><label>Среднее поступление, ₽<input type="number" id="ec-plan-average" min="1" max="1000000" step="1" value="190"></label></div><div class="ec-plan-numbers"><span class="ec-caption">Поступления<strong id="ec-plan-revenue">—</strong></span><span class="ec-caption">Продажи в месяц<strong id="ec-plan-sales">—</strong></span></div><div class="ec-caption" id="ec-plan-split" style="margin-top:14px"></div></div>
</div></details>
<dialog id="ec-dialog" aria-labelledby="ec-dialog-title"><form id="ec-form"><h2 id="ec-dialog-title"></h2><div class="ec-form-grid" id="ec-fields"></div><p class="ec-form-note" id="ec-form-note" hidden></p><div class="ec-form-error" id="ec-form-error" role="alert" hidden></div><div class="ec-form-actions"><button type="button" class="btn-action btn-danger" id="ec-delete" hidden>Удалить</button><button type="button" class="btn-action" id="ec-cancel">Отмена</button><button type="submit" class="btn-action btn-primary" id="ec-submit">Сохранить</button></div></form></dialog>
</div>`;

export const ECONOMY_CLIENT_JS = String.raw`
(function() {
 'use strict';
 var stats = null, period = 'month', expenseFilter = 'all', receiptMode = 'actual', page = 0;
 var requestId = 0, loading = null, dialogContext = null, saving = false, returnFocus = null;
 var stores = {web:'СБП',appstore:'App Store',googleplay:'Google Play',rustore:'RuStore',other:'Другое'};
 var frequencies = {once:'Разовый',monthly:'Ежемесячно',yearly:'Ежегодно'};
 var editIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m16 3 5 5-12 12-6 1 1-6Z M14 5l5 5"/></svg>';
 var deleteIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/></svg>';
 function el(id) { return document.getElementById(id); }
 function esc(value) { return String(value == null ? '' : value).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];}); }
 function num(n, decimals) { return Number(n || 0).toLocaleString('ru-RU',{maximumFractionDigits:decimals == null ? 2 : decimals}); }
 function rub(n) { return num(n) + ' ₽'; }
 function pct(n) { return num(n) + '%'; }
 function set(id,value) { var node=el(id); if(node) node.textContent=value; }
 function today() { return new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Moscow'}).format(new Date()); }
 function dateText(value, year) { var d=new Date(value); return Number.isFinite(d.getTime()) ? d.toLocaleDateString('ru-RU',{timeZone:'Europe/Moscow',day:'numeric',month:'short',year:year?'numeric':undefined}) : '—'; }
 function field(name) { return el('ec-form').elements.namedItem(name); }
 function feedback(message,error) { var node=el('ec-feedback'); node.hidden=false; node.classList.toggle('error',!!error); node.querySelector('span').textContent=message; }
 function activate(container,attribute,value) { el(container).querySelectorAll('button').forEach(function(button){var active=button.getAttribute(attribute)===value;button.classList.toggle('active',active);button.setAttribute('aria-pressed',String(active));}); }
 function enableActions() { ['ec-settings','ec-edit-shares','ec-add-expense','ec-add-revenue'].forEach(function(id){el(id).disabled=!stats||saving;}); }

 async function loadEconomy(force) {
  if (loading && force !== true) return loading;
  var id=++requestId, selectedPeriod=period;
  el('ec-data-state').className='admin-data-state loading';set('ec-data-state','Загрузка…');
  el('economy-view').setAttribute('aria-busy','true');
  var task=(async function(){
   try {
    var response=await fetch('/api/admin/economy/stats?period='+selectedPeriod);
    if(response.status===401){if(typeof checkAuthAndLoad==='function')checkAuthAndLoad();throw new Error('Войдите в админку заново');}
    var data=await response.json();if(!response.ok || !data.ok)throw new Error(data.error||'Не удалось загрузить данные');
    if(id!==requestId)return;
    var first=!stats;stats=data;
    if(first)el('ec-plan-target').value=data.config.targetMonthlyProfit ?? 50000;
    render();enableActions();
    el('ec-data-state').className='admin-data-state ready';set('ec-data-state','Обновлено '+new Date().toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}));
    return true;
   } catch(error) {
    if(id!==requestId)return;
    el('ec-data-state').className='admin-data-state error';set('ec-data-state','Ошибка загрузки');
    feedback(error.message+(stats?' · показаны предыдущие данные':''),true);
    if(!stats){el('ec-expenses-body').innerHTML='<tr><td colspan="4" class="ec-empty">Не удалось загрузить расходы</td></tr>';el('ec-receipts-body').innerHTML='<tr><td colspan="6" class="ec-empty">Нажмите «Обновить», чтобы повторить</td></tr>';}
    return false;
   } finally {if(id===requestId){el('economy-view').setAttribute('aria-busy','false');loading=null;}}
  })();loading=task;return task;
 }
 function render() {
  var rev=stats.revenue,exp=stats.expenses,profit=stats.profit,cfg=stats.config;
  set('ec-gross-val',rub(rev.grossRub));set('ec-costs-val',rub(exp.totalRub));set('ec-reinvest-val',rub(profit.reinvestRub));set('ec-net-val',rub(profit.distributableNetRub));
  var byStore={web:rev.webRub,appstore:rev.appstoreRub,googleplay:rev.gplayRub,rustore:rev.rustoreRub,other:rev.otherRub};
  set('ec-gross-sub',Object.keys(stores).filter(function(key){return key==='web'||Number(byStore[key])>0;}).map(function(key){return stores[key]+' '+rub(byStore[key]);}).join(' · ')+(rev.includedStoreSalesRub>0?' · магазины по тарифу':''));
  set('ec-costs-sub','Разовые '+rub(exp.oneOffRub)+' · постоянные '+rub(exp.recurringRub)+(exp.ai?.includedInTotal?' · ИИ '+rub(exp.ai.periodRub):''));
  set('ec-reinvest-sub',pct(cfg.reinvestPercent)+' от прибыли после расходов');
  var loss=profit.distributableNetRub<0;el('ec-net-card').classList.toggle('is-loss',loss);set('ec-net-label',loss?'Убыток':'К распределению');set('ec-net-sub',loss?'Выплаты — 0 ₽':'Сергей и Никита');
  ['sergey','nikita'].forEach(function(key,index){var p=stats.partners[key],suffix=index?'n':'s';set('ec-share-'+suffix,pct(p.percent));set('ec-payout-'+suffix,rub(p.payoutRub));el('ec-bar-'+suffix).style.width=p.percent+'%';});
  set('ec-fund-pct','· '+pct(cfg.reinvestPercent));set('ec-fund-total',rub(profit.reinvestRub));
  set('ec-recurring-total',rub(exp.recurringRub));set('ec-once-total',rub(exp.oneOffRub));
  el('ec-ai-note').hidden=!exp.ai;set('ec-ai-total',exp.ai?.available?rub(exp.ai.rub):'—');set('ec-ai-scope',!exp.ai?.available?'Нет данных':exp.ai.includedInTotal?'В расходах':'Вне итога');
  var range=stats.periodInfo || {};
  var start=range.from, end=range.to;
  set('ec-period-note',(start?dateText(start,true)+' — '+dateText(end,true):({month:'Текущий месяц', '30d':'Последние 30 дней',all:'За всё время'})[period])+' · инфраструктура по бюджету');
  renderExpenses();renderReceipts();updatePlanner();
 }
 function editButton(kind,id,title) { return '<button type="button" class="ec-edit" data-'+kind+'-id="'+esc(id)+'" aria-label="'+esc(title)+'" title="'+esc(title)+'">'+editIcon+'</button>'; }
 function renderExpenses() {
  if(!stats)return;
  var lines=(stats.expenses.lines||[]).filter(function(line){return expenseFilter==='all'||(expenseFilter==='once'?line.frequency==='once':line.frequency!=='once');});
  el('ec-expenses-body').innerHTML=lines.length?lines.map(function(line){
   var builtin=!!line.builtin || line.source==='builtin',amount=Number(line.amount ?? line.amountRub ?? 0),currency=line.currency||'RUB';
   var frequency=line.frequency||(line.monthly?'monthly':'once');
   var rate=(currency==='USD'?'$'+num(amount):rub(amount));
   var meta=builtin?'Бюджет':frequency==='once'?dateText(line.date||line.createdAt,true):'С '+dateText(line.date||line.createdAt,true)+(line.endDate?' · до '+dateText(line.endDate,true):'');
   var count=Number(line.occurrences)||0;
   return '<tr><td class="ec-name"><strong>'+esc(line.title)+'</strong><span class="ec-sub">'+esc(meta)+'</span></td><td><span class="ec-pill '+(frequency==='once'?'':'blue')+'">'+esc(frequencies[frequency]||'По расходу')+'</span><span class="ec-sub">'+rate+(frequency==='monthly'?' / мес':frequency==='yearly'?' / год':'')+'</span></td><td class="ec-money">'+rub(line.periodRub)+'<span class="ec-sub">'+(builtin?'По дням периода':count===0?'Вне периода':count>1?count+' платежа':'')+'</span></td><td class="ec-cell-action"><div class="ec-row-actions">'+(builtin?'<button type="button" class="ec-edit" data-builtin="true" aria-label="Изменить бюджет '+esc(line.title)+'" title="Изменить">'+editIcon+'</button>':editButton('expense',line.id,'Редактировать '+line.title))+'<button type="button" class="ec-edit ec-remove" data-delete-expense-id="'+esc(line.id)+'" aria-label="Удалить расход '+esc(line.title)+'" title="Удалить">'+deleteIcon+'</button></div></td></tr>';
  }).join(''):'<tr><td colspan="4" class="ec-empty">'+(expenseFilter==='once'?'Разовых расходов пока нет':'Расходов пока нет')+'</td></tr>';
 }
 function renderReceipts() {
  if(!stats)return;
  var q=el('ec-search').value.trim().toLowerCase(),store=el('ec-store-filter').value,showTests=el('ec-show-tests').checked;
  var rows=(receiptMode==='actual'?stats.receipts:stats.estimatedReceipts)||[];
  rows=rows.filter(function(row){return (showTests||!row.isTest)&&(store==='all'||row.storeKey===store)&&(!q||[row.customer,row.title,row.email,row.txId,row.id,row.store].join(' ').toLowerCase().includes(q));});
  var pageSize=12,pages=Math.max(1,Math.ceil(rows.length/pageSize));page=Math.min(page,pages-1);
  set('ec-receipts-count',num(rows.length));set('ec-ledger-note',receiptMode==='actual'?'Все источники · покупки магазинов по тарифу':'По тарифу · выплата заменяет оценку своего магазина за период');
  el('ec-show-tests').closest('label').hidden=false;
  el('ec-receipts-body').innerHTML=rows.length?rows.slice(page*pageSize,(page+1)*pageSize).map(function(row){
   var manual=(stats.config.manualRevenues||[]).some(function(r){return r.id===row.id;});
   var status=row.isTest?'<span class="ec-pill amber">'+(row.includedInRevenue?'Тест · в доходе':'Тест · вне дохода')+'</span>':row.type==='estimate'?'<span class="ec-pill">'+(row.replacedByPayout?'Учтено выплатой':'По тарифу · в доходе')+'</span>':'<span class="ec-pill green">Получено</span>';
   var title=row.customer||row.title||'Поступление';
   return '<tr><td style="white-space:nowrap">'+esc(dateText(row.date,true))+'</td><td class="ec-name"><strong>'+esc(title)+'</strong>'+(row.email?'<span class="ec-sub">'+esc(row.email)+'</span>':'')+'<span class="ec-sub">'+esc(row.tier||'')+'</span>'+(row.txId?'<button type="button" class="ec-receipt-id" data-copy="'+esc(row.txId)+'" title="Скопировать '+esc(row.txId)+'" aria-label="Скопировать номер заказа">'+esc(row.txId)+'</button>':'')+'</td><td><span class="ec-pill '+(row.storeKey==='web'?'blue':'')+'">'+esc(stores[row.storeKey]||row.store||'Другое')+'</span></td><td>'+status+'</td><td class="ec-money">'+rub(row.amountRub)+'</td><td class="ec-cell-action">'+(manual?editButton('revenue',row.id,'Редактировать '+title):'')+'</td></tr>';
  }).join(''):'<tr><td colspan="6" class="ec-empty">'+(q||store!=='all'?'Ничего не найдено':receiptMode==='actual'?'Поступлений за этот период пока нет':'Покупок за этот период пока нет')+'</td></tr>';
  set('ec-page-info',rows.length?(page*pageSize+1)+'–'+Math.min((page+1)*pageSize,rows.length)+' из '+rows.length:'');el('ec-prev').disabled=page===0;el('ec-next').disabled=page>=pages-1;
 }
 function updatePlanner() {
  if(!stats)return;
  var monthly=Number(stats.expenses.monthlyRub)||0,target=Math.max(0,Number(el('ec-plan-target').value)||0),average=Math.max(1,Number(el('ec-plan-average').value)||1),factor=1-stats.config.reinvestPercent/100;
  var possible=factor>0 || target===0,required=possible?monthly+(target===0?0:target/factor):0;
  set('ec-monthly-cost',rub(monthly));set('ec-be-week',num(Math.ceil(monthly/99))+' продаж');set('ec-be-quarter',num(Math.ceil(monthly/290))+' продаж');
  var coverage=stats.expenses.totalRub>0?Math.max(0,Math.round(stats.revenue.grossRub/stats.expenses.totalRub*100)):100;el('ec-coverage-bar').style.width=Math.min(100,coverage)+'%';set('ec-coverage','Покрытие расходов периода · '+num(coverage)+'%');
  set('ec-plan-revenue',possible?rub(Math.ceil(required)):'—');set('ec-plan-sales',possible?num(Math.ceil(required/average)):'—');
  set('ec-plan-split',possible?'Сергей '+rub(target*stats.partners.sergey.percent/100)+' · Никита '+rub(target*stats.partners.nikita.percent/100):'При фонде развития 100% прибыль не распределяется');
 }
 function input(name,label,value,options) { options=options||{};return '<label class="ec-field '+(options.full?'full':'')+'">'+esc(label)+'<input name="'+name+'" type="'+(options.type||'number')+'" value="'+esc(value)+'" '+(options.required===false?'':'required')+' '+(options.type==='text'?'maxlength="120"':options.type==='date'?'':'min="'+(options.min??0)+'" max="'+(options.max??100000000)+'" step="'+(options.step||'0.01')+'"')+'></label>'; }
 function select(name,label,value,choices,full) {return '<label class="ec-field '+(full?'full':'')+'">'+esc(label)+'<select name="'+name+'">'+Object.keys(choices).map(function(key){return '<option value="'+esc(key)+'" '+(key===value?'selected':'')+'>'+esc(choices[key])+'</option>';}).join('')+'</select></label>';}
 function showForm(kind,item) {
  if(!stats||saving)return;item=item||{};returnFocus=document.activeElement;dialogContext={kind:kind,id:item.id||null,confirmDelete:false};
  var html='',title='',cfg=stats.config,note='';
  if(kind==='expense') {
   title=item.id?'Редактировать расход':'Новый расход';
   html=input('title','Название',item.title||'',{type:'text',full:true})+input('amount','Сумма',item.amount??item.amountRub??'',{min:0.01})+select('currency','Валюта',item.currency||'RUB',{RUB:'Рубли · ₽',USD:'Доллары · $'})+select('frequency','Повторение',item.frequency||(item.monthly?'monthly':'once'),frequencies,true)+input('date','Дата платежа',(item.date||item.createdAt||today()).slice(0,10),{type:'date'})+input('endDate','Дата окончания',item.endDate?item.endDate.slice(0,10):'',{type:'date',required:false})+'<div class="ec-form-preview" id="ec-form-preview"></div>';
  } else if(kind==='shares') {
   title='Распределение прибыли';html=input('sergeySharePercent','Сергей, %',cfg.sergeySharePercent,{max:100})+input('nikitaSharePercent','Никита, %',cfg.nikitaSharePercent,{max:100})+input('reinvestPercent','Фонд развития, %',cfg.reinvestPercent,{max:100,full:true})+'<div class="ec-form-preview" id="ec-form-preview"></div>';note='Доли применяются ко всем периодам расчёта.';
  } else if(kind==='settings') {
   title='Параметры экономики';html=input('usdRate','Курс доллара, ₽',cfg.usdRate,{min:0.01,full:true})+input('cloudflareMonthlyUsd','Cloudflare, $ / мес',cfg.cloudflareMonthlyUsd)+input('domainMonthlyRub','Домен, ₽ / мес',cfg.domainMonthlyRub)+'<label class="ec-form-check"><input type="checkbox" name="cloudflareEnabled" '+(cfg.cloudflareEnabled!==false?'checked':'')+'>Учитывать бюджет Cloudflare</label><label class="ec-form-check"><input type="checkbox" name="domainEnabled" '+(cfg.domainEnabled!==false?'checked':'')+'>Учитывать бюджет домена</label><label class="ec-form-check"><input type="checkbox" name="excludeTestOrders" '+(cfg.excludeTestOrders?'checked':'')+'>Не учитывать тестовые оплаты в доходе</label>';note='Для точных списаний отключите бюджет и добавьте расходы с датой.';
  } else if(kind==='delete-expense') {
   title='Удалить расход?';html='<div class="ec-delete-summary"><strong>'+esc(item.title)+'</strong><span>'+rub(item.periodRub)+' в выбранном периоде</span></div>';note=item.builtin?'Можно вернуть в параметрах экономики.':'Расход будет исключён из расчётов за все периоды.';
  } else {
   title=item.id?'Редактировать поступление':'Новое поступление';html=input('title','Описание',item.title||'',{type:'text',full:true})+input('amountRub','Получено, ₽',item.amountRub??'',{min:0.01})+input('date','Дата получения',(item.date||today()).slice(0,10),{type:'date'})+select('store','Источник',item.store||'appstore',{appstore:'App Store',googleplay:'Google Play',rustore:'RuStore',other:'Другое'},true);note='Выплата магазина за выбранный период заменяет оценку его продаж в доходе. Другие поступления прибавляются отдельно.';
  }
  set('ec-dialog-title',title);el('ec-fields').innerHTML=html;el('ec-form-error').hidden=true;el('ec-form-note').hidden=!note;set('ec-form-note',note);el('ec-delete').hidden=!item.id||kind==='delete-expense';set('ec-delete','Удалить');set('ec-submit',kind==='delete-expense'?'Удалить':item.id||kind==='shares'||kind==='settings'?'Сохранить':'Добавить');el('ec-submit').classList.toggle('btn-danger',kind==='delete-expense');el('ec-submit').classList.toggle('btn-primary',kind!=='delete-expense');el('ec-dialog').showModal();updateFormPreview();
 }
 function updateFormPreview(changed) {
  if(!dialogContext)return;
  if(dialogContext.kind==='shares') {
   if(changed==='sergeySharePercent'||changed==='nikitaSharePercent'){var other=changed==='sergeySharePercent'?'nikitaSharePercent':'sergeySharePercent';var value=Number(field(changed).value);if(field(changed).value!==''&&Number.isFinite(value)&&value>=0&&value<=100)field(other).value=Number((100-value).toFixed(2));}
   el('ec-form-preview').innerHTML='В развитие <b>'+pct(field('reinvestPercent').value)+'</b> · доли <b>'+pct(Number(field('sergeySharePercent').value)+Number(field('nikitaSharePercent').value))+'</b>';
  }
  if(dialogContext.kind==='expense') {
   var frequency=field('frequency').value,isOnce=frequency==='once',amount=Number(field('amount').value)||0,rubles=amount*(field('currency').value==='USD'?stats.config.usdRate:1);field('endDate').disabled=isOnce;field('endDate').closest('label').hidden=isOnce;field('date').closest('label').firstChild.textContent=isOnce?'Дата платежа':'Первый платёж';field('endDate').min=field('date').value;
   el('ec-form-preview').innerHTML=isOnce?'Разовый расход · <b>'+rub(rubles)+'</b>':'Бюджет в месяц · <b>'+rub(frequency==='yearly'?rubles/12:rubles)+'</b>';
  }
 }
 function closeForm() {if(saving)return;el('ec-dialog').close();dialogContext=null;if(returnFocus?.isConnected)returnFocus.focus();}
 async function mutate(path,body) {
  var response=await fetch('/api/admin/economy/'+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  var data;try{data=await response.json();}catch(_){throw new Error('Не удалось получить ответ сервера');}
  if(!response.ok||!data.ok)throw new Error(data.error||'Не удалось сохранить');return data;
 }
 async function submitForm(event,deleting) {
  if(event)event.preventDefault();if(saving||!dialogContext)return;
  var context=dialogContext,body={},path='',kind=context.kind;
  deleting=deleting===true||kind==='delete-expense';
  if(deleting){path=(kind==='expense'||kind==='delete-expense'?'expenses':'revenues')+'/delete';body.id=context.id;}
  else {
   if(!el('ec-form').reportValidity())return;
   if(kind==='expense'){body={title:field('title').value.trim(),amount:Number(field('amount').value),currency:field('currency').value,frequency:field('frequency').value,date:field('date').value,endDate:field('frequency').value==='once'?null:field('endDate').value||null};path='expenses/'+(context.id?'update':'add');}
   else if(kind==='revenue'){body={title:field('title').value.trim(),amountRub:Number(field('amountRub').value),store:field('store').value,date:field('date').value};path='revenues/'+(context.id?'update':'add');}
   else if(kind==='shares'){body={nikitaSharePercent:Number(field('nikitaSharePercent').value),reinvestPercent:Number(field('reinvestPercent').value)};if(Math.abs(Number(field('sergeySharePercent').value)+body.nikitaSharePercent-100)>.001){formError('Сумма долей должна быть 100%');return;}path='settings';}
   else{body={usdRate:Number(field('usdRate').value),cloudflareMonthlyUsd:Number(field('cloudflareMonthlyUsd').value),domainMonthlyRub:Number(field('domainMonthlyRub').value),cloudflareEnabled:field('cloudflareEnabled').checked,domainEnabled:field('domainEnabled').checked,excludeTestOrders:field('excludeTestOrders').checked};path='settings';}
   if(context.id)body.id=context.id;
  }
  saving=true;enableActions();el('ec-form-error').hidden=true;var submitLabel=el('ec-submit').textContent;el('ec-form').querySelectorAll('button').forEach(function(button){button.disabled=true;});set('ec-submit',deleting?'Удаление…':'Сохранение…');
  try{await mutate(path,body);saving=false;closeForm();saving=true;feedback(deleting?(kind==='revenue'?'Поступление удалено':'Расход удалён'):'Сохранено');await loadEconomy(true);}
  catch(error){formError(error.message);}
  finally{saving=false;enableActions();el('ec-form').querySelectorAll('button').forEach(function(button){button.disabled=false;});set('ec-submit',submitLabel);if(deleting&&!dialogContext&&!returnFocus?.isConnected)el(kind==='revenue'?'ec-add-revenue':'ec-add-expense').focus();}
 }
 function formError(message){el('ec-form-error').hidden=false;set('ec-form-error',message);}
 function init() {
  if(!el('economy-view'))return;
  window.loadEconomy=loadEconomy;
  el('ec-period-tabs').addEventListener('click',function(event){var button=event.target.closest('[data-period]');if(!button)return;period=button.dataset.period;page=0;activate('ec-period-tabs','data-period',period);loadEconomy(true);});
  el('ec-refresh').addEventListener('click',function(){loadEconomy(true);});
  el('ec-expense-filter').addEventListener('click',function(event){var button=event.target.closest('[data-filter]');if(!button)return;expenseFilter=button.dataset.filter;activate('ec-expense-filter','data-filter',expenseFilter);renderExpenses();});
  el('ec-receipt-mode').addEventListener('click',function(event){var button=event.target.closest('[data-mode]');if(!button)return;receiptMode=button.dataset.mode;page=0;activate('ec-receipt-mode','data-mode',receiptMode);renderReceipts();});
  ['ec-search','ec-store-filter','ec-show-tests'].forEach(function(id){el(id).addEventListener(id==='ec-search'?'input':'change',function(){page=0;renderReceipts();});});
  el('ec-prev').onclick=function(){page--;renderReceipts();};el('ec-next').onclick=function(){page++;renderReceipts();};
  el('ec-settings').onclick=function(){showForm('settings');};el('ec-edit-shares').onclick=function(){showForm('shares');};el('ec-add-expense').onclick=function(){showForm('expense');};el('ec-add-revenue').onclick=function(){showForm('revenue');};
  el('ec-expenses-body').addEventListener('click',function(event){var button=event.target.closest('button');if(!button||!stats)return;if(button.dataset.deleteExpenseId){var line=stats.expenses.lines.find(function(expense){return expense.id===button.dataset.deleteExpenseId;});if(line)showForm('delete-expense',line);return;}if(button.hasAttribute('data-builtin'))return showForm('settings');var item=stats.config.extraExpenses.find(function(expense){return expense.id===button.dataset.expenseId;});if(item)showForm('expense',item);});
  el('ec-receipts-body').addEventListener('click',async function(event){var button=event.target.closest('button');if(!button)return;if(button.dataset.revenueId){var item=stats.config.manualRevenues.find(function(revenue){return revenue.id===button.dataset.revenueId;});if(item)showForm('revenue',item);}else if(button.dataset.copy){try{await navigator.clipboard.writeText(button.dataset.copy);feedback('Номер заказа скопирован');}catch(_){feedback('Не удалось скопировать номер заказа',true);}}});
  el('ec-feedback').querySelector('button').onclick=function(){el('ec-feedback').hidden=true;};
  ['ec-plan-target','ec-plan-average'].forEach(function(id){el(id).addEventListener('input',updatePlanner);});
  el('ec-form').addEventListener('input',function(event){updateFormPreview(event.target.name);});el('ec-form').addEventListener('change',function(event){updateFormPreview(event.target.name);});
  el('ec-form').addEventListener('submit',submitForm);el('ec-cancel').onclick=closeForm;
  el('ec-delete').onclick=function(){if(!dialogContext.confirmDelete){dialogContext.confirmDelete=true;set('ec-delete','Подтвердить удаление');return;}submitForm(null,true);};
  el('ec-dialog').addEventListener('cancel',function(event){event.preventDefault();closeForm();});
  el('ec-dialog').addEventListener('click',function(event){if(event.target===el('ec-dialog')){var rect=el('ec-dialog').getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)closeForm();}});
  if(location.hash.split('/')[0]==='#economy'||localStorage.getItem('pdd-admin-feature')==='economy')loadEconomy();
 }
 // Оболочка вызывает loadEconomy при восстановлении вкладки и переходах навигации.
 window.loadEconomy=loadEconomy;
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();`;
