// Раздел «ИИ»: отдельная разметка поверх существующего клиента и API.
// Все управляющие ID и значения моделей сохранены из legacy admin HTML.
export const AI_VIEW_HTML = String.raw`
<div id="ai-view" style="display:none;">
<style>
.ai-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;margin-bottom:18px}
.ai-kpi,.ai-card{min-width:0;background:#fff;border:0;border-radius:20px;padding:24px;box-shadow:none}
.ai-kpi{display:flex;flex-direction:column;gap:16px;min-height:166px}
.ai-kpi-label{font-size:12px;font-weight:500;color:var(--text-muted,#747B88);line-height:1.4}
.ai-kpi-value{font-size:36px;line-height:1.1;letter-spacing:-1.4px;font-weight:550;color:var(--text,#17191E);font-variant-numeric:tabular-nums;overflow-wrap:anywhere}
.ai-kpi-model{font-size:23px;line-height:1.25;letter-spacing:-.6px}
.ai-kpi-footer{font-size:11px;line-height:1.7;color:var(--text-muted,#747B88);margin-top:auto;display:flex;flex-wrap:wrap;gap:4px 10px}
.ai-kpi-footer b{font-weight:550;color:var(--text,#17191E);font-variant-numeric:tabular-nums}
.ai-kpi-highlight{background:#0574F8}.ai-kpi-highlight .ai-kpi-value,.ai-kpi-highlight .ai-kpi-footer b{color:white}.ai-kpi-highlight .ai-kpi-label,.ai-kpi-highlight .ai-kpi-footer{color:#d4e8ff}
.ai-workspace{display:grid;grid-template-columns:minmax(280px,.7fr) minmax(0,1.3fr);gap:18px;align-items:start}
.ai-card-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:24px}
.ai-card-title{font-size:16px;font-weight:650;letter-spacing:-.35px;color:var(--text,#17191E);margin:0}
.ai-field{display:flex;flex-direction:column;gap:10px;min-width:0}
.ai-field-label{font-size:12px;font-weight:500;color:var(--text-muted,#747B88)}
.ai-input{width:100%;min-width:0;border:0;border-radius:12px;background:#F4F5F7;padding:13px 14px;font-size:13px;line-height:1.5;color:var(--text,#17191E);outline-color:#0574F8;box-sizing:border-box}
.ai-model-actions{display:flex;justify-content:flex-end;margin-top:18px}
.ai-test-inputs{display:flex;gap:10px;align-items:end;margin-bottom:20px}.ai-test-inputs .ai-field{flex:1}.ai-test-inputs button{flex-shrink:0;min-height:45px}
.ai-response{background:#F4F5F7;border:0;border-radius:14px;padding:18px;font-size:13px;line-height:1.7;color:var(--text,#17191E);min-height:128px;max-height:560px;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere}
.ai-scope{font-size:11px;color:var(--text-muted,#747B88);margin-top:18px;line-height:1.6}.ai-scope summary{cursor:pointer;width:fit-content;list-style:none;display:flex;gap:8px;align-items:center}.ai-scope summary::-webkit-details-marker{display:none}.ai-scope summary:after{content:'+';font-size:16px;line-height:1}.ai-scope[open] summary:after{content:'−'}.ai-scope p{margin:10px 0 0;max-width:320px}
.ai-input:focus-visible,.ai-scope summary:focus-visible{outline:2px solid #0574F8;outline-offset:3px}
@media(max-width:1120px){.ai-kpi{padding:20px}.ai-kpi-value{font-size:32px}.ai-kpi-model{font-size:21px}.ai-workspace{grid-template-columns:1fr}.ai-model-actions{justify-content:flex-start}}
@media(max-width:900px){.ai-kpis{grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}}
@media(max-width:640px){.ai-kpi,.ai-card{padding:20px;border-radius:18px}.ai-test-inputs{flex-direction:column;align-items:stretch}.ai-test-inputs button{align-self:flex-start}.ai-test-inputs .ai-field{width:100%}.ai-kpi-value{font-size:30px}.ai-kpi-model{font-size:21px}.ai-card-head{margin-bottom:20px}}
@media(max-width:420px){.ai-kpis{grid-template-columns:1fr}.ai-kpi{min-height:145px}.ai-model-actions button,.ai-test-inputs button{width:100%;justify-content:center}.ai-model-actions{display:block}}
</style>
<div class="ai-kpis">
 <div class="ai-kpi ai-kpi-highlight">
  <span class="ai-kpi-label">Запросы к ИИ</span>
  <div class="ai-kpi-value" id="ai-m-total">0</div>
  <div class="ai-kpi-footer"><span>Сегодня <b id="ai-m-today">0</b></span></div>
 </div>
 <div class="ai-kpi">
  <span class="ai-kpi-label">Расходы</span>
  <div class="ai-kpi-value" id="ai-m-cost-usd">$0.00000</div>
  <div class="ai-kpi-footer"><span id="ai-m-cost-rub">~0.00 ₽</span></div>
 </div>
 <div class="ai-kpi">
  <span class="ai-kpi-label">Токены</span>
  <div class="ai-kpi-value" id="ai-m-tokens-k">0k</div>
  <div class="ai-kpi-footer"><span>Всего <b id="ai-m-tokens-total">0</b></span><span>Вход <b id="ai-m-tokens-prompt">0</b></span><span>Выход <b id="ai-m-tokens-cand">0</b></span></div>
 </div>
 <div class="ai-kpi">
  <span class="ai-kpi-label">Текущая модель</span>
  <div class="ai-kpi-value ai-kpi-model" id="ai-m-model">—</div>
 </div>
</div>
<div class="ai-workspace">
 <section class="ai-card" aria-labelledby="ai-model-title">
  <div class="ai-card-head"><h2 class="ai-card-title" id="ai-model-title">Модель</h2></div>
  <div class="ai-field">
   <label class="ai-field-label" for="ai-model-select">Модель для разбора вопросов</label>
   <select id="ai-model-select" class="ai-input">
    <option value="gemini-3.6-flash">Gemini 3.6 Flash</option>
    <option value="gemini-2.5-flash">Gemini 2.5 Flash</option>
    <option value="gemini-1.5-flash">Gemini 1.5 Flash</option>
    <option value="gemini-2.5-pro">Gemini 2.5 Pro</option>
   </select>
  </div>
  <div class="ai-model-actions"><button type="button" class="btn-action btn-primary" id="save-ai-model-btn">Применить модель</button></div>
  <details class="ai-scope admin-disclosure"><summary>Область применения</summary><p>Выбранная модель применяется сразу для всех пользователей приложения.</p></details>
 </section>
 <section class="ai-card" aria-labelledby="ai-test-title">
  <div class="ai-card-head"><h2 class="ai-card-title" id="ai-test-title">Проверка ответа</h2></div>
  <div class="ai-test-inputs">
   <div class="ai-field"><label class="ai-field-label" for="ai-test-prompt">Вопрос</label><input type="text" id="ai-test-prompt" class="ai-input" placeholder="Вопрос по ПДД" value="Разрешен ли разворот на пешеходном переходе?"></div>
   <button type="button" class="btn-action btn-primary" id="ai-test-send-btn">Отправить</button>
  </div>
  <div id="ai-test-result-box" class="ai-response" role="status" aria-live="polite">Ответ появится здесь</div>
 </section>
</div>
</div>
`;
