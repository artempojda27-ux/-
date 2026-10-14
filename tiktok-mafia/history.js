/**
 * ПАМЯТЬ МЕЖДУ ПАРТИЯМИ.
 *
 * После каждой партии роли вскрываются — значит всё, что было, становится публичным
 * знанием для следующей. Персонажи это помнят. Из накопленных обид и союзов
 * сам собой вырастает сериал: ты не программируешь вражду Олега и Нины,
 * она заводится после того, как он второй раз слил её невиновной.
 *
 * Хранится в history.json рядом со скриптом.
 */

const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, 'history.json');

const EMPTY = { partyNo: 0, players: {}, pairs: {} };

function load() {
  try {
    return JSON.parse(fs.readFileSync(FILE, 'utf8'));
  } catch {
    return JSON.parse(JSON.stringify(EMPTY));
  }
}

function save(h) {
  fs.writeFileSync(FILE, JSON.stringify(h, null, 2));
}

const keyOf = (a, b) => `${a}|${b}`; // направленный: что A помнит про B

function bump(h, a, b, field, n = 1) {
  const k = keyOf(a, b);
  h.pairs[k] = h.pairs[k] || {};
  h.pairs[k][field] = (h.pairs[k][field] || 0) + n;
}

function playerRec(h, name) {
  h.players[name] = h.players[name] || {
    parties: 0,
    asTraitor: 0,
    wins: 0,
    lastPlayed: 0,
    traitorStreak: 0,
  };
  return h.players[name];
}

/**
 * Записать завершённую партию.
 * events — что произошло по ходу: обвинения, ночные жертвы, изгнания.
 */
function recordParty(state, winner) {
  const h = load();
  h.partyNo++;

  const roster = state.players.map((p) => p.name);

  for (const p of state.players) {
    const rec = playerRec(h, p.name);
    rec.parties++;
    rec.lastPlayed = h.partyNo;
    if (p.role === 'traitor') {
      rec.asTraitor++;
      rec.traitorStreak++;
    } else {
      rec.traitorStreak = 0;
    }
    if ((p.role === 'traitor') === (winner === 'traitor')) rec.wins++;
  }

  const roleOf = (n) => state.players.find((p) => p.name === n)?.role;

  // обвинения: кто кого топил и был ли тот виноват
  for (const acc of state.accusations) {
    if (!roster.includes(acc.from) || !roster.includes(acc.to)) continue;
    if (roleOf(acc.to) === 'faithful' && roleOf(acc.from) === 'faithful') {
      bump(h, acc.to, acc.from, 'unfairHeat'); // топил меня, а я был верным
    }
    if (roleOf(acc.to) === 'traitor') {
      bump(h, acc.to, acc.from, 'sawThroughMe'); // раскусил меня
      bump(h, acc.from, acc.to, 'iWasRight');
    }
  }

  // ночные жертвы: предатели помнят, кого убрали; жертва помнит, кто это был
  for (const kill of state.nightKills) {
    for (const t of kill.traitors) {
      bump(h, kill.victim, t, 'killedMe');
      bump(h, t, kill.victim, 'iKilled');
    }
  }

  // напарники
  const traitors = state.players.filter((p) => p.role === 'traitor').map((p) => p.name);
  if (traitors.length === 2) {
    bump(h, traitors[0], traitors[1], 'partner');
    bump(h, traitors[1], traitors[0], 'partner');
  }

  // дожили вдвоём до конца — общий окоп
  const survivors = state.players.filter((p) => p.alive && p.role === 'faithful').map((p) => p.name);
  for (const a of survivors) for (const b of survivors) if (a !== b) bump(h, a, b, 'survivedTogether');

  save(h);
  return h.partyNo;
}

/**
 * Что персонаж помнит — 2-3 самые сильные строки про конкретных людей за столом.
 * Больше трёх не даём: промпт распухает, а модель начинает пересказывать историю
 * вместо того, чтобы играть.
 */
function historyFor(name, roster) {
  const h = load();
  if (h.partyNo === 0) return [];

  // род берём из подсказки для TTS — отдельное поле заводить не нужно
  const { CAST } = require('./characters');
  const isF = (n) => (CAST.find((c) => c.name === n)?.voice || '').startsWith('женский');
  const a = (n) => (isF(n) ? 'а' : ''); // окончание глагола прошедшего времени
  const was = (n) => (isF(n) ? 'была' : 'был');

  const lines = [];
  for (const other of roster) {
    if (other === name) continue;
    const p = h.pairs[keyOf(name, other)] || {};

    if (p.killedMe)
      lines.push({ w: 5 + p.killedMe, t: `${other} ${was(other)} предателем и убрал${a(other)} тебя ночью (раз: ${p.killedMe})` });
    if (p.unfairHeat >= 2)
      lines.push({ w: 4 + p.unfairHeat, t: `${other} топил${a(other)} тебя невиновного уже ${p.unfairHeat} раза — ты это не забыл` });
    else if (p.unfairHeat === 1)
      lines.push({ w: 3, t: `${other} однажды топил${a(other)} тебя, когда ты был верным` });
    if (p.partner)
      lines.push({ w: 4 + p.partner, t: `вы с ${other} уже были предателями в паре (раз: ${p.partner}) — между вами есть понимание` });
    if (p.sawThroughMe)
      lines.push({ w: 3, t: `${other} тебя однажды раскусил${a(other)} — читает тебя лучше других` });
    if (p.survivedTogether >= 2)
      lines.push({ w: 2, t: `вы с ${other} не раз доходили до конца вместе, ты ему скорее доверяешь` });
  }

  lines.sort((a2, b2) => b2.w - a2.w);
  const seen = new Set();
  return lines.filter((x) => !seen.has(x.t) && seen.add(x.t)).slice(0, 3).map((x) => x.t);
}

/** Личная сводка для персонажа — идёт на экран и в промпт */
function statsFor(name) {
  const h = load();
  const r = h.players[name];
  if (!r || !r.parties) return null;
  return r;
}

/** Кто давно не играл — их берём в состав в первую очередь */
function rotationScore(name) {
  const h = load();
  const r = h.players[name];
  if (!r) return 999; // ни разу не играл — максимальный приоритет
  return h.partyNo - r.lastPlayed;
}

function partyNumber() {
  return load().partyNo;
}

module.exports = { recordParty, historyFor, statsFor, rotationScore, partyNumber };
