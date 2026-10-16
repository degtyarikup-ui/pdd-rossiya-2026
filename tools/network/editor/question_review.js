// First-pass question selection. This never edits a scene or enables it in the game.
// Integration: mount #question-review, load after App.loadList(), route via App.showQuestions().
// The editor can suppress its shortcuts while active(); this module owns review shortcuts.
const QuestionReview = (() => {
  const { state, esc, ic } = App;
  const $ = selector => document.querySelector(selector);
  const STORE = 'network-editor-question-review';
  // Statuses come from the server (question_pool.py): game, ai (awaiting approval), plan.
  const FILTERS = [['game', 'В игре'], ['plan', 'Не в игре'], ['ai', 'Реализовано ИИ']];
  let filter = 'plan', query = '', selected = null, shown = false, loading = null;
  let busy = false, editing = false, error = '', saved = '', history = [], imageZoom = false;
  let trail = [], trailIndex = -1, mode = 'review';
  state.questions = state.questions || [];
  state.questionsLoaded = false;
  try {
    const preference = JSON.parse(localStorage.getItem(STORE) || '{}');
    if (FILTERS.some(([key]) => key === preference.filter)) filter = preference.filter;
  } catch (_) { /* The server keeps decisions even without browser storage. */ }
  const pool = () => state.questions || [];
  // Questions sorted as "не добавляем" leave the stand; their decision stays on the server for undo.
  const kept = () => pool().filter(question => question.decision !== 'no');
  const current = () => pool().find(question => question.id === selected);
  const title = question => `Билет ${question.ticket} · вопрос ${question.number}`;
  const category = question => (question.categories || [question.category]).filter(Boolean).map(key => ({ab:'A/B',cd:'C/D'}[key] || key)).join(' · ');
  const normalized = value => String(value || '').toLowerCase().replace(/ё/g, 'е').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  function matches(question, text = query) {
    const needle = normalized(text);
    if (!needle) return true;
    const references = (question.occurrences || []).map(item => `${item.id} Билет ${item.ticket} вопрос ${item.number}`).join(' ');
    const haystack = normalized([question.id, title(question), category(question), question.question, references].join(' '));
    return needle.split(' ').every(word => haystack.includes(word));
  }
  function list(text = query) {
    return kept().filter(question => matches(question, text) && question.status === filter);
  }
  const count = key => kept().filter(question => question.status === key).length;
  function badge(question) {
    if (question.status === 'game') return '<i class="badge good">В игре</i>';
    if (question.status === 'ai') return '<i class="badge ai">Реализовано ИИ</i>';
    return question.decision === 'yes' ? '<i class="badge good">Реализуем</i>' : '<i class="badge">Не просмотрен</i>';
  }
  function photo(question, cls = '', lazy = true) {
    return question.imageUrl ? `<img class="${cls}" src="${esc(question.imageUrl)}" alt="Иллюстрация к вопросу" ${lazy ? 'loading="lazy"' : ''}>` : `<span class="qr-no-photo ${cls}">${ic('image')}<span>Без иллюстрации</span></span>`;
  }
  function filterHtml() {
    return `<label class="scene-status-filter question-filters">Показать вопросы<select data-question-status aria-label="Показать вопросы" ${busy ? 'disabled' : ''}>${FILTERS.map(([key, label]) => `<option value="${key}" ${filter === key ? 'selected' : ''}>${label} · ${count(key)}</option>`).join('')}</select></label>`;
  }
  function sidebarHtml(text = query, { filtersCollapsed = false } = {}) {
    if (!state.questionsLoaded) return `<div class="question-pane-tools"><p class="muted">${error ? esc(error) : 'Загружаем вопросы из билетов…'}</p>${error ? '<button class="btn wide" data-qr="retry">Повторить загрузку</button>' : ''}</div>`;
    const items = list(text);
    return `<div class="question-pane-tools"><div id="question-filter-options" ${filtersCollapsed ? 'hidden' : ''}>${filterHtml()}</div></div>
      <div class="scene-list question-list">${items.map(question => `<button class="scene-row ${question.id === selected ? 'on' : ''}" data-question="${esc(question.id)}" aria-label="${esc(title(question))}"><span class="scene-pic question-pic">${photo(question)}</span><span class="scene-text"><b>${esc(title(question))}</b><span class="badges">${badge(question)}</span></span></button>`).join('') || '<p class="empty-note">В этой группе вопросов нет</p>'}</div>`;
  }
  function homeHtml(text = query) {
    return `<div class="question-home-tools">${filterHtml()}<button class="btn primary" data-qr="start">${ic('play')}Открыть вопросы для отбора</button></div><div class="home-grid">${list(text).map(question => `<button class="card-scene" data-question="${esc(question.id)}"><span class="card-pic question-card-pic">${photo(question)}</span><span class="card-body"><b>${esc(title(question))} · ${esc(category(question))}</b><span class="question-card-text">${esc(question.question)}</span><span class="badges">${badge(question)}</span></span></button>`).join('') || '<p class="empty-note">В этой группе вопросов нет</p>'}</div>`;
  }
  function remember() {
    try { localStorage.setItem(STORE, JSON.stringify({ filter })); } catch (_) { /* Optional view preference. */ }
  }
  function updateLocation() {
    if (!shown) return;
    const params = new URLSearchParams({ filter: 'questions' });
    if (selected) params.set('question', selected);
    window.history.replaceState(null, '', `?${params}`);
  }
  function refreshPanels() {
    App.renderPanels?.({ only: ['left'] });
    if (!$('#home-screen').hidden) App.renderHome?.();
  }
  function refresh() { render(); refreshPanels(); }
  async function load({ refresh: reload = false } = {}) {
    if (loading) {
      if (!reload) return loading;
      // A refresh can follow a scene save/promotion newer than the current GET.
      // Wait, then request again; reusing that response could resurrect the candidate.
      await loading.catch(() => {});
      return load({ refresh: true });
    }
    if (state.questionsLoaded && !reload) return pool();
    error = '';
    loading = App.api('/api/questions').then(data => {
      state.questions = data.questions || [];
      state.questionsLoaded = true;
      if (!pool().some(question => question.id === selected)) selected = null;
      refresh();
      return pool();
    }).catch(reason => {
      error = `Не удалось загрузить вопросы: ${reason.message}`;
      refresh();
      throw reason;
    }).finally(() => { loading = null; });
    render();
    return loading;
  }
  function setSelected(id) {
    selected = id || null;
    if (trail[trailIndex] !== selected) { trail = trail.slice(0, trailIndex + 1); trail.push(selected); trailIndex = trail.length - 1; }
  }
  function choose(id) {
    setSelected(id);
    imageZoom = false;
    error = '';
    saved = '';
    updateLocation();
    render();
    refreshPanels();
  }
  async function open(id) {
    if (busy || editing) return;
    shown = true;
    mode = 'review';
    document.body.classList.add('question-reviewing');
    $('#question-review').hidden = false;
    App.showHome(false);
    render();
    try { await load(); } catch (_) { return; }
    const requested = id && pool().find(question => question.id === id);
    if (requested && !list().includes(requested)) { filter = requested.status || 'plan'; remember(); }
    const keep = list().find(question => question.id === selected);
    choose(requested?.id || keep?.id || (list().find(question => !question.decision) || list()[0])?.id);
  }
  function close() {
    if (!shown) return;
    shown = false;
    imageZoom = false;
    $('#question-review').hidden = true;
    document.body.classList.remove('question-reviewing');
    if (new URLSearchParams(location.search).get('filter') === 'questions') window.history.replaceState(null, '', state.id ? `?scene=${state.id}` : '?filter=all');
    if (!state.S) App.showHome(true);
  }
  function navigate(step) {
    if (busy) return;
    if (step < 0 || trailIndex < trail.length - 1) {
      const index = trailIndex + step;
      if (index >= 0 && index < trail.length) {
        trailIndex = index; selected = trail[index]; imageZoom = false; error = ''; saved = ''; updateLocation(); refresh();
      }
      return;
    }
    const visible = list(), index = visible.findIndex(question => question.id === selected);
    const next = visible[index + step];
    if (next) choose(next.id);
  }
  function nextAfter(id, candidates) {
    const all = pool(), previous = all.findIndex(question => question.id === id);
    return candidates.find(question => all.indexOf(question) > previous) || candidates[0];
  }
  async function decide(decision) {
    const question = current();
    // Questions already in the game or waiting for AI approval have no plan decision.
    if (busy || !question || question.status !== 'plan' || !['yes', 'no'].includes(decision)) return;
    const id = question.id, before = question.decision || null;
    busy = true; error = ''; saved = '';
    render();
    try {
      const response = await App.api(`/api/questions/${encodeURIComponent(id)}/decision`, { decision });
      const record = response.question || response;
      const updated = { ...question, ...record, decision };
      state.questions = pool().map(item => item.id === id ? updated : item);
      if (before !== decision) history.push({ id, before, after: decision });
      saved = `${title(question)}: ${decision === 'yes' ? 'реализуем' : 'не добавляем'} · сохранено`;
      const candidates = list().filter(item => item.id !== id);
      const undecided = candidates.filter(item => !item.decision);
      setSelected(nextAfter(id, undecided.length ? undecided : candidates)?.id);
      imageZoom = false;
      updateLocation();
    } catch (reason) {
      error = `Решение не сохранено: ${reason.message}. Попробуйте ещё раз.`;
    } finally { busy = false; refresh(); }
  }
  async function undo() {
    if (busy || !history.length) return;
    const previous = history[history.length - 1], question = pool().find(item => item.id === previous.id);
    if (!question) return;
    busy = true; error = ''; saved = '';
    render();
    try {
      const response = await App.api(`/api/questions/${encodeURIComponent(previous.id)}/decision`, { decision: previous.before });
      const record = response.question || response;
      state.questions = pool().map(item => item.id === previous.id ? { ...item, ...record, decision: previous.before } : item);
      history.pop();
      // A question sorted "no" is hidden; undo must bring it back into the group it belongs to.
      filter = pool().find(item => item.id === previous.id)?.status || 'plan';
      remember();
      setSelected(previous.id);
      saved = 'Последнее решение отменено · сохранено';
      updateLocation();
    } catch (reason) { error = `Не удалось отменить решение: ${reason.message}`; }
    finally { busy = false; refresh(); }
  }
  async function openEditor(candidateId) {
    if (busy || editing) return;
    const id = candidateId || selected || list()[0]?.id;
    if (!id) return;
    editing = true;
    render();
    try {
      await App.openScene(id);
      if (state.id === id) { mode = 'editor'; selected = id; close(); refreshPanels(); }
    } catch (reason) { error = `Не удалось открыть сцену: ${reason.message}`; if (!shown) App.toast(error, 'bad'); }
    finally { editing = false; render(); }
  }
  function render() {
    if (!shown) return;
    const mount = $('#question-review');
    if (!mount) return;
    const question = current(), visible = list();
    const index = visible.findIndex(item => item.id === selected);
    const disabled = busy || editing ? 'disabled' : '';
    // Only plan questions take a decision; game and AI questions are handled elsewhere.
    const decidable = Boolean(question && question.status === 'plan');
    // A road question already in the game has no ticket scene to build or edit.
    const editable = Boolean(question && (question.hasScene || question.status !== 'game'));
    const total = Math.max(1, kept().length);
    mount.innerHTML = `<header class="qr-head"><div><span class="qr-eyebrow">ВОПРОСЫ ДЛЯ ИГРЫ</span><h1>${question ? esc(title(question)) : 'Отбор вопросов'}</h1>${question ? `<p>${esc(category(question))} ${badge(question)}</p>` : ''}</div>
      <div class="qr-mode"><button class="btn primary" data-qr="editor" ${!editable || disabled ? 'disabled' : ''} title="${editable ? '' : 'Дорожный вопрос уже в игре: отдельной сцены в редакторе нет'}">${ic('cursor')}${editing ? 'Открываем…' : 'Открыть в редакторе'}</button><button class="icon-btn" data-qr="close" aria-label="Вернуться к текущей сцене" ${disabled}>${ic('x')}</button></div></header>
      <div class="qr-progress"><span><b>${count('game')}</b> из ${kept().length} в игре</span><progress max="${total}" value="${count('game')}" aria-label="Вопросы в игре"></progress><span>${count('ai')} реализовано ИИ · ${count('plan')} не в игре</span></div>
      ${error ? `<div class="qr-error" role="alert">${ic('alert')}<span>${esc(error)}</span>${!state.questionsLoaded ? '<button class="btn" data-qr="retry">Повторить</button>' : ''}</div>` : ''}
      <div class="qr-scroll">${!state.questionsLoaded ? `<div class="qr-empty"><h2>${error ? 'Вопросы не загружены' : 'Загружаем экзаменационные билеты…'}</h2></div>` : question ? `<article class="qr-card"><div class="qr-photo">${question.imageUrl ? `<button data-qr="zoom" aria-label="Увеличить иллюстрацию">${photo(question, '', false)}<span class="qr-zoom-hint">${ic('zoomin')}Увеличить</span></button>` : photo(question)}</div><div class="qr-question"><h2>${esc(question.question)}</h2><ol class="qr-answers">${(question.answers || []).map(answer => `<li class="${answer.correct ? 'correct' : ''}"><span>${esc(answer.text)}</span>${answer.correct ? `<span class="qr-correct">${ic('check-circle')}Верный ответ</span>` : ''}</li>`).join('')}</ol>${question.comment ? `<details class="qr-comment"><summary>Пояснение к вопросу</summary><div>${esc(question.comment).replace(/\n/g, '<br>')}</div></details>` : ''}</div></article>` : `<div class="qr-empty">${ic('check-circle')}<h2>В этой группе вопросов нет</h2><p>${query ? 'Измените поиск или выберите другую группу слева.' : 'Выберите другую группу слева, чтобы посмотреть остальные вопросы.'}</p><div>${filterHtml()}</div></div>`}</div>
      <footer class="qr-foot"><div class="qr-feedback" role="status">${busy ? 'Сохраняем решение…' : saved ? esc(saved) : !question ? '' : question.status === 'game' ? 'Вопрос уже в игре.' : question.status === 'ai' ? 'Вариант ИИ ждёт одобрения в разделе «На одобрение».' : '«Да» — запланировать сцену. «Нет» — исключить из планов.'}</div><div class="qr-actions"><button class="qr-decision no" data-qr="no" ${!decidable || disabled ? 'disabled' : ''}>${ic('x')}Нет — не добавляем<kbd>←</kbd></button><button class="qr-decision yes" data-qr="yes" ${!decidable || disabled ? 'disabled' : ''}>${ic('check-circle')}Да — реализуем<kbd>→</kbd></button></div><div class="qr-navigation"><button class="btn ghost" data-qr="previous" ${trailIndex <= 0 || disabled ? 'disabled' : ''}>${ic('chevron', 'qr-back')}Предыдущий</button><button class="btn ghost" data-qr="undo" ${!history.length || disabled ? 'disabled' : ''}>${ic('undo')}Отменить решение</button><button class="btn ghost" data-qr="next" ${(trailIndex >= trail.length - 1 && (index < 0 && !visible.length || index >= visible.length - 1)) || disabled ? 'disabled' : ''}>Пропустить${ic('chevron')}</button></div></footer>
      ${imageZoom && question?.imageUrl ? `<div class="qr-lightbox" role="dialog" aria-modal="true" aria-label="Иллюстрация к вопросу" data-qr="zoom-close"><button class="icon-btn" data-qr="zoom-close" aria-label="Закрыть иллюстрацию">${ic('x')}</button>${photo(question, '', false)}</div>` : ''}`;
  }
  function setQuery(value) {
    query = value;
    if (shown) {
      const visible = list();
      if (!visible.some(question => question.id === selected)) { setSelected(visible[0]?.id); updateLocation(); }
      render();
    }
  }
  function setFilter(value) {
    if (busy || !FILTERS.some(([key]) => key === value)) return;
    filter = value;
    remember();
    choose(list().find(question => question.id === selected)?.id || list()[0]?.id);
    refreshPanels();
  }
  function keydown(event) {
    if (!shown || !$('#home-screen').hidden || event.defaultPrevented || !$('#confirm')?.hidden || !$('#keys')?.hidden) return;
    const target = event.target;
    if (target && (['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName) || target.isContentEditable)) return;
    const key = event.key.toLowerCase();
    if (key === 'escape') { event.preventDefault(); event.stopImmediatePropagation(); if (imageZoom) { imageZoom = false; render(); } else close(); return; }
    if (event.repeat || busy || editing || imageZoom || event.altKey) return;
    const command = event.metaKey || event.ctrlKey;
    let action;
    if (command && !event.shiftKey && key === 'z') action = undo;
    else if (!command && !event.shiftKey && ['arrowleft', 'n', 'т'].includes(key)) action = () => decide('no');
    else if (!command && !event.shiftKey && ['arrowright', 'y', 'н'].includes(key)) action = () => decide('yes');
    else if (!command && key === 'arrowup') action = () => navigate(-1);
    else if (!command && key === 'arrowdown') action = () => navigate(1);
    if (action) { event.preventDefault(); event.stopImmediatePropagation(); action(); }
  }
  document.addEventListener('keydown', keydown, true);
  document.addEventListener('change', event => {
    if (event.target.matches?.('[data-question-status]')) setFilter(event.target.value);
  });
  document.addEventListener('click', event => {
    const candidate = event.target.closest('[data-question]');
    if (candidate) {
      if (!busy) {
        App.showQuestions(candidate.dataset.question);
      }
      return;
    }
    const change = event.target.closest('[data-qfilter]');
    if (change) { setFilter(change.dataset.qfilter); return; }
    const button = event.target.closest('[data-qr]');
    if (!button || button.disabled) return;
    const action = button.dataset.qr;
    if (action === 'start') { App.showQuestions(); return; }
    if (action === 'editor-mode') { openEditor(); return; }
    if (action === 'retry') { load({ refresh: true }).then(() => { if (shown) choose(list()[0]?.id); }).catch(() => {}); return; }
    if (!shown) return;
    if (action === 'close') close();
    else if (action === 'yes' || action === 'no') decide(action);
    else if (action === 'undo') undo();
    else if (action === 'previous') navigate(-1);
    else if (action === 'next') navigate(1);
    else if (action === 'editor') openEditor();
    else if (action === 'zoom' || action === 'zoom-close') { imageZoom = action === 'zoom'; render(); }
  });
  return { load, open, close, active: () => shown, keydown, currentId: () => selected, refresh,
    sidebarHtml, homeHtml, setQuery, setFilter, list, count, visibleCount: () => kept().length, mode: () => mode,
    filterSummary: text => ({ label: FILTERS.find(([key]) => key === filter)[1], count: list(text).length }) };
})();
