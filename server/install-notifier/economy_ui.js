// Экономика: итог периода и единый журнал с отдельным учётом переводов и комиссий.
export const ECONOMY_NAV_HTML = String.raw`
<button class="nav-item" data-feature="economy"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg><span>Экономика</span></button>`;

export const ECONOMY_VIEW_HTML = String.raw`
<div id="economy-view" style="display:none">
<style>
#economy-view{color:var(--text,#17191E);--ec-muted:#747B88;--ec-line:#EDF0F3;--ec-soft:#F4F6F9;--ec-blue:#0574F8;--ec-red:#C54C35}
#economy-view [hidden]{display:none!important}#economy-view button{cursor:pointer}#economy-view button:disabled{cursor:default}
.ec-toolbar,.ec-actions,.ec-head,.ec-pager{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}.ec-actions{justify-content:flex-end;gap:8px}.ec-toolbar{margin-bottom:16px}.ec-toolbar .admin-data-state{padding:0;font-size:10.5px}.ec-period-note{font-size:11px;color:var(--ec-muted);margin:0 0 15px}.ec-seg{display:flex;gap:3px;padding:4px;background:#E9ECF1;border-radius:11px;width:fit-content;max-width:100%}
#economy-view .ec-seg button{border:0;padding:8px 12px;min-height:34px;border-radius:8px;background:transparent;color:var(--ec-muted);font-size:11.5px;font-weight:550;white-space:nowrap}#economy-view .ec-seg button.active{background:#17191E;color:white}
#economy-view .ec-card{background:#fff;border-radius:20px;padding:23px 24px;min-width:0}.ec-kpis{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin-bottom:14px}.ec-kpi-label{font-size:12px;color:var(--ec-muted);font-weight:500}.ec-value{font-size:34px;font-weight:590;letter-spacing:-1.1px;line-height:1.2;font-variant-numeric:tabular-nums;margin:14px 0 7px;overflow-wrap:anywhere}.ec-caption{font-size:11px;color:var(--ec-muted);line-height:1.5}.ec-caption:empty{display:none}
#economy-view .ec-net{background:#0574F8;color:#fff}.ec-net .ec-value,.ec-net .ec-kpi-label{color:#fff}.ec-net .ec-caption{color:#DCEBFF}#economy-view .ec-net.is-loss{background:#FCEDE8;color:var(--text,#17191E)}.ec-net.is-loss .ec-value{color:var(--ec-red)}.ec-net.is-loss .ec-kpi-label,.ec-net.is-loss .ec-caption{color:var(--ec-muted)}
.ec-allocation{display:grid;grid-template-columns:repeat(3,minmax(0,1fr)) auto;align-items:center;gap:20px;margin-bottom:24px;padding:9px 22px}.ec-allocation-item{min-width:0}.ec-allocation-item+.ec-allocation-item{padding-left:20px;border-left:1px solid #E0E5EC}.ec-allocation-label{font-size:11px;color:var(--ec-muted)}.ec-allocation-label span{margin-left:5px;color:#9098A5}.ec-allocation-amount{font-size:18px;font-weight:570;letter-spacing:-.35px;font-variant-numeric:tabular-nums;white-space:nowrap;margin-top:3px}.ec-head{margin-bottom:18px;min-height:34px}.ec-head h2{font-size:15px;letter-spacing:-.3px;font-weight:600;margin:0}.ec-head-title{display:flex;align-items:center;gap:8px}.ec-head-title .ec-caption{font-variant-numeric:tabular-nums}
.ec-ledger-tabs{display:flex;gap:20px;border-bottom:1px solid var(--ec-line);margin-bottom:17px;overflow-x:auto;scrollbar-width:none}.ec-ledger-tabs::-webkit-scrollbar{display:none}#economy-view .ec-ledger-tabs button{border:0;border-bottom:2px solid transparent;background:none;color:var(--ec-muted);font-size:12px;font-weight:500;padding:0 0 12px;white-space:nowrap;min-height:34px}#economy-view .ec-ledger-tabs button.active{color:#17191E;border-bottom-color:#17191E;font-weight:600}
.ec-ledger-tools{display:flex;gap:10px;align-items:center;margin-bottom:18px}.ec-search{width:100%;min-width:0;flex:1;padding:9px 12px}.ec-ledger-tools select{padding:9px 11px;max-width:160px}.ec-check{display:flex;align-items:center;gap:6px;font-size:11px;color:var(--ec-muted);white-space:nowrap}.ec-check input{margin:0}
.ec-table-wrap{max-width:100%;overflow:auto}.ec-table{border-collapse:collapse;width:100%;font-size:12px;line-height:1.5}#economy-view .ec-table th{font-size:10px;color:#89919F;font-weight:500;letter-spacing:.3px;text-align:left;padding:0 12px 11px 0;white-space:nowrap}#economy-view .ec-table td{border-top:1px solid var(--ec-line);padding:14px 12px 14px 0;vertical-align:middle;font-weight:450}#economy-view .ec-table th:last-child,#economy-view .ec-table td:last-child{padding-right:0}.ec-table .ec-money{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums;font-weight:550}.ec-table .ec-date{font-size:11px;color:var(--ec-muted);white-space:nowrap;width:100px}.ec-table .ec-cell-action{width:32px;text-align:right}.ec-name{min-width:120px;max-width:420px;overflow-wrap:anywhere}.ec-sub{display:block;color:var(--ec-muted);font-size:10.5px;font-weight:400;margin-top:3px}.ec-kind{font-size:11px;color:var(--ec-muted);white-space:nowrap}.ec-money.income{color:#16865F}.ec-money.commission,.ec-money.expense{color:#444C59}
#economy-view .ec-row-title{border:0;background:none;padding:0;color:inherit;font-size:12px;font-weight:550;text-align:left;line-height:1.5;max-width:100%;overflow-wrap:anywhere}#economy-view .ec-row-title:hover{color:var(--ec-blue)}.ec-badge{display:inline-block;font-size:10px;color:#8791A0;font-weight:400;margin-left:6px}.ec-badge.test{color:#A66A12}#economy-view .ec-edit{display:inline-flex;align-items:center;justify-content:center;border:0;background:#F3F5F8;color:#717D90;width:32px;height:32px;border-radius:9px;padding:7px;flex-shrink:0}#economy-view .ec-edit:hover{background:#E8F1FF;color:var(--ec-blue)}.ec-edit svg{width:14px;height:14px}.ec-empty{text-align:center;padding:36px 12px!important;color:var(--ec-muted);font-size:12px}.ec-pager{margin-top:15px;font-size:11px;color:var(--ec-muted)}.ec-pager .ec-actions{gap:6px}
/* Operation identity: the same symbol and colour remain visible on mobile. */
#ec-receipts-body tr{--ec-operation:#137A54;--ec-operation-bg:#E8F5EE}
#ec-receipts-body tr[data-row-kind="expense"]{--ec-operation:#B44337;--ec-operation-bg:#FCEEEA}
#ec-receipts-body tr[data-row-kind="withdrawal"]{--ec-operation:#1D60B4;--ec-operation-bg:#EAF2FF}
#ec-receipts-body tr[data-row-kind="commission"]{--ec-operation:#94620B;--ec-operation-bg:#FFF3DC}
.ec-operation{display:flex;align-items:center;gap:12px;min-width:0}.ec-operation-text{min-width:0;flex:1}.ec-operation-icon{display:inline-flex;align-items:center;justify-content:center;flex:0 0 36px;width:36px;height:36px;border-radius:11px;background:var(--ec-operation-bg);color:var(--ec-operation)}.ec-operation-icon svg{width:19px;height:19px}
#ec-receipts-body .ec-row-title{font-size:13px;font-weight:650}#ec-receipts-body .ec-sub{font-size:11px;margin-top:4px}
.ec-type-badge{display:inline-flex;align-items:center;white-space:nowrap;padding:5px 9px;border-radius:7px;background:var(--ec-operation-bg);color:var(--ec-operation);font-size:11px;font-weight:600;line-height:1.35}
#economy-view #ec-receipts-body .ec-money{font-size:14px;font-weight:650;color:var(--ec-operation)}#ec-receipts-body .ec-money .ec-sub{font-size:10.5px;font-weight:450}
#ec-receipts-body tr:hover{background:#FAFBFD}#ec-receipts-body .ec-row-title:focus-visible{outline:2px solid var(--ec-blue);outline-offset:4px;border-radius:3px}
.ec-disclosure{background:#fff;border-radius:18px;margin-top:14px}.ec-disclosure>summary{display:flex;align-items:center;gap:12px;list-style:none;cursor:pointer;padding:18px 24px;font-size:12px;font-weight:550}.ec-disclosure>summary::-webkit-details-marker{display:none}.ec-disclosure>summary:after{content:'+';margin-left:auto;color:#89919F;font-size:18px;font-weight:400}.ec-disclosure[open]>summary:after{content:'−'}.ec-disclosure-body{padding:0 24px 22px}.ec-register-tools{display:flex;justify-content:space-between;gap:12px;align-items:center;margin:0 0 14px}.ec-register-tools select{padding:8px 12px}.ec-register-note{font-size:11px;color:var(--ec-muted);margin-top:13px}.ec-planner-grid{display:grid;grid-template-columns:1fr 1fr;gap:24px}.ec-planner-grid>div+div{border-left:1px solid var(--ec-line);padding-left:24px}.ec-plan-title{font-size:12px;font-weight:550;margin-bottom:10px}.ec-plan-amount{font-size:25px;font-weight:580;letter-spacing:-.7px;margin-bottom:8px}.ec-plan-controls{display:grid;grid-template-columns:1fr 1fr;gap:12px}.ec-plan-numbers{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-top:16px}.ec-plan-numbers strong{display:block;font-size:18px;font-weight:570;margin-top:4px;color:#343B49}.ec-plan-controls label{font-size:11px;color:var(--ec-muted);display:flex;flex-direction:column;gap:6px}.ec-plan-controls input{padding:9px 12px;box-sizing:border-box;width:100%}
.ec-platega-balances{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px}.ec-platega-balance{padding:14px 16px;background:var(--ec-soft);border-radius:12px}.ec-platega-balance strong{display:block;font-size:21px;font-weight:570;letter-spacing:-.4px;margin:4px 0;font-variant-numeric:tabular-nums}.ec-platega-status{font-size:11px;color:var(--ec-muted);min-width:0}.ec-platega-status.error{color:var(--ec-red)}.ec-feedback{display:flex;align-items:center;justify-content:space-between;gap:12px;background:#E9F6EF;color:#16774F;font-size:12px;padding:12px 16px;margin-bottom:15px;border-radius:12px}.ec-feedback.error{background:#FCEDE8;color:#B1432D}.ec-feedback button{border:0;background:none;color:inherit;font-size:18px;padding:0;line-height:1}
#ec-dialog{margin:auto;padding:0;border:0;border-radius:22px;width:min(460px,calc(100% - 32px));max-height:calc(100svh - 32px);overflow:auto;color:#17191E;background:#fff;box-shadow:0 20px 80px #17223622}#ec-dialog::backdrop{background:#17223655;backdrop-filter:blur(3px)}#ec-form{padding:26px}#ec-dialog h2{font-size:21px;font-weight:600;letter-spacing:-.6px;margin:0 0 21px}.ec-form-grid{display:grid;grid-template-columns:1fr 1fr;gap:15px}.ec-field{display:flex;flex-direction:column;gap:7px;font-size:11px;font-weight:500;color:#6D7583;min-width:0}.ec-field.full{grid-column:1/-1}.ec-field input,.ec-field select{width:100%;box-sizing:border-box;padding:11px 12px;font-weight:450}.ec-form-check{display:flex;align-items:center;gap:8px;grid-column:1/-1;font-size:12px;color:#555E6E}.ec-form-preview{grid-column:1/-1;background:var(--ec-soft);border-radius:11px;padding:13px;font-size:12px;color:var(--ec-muted);line-height:1.65}.ec-preview-line{display:flex;align-items:center;justify-content:space-between;gap:10px}.ec-form-preview b{font-weight:600;color:#343B49;font-variant-numeric:tabular-nums}.ec-form-actions{display:flex;align-items:center;justify-content:flex-end;gap:8px;flex-wrap:wrap;margin-top:23px}.ec-form-actions #ec-delete{margin-right:auto}.ec-form-error{font-size:12px;color:#B1432D;background:#FCEDE8;padding:11px 12px;border-radius:10px;margin-top:16px}.ec-form-note{font-size:11px;color:var(--ec-muted);margin:13px 0 0;line-height:1.5}.ec-settings-extra{grid-column:1/-1;border-top:1px solid var(--ec-line);padding-top:12px}.ec-settings-extra summary{cursor:pointer;font-size:12px;font-weight:500;color:#555E6E}.ec-settings-extra .ec-form-grid{margin-top:16px}.ec-detail-list{grid-column:1/-1;margin:0;display:grid;grid-template-columns:1fr auto;gap:12px 18px;font-size:12px}.ec-detail-list dt{color:var(--ec-muted)}.ec-detail-list dd{margin:0;text-align:right;overflow-wrap:anywhere;min-width:0;max-width:240px}.ec-detail-list .ec-wide{grid-column:1/-1;text-align:left}.ec-detail-copy{font:inherit;background:var(--ec-soft);border:0;padding:8px 10px;border-radius:8px;max-width:100%;overflow-wrap:anywhere;color:#576476;text-align:left}
@media(max-width:1150px){.ec-value{font-size:29px}.ec-allocation{gap:14px;padding:8px 17px}.ec-allocation-item+.ec-allocation-item{padding-left:14px}.ec-allocation-amount{font-size:17px}}
@media(max-width:900px){.ec-toolbar .admin-data-state{display:none}.ec-value{font-size:26px}.ec-allocation{grid-template-columns:repeat(3,minmax(0,1fr));position:relative;padding-right:8px;padding-bottom:42px}.ec-allocation>#ec-edit-shares{position:absolute;bottom:0;right:0}.ec-planner-grid{grid-template-columns:1fr}.ec-planner-grid>div+div{border-left:0;border-top:1px solid var(--ec-line);padding:20px 0 0}}
@media(max-width:600px){.ec-toolbar{gap:12px}.ec-toolbar>.ec-actions{width:100%;justify-content:flex-end}.ec-toolbar .ec-seg{width:100%}.ec-toolbar .ec-seg button{flex:1}.ec-toolbar #ec-add-operation{margin-left:auto}.ec-kpis{grid-template-columns:1fr 1fr;gap:10px}#economy-view .ec-card{padding:18px}.ec-kpis>.ec-net{grid-column:1/-1;display:grid;grid-template-columns:1fr auto;align-items:center;gap:3px 10px}.ec-net .ec-value{grid-column:2;grid-row:1/3;margin:0}.ec-net .ec-caption{grid-column:1}.ec-value{font-size:27px;margin:12px 0 7px}.ec-kpi-label{font-size:11px}.ec-allocation{gap:9px;padding-left:5px;margin-bottom:18px}.ec-allocation-item+.ec-allocation-item{padding-left:10px}.ec-allocation-amount{font-size:16px}.ec-allocation-label{font-size:10px}.ec-allocation-label span{display:block;margin:0}.ec-ledger-tabs{gap:18px}.ec-ledger-tabs button{font-size:11px!important}.ec-ledger-tools{flex-wrap:wrap;gap:9px}.ec-search{flex-basis:100%}.ec-ledger-tools select{flex:1;max-width:none}.ec-ledger-tools .ec-check{padding:8px 0 8px 6px}.ec-disclosure>summary{padding:18px}.ec-disclosure-body{padding:0 18px 20px}
 #economy-view .ec-table,#economy-view .ec-table tbody{display:block}#economy-view .ec-table thead{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}#economy-view .ec-table tr{display:grid;grid-template-columns:minmax(0,1fr) auto 28px;gap:5px 9px;padding:14px 0;border-top:1px solid var(--ec-line);align-items:center}#economy-view .ec-table td{border:0;padding:0;min-width:0}#economy-view .ec-table .ec-name{min-width:0;max-width:none;grid-column:1;grid-row:1}#economy-view .ec-table .ec-date{grid-column:1;grid-row:2;font-size:10.5px;width:auto}#economy-view .ec-table .ec-kind{grid-column:1;grid-row:3;font-size:10px}#economy-view .ec-table .ec-money{grid-column:2;grid-row:1/3;white-space:normal;overflow-wrap:anywhere;max-width:112px;font-size:12px}#economy-view .ec-table .ec-cell-action{grid-column:3;grid-row:1/3;width:auto}#economy-view .ec-table .ec-empty{grid-column:1/-1}.ec-table .ec-edit{width:28px!important;height:30px!important}#ec-form{padding:22px}.ec-detail-list dd{max-width:180px}}
@media(max-width:600px){.ec-operation{gap:8px;align-items:flex-start}.ec-operation-icon{flex-basis:28px;width:28px;height:28px;border-radius:9px;margin-top:1px}.ec-operation-icon svg{width:17px;height:17px}#ec-receipts-body .ec-row-title{font-size:12px}#ec-receipts-body .ec-sub{font-size:10px}#economy-view #ec-receipts-body .ec-date,#economy-view #ec-receipts-body .ec-kind{padding-left:36px}#economy-view #ec-receipts-body .ec-money{font-size:13px}.ec-type-badge{font-size:10px;padding:3px 7px}}
@media(max-width:370px){.ec-allocation-amount{font-size:14px}.ec-value{font-size:24px}.ec-form-grid{gap:14px 10px}.ec-ledger-tabs{gap:14px}}
</style>
<div class="ec-toolbar">
 <div class="ec-seg" id="ec-period-tabs" aria-label="Период"><button type="button" data-period="month" class="active" aria-pressed="true">Этот месяц</button><button type="button" data-period="30d" aria-pressed="false">30 дней</button><button type="button" data-period="all" aria-pressed="false">Всё время</button></div>
 <div class="ec-actions"><span class="admin-data-state loading" id="ec-data-state" role="status">Загрузка…</span><button type="button" class="btn-action" id="ec-refresh" aria-label="Обновить данные">Обновить</button><button type="button" class="btn-action" id="ec-settings" disabled>Настройки</button><button type="button" class="btn-action btn-primary" id="ec-add-operation" disabled>+ Операция</button></div>
</div>
<div id="ec-feedback" class="ec-feedback" role="status" hidden><span></span><button type="button" aria-label="Закрыть сообщение">×</button></div>
<p class="ec-period-note" id="ec-period-note">&nbsp;</p>
<div class="ec-kpis" aria-label="Итоги периода">
 <div class="ec-card"><div class="ec-kpi-label">Доход</div><div class="ec-value" id="ec-gross-val">—</div><div class="ec-caption" id="ec-gross-sub"></div></div>
 <div class="ec-card"><div class="ec-kpi-label">Расходы</div><div class="ec-value" id="ec-costs-val">—</div><div class="ec-caption" id="ec-costs-sub"></div></div>
 <div class="ec-card ec-net" id="ec-net-card"><div class="ec-kpi-label" id="ec-net-label">Прибыль</div><div class="ec-value" id="ec-net-val">—</div><div class="ec-caption" id="ec-net-sub">После расходов и комиссий</div></div>
</div>
<section class="ec-allocation" aria-label="Распределение прибыли">
 <div class="ec-allocation-item"><div class="ec-allocation-label">В развитие <span id="ec-fund-pct"></span></div><div class="ec-allocation-amount" id="ec-fund-total">—</div></div>
 <div class="ec-allocation-item"><div class="ec-allocation-label">Сергей <span id="ec-share-s"></span></div><div class="ec-allocation-amount" id="ec-payout-s">—</div></div>
 <div class="ec-allocation-item"><div class="ec-allocation-label">Никита <span id="ec-share-n"></span></div><div class="ec-allocation-amount" id="ec-payout-n">—</div></div>
 <button type="button" class="btn-action" id="ec-edit-shares" disabled>Изменить доли</button>
</section>
<section class="ec-card" aria-labelledby="ec-income-title">
 <div class="ec-head"><div class="ec-head-title"><h2 id="ec-income-title">Операции</h2><span class="ec-caption" id="ec-receipts-count"></span></div><span class="ec-caption" id="ec-withdrawn-total"></span></div>
 <div class="ec-ledger-tabs" id="ec-receipt-mode" aria-label="Вид операций"><button type="button" class="active" data-mode="all" aria-pressed="true">Все</button><button type="button" data-mode="income" aria-pressed="false">Поступления</button><button type="button" data-mode="expense" aria-pressed="false">Расходы</button><button type="button" data-mode="withdrawal" aria-pressed="false">Выводы</button><button type="button" data-mode="commission" aria-pressed="false">Комиссии</button></div>
 <div class="ec-ledger-tools"><input type="search" class="ec-search" id="ec-search" placeholder="Поиск операций" aria-label="Поиск операций"><select id="ec-store-filter" aria-label="Источник операции"><option value="all">Все источники</option><option value="web">СБП · Platega</option><option value="appstore">App Store</option><option value="googleplay">Google Play</option><option value="rustore">RuStore</option><option value="other">Другие</option></select><label class="ec-check"><input type="checkbox" id="ec-show-tests">Тестовые</label></div>
 <div class="ec-table-wrap"><table class="ec-table"><thead><tr><th>Дата</th><th>Операция</th><th>Тип</th><th class="ec-money">Сумма</th><th aria-label="Действия"></th></tr></thead><tbody id="ec-receipts-body"><tr><td colspan="5" class="ec-empty">Загрузка операций…</td></tr></tbody></table></div>
 <div class="ec-pager"><span id="ec-page-info"></span><div class="ec-actions"><button type="button" class="btn-action" id="ec-prev" aria-label="Предыдущая страница" disabled>←</button><button type="button" class="btn-action" id="ec-next" aria-label="Следующая страница" disabled>→</button></div></div>
</section>
<details class="ec-disclosure" id="ec-platega-panel"><summary>Platega <span class="ec-caption">Баланс сейчас</span></summary><div class="ec-disclosure-body"><div class="ec-head"><span class="ec-platega-status" id="ec-platega-status" role="status"></span><button type="button" class="btn-action" id="ec-platega-refresh">Обновить баланс</button></div><div class="ec-platega-balances" id="ec-platega-body"></div></div></details>
<details class="ec-disclosure" id="ec-cloudflare-panel" hidden><summary>Cloudflare <span class="ec-caption" id="ec-cloudflare-summary"></span></summary><div class="ec-disclosure-body"><div class="ec-head"><span class="ec-platega-status" id="ec-cloudflare-status" role="status"></span><button type="button" class="btn-action" id="ec-cloudflare-refresh">Синхронизировать</button></div><div id="ec-cloudflare-body"></div></div></details>
<details class="ec-disclosure" id="ec-expense-register"><summary>Регулярные расходы и архив <span class="ec-caption" id="ec-monthly-cost"></span></summary><div class="ec-disclosure-body">
 <div class="ec-register-tools"><select id="ec-expense-filter" aria-label="Вид расходов"><option value="all">Все записи</option><option value="recurring">Регулярные</option><option value="once">Разовые</option></select><button type="button" class="btn-action" id="ec-add-expense" disabled>+ Расход</button></div>
 <div class="ec-table-wrap"><table class="ec-table"><thead><tr><th>Дата</th><th>Статья</th><th>Повторение</th><th class="ec-money">Сумма</th><th aria-label="Действия"></th></tr></thead><tbody id="ec-expenses-body"></tbody></table></div>
 <div class="ec-register-note" id="ec-ai-note" hidden></div>
</div></details>
<details class="ec-disclosure" id="ec-planning"><summary>Планирование</summary><div class="ec-disclosure-body ec-planner-grid">
 <div><div class="ec-plan-title">Окупить регулярные расходы</div><div class="ec-plan-amount" id="ec-plan-cost">—</div><div class="ec-caption" id="ec-plan-fee"></div><div class="ec-plan-numbers"><span class="ec-caption">Тариф 99 ₽<strong id="ec-be-week">—</strong></span><span class="ec-caption">Тариф 290 ₽<strong id="ec-be-quarter">—</strong></span></div></div>
 <div><div class="ec-plan-title">Прибыль к распределению</div><div class="ec-plan-controls"><label>Цель, ₽ / мес<input type="number" id="ec-plan-target" min="0" max="100000000" step="1000" value="50000"></label><label>Средний платёж, ₽<input type="number" id="ec-plan-average" min="1" max="1000000" step="1" value="190"></label></div><div class="ec-plan-numbers"><span class="ec-caption">Нужен доход<strong id="ec-plan-revenue">—</strong></span><span class="ec-caption">Продаж в месяц<strong id="ec-plan-sales">—</strong></span></div></div>
</div></details>
<dialog id="ec-dialog" aria-labelledby="ec-dialog-title"><form id="ec-form"><h2 id="ec-dialog-title"></h2><div class="ec-form-grid" id="ec-fields"></div><p class="ec-form-note" id="ec-form-note" hidden></p><div class="ec-form-error" id="ec-form-error" role="alert" hidden></div><div class="ec-form-actions"><button type="button" class="btn-action btn-danger" id="ec-delete" hidden>Удалить</button><button type="button" class="btn-action" id="ec-cancel">Отмена</button><button type="submit" class="btn-action btn-primary" id="ec-submit">Сохранить</button></div></form></dialog>
</div>`;

export const ECONOMY_CLIENT_JS = String.raw`
(function() {
 'use strict';
 var stats=null,period='month',receiptMode='all',page=0,requestId=0,loading=null,dialogContext=null,saving=false,returnFocus=null,journal=[],plategaData=null,plategaLoading=false;
 var stores={web:'СБП · Platega',appstore:'App Store',googleplay:'Google Play',rustore:'RuStore',other:'Другое'};
 var frequencies={once:'Без повторения',monthly:'Ежемесячно',yearly:'Ежегодно'};
 var operationTypes={revenue:'Поступление',expense:'Расход',withdrawal:'Вывод',commission:'Комиссия'};
 var kindLabels={income:'Поступление',expense:'Расход',withdrawal:'Вывод',commission:'Комиссия'};
 var operationIconPaths={
  income:'<path d="m17 7-10 10M7 7v10h10"/>',
  expense:'<path d="M7 17 17 7M7 7h10v10"/>',
  withdrawal:'<path d="M4 4v16m4-8h12m-5-5 5 5-5 5"/>',
  commission:'<path d="m7 17 10-10"/><circle cx="7.5" cy="7.5" r="2.5"/><circle cx="16.5" cy="16.5" r="2.5"/>'
 };
 function operationIcon(kind){return '<span class="ec-operation-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" focusable="false">'+operationIconPaths[kind]+'</svg></span>';}
 var editIcon='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m16 3 5 5-12 12-6 1 1-6Z M14 5l5 5"/></svg>';
 var infoIcon='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7v1"/></svg>';
 function el(id){return document.getElementById(id);}
 function esc(value){return String(value==null?'':value).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];});}
 function num(value){return Number(value||0).toLocaleString('ru-RU',{maximumFractionDigits:2});}
 function rub(value){return num(value)+' ₽';}
 function money(value,currency){return currency==='USD'?'$'+num(value):rub(value);}
 function pct(value){return num(value)+'%';}
 function set(id,value){var node=el(id);if(node)node.textContent=value;}
 function today(){return new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Moscow'}).format(new Date());}
 function dateText(value,year){var date=new Date(value);return Number.isFinite(date.getTime())?date.toLocaleDateString('ru-RU',{timeZone:'Europe/Moscow',day:'numeric',month:'short',year:year?'numeric':undefined}):'—';}
 function field(name){return el('ec-form').elements.namedItem(name);}
 function feedback(message,error){el('ec-feedback').hidden=false;el('ec-feedback').classList.toggle('error',!!error);el('ec-feedback').querySelector('span').textContent=message;}
 function activate(container,attribute,value){el(container).querySelectorAll('button').forEach(function(button){var active=button.getAttribute(attribute)===value;button.classList.toggle('active',active);button.setAttribute('aria-pressed',String(active));});}
 function enableActions(){['ec-settings','ec-edit-shares','ec-add-operation','ec-add-expense'].forEach(function(id){el(id).disabled=!stats||saving||stats.period!==period;});}
 async function loadEconomy(force){
  var id=++requestId,selectedPeriod=period;
  el('ec-data-state').hidden=false;el('ec-data-state').className='admin-data-state loading';set('ec-data-state',stats?'Обновление…':'Загрузка…');enableActions();
  function accept(data,meta){
   if(id!==requestId||selectedPeriod!==period)return;if(!data.ok)throw new Error(data.error||'Не удалось загрузить данные');
   var first=!stats;stats=data;if(first)el('ec-plan-target').value=data.config.targetMonthlyProfit??50000;
   render();enableActions();el('ec-data-state').className='admin-data-state '+(meta?.refreshing?'loading':'ready');
   set('ec-data-state',meta?.refreshing?'Обновление…':'Обновлено '+new Date(meta?.updatedAt||Date.now()).toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}));
  }
  var task=(async function(){
   try{
    var url='/api/admin/economy/stats?period='+selectedPeriod;
    if(window.AdminData)await AdminData.load(url,{view:'economy-view',force:force===true,onData:accept});
    else{var response=await fetch(url);if(response.status===401){if(typeof checkAuthAndLoad==='function')checkAuthAndLoad();throw new Error('Войдите в админку заново');}var data=await response.json();if(!response.ok)throw new Error(data.error||'Не удалось загрузить данные');accept(data,{});}
    return true;
   }catch(error){
    if(id!==requestId)return;
    el('ec-data-state').className='admin-data-state error';
    if(window.AdminData){
     el('ec-data-state').hidden=true;
     if(el('ec-feedback').classList.contains('error'))el('ec-feedback').hidden=true;
    }else{
     set('ec-data-state','Ошибка обновления');feedback(error.message+(stats?' · показаны предыдущие данные':''),true);
     if(!stats)el('ec-receipts-body').innerHTML='<tr><td colspan="5" class="ec-empty">Нажмите «Обновить», чтобы повторить</td></tr>';
    }
    return false;
   }
   finally{if(id===requestId)loading=null;}
  })();loading=task;return task;
 }
 async function loadPlatega(force){
  if(plategaLoading)return;plategaLoading=true;el('ec-platega-refresh').disabled=true;el('ec-platega-status').classList.remove('error');set('ec-platega-status',plategaData?'Обновление…':'Загрузка…');
  function accept(data){
   if(!data.ok)throw new Error(data.error||'Не удалось загрузить баланс');plategaData=data;
   if(!data.configured){set('ec-platega-status','Platega не подключена');el('ec-platega-body').innerHTML='';return;}
   set('ec-platega-status','Обновлено '+new Date(data.updatedAt||Date.now()).toLocaleString('ru-RU',{timeZone:'Europe/Moscow',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}));
   var balances=(data.balances||[]).filter(function(item){return Number.isFinite(Number(item.amount));});
   el('ec-platega-body').innerHTML=balances.length?balances.map(function(item){return '<div class="ec-platega-balance"><span class="ec-caption">'+esc(item.currency)+'</span><strong>'+esc(num(item.amount))+'</strong>'+(item.frozenBalance!=null?'<span class="ec-caption">Заморожено '+esc(num(item.frozenBalance))+'</span>':'')+'</div>';}).join(''):'<div class="ec-caption">Балансы не получены</div>';
  }
  try{
   if(window.AdminData)await AdminData.load('/api/admin/economy/platega',{view:'ec-platega-body',ttl:15000,force:force===true,onData:accept});
   else{var response=await fetch('/api/admin/economy/platega'),data=await response.json();if(!response.ok)throw new Error(data.error||'Не удалось загрузить баланс');accept(data);}
  }catch(error){el('ec-platega-status').classList.add('error');set('ec-platega-status',(plategaData?.configured?'Показан предыдущий баланс. ':'')+(error.message||'Не удалось загрузить баланс'));}
  finally{plategaLoading=false;el('ec-platega-refresh').disabled=false;}
 }
 function render(){
  var rev=stats.revenue,exp=stats.expenses,profit=stats.profit,cfg=stats.config;
  set('ec-gross-val',rub(rev.grossRub));set('ec-costs-val',rub(exp.totalRub));set('ec-net-val',rub(profit.operatingRub));
  set('ec-gross-sub',rev.includedStoreSalesRub>0?'Оценка продаж магазинов: '+rub(rev.includedStoreSalesRub):rev.ordersCount?num(rev.ordersCount)+' оплат СБП':'За выбранный период');
  var commissions=(exp.paymentFeesRub||0)+(exp.withdrawalFeesRub||0)+(exp.lines||[]).filter(function(line){return line.category==='commission';}).reduce(function(sum,line){return sum+line.periodRub;},0);
  set('ec-costs-sub',stats.cloudflare?.stale?'Cloudflare: показаны прежние счета':'Комиссии '+rub(commissions)+' · Platega '+pct(cfg.paymentFeePercent));
  var loss=profit.operatingRub<0;el('ec-net-card').classList.toggle('is-loss',loss);set('ec-net-label',loss?'Убыток':'Прибыль');set('ec-net-sub',loss?'Распределение — 0 ₽':rev.includedStoreSalesRub>0?'Оценка после расходов':'После расходов и комиссий');
  set('ec-fund-pct',pct(cfg.reinvestPercent));set('ec-fund-total',rub(profit.reinvestRub));
  ['sergey','nikita'].forEach(function(key,index){var partner=stats.partners[key],suffix=index?'n':'s';set('ec-share-'+suffix,pct(partner.percent)+' доли');set('ec-payout-'+suffix,rub(partner.payoutRub));});
  var range=stats.periodInfo||{};set('ec-period-note',range.from?dateText(range.from,true)+' — '+dateText(range.to,true):'');
  set('ec-withdrawn-total',stats.withdrawalSummary?.count?'Выведено '+rub(stats.withdrawalSummary.receivedRub):'');
  set('ec-monthly-cost',rub(exp.monthlyRub)+' / мес');
  el('ec-ai-note').hidden=!exp.ai?.available;set('ec-ai-note','Gemini: '+rub(exp.ai?.rub)+(exp.ai?.includedInTotal?' · учтено в расходах':' за всё время · вне итога периода'));
  journal=buildJournal();renderReceipts();renderExpenses();renderCloudflare();updatePlanner();
 }
 function renderCloudflare(){
  var cf=stats.cloudflare;el('ec-cloudflare-panel').hidden=!cf?.configured;if(!cf?.configured)return;
  set('ec-cloudflare-summary',cf.stale?'Не обновлено · показаны прежние счета':'По счетам · весь аккаунт');
  set('ec-cloudflare-status',cf.stale?cf.error:'Обновлено '+new Date(cf.updatedAt).toLocaleString('ru-RU',{timeZone:'Europe/Moscow',day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}));el('ec-cloudflare-status').classList.toggle('error',!!cf.stale);
  var invoices=cf.invoices||[],periodLines=(stats.expenses.lines||[]).filter(function(line){return line.imported&&line.occurrences;});
  var html='<div class="ec-platega-balances"><div class="ec-platega-balance"><span class="ec-caption">Счета за выбранный период</span><strong>'+rub(periodLines.reduce(function(sum,line){return sum+line.periodRub;},0))+'</strong><span class="ec-caption">'+num(periodLines.length)+' счетов · в расходах</span></div><div class="ec-platega-balance"><span class="ec-caption">Потребление сверх тарифа</span><strong>'+(cf.usage?money(cf.usage.usd,'USD'):'—')+'</strong><span class="ec-caption">'+(cf.usage?.from?esc(dateText(cf.usage.from,true))+' — '+esc(dateText(cf.usage.to,true)):'Данные недоступны')+' · вне итога</span></div><div class="ec-platega-balance"><span class="ec-caption">Тарифы аккаунта</span><strong>'+(cf.subscriptions?money(cf.subscriptions.reduce(function(sum,item){return sum+item.usd;},0),'USD')+' / мес':'—')+'</strong><span class="ec-caption">Фиксированная часть</span></div></div>';
  html+='<p class="ec-register-note">Счета всего аккаунта, включая другие проекты. В прибыли — закрытые счета по дате выставления. Рубли — по курсу '+rub(stats.config.usdRate)+' / $.</p>';
  if(cf.pending)html+='<p class="ec-register-note">Не включено записей другого типа или статуса: '+num(cf.pending)+'.</p>';
  if(cf.usage?.services?.length)html+='<div class="ec-register-note">'+cf.usage.services.map(function(item){return esc(item.name)+': '+money(item.usd,'USD');}).join(' · ')+'</div>';
  el('ec-cloudflare-body').innerHTML=html;
 }
 async function syncCloudflare(){
  el('ec-cloudflare-refresh').disabled=true;set('ec-cloudflare-status','Синхронизация…');
  try{var result=await mutate('cloudflare/sync',{});if(result.stale)throw new Error(result.error);await loadEconomy(true);}
  catch(error){set('ec-cloudflare-status',error.message);el('ec-cloudflare-status').classList.add('error');}
  finally{el('ec-cloudflare-refresh').disabled=false;}
 }
 function buildJournal(){
  var range=stats.periodInfo||{},rows=[];
  (stats.receipts||[]).forEach(function(receipt){
   var manual=(stats.config.manualRevenues||[]).find(function(item){return item.id===receipt.id;});
   rows.push({key:'receipt:'+receipt.id,id:receipt.id,kind:receipt.includedInRevenue||receipt.isTest?'income':'withdrawal',date:receipt.date,title:receipt.customer||receipt.title||'Поступление',sourceKey:receipt.storeKey,source:stores[receipt.storeKey]||receipt.store,amountRub:receipt.amountRub,amount:manual?.amount,currency:manual?.currency,sub:receipt.type==='estimate'?'По тарифу, до комиссии':receipt.isTest?(receipt.includedInRevenue?'Тест · учтён':'Тест · не учтён'):!receipt.includedInRevenue?'Выплата магазина · доход уже учтён':'',search:[receipt.email,receipt.txId,receipt.tier].join(' '),isTest:receipt.isTest,editKind:manual?'revenue':null,original:receipt});
  });
  (stats.expenses.lines||[]).filter(function(line){return line.periodRub>0;}).forEach(function(line){
   var recurring=line.frequency!=='once';rows.push({key:'expense:'+line.id,id:line.id,kind:line.category==='commission'?'commission':'expense',date:recurring?range.to:line.date,dateLabel:recurring?'За период':null,title:line.title,sourceKey:'other',source:line.imported?'Cloudflare · весь аккаунт':'Проект',amountRub:line.periodRub,amount:!recurring?line.amount:null,currency:line.currency,sub:line.imported?'Счёт · API':line.builtin?'Бюджет':recurring?frequencies[line.frequency]+(line.occurrences>1?' · '+num(line.occurrences)+' списаний':''):'',editKind:line.imported?null:line.builtin?'builtin':line.category==='commission'?'commission':'expense',original:line});
  });
  if(stats.expenses.paymentFeesRub>0)rows.push({key:'payment-fees',kind:'commission',date:range.to,dateLabel:'За период',title:'Комиссия Platega',sourceKey:'web',source:stores.web,amountRub:stats.expenses.paymentFeesRub,sub:pct(stats.config.paymentFeePercent)+' с платежей',original:{}});
  (stats.withdrawals||[]).forEach(function(item){
   var received=item.currency==='USD'?item.receivedRub/item.usdRate:item.receivedRub;
   rows.push({key:'withdrawal:'+item.id,id:item.id,kind:'withdrawal',date:item.date,title:item.title||'Вывод средств',sourceKey:item.store,source:stores[item.store]||'Другое',amountRub:item.receivedRub,amount:received,currency:item.currency,sub:item.fee>0?'Комиссия '+money(item.fee,item.currency):'Без комиссии',editKind:'withdrawal',original:item});
   if(item.feeRub>0)rows.push({key:'withdrawal-fee:'+item.id,id:item.id,kind:'commission',date:item.date,title:'Комиссия за вывод',sourceKey:item.store,source:stores[item.store]||'Другое',amountRub:item.feeRub,amount:item.fee,currency:item.currency,sub:item.title||'Вывод средств',editKind:'withdrawal',original:item,hiddenInAll:true});
  });
  if(stats.expenses.ai?.includedInTotal&&stats.expenses.ai.periodRub>0)rows.push({key:'ai',kind:'expense',date:range.to,dateLabel:'За всё время',title:'Gemini',sourceKey:'other',source:'Проект',amountRub:stats.expenses.ai.periodRub,sub:'',original:{}});
  return rows.sort(function(a,b){return Date.parse(b.date)-Date.parse(a.date)||a.key.localeCompare(b.key);});
 }
 function rowAction(row){return row.editKind?'data-edit-kind="'+esc(row.editKind)+'" data-id="'+esc(row.id)+'"':'data-detail-key="'+esc(row.key)+'"';}
 function renderReceipts(){
  if(!stats)return;
  var query=el('ec-search').value.trim().toLowerCase(),source=el('ec-store-filter').value,showTests=el('ec-show-tests').checked;
  var rows=journal.filter(function(row){return (showTests||!row.isTest)&&(source==='all'||source===row.sourceKey)&&(receiptMode==='all'?!row.hiddenInAll:receiptMode==='expense'?row.kind==='expense'||row.kind==='commission':row.kind===receiptMode)&&(!query||[row.title,row.sub,row.source,row.id,row.search].join(' ').toLowerCase().includes(query));});
  var size=10,pages=Math.max(1,Math.ceil(rows.length/size));page=Math.min(page,pages-1);set('ec-receipts-count',num(rows.length));
  el('ec-receipts-body').innerHTML=rows.length?rows.slice(page*size,(page+1)*size).map(function(row){
   var sign=row.kind==='income'?'+':row.kind==='expense'||row.kind==='commission'?'−':'';
   var sub=[row.source,row.sub].filter(Boolean).join(' · ');
   return '<tr data-row-kind="'+row.kind+'"><td class="ec-date">'+esc(row.dateLabel||dateText(row.date,true))+'</td><td class="ec-name"><div class="ec-operation">'+operationIcon(row.kind)+'<div class="ec-operation-text"><button type="button" class="ec-row-title" '+rowAction(row)+'>'+esc(row.title)+'</button><span class="ec-sub">'+esc(sub)+'</span></div></div></td><td class="ec-kind"><span class="ec-type-badge">'+kindLabels[row.kind]+'</span></td><td class="ec-money '+row.kind+'">'+sign+rub(row.amountRub)+(row.currency==='USD'&&row.amount!=null?'<span class="ec-sub">'+money(row.amount,'USD')+'</span>':'')+'</td><td class="ec-cell-action"><button type="button" class="ec-edit" '+rowAction(row)+' aria-label="'+esc((row.editKind?'Редактировать ':'Подробнее: ')+row.title)+'" title="'+(row.editKind?'Редактировать':'Подробнее')+'">'+(row.editKind?editIcon:infoIcon)+'</button></td></tr>';
  }).join(''):'<tr><td colspan="5" class="ec-empty">'+(query||source!=='all'?'Ничего не найдено':'За этот период операций нет')+'</td></tr>';
  set('ec-page-info',rows.length?(page*size+1)+'–'+Math.min((page+1)*size,rows.length)+' из '+rows.length:'');el('ec-prev').disabled=page===0;el('ec-next').disabled=page>=pages-1;
 }
 function renderExpenses(){
  if(!stats)return;var filter=el('ec-expense-filter').value;
  var lines=(stats.expenses.lines||[]).filter(function(line){return filter==='all'||(filter==='once'?line.frequency==='once':line.frequency!=='once');});
  el('ec-expenses-body').innerHTML=lines.length?lines.map(function(line){var kind=line.builtin?'builtin':line.category==='commission'?'commission':'expense',amount=money(line.amount??line.amountRub,line.currency),action=line.imported?'data-detail-key="expense:'+esc(line.id)+'"':'data-edit-kind="'+kind+'" data-id="'+esc(line.id)+'"';return '<tr><td class="ec-date">'+(line.builtin?'Бюджет':esc(dateText(line.date,true)))+'</td><td class="ec-name"><button type="button" class="ec-row-title" '+action+'>'+esc(line.title)+'</button>'+(line.imported?'<span class="ec-sub">Cloudflare · весь аккаунт · API</span>':line.endDate?'<span class="ec-sub">До '+esc(dateText(line.endDate,true))+'</span>':'')+'</td><td class="ec-kind">'+(line.frequency==='once'?'Разовый':frequencies[line.frequency])+'</td><td class="ec-money">'+amount+'</td><td class="ec-cell-action"><button type="button" class="ec-edit" '+action+' aria-label="'+(line.imported?'Подробнее: ':'Редактировать ')+esc(line.title)+'">'+(line.imported?infoIcon:editIcon)+'</button></td></tr>';}).join(''):'<tr><td colspan="5" class="ec-empty">Расходов пока нет</td></tr>';
 }
 function updatePlanner(){
  if(!stats)return;var monthly=Number(stats.expenses.monthlyRub)||0,target=Math.max(0,Number(el('ec-plan-target').value)||0),average=Math.max(1,Number(el('ec-plan-average').value)||1),reinvestFactor=1-stats.config.reinvestPercent/100,feeFactor=1-stats.config.paymentFeePercent/100;
  var possible=feeFactor>0&&(reinvestFactor>0||target===0),required=possible?(monthly+(target===0?0:target/reinvestFactor))/feeFactor:0;
  set('ec-plan-cost',rub(monthly)+' / мес');set('ec-plan-fee','С учётом комиссии Platega '+pct(stats.config.paymentFeePercent));
  set('ec-be-week',feeFactor>0?num(Math.ceil(monthly/(99*feeFactor)))+' продаж':'—');set('ec-be-quarter',feeFactor>0?num(Math.ceil(monthly/(290*feeFactor)))+' продаж':'—');
  set('ec-plan-revenue',possible?rub(Math.ceil(required)):'—');set('ec-plan-sales',possible?num(Math.ceil(required/average)):'—');
 }
 function input(name,label,value,options){options=options||{};return '<label class="ec-field '+(options.full?'full':'')+'"><span>'+esc(label)+'</span><input name="'+name+'" type="'+(options.type||'number')+'" value="'+esc(value)+'" '+(options.required===false?'':'required')+' '+(options.type==='text'?'maxlength="160"':options.type==='date'?(options.max?'max="'+esc(options.max)+'"':''):'min="'+(options.min??0)+'" max="'+(options.max??100000000)+'" step="'+(options.step||'0.01')+'"')+'></label>';}
 function select(name,label,value,choices,full){return '<label class="ec-field '+(full?'full':'')+'"><span>'+esc(label)+'</span><select name="'+name+'">'+Object.keys(choices).map(function(key){return '<option value="'+esc(key)+'" '+(key===value?'selected':'')+'>'+esc(choices[key])+'</option>';}).join('')+'</select></label>';}
 function formNote(note){el('ec-form-note').hidden=!note;set('ec-form-note',note);}
 function operationFields(kind,item){
  var cfg=stats.config,expense=kind==='expense'||kind==='commission',currency=item.currency||(kind==='withdrawal'?'USD':'RUB');
  var html=select('operationType','Тип операции',kind,operationTypes,true)+input('amount',kind==='withdrawal'?'Сумма вывода':'Сумма',item.amount??item.amountRub??'',{min:0.01})+select('currency','Валюта',currency,{RUB:'Рубли · ₽',USD:'Доллары · $'});
  if(kind==='withdrawal')html+=input('fee','Комиссия',item.fee??0)+select('feeMode','Как списана',item.feeMode||'additional',{additional:'Сверх суммы',included:'Из суммы вывода'});
  html+=input('date',expense?'Дата платежа':'Дата',(item.date||today()).slice(0,10),{type:'date',max:expense?undefined:today()});
  if(expense)html+=select('frequency','Повторение',item.frequency||'once',frequencies);
  else html+=select('store',kind==='withdrawal'?'Откуда':'Источник',item.store||(kind==='withdrawal'?'web':'other'),stores);
  html+=input('title',kind==='withdrawal'?'Название (необязательно)':'Название',item.title||'',{type:'text',full:true,required:kind!=='withdrawal'});
  if(expense)html+=input('endDate','Повторять до',item.endDate||'',{type:'date',required:false,full:true});
  if(!expense)html+=input('usdRate','Курс на дату операции, ₽ / $',item.id&&item.currency!=='USD'?cfg.usdRate:item.usdRate??cfg.usdRate,{min:0.0001,step:'0.0001',max:100000,full:true});
  html+='<div class="ec-form-preview" id="ec-form-preview"></div>';
  return html;
 }
 function showForm(kind,item){
  if(!stats||saving||stats.period!==period)return;item=item||{};returnFocus=document.activeElement;dialogContext={kind:kind,id:item.id||null,confirmDelete:false,item:item};var html='',heading='',note='';
  if(Object.hasOwn(operationTypes,kind)){heading=item.id?'Изменить операцию':'Новая операция';html=operationFields(kind,item);}
  else if(kind==='shares'){heading='Распределение прибыли';html=input('reinvestPercent','В развитие, %',stats.config.reinvestPercent,{max:100,full:true})+input('sergeySharePercent','Сергей, %',stats.config.sergeySharePercent,{max:100})+input('nikitaSharePercent','Никита, %',stats.config.nikitaSharePercent,{max:100})+'<div class="ec-form-preview" id="ec-form-preview"></div>';note='Доли делят остаток после отчисления в развитие.';}
  else if(kind==='settings'){
   heading='Настройки экономики';var cfg=stats.config;
   html=input('paymentFeePercent','Комиссия Platega, %',cfg.paymentFeePercent??8,{max:100})+input('usdRate','Курс доллара, ₽',cfg.usdRate,{min:0.0001,step:'0.0001',max:100000})+'<details class="ec-settings-extra"><summary>Бюджет инфраструктуры</summary><div class="ec-form-grid">'+(stats.cloudflare?.configured?'<input type="hidden" name="cloudflareMonthlyUsd" value="'+esc(cfg.cloudflareMonthlyUsd)+'"><p class="ec-form-note">Cloudflare: счета через API. Бюджет не используется.</p>':input('cloudflareMonthlyUsd','Cloudflare, $ / мес',cfg.cloudflareMonthlyUsd))+input('domainMonthlyRub','Домен, ₽ / мес',cfg.domainMonthlyRub)+'<label class="ec-form-check"><input type="checkbox" name="cloudflareEnabled" '+(stats.cloudflare?.configured?'disabled ':'')+(cfg.cloudflareEnabled!==false?'checked':'')+'>Учитывать Cloudflare</label><label class="ec-form-check"><input type="checkbox" name="domainEnabled" '+(cfg.domainEnabled!==false?'checked':'')+'>Учитывать домен</label><p class="ec-form-note" style="grid-column:1/-1;margin:0">Бюджет распределяется по дням. При учёте реальных списаний отключите его.</p></div></details><label class="ec-form-check"><input type="checkbox" name="excludeTestOrders" '+(cfg.excludeTestOrders?'checked':'')+'>Исключать тестовые оплаты</label>';
   note='Комиссия применяется к платежам СБП. Курс по умолчанию — для новых операций и бюджета.';
  }else if(kind==='builtin'){
   heading=item.title;html=input('amount',item.currency==='USD'?'Бюджет, $ / мес':'Бюджет, ₽ / мес',item.amount,{full:true})+'<div class="ec-form-preview">В выбранном периоде <b>'+rub(item.periodRub)+'</b></div>';note='Бюджет распределяется по дням месяца.';
  }
  set('ec-dialog-title',heading);el('ec-fields').innerHTML=html;el('ec-form-error').hidden=true;formNote(note);el('ec-delete').hidden=!item.id;set('ec-delete',kind==='builtin'?'Отключить':'Удалить');el('ec-submit').hidden=false;set('ec-submit',item.id||kind==='shares'||kind==='settings'?'Сохранить':'Добавить');set('ec-cancel','Отмена');if(item.id&&field('operationType'))field('operationType').disabled=true;updateFormPreview();el('ec-dialog').showModal();
 }
 function updateFormPreview(changed){
  if(!dialogContext)return;var kind=dialogContext.kind;
  if(kind==='shares'){
   if(changed==='sergeySharePercent'||changed==='nikitaSharePercent'){var other=changed==='sergeySharePercent'?'nikitaSharePercent':'sergeySharePercent',value=Number(field(changed).value);if(field(changed).value!==''&&Number.isFinite(value)&&value>=0&&value<=100)field(other).value=Number((100-value).toFixed(2));}
   var profit=Math.max(0,stats.profit.operatingRub),fund=profit*Number(field('reinvestPercent').value)/100,payout=profit-fund;
   el('ec-form-preview').innerHTML=previewLine('В развитие',rub(fund))+previewLine('Сергей',rub(payout*Number(field('sergeySharePercent').value)/100))+previewLine('Никита',rub(payout*Number(field('nikitaSharePercent').value)/100));return;
  }
  if(!Object.hasOwn(operationTypes,kind))return;
  var amount=Number(field('amount').value)||0,currency=field('currency').value,expense=kind==='expense'||kind==='commission',rate=expense?stats.config.usdRate:Number(field('usdRate').value)||0,rubles=amount*(currency==='USD'?rate:1),note='';
  if(field('usdRate')){field('usdRate').closest('label').hidden=currency!=='USD';field('usdRate').disabled=currency!=='USD';}
  if(expense){var once=field('frequency').value==='once';field('endDate').closest('label').hidden=once;field('endDate').disabled=once;field('endDate').min=field('date').value;field('date').closest('label').querySelector('span').textContent=once?'Дата платежа':'Первый платёж';el('ec-form-preview').innerHTML=previewLine(once?'В расходах':field('frequency').value==='yearly'?'Каждый год':'Каждый месяц',rub(rubles));if(currency==='USD')note='Расход пересчитывается по курсу в настройках: '+rub(rate)+' / $.';}
  if(kind==='withdrawal'){
   var fee=Number(field('fee').value)||0,included=field('feeMode').value==='included',received=included?amount-fee:amount,debited=included?amount:amount+fee;
   el('ec-form-preview').innerHTML=previewLine('Получено',money(received,currency))+previewLine('Списано',money(debited,currency))+previewLine('В расходах только комиссия',rub(fee*(currency==='USD'?rate:1)));
   field('fee').max=included?amount:100000000;
  }
  if(kind==='revenue'){
   var store=field('store').value,isPayout=['appstore','googleplay','rustore'].includes(store),fee=store==='web'?rubles*stats.config.paymentFeePercent/100:0;
   el('ec-form-preview').innerHTML=isPayout?previewLine('Выплата магазина',rub(rubles)):previewLine('В доходе',rub(rubles))+(fee?previewLine('Комиссия '+pct(stats.config.paymentFeePercent),rub(fee)):'');
   note=isPayout?'Продажи уже учтены. Выплата сохранится без повторного дохода.':'';
  }
  formNote(note);
 }
 function previewLine(label,value){return '<div class="ec-preview-line"><span>'+esc(label)+'</span><b>'+esc(value)+'</b></div>';}
 function formDraft(){var result={};['title','date','amount','currency','usdRate','fee','feeMode','store','frequency','endDate'].forEach(function(name){var node=field(name);if(node)result[name]=node.value;});return result;}
 function detailLine(label,value,raw){return '<dt>'+esc(label)+'</dt><dd>'+ (raw?value:esc(value))+'</dd>';}
 function showDetails(key){
  var row=journal.find(function(item){return item.key===key;});if(!row){var invoice=(stats.expenses.lines||[]).find(function(line){return line.imported&&'expense:'+line.id===key;});if(invoice)row={title:invoice.title,amountRub:invoice.amountRub,date:invoice.date,source:'Cloudflare · весь аккаунт',original:invoice};}if(!row||saving)return;
  returnFocus=document.activeElement;dialogContext={kind:'detail'};set('ec-dialog-title',row.title);var receipt=row.original||{},html=detailLine('Сумма',rub(row.amountRub))+detailLine('Дата',row.dateLabel||dateText(row.date,true))+detailLine('Источник',row.source);
  if(receipt.imported)html+=detailLine('Счёт',receipt.receipt||receipt.id)+detailLine('В валюте счёта',money(receipt.amount,receipt.currency))+detailLine('Курс',rub(stats.config.usdRate)+' / $')+detailLine('Учёт','Закрытый счёт · весь аккаунт')+(receipt.matchedManualId?detailLine('Сверка','Заменяет совпадающую ручную запись'): '');
  if(receipt.type==='estimate')html+=detailLine('Учёт','По тарифу, до комиссии');
  if(receipt.email)html+=detailLine('Email',receipt.email);
  if(receipt.tier)html+=detailLine('Тариф',receipt.tier);
  if(receipt.feeRub>0)html+=detailLine('Комиссия '+pct(receipt.paymentFeePercent??stats.config.paymentFeePercent),rub(receipt.feeRub))+detailLine('После комиссии',rub(receipt.netRub));
  if(receipt.isTest)html+=detailLine('Тестовая оплата',receipt.includedInRevenue?'Включена в доход':'Исключена из дохода');
  if(receipt.txId)html+='<dt class="ec-wide">Номер заказа</dt><dd class="ec-wide"><button type="button" class="ec-detail-copy" data-copy="'+esc(receipt.txId)+'" title="Скопировать номер заказа">'+esc(receipt.txId)+'</button></dd>';
  el('ec-fields').innerHTML='<dl class="ec-detail-list">'+html+'</dl>';formNote(key==='payment-fees'?'Рассчитывается автоматически по каждому платежу СБП.':receipt.type==='estimate'?'Сумма по тарифу. Комиссии и выплаты магазина могут отличаться.':'');el('ec-form-error').hidden=true;el('ec-delete').hidden=true;el('ec-submit').hidden=true;set('ec-cancel','Закрыть');el('ec-dialog').showModal();
 }
 function closeForm(){if(saving)return;el('ec-dialog').close();dialogContext=null;if(returnFocus?.isConnected)returnFocus.focus();}
 async function mutate(path,body){var response=await fetch('/api/admin/economy/'+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});var data;try{data=await response.json();}catch(_){throw new Error('Не удалось получить ответ сервера');}if(!response.ok||!data.ok)throw new Error(data.error||'Не удалось сохранить');return data;}
 async function submitForm(event,deleting){
  if(event)event.preventDefault();if(saving||!dialogContext||dialogContext.kind==='detail')return;
  var context=dialogContext,kind=context.kind,body={},path='',expense=kind==='expense'||kind==='commission',group=expense||kind==='builtin'?'expenses':kind==='withdrawal'?'withdrawals':'revenues';
  if(deleting===true){path=group+'/delete';body.id=context.id;}
  else{
   if(!el('ec-form').reportValidity())return;
   if(Object.hasOwn(operationTypes,kind)){
    body={title:field('title').value.trim(),amount:Number(field('amount').value),currency:field('currency').value,date:field('date').value};
    if(expense){body.frequency=field('frequency').value;body.endDate=body.frequency==='once'?null:field('endDate').value||null;body.category=kind==='commission'?'commission':'expense';}
    else{body.store=field('store').value;if(body.currency==='USD')body.usdRate=Number(field('usdRate').value);}
    if(kind==='withdrawal'){body.fee=Number(field('fee').value);body.feeMode=field('feeMode').value;}
    path=group+'/'+(context.id?'update':'add');if(context.id)body.id=context.id;
   }else if(kind==='shares'){body={nikitaSharePercent:Number(field('nikitaSharePercent').value),reinvestPercent:Number(field('reinvestPercent').value)};if(Math.abs(Number(field('sergeySharePercent').value)+body.nikitaSharePercent-100)>.001){formError('Сумма долей должна быть 100%');return;}path='settings';}
   else if(kind==='builtin'){body[context.item.source==='cloudflare'?'cloudflareMonthlyUsd':'domainMonthlyRub']=Number(field('amount').value);path='settings';}
   else{body={paymentFeePercent:Number(field('paymentFeePercent').value),usdRate:Number(field('usdRate').value),cloudflareMonthlyUsd:Number(field('cloudflareMonthlyUsd').value),domainMonthlyRub:Number(field('domainMonthlyRub').value),cloudflareEnabled:field('cloudflareEnabled').checked,domainEnabled:field('domainEnabled').checked,excludeTestOrders:field('excludeTestOrders').checked};path='settings';}
  }
  saving=true;enableActions();el('ec-form-error').hidden=true;var submitLabel=el('ec-submit').textContent,controls=Array.from(el('ec-form').querySelectorAll('button,input,select')).map(function(node){var state={node:node,disabled:node.disabled};node.disabled=true;return state;});set('ec-submit',deleting?'Удаление…':'Сохранение…');
  try{await mutate(path,body);saving=false;closeForm();saving=true;feedback(deleting?(kind==='builtin'?'Бюджет отключён':'Операция удалена'):'Сохранено');await loadEconomy(true);}
  catch(error){formError(error.message);}
  finally{saving=false;enableActions();controls.forEach(function(state){state.node.disabled=state.disabled;});set('ec-submit',submitLabel);if(!dialogContext&&!returnFocus?.isConnected)el('ec-add-operation').focus();}
 }
 function formError(message){el('ec-form-error').hidden=false;set('ec-form-error',message);}
 function openRow(event){var button=event.target.closest('button');if(!button||!stats)return;if(button.dataset.detailKey)return showDetails(button.dataset.detailKey);var kind=button.dataset.editKind,id=button.dataset.id;if(!kind)return;var list=kind==='builtin'?stats.expenses.lines:kind==='revenue'?stats.config.manualRevenues:kind==='withdrawal'?stats.config.withdrawals:stats.config.extraExpenses;var item=(list||[]).find(function(row){return row.id===id;});if(item)showForm(kind,item);}
 function init(){
  if(!el('economy-view'))return;window.loadEconomy=loadEconomy;
  el('ec-period-tabs').addEventListener('click',function(event){var button=event.target.closest('[data-period]');if(!button)return;period=button.dataset.period;page=0;activate('ec-period-tabs','data-period',period);loadEconomy(false);});
  el('ec-refresh').onclick=function(){loadEconomy(true);};el('ec-settings').onclick=function(){showForm('settings');};el('ec-edit-shares').onclick=function(){showForm('shares');};el('ec-add-operation').onclick=function(){showForm('expense');};el('ec-add-expense').onclick=function(){showForm('expense');};
  el('ec-receipt-mode').addEventListener('click',function(event){var button=event.target.closest('[data-mode]');if(!button)return;receiptMode=button.dataset.mode;page=0;activate('ec-receipt-mode','data-mode',receiptMode);renderReceipts();});
  el('ec-expense-filter').addEventListener('change',renderExpenses);
  el('ec-platega-panel').addEventListener('toggle',function(){if(this.open)loadPlatega(false);});el('ec-platega-refresh').onclick=function(){loadPlatega(true);};el('ec-cloudflare-refresh').onclick=syncCloudflare;
  ['ec-search','ec-store-filter','ec-show-tests'].forEach(function(id){el(id).addEventListener(id==='ec-search'?'input':'change',function(){page=0;renderReceipts();});});
  el('ec-prev').onclick=function(){page--;renderReceipts();};el('ec-next').onclick=function(){page++;renderReceipts();};el('ec-receipts-body').addEventListener('click',openRow);el('ec-expenses-body').addEventListener('click',openRow);
  el('ec-feedback').querySelector('button').onclick=function(){el('ec-feedback').hidden=true;};['ec-plan-target','ec-plan-average'].forEach(function(id){el(id).addEventListener('input',updatePlanner);});
  el('ec-form').addEventListener('input',function(event){if(event.target.name!=='operationType')updateFormPreview(event.target.name);});
  el('ec-form').addEventListener('change',function(event){
   if(event.target.name==='operationType'&&!dialogContext.id){var draft=formDraft(),kind=event.target.value;dialogContext.kind=kind;if(kind==='withdrawal'&&!draft.title&&draft.amount==='')draft.currency='USD';el('ec-fields').innerHTML=operationFields(kind,draft);field('operationType').focus();}
   updateFormPreview(event.target.name);
  });
  el('ec-form').addEventListener('submit',submitForm);el('ec-cancel').onclick=closeForm;
  el('ec-delete').onclick=function(){if(!dialogContext.confirmDelete){dialogContext.confirmDelete=true;set('ec-delete',dialogContext.kind==='builtin'?'Подтвердить отключение':'Подтвердить удаление');return;}submitForm(null,true);};
  el('ec-fields').addEventListener('click',async function(event){var button=event.target.closest('[data-copy]');if(!button)return;try{await navigator.clipboard.writeText(button.dataset.copy);set('ec-form-note','Номер заказа скопирован');el('ec-form-note').hidden=false;}catch(_){formError('Не удалось скопировать номер заказа');}});
  el('ec-dialog').addEventListener('cancel',function(event){event.preventDefault();closeForm();});
  el('ec-dialog').addEventListener('click',function(event){if(event.target===el('ec-dialog')){var rect=el('ec-dialog').getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)closeForm();}});
  if(location.hash.split('/')[0]==='#economy'||localStorage.getItem('pdd-admin-feature')==='economy')loadEconomy();
 }
 window.loadEconomy=loadEconomy;if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();`;
