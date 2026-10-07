// Итоги недельного рейтинга игры для ачивки «Покоритель рейтинга».
//
// Таблица недели (game_lb:<неделя>) живёт 21 день и итогового места нигде не
// запоминает. Когда неделя закрывается, лучшие места её топа переносятся в
// один документ game_best = { userId: лучшее место за всё время }. В него
// попадают только первые GAME_BEST_TOP игроков недели, так что документ
// растёт медленно (≤100 записей в неделю), а запись в KV — одна на неделю.
// Имён и очков здесь нет: только id игрока и место.

export const GAME_BEST_TOP = 100;
// Неделя засчитывается, только если в ней сыграло не меньше стольких игроков:
// иначе при двух-трёх участниках все становились бы «призёрами».
export const GAME_MIN_PLAYERS = 10;

const BEST_KEY = 'game_best';
const FINAL_PREFIX = 'game_lb_final:';

async function readBest(env) {
  try {
    const raw = await env.INSTALLS.get(BEST_KEY);
    const doc = raw ? JSON.parse(raw) : {};
    return doc && typeof doc === 'object' && !Array.isArray(doc) ? doc : {};
  } catch (_) {
    return {};
  }
}

// Закрывает неделю: учитывает места игроков и ставит отметку «закрыта».
// `ranked` — таблица недели по убыванию очков ([{ userId, score }, ...]).
// Безопасно вызывать повторно: закрытая неделя пропускается, а если запись
// оборвётся между шагами, повтор даст тот же результат (берётся лучшее место).
export async function finalizeGameWeek(env, week, ranked) {
  if (!env.INSTALLS) return false;
  const marker = FINAL_PREFIX + week;
  if (await env.INSTALLS.get(marker)) return false;

  const players = ranked.filter(r => r && r.userId && r.score > 0);
  const counted = players.length >= GAME_MIN_PLAYERS;
  if (counted) {
    const best = await readBest(env);
    let changed = false;
    players.slice(0, GAME_BEST_TOP).forEach((r, i) => {
      const rank = i + 1;
      if (!(best[r.userId] <= rank)) { best[r.userId] = rank; changed = true; }
    });
    if (changed) await env.INSTALLS.put(BEST_KEY, JSON.stringify(best));
  }
  await env.INSTALLS.put(marker, JSON.stringify({
    week, players: players.length, counted, finalizedAt: new Date().toISOString(),
  }));
  return true;
}

// Лучшее место игрока за все закрытые недели или null.
export async function bestGameRank(env, userId) {
  if (!env.INSTALLS || !userId) return null;
  const rank = (await readBest(env))[userId];
  return Number.isInteger(rank) && rank > 0 ? rank : null;
}

// Удаление аккаунта: место игрока из истории тоже убирается.
export async function deleteGameBest(env, userId) {
  if (!env.INSTALLS || !userId) return;
  const best = await readBest(env);
  if (userId in best) {
    delete best[userId];
    await env.INSTALLS.put(BEST_KEY, JSON.stringify(best));
  }
}

// Закрывает несколько последних законченных недель. Первый запуск после
// выкладки сразу подхватывает недели, чьи таблицы ещё не удалены.
let lastClosedFor = '';
export async function closeFinishedGameWeeks(env, currentWeek, weekKeyAt, readBoard, rankBoard, count = 4) {
  if (!env.INSTALLS || lastClosedFor === currentWeek) return;
  for (let i = 1; i <= count; i++) {
    const week = weekKeyAt(new Date(Date.now() - i * 7 * 86400000));
    await finalizeGameWeek(env, week, rankBoard(await readBoard(env, week)));
  }
  lastClosedFor = currentWeek;
}
export function resetClosedWeekCache() { lastClosedFor = ''; }
