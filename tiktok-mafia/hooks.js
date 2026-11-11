/**
 * КРЮЧКИ УДЕРЖАНИЯ.
 *
 * В лайв заходят в любую секунду, поэтому крючок нужен не один раз в
 * начале, а постоянно. Здесь всё, что делает зрителя игроком:
 *
 *   ответ по нику   персонаж отвечает на комментарий конкретного зрителя
 *   предсказание    ночью зал угадывает жертву, утром — сколько угадали
 *   открытая петля  в начале дня анонс того, что раскроется после голоса
 *   улика           правдивая подсказка, где ночью была мафия
 *   детективы       кто чаще голосует за настоящую мафию — топ на экране
 *   тизер серии     финал обещает продолжение
 *
 * Модуль хранит только память о зрителях; что и когда показать, решает
 * движок. Доска детективов живёт между партиями в detectives.json.
 */

const fs = require('fs');
const path = require('path');
const { tr } = require('./i18n');

const FILE = path.join(__dirname, 'detectives.json');
/** Случайный вариант фразы на языке эфира: русский или английская основа */
const pickTr = (ru, en) => { const i = Math.floor(Math.random() * ru.length); return tr(ru[i], en[i]); };

// ─── чат ───
const chat = [];            // { user, text, named, at }
const answered = new Set(); // кому уже ответили в этой партии: не больше раза на зрителя

function noteComment(user, text, named) {
  if (!user || !text) return;
  const clean = String(text).replace(/\s+/g, ' ').trim().slice(0, 140);
  if (clean.length < 3) return;
  chat.push({ user: String(user).replace(/^@/, '').slice(0, 24), text: clean, named, at: Date.now() });
  if (chat.length > 300) chat.splice(0, chat.length - 300);
  if (prediction.open && named) prediction.guesses.set(user, named);
}

/**
 * Комментарий, на который персонажу стоит ответить. Свежий, ещё без ответа;
 * сначала те, где его назвали по имени, потом вопросы и обвинения других.
 */
function viewerFor(speaker, alive) {
  const now = Date.now();
  const fresh = chat.filter((c) => now - c.at < 45000 && !answered.has(c.user));
  if (!fresh.length) return null;
  const about = fresh.filter((c) => c.named === speaker);
  const pool = about.length ? about
    : fresh.filter((c) => /\?/.test(c.text) || (c.named && alive.includes(c.named)));
  if (!pool.length) return null;
  const c = pool[pool.length - 1];
  answered.add(c.user);
  return c;
}

// ─── предсказание ночи ───
const prediction = { open: false, guesses: new Map() };
function openPrediction() {
  prediction.open = true;
  prediction.guesses = new Map();
}
/** Закрыть и посчитать: сколько назвали жертву. null — если никто не гадал */
function closePrediction(victimName) {
  prediction.open = false;
  const total = prediction.guesses.size;
  if (!total) return null;
  const right = [...prediction.guesses].filter(([, n]) => n === victimName).map(([u]) => u);
  return { total, right: right.length, pct: Math.round((right.length / total) * 100), users: right.slice(0, 3) };
}

// ─── голоса и детективы ───
let ballots = new Map();     // user → имя, за кого голосовал в этом окне
function resetBallots() { ballots = new Map(); }
function noteBallot(user, name) { if (user && name) ballots.set(String(user).replace(/^@/, ''), name); }

function loadBoard() {
  try { return JSON.parse(fs.readFileSync(FILE, 'utf8')); } catch { return {}; }
}
function saveBoard(b) {
  try { fs.writeFileSync(FILE, JSON.stringify(b)); } catch {}
}
/**
 * Изгнали игрока: каждый голосовавший получает попытку, угадавшие мафию —
 * очко. Возвращает топ-3, если в окне вообще кто-то голосовал.
 */
function scoreBallots(banishedName, wasTraitor) {
  if (!ballots.size) return null;
  const board = loadBoard();
  for (const [user, name] of ballots) {
    const row = board[user] || (board[user] = { right: 0, total: 0 });
    row.total++;
    if (wasTraitor && name === banishedName) row.right++;
  }
  saveBoard(board);
  return top(board);
}
function top(board = loadBoard(), n = 3) {
  return Object.entries(board)
    .filter(([, r]) => r.right > 0)
    .sort((a, b) => b[1].right - a[1].right || a[1].total - b[1].total)
    .slice(0, n)
    .map(([user, r]) => ({ user, right: r.right, total: r.total }));
}

// ─── тексты крючков ───

/** Открытая петля в начале дня: обещание, что ответ будет после голосования */
function openLoop(round) {
  return pickTr([
    'Кто-то из них сейчас соврёт про эту ночь. Ответ — после голосования.',
    'Один из говорящих знает, кто это сделал. Слушайте, кто первым сменит тему.',
    'Сегодня город ошибётся или нет. Узнаем через две минуты.',
    'Мафия сидит среди них и кивает. Смотрите, кто кивает слишком охотно.',
  ], [
    'One of them is about to lie about last night. The answer comes after the vote.',
    'Someone speaking now knows who did it. Watch who changes the subject first.',
    'Today the city gets it right, or it doesn\'t. Two minutes to find out.',
    'The mafia is sitting with them, nodding along. Watch who nods too eagerly.',
  ]) + (round > 2 ? tr(' Ошибиться уже нельзя.', ' There is no room for mistakes now.') : '');
}

/** Улика: правдивая, но неполная. Место, где ночью был кто-то из мафии */
function clue(placeName, hour) {
  return pickTr([
    `Таксист видел, как около ${hour} кто-то быстро уходил от места «${placeName}». Лица не разглядел.`,
    `Камера у места «${placeName}» записала тень в ${hour}. Кто из них был там ночью?`,
    `В ${hour} у места «${placeName}» лаяли собаки. Значит, кто-то там был.`,
  ], [
    `A cab driver saw someone hurrying away from ${placeName} around ${hour}. No face.`,
    `A camera near ${placeName} caught a shadow at ${hour}. Which of them was there last night?`,
    `Dogs were barking near ${placeName} at ${hour}. Someone was there.`,
  ]);
}

/** Тизер следующей серии: финал не отпускает, а обещает продолжение */
function teaser(state, winner) {
  const innocentOut = state.players.find((p) => p.outBy === 'vote' && p.role !== 'traitor');
  const mafiaLeft = state.players.find((p) => p.alive && p.role === 'traitor');
  if (winner !== 'faithful' && mafiaLeft) {
    return tr(`В следующей серии: ${mafiaLeft.name} всё ещё в городе. И теперь знает, кто голосовал против.`,
      `Next episode: ${mafiaLeft.name} is still in the city. And now knows who voted against them.`);
  }
  if (innocentOut) {
    return tr(`В следующей серии: ${innocentOut.name} вернётся. И помнит, кто голосовал против.`,
      `Next episode: ${innocentOut.name} comes back. And remembers who voted them out.`);
  }
  return tr('В следующей серии: город спит спокойно. Пока.', 'Next episode: the city sleeps easy. For now.');
}

/** Новая партия: ответы по нику снова доступны каждому */
function newParty() {
  answered.clear();
  resetBallots();
  prediction.open = false;
}

module.exports = {
  noteComment, viewerFor, openPrediction, closePrediction,
  resetBallots, noteBallot, scoreBallots, top,
  openLoop, clue, teaser, newParty,
};
