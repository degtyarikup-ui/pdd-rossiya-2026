// Answer letters share one namespace whether they have a route or stand alone.
const AnswerMark = (() => {
  const modes = [['answer', 'Ответ', 'Линия или стрелка с буквой'], ['annotation', 'Линия', 'Обозначение без буквы'], ['letter', 'Буква', 'Кружок в любом месте'], ['text', 'Текст', 'Свободная надпись на сцене']];
  const free = (scene, except) => Catalog.LETTERS.filter(l => !scene.routes.some(r => r.kind === 'choice' && r !== except && r.label === l));
  const position = r => r.labelPosition || r.points?.[Math.floor(r.points.length / 2)];
  function picture(mode, letter = 'А') {
    if (mode === 'text') return '<svg viewBox="0 0 72 44"><text x="36" y="32" text-anchor="middle" fill="currentColor" font-size="30">Тт</text></svg>';
    if (!Catalog.LETTERS.includes(letter)) letter = 'А';
    const circle = `<circle cx="${mode === 'letter' ? 36 : 16}" cy="22" r="12" fill="currentColor"/><text x="${mode === 'letter' ? 36 : 16}" y="26.5" text-anchor="middle" fill="white" font-size="13" font-weight="700">${letter}</text>`;
    return `<svg viewBox="0 0 72 44" aria-hidden="true">${mode !== 'annotation' ? circle : ''}${mode !== 'letter' ? `<path d="M${mode === 'annotation' ? 12 : 31} 22H60${mode === 'answer' ? 'm-7-7 7 7-7 7' : ''}" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>` : ''}</svg>`;
  }
  function create(scene, label, points, at, letterOnly = false, arrowhead = true) {
    if (!free(scene).includes(label)) return null;
    const route = {id: `choice_${label}`, kind: 'choice', label, points, labelPosition: [...at]};
    if (letterOnly) route.display = 'letter';
    if (!arrowhead) route.arrowhead = false;
    scene.routes.push(route);
    return {t: 'route', id: route.id};
  }
  return {modes, free, position, picture, create};
})();
if (typeof module !== 'undefined') module.exports = AnswerMark;
