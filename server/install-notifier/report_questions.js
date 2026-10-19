import { reportQuestions } from './report_questions_data.js';

const byId = new Map();
const byScene = new Map();
for (const row of reportQuestions) {
  const [category, ticket, number, id, variantId] = row;
  byScene.set(`ticket_${category === 'cd' ? 'cd_' : ''}${ticket}_${number}`, row);
  for (const key of [id, variantId].filter(Boolean)) {
    if (!byId.has(key)) byId.set(key, []);
    byId.get(key).push(row);
  }
}

// Resolve only bundled content. Never fetch a client-provided image URL or
// trust a client-provided correct answer. Legacy IDs may have several diagrams.
export function reportQuestionDetails(body) {
  if (body.country && body.country !== 'ru') return null;
  const id = body.question_id;
  if (typeof id !== 'string') return null;
  let candidates = byScene.has(id) ? [byScene.get(id)] : (byId.get(id) || []);
  if (body.ticket) candidates = candidates.filter(row => row[1] === Number(body.ticket));
  if (body.category === 'ab' || body.category === 'cd') candidates = candidates.filter(row => row[0] === body.category);
  if (!candidates.length) return null;
  const row = candidates[0];
  if (candidates.some(other => other[6] !== row[6])) return null;
  const sameImage = candidates.every(other => other[5] === row[5]);
  const [category, ticket, number, , , image, correctAnswer] = row;
  return {
    ticket, number, correctAnswer,
    photoUrl: image && sameImage ? `https://pdd-drive.ru/app/assets/assets/countries/ru/images/questions_${category}/${image}.webp` : null,
  };
}

// Used at the durable queue boundary as well as by report lookup.
export function isReportPhotoUrl(value) {
  return typeof value === 'string' && /^https:\/\/pdd-drive\.ru\/app\/assets\/assets\/countries\/ru\/images\/questions_(?:ab|cd)\/[a-zA-Z0-9_-]+\.webp$/.test(value);
}

// Old game builds already send mode=city; never infer origin from a ticket ID,
// since the same ticket question can appear in training and in the game.
export function reportSourceLabel(body) {
  if (body.mode === 'city') return '🎮 <b>Источник:</b> Игра «Живой город»';
  if (body.source === 'game') return '🎮 <b>Источник:</b> Игра';
  if (body.source === 'training' || (typeof body.mode === 'string' && body.mode.trim())) {
    return '📚 <b>Источник:</b> Обычное обучение';
  }
  return '• <b>Источник:</b> Не указан';
}
