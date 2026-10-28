// Saved question backlog. Selecting a question opens its scene through the normal
// editor flow, including the confirmation for unsaved work. Legacy decisions are read only.
const QuestionPlan = (() => {
  const { state, esc, ic } = App;
  const STORE = 'network-editor-question-review';
  const FILTERS = [['game', 'В игре'], ['plan', 'Не в игре'], ['ai', 'Реализовано ИИ']];
  let filter = 'plan', query = '', loading = null, opening = false, error = '';
  state.questions = state.questions || [];
  state.questionsLoaded = false;
  try {
    const preference = JSON.parse(localStorage.getItem(STORE) || '{}');
    if (FILTERS.some(([key]) => key === preference.filter)) filter = preference.filter;
  } catch (_) { /* Optional view preference. */ }
  const pool = () => state.questions || [];
  // Preserve every selected question and existing scene. Unsorted questions no
  // longer form a review queue; their original records remain on the server.
  const kept = () => pool().filter(question => question.decision === 'yes' || question.hasScene || question.status !== 'plan');
  const title = question => `Билет ${question.ticket} · вопрос ${question.number}`;
  const category = question => (question.categories || [question.category]).filter(Boolean).map(key => ({ab:'A/B',cd:'C/D'}[key] || key)).join(' · ');
  const normalized = value => String(value || '').toLowerCase().replace(/ё/g, 'е').replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  function matches(question, text) {
    const needle = normalized(text);
    if (!needle) return true;
    const references = (question.occurrences || []).map(item => `${item.id} Билет ${item.ticket} вопрос ${item.number}`).join(' ');
    const haystack = normalized([question.id, title(question), category(question), question.question, references].join(' '));
    return needle.split(' ').every(word => haystack.includes(word));
  }
  const list = (text = query) => kept().filter(question => matches(question, text) && question.status === filter);
  const count = key => kept().filter(question => question.status === key).length;
  function badge(question) {
    if (question.status === 'game') return '<i class="badge good">В игре</i>';
    if (question.status === 'ai') return '<i class="badge ai">Реализовано ИИ</i>';
    return '<i class="badge good">Реализуем</i>';
  }
  function photo(question) {
    return question.imageUrl ? `<img src="${esc(question.imageUrl)}" alt="Иллюстрация к вопросу" loading="lazy">` : `<span class="question-no-photo">${ic('image')}</span>`;
  }
  // Road questions already handled by the game have no editable ticket scene.
  const editable = question => question.hasScene || question.status !== 'game';
  function filterHtml() {
    return `<label class="scene-status-filter question-filters">Показать вопросы<select data-question-status aria-label="Показать вопросы">${FILTERS.map(([key, label]) => `<option value="${key}" ${filter === key ? 'selected' : ''}>${label} · ${count(key)}</option>`).join('')}</select></label>`;
  }
  function loadingHtml() {
    return `<div class="question-pane-tools"><p class="muted" role="status">${error ? esc(error) : 'Загружаем вопросы из билетов…'}</p>${error ? '<button class="btn wide" data-question-retry>Повторить загрузку</button>' : ''}</div>`;
  }
  function sidebarHtml(text = query, { filtersCollapsed = false } = {}) {
    if (!state.questionsLoaded) return loadingHtml();
    return `<div class="question-pane-tools"><div id="question-filter-options" ${filtersCollapsed ? 'hidden' : ''}>${filterHtml()}</div></div>
      <div class="scene-list question-list">${list(text).map(question => `<button class="scene-row ${question.id === state.id ? 'on' : ''}" data-plan-question="${esc(question.id)}" aria-label="${esc(title(question))}" ${editable(question) ? '' : 'disabled title="Дорожный вопрос уже в игре: отдельной сцены в редакторе нет"'}><span class="scene-pic question-pic">${photo(question)}</span><span class="scene-text"><b>${esc(title(question))}</b><span class="badges">${badge(question)}</span></span></button>`).join('') || '<p class="empty-note">В этой группе вопросов нет</p>'}</div>`;
  }
  function homeHtml(text = query) {
    if (!state.questionsLoaded) return loadingHtml();
    return `<div class="question-home-tools">${filterHtml()}</div><div class="home-grid">${list(text).map(question => `<button class="card-scene" data-plan-question="${esc(question.id)}" ${editable(question) ? '' : 'disabled title="Дорожный вопрос уже в игре: отдельной сцены в редакторе нет"'}><span class="card-pic question-card-pic">${photo(question)}</span><span class="card-body"><b>${esc(title(question))} · ${esc(category(question))}</b><span class="question-card-text">${esc(question.question)}</span><span class="badges">${badge(question)}</span></span></button>`).join('') || '<p class="empty-note">В этой группе вопросов нет</p>'}</div>`;
  }
  function remember() {
    try { localStorage.setItem(STORE, JSON.stringify({ filter })); } catch (_) { /* Optional view preference. */ }
  }
  function refresh() {
    App.renderPanels?.({ only: ['left'] });
    if (!document.querySelector('#home-screen').hidden) App.renderHome?.();
  }
  async function load({ refresh: reload = false } = {}) {
    if (loading) {
      if (!reload) return loading;
      // A save/promotion can be newer than the pending GET. Fetch again afterward.
      await loading.catch(() => {});
      return load({ refresh: true });
    }
    if (state.questionsLoaded && !reload) return pool();
    error = '';
    loading = App.api('/api/questions').then(data => {
      state.questions = data.questions || [];
      state.questionsLoaded = true;
      refresh();
      return pool();
    }).catch(reason => {
      error = `Не удалось загрузить вопросы: ${reason.message}`;
      refresh();
      throw reason;
    }).finally(() => { loading = null; });
    return loading;
  }
  async function open(id) {
    if (opening) return;
    opening = true;
    try {
      await load();
      if (!id) {
        App.showHome(true);
        window.history.replaceState(null, '', '?filter=questions');
        return;
      }
      const question = pool().find(item => item.id === id);
      if (!question || !editable(question)) { App.showHome(true); return; }
      await App.openScene(id);
      if (state.id === id) { filter = question.status; remember(); refresh(); }
    } catch (reason) {
      if (!state.S) App.showHome(true);
      App.toast(reason.message, 'bad');
    }
    finally { opening = false; }
  }
  function setFilter(value) {
    if (!FILTERS.some(([key]) => key === value)) return;
    filter = value;
    remember();
    refresh();
  }
  document.addEventListener('change', event => {
    if (event.target.matches?.('[data-question-status]')) setFilter(event.target.value);
  });
  document.addEventListener('click', event => {
    const candidate = event.target.closest('[data-plan-question]');
    if (candidate) {
      if (!candidate.disabled) App.showQuestions(candidate.dataset.planQuestion);
      return;
    }
    if (event.target.closest('[data-question-retry]')) load({ refresh: true }).catch(() => {});
  });
  return { load, open, refresh, sidebarHtml, homeHtml, setQuery: value => { query = value; }, setFilter,
    list, count, visibleCount: () => kept().length,
    filterSummary: text => ({ label: FILTERS.find(([key]) => key === filter)[1], count: list(text).length }) };
})();
