import { AI_MODELS, AI_DEFAULT_MODEL } from './ai_models.js';

// Раздел «ИИ»: разметка и клиент поверх исторической оболочки админки.
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
  <div style="display:flex;align-items:center;justify-content:space-between">
   <span class="ai-kpi-label">Текущая модель</span>
   <span style="display:inline-flex;align-items:center;opacity:0.9" title="Google Gemini">
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z" fill="#FBBC05"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z" fill="#EA4335"/></svg>
   </span>
  </div>
  <div class="ai-kpi-value ai-kpi-model" id="ai-m-model">—</div>
  <div class="ai-kpi-footer"><span>Провайдер: <b>Google AI Studio</b></span></div>
 </div>
</div>
<div class="ai-workspace">
 <section class="ai-card" aria-labelledby="ai-model-title">
  <div class="ai-card-head">
   <h2 class="ai-card-title" id="ai-model-title" style="display:flex;align-items:center;gap:8px">
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z" fill="#FBBC05"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z" fill="#EA4335"/></svg>
    Google Gemini
   </h2>
   <span style="font-size:11px;font-weight:600;color:var(--text-muted);background:#F4F5F7;padding:4px 9px;border-radius:8px">Google AI</span>
  </div>
  <div class="ai-field">
   <label class="ai-field-label" for="ai-model-select">Модель для разбора вопросов</label>
   <select id="ai-model-select" class="ai-input">
    ${Object.entries(AI_MODELS).map(([id, model]) => `<option value="${id}">${model.name}</option>`).join('\n    ')}
   </select>
   <div class="ai-scope" id="ai-model-description" aria-live="polite">${AI_MODELS[AI_DEFAULT_MODEL].description}</div>
  </div>
  <div class="ai-model-actions"><button type="button" class="btn-action btn-primary" id="save-ai-model-btn">Применить модель</button></div>
  <details class="ai-scope admin-disclosure"><summary>Область применения</summary><p>Выбранная модель применяется сразу для всех пользователей приложения.</p></details>
 </section>
 <section class="ai-card" aria-labelledby="ai-test-title">
  <div class="ai-card-head"><h2 class="ai-card-title" id="ai-test-title">Проверка ответа</h2></div>
  <div class="ai-test-inputs">
   <div class="ai-field"><label class="ai-field-label" for="ai-test-prompt">Вопрос</label><input type="text" id="ai-test-prompt" class="ai-input" placeholder="Вопрос по ПДД" value="Разрешен ли разворот на пешеходном переходе?"></div>
   <button type="button" class="btn-action btn-primary" id="ai-test-send-btn">Проверить модель</button>
  </div>
  <div id="ai-test-result-box" class="ai-response" role="status" aria-live="polite">Проверка использует выбранную модель. Для всех пользователей она изменится после нажатия «Применить модель».</div>
 </section>
</div>
</div>
`;

export const AI_CLIENT_JS = String.raw`
let aiAvailableModels = [];
function updateAiModelDescription() {
  const model = aiAvailableModels.find(m => m.id === document.getElementById('ai-model-select').value);
  document.getElementById('ai-model-description').textContent = model
    ? model.description + '. Вход: ' + model.inputPrice + ', выход (включая размышления): ' + model.outputPrice + ' токенов.' : '';
}
async function loadAiStats() {
  try {
    const res = await fetch('/api/admin/ai/stats');
    if (res.status === 401) { checkAuthAndLoad(); return; }
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error('Не удалось загрузить настройки ИИ');
    const s = data.stats;
    document.getElementById('ai-m-total').innerText = (s.totalRequests || 0).toLocaleString();
    document.getElementById('ai-m-today').innerText = (s.todayRequests || 0).toLocaleString();
    document.getElementById('ai-m-cost-usd').innerText = '$' + (s.costUsd || 0).toFixed(5);
    document.getElementById('ai-m-cost-rub').innerText = '~' + (s.costRub || 0) + ' ₽';
    document.getElementById('ai-m-tokens-total').innerText = (s.totalTokens || 0).toLocaleString();
    document.getElementById('ai-m-tokens-k').innerText = Math.round((s.totalTokens || 0) / 1000) + 'k';
    document.getElementById('ai-m-tokens-prompt').innerText = (s.promptTokens || 0).toLocaleString();
    document.getElementById('ai-m-tokens-cand').innerText = (s.candidateTokens || 0).toLocaleString();
    document.getElementById('ai-m-model').innerText = s.activeModelName || s.activeModel;
    aiAvailableModels = s.availableModels || [];
    document.getElementById('ai-model-select').value = s.activeModel;
    updateAiModelDescription();
  } catch (err) { console.error('loadAiStats error:', err); }
}
document.getElementById('ai-model-select').addEventListener('change', updateAiModelDescription);
document.getElementById('save-ai-model-btn').addEventListener('click', async function() {
  this.disabled = true;
  this.innerText = 'Сохранение...';
  try {
    const res = await fetch('/api/admin/ai/config', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ model: document.getElementById('ai-model-select').value })
    });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.error || 'Не удалось сохранить модель');
    await loadAiStats();
    this.innerText = 'Применено!';
  } catch (error) {
    alert('Ошибка сохранения: ' + error.message);
  } finally {
    this.disabled = false;
    setTimeout(() => { this.innerText = 'Применить модель'; }, 2000);
  }
});
document.getElementById('ai-test-send-btn').addEventListener('click', async function() {
  const prompt = document.getElementById('ai-test-prompt').value.trim();
  if (!prompt) return;
  const model = document.getElementById('ai-model-select').value;
  const name = aiAvailableModels.find(m => m.id === model)?.name || model;
  const box = document.getElementById('ai-test-result-box');
  this.disabled = true;
  this.innerText = 'Думает...';
  box.innerText = 'Проверяем ' + name + '…';
  try {
    const res = await fetch('/api/admin/ai/test', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ prompt, model })
    });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.error === 'ai_unavailable'
      ? 'Модель сейчас недоступна или не успела ответить. Попробуйте ещё раз.'
      : data.error || 'Не удалось получить ответ');
    box.innerText = name + '\n\n' + data.reply;
  } catch (error) { box.innerText = 'Ошибка: ' + error.message; }
  finally { this.disabled = false; this.innerText = 'Проверить модель'; }
});
`;

export function enhanceAiClientJs(source) {
  const start = source.indexOf('async function loadAiStats()');
  if (start === -1) throw new Error('Legacy AI client boundary missing');
  return source.slice(0, start) + AI_CLIENT_JS;
}
