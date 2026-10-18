#!/usr/bin/env node
/**
 * ПРЕДАТЕЛИ — офлайн-движок партии.
 * Node 18+, без зависимостей.
 *
 * Запуск:
 *   ANTHROPIC_API_KEY=sk-... node traitors-engine.js
 *   PROVIDER=mock node traitors-engine.js --fast     // прогнать логику без API
 *
 * Переменные окружения:
 *   PROVIDER   anthropic | openai | mock   (default: anthropic)
 *   MODEL      default: claude-haiku-4-5-20251001
 *   BASE_URL   для OpenRouter/DeepSeek и прочих OpenAI-совместимых
 *   ANTHROPIC_API_KEY / OPENAI_API_KEY
 *
 * Флаги:
 *   --fast     без пауз между репликами
 *   --seed=N   фиксированный расклад ролей (для повторяемых прогонов)
 */

'use strict';

const fs = require('fs');

// ─────────────────────────────── КОНФИГ ───────────────────────────────

const ARGS = process.argv.slice(2);
const flag = (name) => ARGS.some((a) => a === `--${name}`);
const opt = (name) => {
  const hit = ARGS.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=')[1] : null;
};

const PROVIDER = process.env.PROVIDER || 'anthropic';
const MODEL = process.env.MODEL || 'claude-haiku-4-5-20251001';
const API_KEY = process.env.ANTHROPIC_API_KEY || process.env.OPENAI_API_KEY || '';
const BASE_URL =
  process.env.BASE_URL ||
  (PROVIDER === 'anthropic' ? 'https://api.anthropic.com' : 'https://api.openai.com/v1');

const CONFIG = {
  rosterSize: 8,           // сколько персонажей из пула выходит в партию
  voteSeconds: Number(process.env.VOTE_SECONDS) || 50,
  beat: Number(process.env.BEAT_MS ?? 2800),   // пауза под карточку главы и закадровый голос // окно голосования. Меньше 45 нельзя: задержка стрима 5-10 сек
  traitorCount: 2,
  linesPerDiscussion: Number(process.env.LINES) || 6,   // сколько реплик в раунде обсуждения
  maxWords: 25,            // жёсткий лимит на реплику
  maxRounds: 12,
  pause: flag('fast') ? 0 : Number(process.env.PAUSE_MS ?? 900),  // PAUSE_MS=0 ускоряет прогон на сервере
};

// ───────────────────────────── ПЕРСОНАЖИ ─────────────────────────────

const { CAST, relationsFor } = require('./characters');

// Род берём из голоса персонажа: «женский, …» → женский род в текстах.
const female = (p) => /^женск/.test(p?.voice || '');
const g = (p, m, f) => (female(p) ? f : m);
const byName = (name) => CAST.find((c) => c.name === name);
const { recordParty, historyFor, statsFor, rotationScore, partyNumber, lastParty } = require('./history');
const { rollEvent, clearEvent } = require('./events');
const { tierByKind } = require('./gifts');
const { CITY, cityTonight, byId, placeEveryone, whoWasAt, nightKnowledge } = require('./city');
const { narrate } = require('./narrator');
const { LANG, tr } = require('./i18n');

const RULES = `Игра «Город засыпает». В городе восемь человек. Двое из них — МАФИЯ, один — ШЕРИФ, остальные — мирные жители.
Ночью город засыпает: все расходятся по местам, а мафия убирает одного человека. Шериф этой же ночью тайно проверяет одного жителя и узнаёт, мафия он или нет.
Днём город обсуждает, кто виноват, и голосованием выгоняет одного. Мирные побеждают, если выгнали обоих мафиози. Мафия побеждает, когда её становится столько же, сколько остальных.
Каждый знает, где он был ночью и кого там видел. Кто был один — алиби у него нет.`;

// ───────────────────── ТРАНСЛЯЦИЯ И ВНЕШНИЕ ГОЛОСА ─────────────────────
// Движок ничего не знает ни про сцену, ни про TikTok. Он просто кричит,
// что произошло, и спрашивает, кого выгнали. Кто это слушает — его не касается.

let broadcast = () => {};
let voteProvider = null;

/** server.js подписывается сюда, чтобы гнать события в сцену */
function setBroadcast(fn) {
  broadcast = fn;
}
/** server.js подставляет сюда реальные голоса зрителей вместо имитации */
function setVoteProvider(fn) {
  voteProvider = fn;
}

/**
 * Действия, купленные подарками. Сервер кидает их сюда в любой момент,
 * движок разбирает очередь на стыках: перед репликой, перед ночью,
 * перед изгнанием. Так донат срабатывает быстро, но не рвёт сцену посередине.
 */
const actionQueue = [];
function queueAction(a) {
  actionQueue.push(a);
}

// ссылка на идущую партию: нужна, чтобы сервер мог попросить речь посреди голосования
let currentState = null;

// ────────────────────────────── УТИЛИТЫ ──────────────────────────────

const C = {
  dim: (s) => `\x1b[2m${s}\x1b[0m`,
  bold: (s) => `\x1b[1m${s}\x1b[0m`,
  red: (s) => `\x1b[31m${s}\x1b[0m`,
  green: (s) => `\x1b[32m${s}\x1b[0m`,
  yellow: (s) => `\x1b[33m${s}\x1b[0m`,
  cyan: (s) => `\x1b[36m${s}\x1b[0m`,
  mag: (s) => `\x1b[35m${s}\x1b[0m`,
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const INITIAL_SEED = Number(opt('seed')) || Math.floor(Math.random() * 1e9);
let seed = INITIAL_SEED;
function rand() {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
}
const pick = (arr) => arr[Math.floor(rand() * arr.length)];
function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const transcript = [];
function say(consoleLine, mdLine) {
  console.log(consoleLine);
  if (mdLine !== null) transcript.push(mdLine === undefined ? stripAnsi(consoleLine) : mdLine);
}
const stripAnsi = (s) => s.replace(/\x1b\[[0-9;]*m/g, '');

// ──────────────────────────── ВЫЗОВ МОДЕЛИ ────────────────────────────

const usage = { calls: 0, inTokens: 0, outTokens: 0, ms: 0 };

async function callLLM(system, user, maxTokens = 200) {
  if (PROVIDER === 'mock') return mockResponse(user, system);

  const started = Date.now();
  let res, data;

  if (PROVIDER === 'anthropic') {
    res = await fetch(`${BASE_URL}/v1/messages`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: maxTokens,
        system,
        messages: [{ role: 'user', content: user }],
      }),
    });
    data = await res.json();
    if (data.error) throw new Error(data.error.message);
    usage.inTokens += data.usage?.input_tokens || 0;
    usage.outTokens += data.usage?.output_tokens || 0;
    var text = data.content.map((b) => b.text || '').join('');
  } else {
    res = await fetch(`${BASE_URL}/chat/completions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${API_KEY}` },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: maxTokens,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
      }),
    });
    data = await res.json();
    if (data.error) throw new Error(data.error.message);
    usage.inTokens += data.usage?.prompt_tokens || 0;
    usage.outTokens += data.usage?.completion_tokens || 0;
    var text = data.choices[0].message.content;
  }

  usage.calls++;
  usage.ms += Date.now() - started;
  return text;
}

function parseJSON(text, fallback) {
  try {
    const clean = text.replace(/```json|```/g, '').trim();
    const start = clean.indexOf('{');
    const end = clean.lastIndexOf('}');
    return JSON.parse(clean.slice(start, end + 1));
  } catch {
    return fallback;
  }
}

// заглушка для прогона логики без API
function mockResponse(user, system = '') {
  if (user.includes('НОЧЬ')) {
    const names = user.match(/ВЕРНЫЕ В ИГРЕ: (.+)/)?.[1].split(', ') || ['Лиза'];
    return JSON.stringify({ target: pick(names), reason: 'слишком много замечает' });
  }
  // список «В ИГРЕ» — в системном промпте, без него подозреваемый всегда был мимо
  const names = (user + '\n' + system).match(/В ИГРЕ: (.+)/)?.[1].split(', ') || ['Лиза'];
  return JSON.stringify({
    line: LANG === 'en' ? pick([
      "I don't like how quiet you've been all round.",
      'Yesterday you defended the one we kicked out. Explain that.',
      'Are you serious? I was asleep all night.',
      'Facts, people. Not feelings.',
      'You were alone last night. Nobody can vouch for you. Nobody.',
      "Funny how you always talk first and say nothing.",
      "I saw who was by the warehouse. I'm not saying yet.",
      "Don't look at me like that. I was at the bar, ask anyone.",
      "Every time someone gets close, you change the subject.",
      "If I were mafia, would I really be this loud? Think.",
      "That alibi is too clean. Real nights are messy.",
      "Okay, I'll say it. I don't trust you. Never did.",
      "We kicked out an innocent yesterday. Let's not do it twice.",
      "You're defending them a little too hard, aren't you?",
    ]) : pick([
      'Мне не нравится, как он молчит весь раунд.',
      'Вчера ты защищал того, кого выгнали. Объяснись.',
      'Да вы серьёзно? Я всю ночь спала.',
      'Давайте по фактам, а не по ощущениям.',
    ]),
    suspect: pick(names),
  });
}

// ───────────────────────────── ИГРОВОЙ ЦИКЛ ─────────────────────────────

function buildAgentSystem(player, state) {
  const alive = state.players.filter((p) => p.alive).map((p) => p.name);
  const partner = state.players.find(
    (p) => p.role === 'traitor' && p.name !== player.name && p.alive
  );

  const roleBlock =
    player.role === 'sheriff'
      ? `ТЫ ШЕРИФ. Результаты проверок знаешь только ты, доказать их нечем.
Откроешься слишком рано — мафия придёт за тобой следующей ночью. Промолчишь — выгонят невиновных.
Решай сам, когда и как вбросить то, что знаешь.

КАК ТЫ ИЩЕШЬ: ${player.asFaithful}`
    : player.role === 'traitor'
      ? `ТЫ МАФИЯ. Напарник: ${partner ? partner.name : 'уже выбыл, ты один'}.

ТВОЯ ШКОЛА ВРАНЬЯ: ${player.asTraitor}

Никогда не выдавай напарника — но и не защищай его заметно. Если напарника топят, а спасти нельзя — сдай его, это выглядит убедительнее всего.`
      : `ТЫ МИРНЫЙ ЖИТЕЛЬ. Кто мафия — не знаешь.

КАК ТЫ ИЩЕШЬ: ${player.asFaithful}`;

  const rel = relationsFor(player.name);
  const relBlock = rel.length ? `\nТВОИ ОТНОШЕНИЯ В ДОМЕ:\n${rel.map((r) => '- ' + r).join('\n')}\n` : '';

  // память о прошлых эфирах: роли вскрываются в конце, значит это общее знание
  const hist = historyFor(player.name, alive);
  const histBlock = hist.length
    ? `\nЧТО БЫЛО В ПРОШЛЫХ ПАРТИЯХ (все это помнят, можешь ссылаться вслух):\n${hist
        .map((r) => '- ' + r)
        .join('\n')}\n`
    : '';

  const mine = state.knowledge[player.name] || [];
  const knowBlock = mine.length
    ? `\nТЫ ЗНАЕШЬ (только ты, вслух это никто не подтвердит):\n${mine.map((k) => '- ' + k).join('\n')}\n`
    : '';

  const ev = state.event;
  let evBlock = '';
  if (ev?.id === 'note') evBlock = `\nСЕГОДНЯ: найдена записка про ${ev.target}. Автор неизвестен — возможно, это подстава.\n`;
  if (ev?.id === 'return') evBlock = `\nСЕГОДНЯ: ${ev.target} ${g(byName(ev.target), 'вернулся', 'вернулась')} в дом. ${g(byName(ev.target), 'Он выбыл', 'Она выбыла')} ночью, значит точно ${g(byName(ev.target), 'верный', 'верная')}.\n`;
  if (state.doubleBanish) evBlock += `\nСЕГОДНЯ ИЗГОНЯЮТ ДВОИХ. Ставки выше обычного.\n`;
  if (state.openVote) evBlock += `\nТЫ ОБЯЗАН назвать одно конкретное имя прямо в реплике. Уклониться нельзя.\n`;

  return `${RULES}

Ты — ${player.name}, ${player.bio}. ${player.archetype}.

КАК ТЫ ГОВОРИШЬ: ${player.speech}
ТВОЯ ПРИВЫЧКА: ${player.tic}
${relBlock}${histBlock}${knowBlock}${evBlock}
${roleBlock}

В ИГРЕ: ${alive.join(', ')}

ФОРМАТ — только JSON, без markdown:
{"line": "твоя реплика", "suspect": "имя или null"}

Жёстко:
- максимум ${player.maxWords} слов
- ${LANG === 'en'
    ? 'ОТВЕЧАЙ ТОЛЬКО ПО-АНГЛИЙСКИ: живой разговорный американский английский, как в реалити-шоу, а не как в книге. Имена пиши как есть.'
    : 'живой разговорный русский, как в реалити-шоу, а не как в книге'}
- реагируй на конкретную реплику, которая прозвучала прямо перед твоей
- не пересказывай правила, не описывай свои действия, только прямая речь
- не повторяй мысль, которую уже высказал кто-то до тебя — возражай или добавляй новое
- без мата и без угроз расправы`;
}

/**
 * Разбор очереди по требованию — сервер зовёт это каждую секунду
 * голосования. Без него купленное во время голосования ждёт следующего
 * стыка: зритель платит и десять секунд не видит ничего. Флаг не даёт
 * двум разборам наложиться, пока модель сочиняет улику.
 */
let draining = false;
async function drainNow() {
  if (draining || !currentState) return [];
  draining = true;
  try {
    return await drainActions(currentState);
  } finally {
    draining = false;
  }
}

/**
 * Последнее слово.
 * Сервер зовёт это посреди голосования, когда кто-то купил Galaxy:
 * обвиняемый получает финальную речь, и голосование стартует заново.
 * Зал ничего не теряет — он просто решает ещё раз, уже послушав человека.
 */
async function requestSpeech(name, mode = 'lastword') {
  const state = currentState;
  if (!state) return null;
  const p = state.players.find((x) => x.name === name && x.alive);
  if (!p) return null;

  const brief = mode === 'lastword'
    ? `Тебя вот-вот изгонят. Это твоё последнее слово перед голосованием.
${p.role === 'traitor'
  ? 'Ты предатель. Врать спокойно и до конца — оправдания должны звучать как у невиновного.'
  : 'Ты верный. Тебя изгоняют ни за что. Говори так, чтобы поверили.'}
Обратись к дому напрямую. Не пересказывай правила.`
    : 'Скажи реплику по ситуации.';

  const raw = await callLLM(
    buildAgentSystem(p, state),
    `${brief}\n\nЧТО ГОВОРИЛИ:\n${publicLog(state)}\n\nТвоя речь:`,
    240
  );
  const out = parseJSON(raw, null);
  if (!out || !out.line) return null;

  state.log.push(`[ПОСЛЕДНЕЕ СЛОВО] ${p.name}: ${out.line}`);
  broadcast({ type: 'lastword', name: p.name, slug: p.slug, text: out.line, voice: p.voice });
  return out.line;
}

/**
 * Объявление покупки на экране.
 * Делает это движок, а не сервер, и только когда действие реально
 * применилось. Иначе зритель видит «проверка → Лиза», платит, а лимит
 * на партию уже исчерпан и ничего не происходит: хуже, чем отказ.
 */
function announce(a) {
  broadcast({ type: 'bought', user: a.user, label: a.label, target: a.target, gift: a.gift });
}

/**
 * Отказ в действии. Молча для зрителя, но с причиной в лог:
 * по этим причинам потом и видно, что пороги стоят не там.
 */
function drop(state, a, reason) {
  state.dropped.push({ ...a, reason });
  broadcast({ type: 'dropped', kind: a.kind, user: a.user, reason });
}

/**
 * Разбор купленных действий.
 * Возвращает список того, что реально применилось — сервер покажет это на экране
 * с именем донатера. Невыполнимое (проверка второй раз, цель уже выбыла)
 * молча отбрасывается: спорить со зрителем в эфире некогда.
 */
async function drainActions(state) {
  const done = [];

  while (actionQueue.length) {
    const a = actionQueue.shift();
    const target = state.players.find((p) => p.name === a.target && p.alive);
    if (!target) { drop(state, a, 'цель уже выбыла'); continue; }

    // потолок на партию, пауза между одинаковыми, окно применения
    const tier = tierByKind(a.kind);
    if (tier) {
      const used = state.actionUse[a.kind] || { n: 0, at: 0 };
      if (tier.perParty && used.n >= tier.perParty) { drop(state, a, 'исчерпан лимит на партию'); continue; }
      if (tier.cooldownMs && Date.now() - used.at < tier.cooldownMs) { drop(state, a, 'слишком часто'); continue; }
      if (tier.maxRound && state.round > tier.maxRound) { drop(state, a, 'поздний раунд'); continue; }
      if (tier.minAlive && state.players.filter((p) => p.alive).length < tier.minAlive) {
        drop(state, a, 'в доме слишком мало людей'); continue;
      }
      state.actionUse[a.kind] = { n: used.n + 1, at: Date.now() };
    }

    switch (a.kind) {
      case 'shield':
        state.shielded = target.name;
        state.log.push(`[${target.name} под защитой на эту ночь]`);
        announce(a);
        done.push({ ...a, ok: true });
        break;

      case 'speak':
        state.forcedSpeakers.push(target.name);
        announce(a);
        done.push({ ...a, ok: true });
        break;

      case 'inspect': {
        const role = target.role;
        state.log.push(`[ПРОВЕРКА: ${target.name} — ${role === 'traitor' ? 'ПРЕДАТЕЛЬ' : 'ВЕРНЫЙ'}]`);
        announce(a);
        broadcast({ type: 'inspect', name: target.name, role, user: a.user });
        done.push({ ...a, ok: true, role });
        break;
      }

      case 'evidence': {
        // улику придумывает модель — так она ложится в текущий разговор,
        // а не выглядит вставкой из другого эфира
        let text = tr(`Кто-то видел, как ${target.name} ночью ${female(target) ? 'выходила' : 'выходил'} из комнаты.`,
          `Someone saw ${target.name} sneaking out last night.`);
        try {
          const raw = await callLLM(
            `Ты анонимный голос в доме. Придумай короткую правдоподобную улику против участника.
Опирайся на то, что уже обсуждали. Максимум 20 слов, ${tr('разговорный русский', 'разговорный АНГЛИЙСКИЙ — пиши только по-английски')}.
ФОРМАТ — только JSON: {"line": "текст улики"}`,
            `УЛИКА ПРОТИВ: ${target.name}\n\nЧТО ОБСУЖДАЛИ:\n${publicLog(state)}`,
            120
          );
          const out = parseJSON(raw, null);
          if (out && out.line) text = out.line;
        } catch {}
        state.log.push(`[УЛИКА против ${target.name}: ${text}]`);
        announce(a);
        broadcast({ type: 'evidence', name: target.name, text, user: a.user });
        done.push({ ...a, ok: true, text });
        break;
      }
    }
  }

  state.applied.push(...done);
  return done;
}

function publicLog(state, limit = 14) {
  return state.log.slice(-limit).join('\n') || '(разговор только начался)';
}

async function nightPhase(state) {
  if (state.skipNight) return null;

  const traitors = state.players.filter((p) => p.alive && p.role === 'traitor');
  const alive = state.players.filter((p) => p.alive);
  if (!traitors.length) return null;

  // город засыпает: все расходятся по местам
  const placement = placeEveryone(state.players, rand, state.city);
  state.placement = placement;

  // мафия выбирает жертву. Убрать можно только того, до кого дошли:
  // либо он там же, где они, либо он остался один — тогда его легко застать
  const targets = alive.filter((p) => {
    if (p.role === 'traitor') return false;
    if (p.name === state.shielded) return false;
    const withThem = traitors.some((t) => placement[t.name] === placement[p.name]);
    const alone = whoWasAt(placement, placement[p.name], [p.name]).length === 0;
    return withThem || alone;
  });
  if (!targets.length) return null;   // до всех не дотянулись — ночь пустая

  const system = `${RULES}

Ты — мафия: ${traitors.map((t) => t.name).join(' и ')}.
Ночью вы убираете одного. Логика: убирать тех, кто ближе всех подобрался к правде,
кому больше всех верят, или того, кто мог вас видеть.

ФОРМАТ — только JSON: {"target": "имя", "reason": "почему, одно предложение"}`;

  const user = `НОЧЬ ${state.round}.
ГДЕ ВЫ: ${traitors.map((t) => `${t.name} — ${byId(placement[t.name]).name}`).join('; ')}
ДО КОГО ДОТЯНУЛИСЬ: ${targets.map((p) => `${p.name} (${byId(placement[p.name]).name})`).join(', ')}
ЧТО ГОВОРИЛИ ДНЁМ:
${publicLog(state)}`;

  const raw = await callLLM(system, user, 160);
  const out = parseJSON(raw, { target: pick(targets).name, reason: '—' });
  const victim = state.players.find((p) => p.name === out.target && targets.includes(p)) || pick(targets);

  victim.alive = false;
  victim.outBy = 'night';
  victim.where = placement[victim.name];
  state.nightKills.push({ victim: victim.name, traitors: traitors.map((t) => t.name) });

  // что каждый узнал за ночь: где был и кого видел
  const known = nightKnowledge(placement);
  for (const p of state.players) {
    if (!p.alive) continue;
    state.knowledge[p.name] = [known[p.name]];
  }

  // свидетели: кто был там же, где всё случилось
  const witnesses = whoWasAt(placement, placement[victim.name], [victim.name])
    .filter((n) => state.players.find((p) => p.name === n && p.alive));
  for (const w of witnesses) {
    state.knowledge[w].push(
      `Ты ${g(byName(w), 'был', 'была')} там же, где ночью убрали ${victim.name}. Говорить об этом или молчать — решай сам.`
    );
  }

  await sheriffCheck(state);

  return {
    victim, reason: out.reason, witnesses,
    where: byId(placement[victim.name]).name,
    whereId: placement[victim.name],
  };
}

/**
 * Шериф проверяет одного за ночь и узнаёт правду — но только для себя.
 * В этом вся его драма: знание есть, а доказать нечем, и стоит открыть рот,
 * как мафия придёт за ним следующей ночью. Платная проверка от зрителей
 * устроена наоборот — она публичная и спорить с ней нельзя.
 */
async function sheriffCheck(state) {
  const sheriff = state.players.find((p) => p.alive && p.role === 'sheriff');
  if (!sheriff) return;

  const pool = state.players.filter((p) => p.alive && p !== sheriff && !state.checked[p.name]);
  if (!pool.length) return;

  let target = pick(pool);
  try {
    const raw = await callLLM(
      `Ты шериф в игре «Город засыпает». Ночью проверяешь одного жителя и узнаёшь, мафия он или нет.
Выбирай того, кто вызывает больше вопросов по разговорам.
ФОРМАТ — только JSON: {"target": "имя"}`,
      `Можно проверить: ${pool.map((p) => p.name).join(', ')}
Уже проверял: ${Object.entries(state.checked).map(([n, r]) => `${n} — ${r}`).join('; ') || 'никого'}
ЧТО ГОВОРИЛИ ДНЁМ:
${publicLog(state)}`,
      100
    );
    const out = parseJSON(raw, null);
    const picked = pool.find((p) => p.name === (out && out.target));
    if (picked) target = picked;
  } catch {}

  const verdict = target.role === 'traitor' ? 'МАФИЯ' : 'не мафия';
  state.checked[target.name] = verdict;
  state.knowledge[sheriff.name] = state.knowledge[sheriff.name] || [];
  state.knowledge[sheriff.name].push(`Ты ${g(sheriff, 'проверил', 'проверила')} ${target.name}: ${verdict}.`);
  // Имя проверенного в эфир НЕ уходит: это знание шерифа, а не зрителей.
  // Показываем только сам факт, что проверка была — этого хватает для нерва.
  broadcast({ type: 'sheriff' });
}

/**
 * Кто берёт слово.
 * Не просто шафл: у каждого свой вес, обвинённый получает право ответа,
 * подряд никто не говорит дважды. Из этого рождается ритм эфира —
 * Давид тараторит, Лиза за партию скажет три фразы, и они будут весомыми.
 */
function pickSpeakers(state, count) {
  const alive = state.players.filter((p) => p.alive);
  const out = [];
  let last = null;

  for (let i = 0; i < count; i++) {
    const pool = alive.filter((p) => p !== last);
    const weights = pool.map((p) => ({
      p,
      w: p.weight / (1 + out.filter((x) => x === p).length * 1.2) + rand() * 0.3,
    }));
    const chosen = weights.reduce((a, b) => (b.w > a.w ? b : a)).p;
    out.push(chosen);
    last = chosen;
  }
  return out;
}

async function discussionPhase(state) {
  const alive = state.players.filter((p) => p.alive);
  const suspicions = {};

  const speakers = pickSpeakers(state, Math.min(CONFIG.linesPerDiscussion, alive.length * 2));

  for (let i = 0; i < speakers.length; i++) {
    let sp = speakers[i];

    // купленное «дать слово» — вне очереди
    const actions = await drainActions(state);
    broadcast({ type: 'actions', actions });
    if (state.forcedSpeakers.length) {
      const forced = state.forcedSpeakers.shift();
      const fp = alive.find((p) => p.name === forced && p.alive);
      if (fp) sp = fp;
    }

    // право ответа: если тебя только что обвинили — отвечаешь вне очереди
    const lastLine = state.log[state.log.length - 1] || '';
    const accused = alive.find((p) => p.name !== sp.name && lastLine.includes(p.name) && !lastLine.startsWith(p.name));
    if (accused && rand() < 0.45) sp = accused;

    const system = buildAgentSystem(sp, state);
    const user = `ДЕНЬ ${state.round}. Обсуждение.

ЧТО УЖЕ СКАЗАЛИ:
${publicLog(state)}

Твоя реплика сейчас:`;

    let out;
    try {
      out = parseJSON(await callLLM(system, user, 200), null);
    } catch (e) {
      say(C.red(`  [ошибка API: ${e.message}]`), null);
      continue;
    }
    if (!out || !out.line) continue;

    state.log.push(`${sp.name}: ${out.line}`);
    // suspect нужен сцене для склейки на реакцию того, на кого показали
    const suspect = out.suspect && alive.some((p) => p.name === out.suspect && p.name !== sp.name) ? out.suspect : null;
    broadcast({ type: 'line', name: sp.name, slug: sp.slug, text: out.line, voice: sp.voice, suspect });
    say(`  ${C.bold(sp.name)}: ${out.line}`, `**${sp.name}:** ${out.line}`);

    if (out.suspect && alive.some((p) => p.name === out.suspect && p.name !== sp.name)) {
      suspicions[out.suspect] = (suspicions[out.suspect] || 0) + 1;
      state.accusations.push({ from: sp.name, to: out.suspect, round: state.round });
    }
    if (CONFIG.pause) await sleep(CONFIG.pause);
  }
  return suspicions;
}

/**
 * Голосование.
 * Если подключён внешний источник (сцена + TikTok) — ждём реальные голоса.
 * Если нет — имитируем по обвинениям персонажей, чтобы отлаживать без эфира.
 */
async function runVote(state, suspicions) {
  const alive = state.players.filter((p) => p.alive);

  if (voteProvider) {
    const tally = await voteProvider(alive.map((p) => p.name), CONFIG.voteSeconds);
    const weights = alive.map((p) => ({ p, w: (tally[p.name] || 0) + 0.001 }));
    const total = weights.reduce((s, x) => s + x.w, 0);
    const target = weights.reduce((a, b) => (b.w > a.w ? b : a)).p;
    return { target, weights, total };
  }

  const weights = alive.map((p) => ({
    p,
    w: 1 + 3 * (suspicions[p.name] || 0) + rand() * 1.5,
  }));
  const total = weights.reduce((s, x) => s + x.w, 0);
  const target = weights.reduce((a, b) => (b.w > a.w ? b : a)).p;
  return { target, weights, total };
}

/** Состав партии: 8 из пула в 14. Приоритет тем, кто давно не играл. */
function pickRoster(size) {
  const scored = CAST.map((c) => ({ c, s: rotationScore(c.name) + rand() * 2.5 }));
  scored.sort((a, b) => b.s - a.s);
  return shuffle(scored.slice(0, size).map((x) => x.c));
}

async function runGame() {
  const roster = pickRoster(CONFIG.rosterSize);
  const roles = shuffle(roster.map((_, i) =>
    i < CONFIG.traitorCount ? 'traitor' : i === CONFIG.traitorCount ? 'sheriff' : 'faithful'));
  const state = {
    round: 0,
    log: [],
    accusations: [],
    nightKills: [],
    event: null,
    shielded: null,
    skipNight: false,
    doubleBanish: false,
    openVote: false,
    forcedSpeakers: [],
    knowledge: {},     // что каждый узнал ночью: где был, кого видел, кого проверил
    checked: {},       // кого уже проверял шериф
    placement: {},
    actionUse: {},     // сколько раз купили каждое действие за партию
    applied: [],       // что сработало
    dropped: [],       // что отклонили и почему
    players: roster.map((c, i) => ({ ...c, role: roles[i], alive: true })),
    city: cityTonight(roster, rand),   // какие места города открыты в эту партию
    verdicts: [],      // решения зала по порядку — из них пишется финал
  };

  say(C.mag('\n╔══════════════════════════════════════╗'));
  say(C.mag(`║   Г О Р О Д   З А С Ы П А Е Т  #${String(partyNumber() + 1).padEnd(4)}║`));
  say(C.mag('╚══════════════════════════════════════╝'));
  say(C.dim(`seed=${INITIAL_SEED}  provider=${PROVIDER}  model=${MODEL}`), null);
  say('');
  currentState = state;

  broadcast({
    type: 'titles',
    lang: LANG,          // сцена переключает надписи и голоса под язык эфира
    no: partyNumber() + 1,
    cast: state.players.map((p) => ({ name: p.name, slug: p.slug, bio: p.bio })),
  });

  broadcast({
    type: 'party',
    lang: LANG,          // сцена переключает надписи и голоса под язык эфира
    no: partyNumber() + 1,
    players: state.players.map((p) => ({ name: p.name, slug: p.slug, bio: p.bio, voice: p.voice })),
  });
  await sleep(CONFIG.beat * 2.5);   // открывающие титры отыгрывают

  // «Ранее в Городе»: чем кончилась прошлая серия и что решил тогда зал
  const recap = narrate.previously(lastParty());
  if (recap) {
    broadcast({ type: 'chapter', title: tr('РАНЕЕ', 'PREVIOUSLY'), sub: tr(`серия ${partyNumber()}`, `episode ${partyNumber()}`) });
    await sleep(CONFIG.beat);
    broadcast({ type: 'narrate', text: recap });
    say(C.dim(recap), `_${recap}_`);
    await sleep(CONFIG.beat * 2.5);
  }

  // Устанавливающая сцена: что это вообще за город. Без неё зритель первую
  // минуту видит только восемь голов и не понимает, где он находится.
  broadcast({
    type: 'montage',
    clock: narrate.clock(1),
    hold: 2400,
    places: [
      { id: CITY.id, name: CITY.name, figures: 0 },
      ...shuffle(state.city).slice(0, 3).map((id) => ({ id, name: byId(id).name, figures: 1 })),
    ],
  });
  await sleep(2400 * 4 + 600);

  say(C.dim('Расклад (зрителям не показывается):'), '_Расклад:_');
  for (const p of state.players) {
    const tag = p.role === 'traitor' ? C.red('МАФИЯ')
      : p.role === 'sheriff' ? C.cyan('ШЕРИФ') : C.dim('мирный');
    const st = statsFor(p.name);
    const streak = st && st.traitorStreak >= 1 && p.role === 'traitor' ? C.dim(` (предатель ${st.traitorStreak + 1}-ю партию подряд)`) : '';
    say(`  ${p.name.padEnd(8)} ${tag}${streak}`, `- ${p.name} — ${p.role === 'traitor' ? '**МАФИЯ**' : p.role === 'sheriff' ? '**ШЕРИФ**' : 'мирный'}`);
  }

  let winner = null;

  while (state.round < CONFIG.maxRounds) {
    state.round++;
    clearEvent(state);

    // ── СОБЫТИЕ ──
    const ev = rollEvent(state, { rand, pick });
    if (ev) {
      broadcast({ type: 'event', title: ev.title, text: ev.text });
      say(C.mag(`\n▸ ${ev.title}`), `\n> **${ev.title}** — ${ev.text}`);
      say(`  ${ev.text}`, null);
      state.log.push(`[${ev.title}: ${ev.text}]`);
      if (CONFIG.pause) await sleep(CONFIG.pause);
    }

    // ── НОЧЬ ──
    if (state.round > 1) {
      await drainActions(state);   // щит должен успеть до выбора жертвы
      // Ночь — отдельная сцена, а не мгновение: карточке главы и закадровому
      // голосу надо дать отзвучать, иначе всё слипается в одну секунду.
      broadcast({ type: 'chapter', title: `${tr('НОЧЬ', 'NIGHT')} ${roman(state.round)}`, sub: narrate.clock(state.round) });
      await sleep(CONFIG.beat);
      broadcast({
        type: 'phase', phase: 'night', round: state.round,
        title: tr('ГОРОД ЗАСЫПАЕТ', 'THE CITY SLEEPS'),
        rain: state.round % 2 === 0,   // погода меняется от ночи к ночи
      });
      broadcast({ type: 'narrate', text: narrate.nightOpen(state.round) });
      await sleep(CONFIG.beat);

      // Перебивка по городу. Показываем места, где этой ночью кто-то есть,
      // но не говорим кто: зритель видит живой город, а не список имён.
      // Заодно ночь перестаёт быть провалом в эфире — это её главная сцена.
      const night = await nightPhase(state);
      const occupied = [...new Set(Object.values(state.placement))];
      broadcast({
        type: 'montage',
        clock: narrate.clock(state.round),
        hold: 2600,
        // число силуэтов — реальное число людей в месте. Кто именно, не говорим:
        // зритель видит, что место обитаемо, и не получает расклада
        places: shuffle(occupied).slice(0, 3).map((id) => ({
          id, name: byId(id).name,
          figures: whoWasAt(state.placement, id).length,
        })),
      });
      await sleep(2600 * 3 + 600);
      say(C.cyan(`\n───── НОЧЬ ${state.round} ─────`), `\n### Ночь ${state.round}`);
      if (night) {
        state.log.push(`[Ночью не стало ${night.victim.name}. Нашли здесь: ${night.where}]`);
        broadcast({
          type: 'out', name: night.victim.name, role: night.victim.role,
          by: 'night', where: night.where,
        });
        broadcast({ type: 'chapter', title: tr('УТРО', 'MORNING'), sub: '' });
        await sleep(CONFIG.beat);
        broadcast({
          type: 'narrate',
          text: narrate.morning(state.round, night.victim.name,
            (night.victim.voice || '').startsWith('женский')),
        });
        await sleep(CONFIG.beat * 1.5);
        broadcast({
          type: 'nightplace', where: night.where, whereId: night.whereId,
          name: night.victim.name, clock: narrate.clock(state.round),
          text: narrate.place(state.round, night.where),
        });
        await sleep(CONFIG.beat * 1.5);
        say(`  ${C.bold(night.victim.name)} — ${night.where}. ${C.green(night.victim.role === 'sheriff' ? g(night.victim, 'Он был ШЕРИФОМ.', 'Она была ШЕРИФОМ.') : g(night.victim, 'Мирный житель.', 'Мирная жительница.'))}`,
            `**${night.victim.name}** ${g(night.victim, 'не пережил', 'не пережила')} ночь. ${night.where}. _(${night.reason})_`);
        if (night.witnesses.length) {
          say(C.dim(`  там же были: ${night.witnesses.join(', ')}`), null);
        }
      } else if (state.skipNight) {
        broadcast({ type: 'chapter', title: tr('УТРО', 'MORNING'), sub: '' });
        await sleep(CONFIG.beat);
        broadcast({ type: 'narrate', text: narrate.quiet(state.round) });
        await sleep(CONFIG.beat * 1.5);
        say(C.green('  Этой ночью никто не выбыл.'), '_Ночь прошла без потерь._');
      }
      if (checkWin(state)) { winner = checkWin(state); break; }
      if (CONFIG.pause) await sleep(CONFIG.pause);
    }

    // ── ОБСУЖДЕНИЕ ──
    if (state.round > 1) {
      broadcast({ type: 'chapter', title: `${tr('ДЕНЬ', 'DAY')} ${roman(state.round)}`, sub: '' });
      await sleep(CONFIG.beat);
    }
    broadcast({ type: 'phase', phase: 'day', round: state.round });
    say(C.yellow(`\n───── ДЕНЬ ${state.round}. Обсуждение ─────`), `\n### День ${state.round}`);
    const suspicions = await discussionPhase(state);

    // ── ГОЛОСОВАНИЕ ──
    say(C.yellow('\n───── ГОЛОСОВАНИЕ ЗРИТЕЛЕЙ ─────'), '\n**Голосование:**');
    broadcast({ type: 'narrate', text: narrate.vote(state.round) });
    await sleep(CONFIG.beat);
    const { target, weights, total } = await runVote(state, suspicions);
    for (const { p, w } of weights.sort((a, b) => b.w - a.w)) {
      const pct = Math.round((w / total) * 100);
      say(`  ${p.name.padEnd(8)} ${'█'.repeat(Math.max(1, Math.round(pct / 3)))} ${pct}%`,
          `- ${p.name} — ${pct}%`);
    }

    await drainActions(state);

    const victim = target;
    const banished = [victim];
    if (state.doubleBanish) {
      const second = weights
        .filter((x) => x.p !== victim && x.p.alive)
        .sort((a, b) => b.w - a.w)[0];
      if (second) banished.push(second.p);
    }

    if (CONFIG.pause) await sleep(CONFIG.pause * 2);
    say('');
    for (const b of banished) {
      b.alive = false;
      b.outBy = 'vote';
      const bw = weights.find((x) => x.p === b);
      state.verdicts.push({ round: state.round, name: b.name, role: b.role, female: female(b),
        pct: bw ? Math.round((bw.w / total) * 100) : 0 });
      const wasTraitor = b.role === 'traitor';
      const roleWord = wasTraitor ? 'МАФИЕЙ' : b.role === 'sheriff' ? 'ШЕРИФОМ' : g(b, 'мирным', 'мирной');
      const was = g(b, 'Он был', 'Она была');
      state.log.push(`[${g(b, 'Изгнан', 'Изгнана')} ${b.name}. ${was} ${roleWord}]`);
      broadcast({ type: 'out', name: b.name, role: b.role, by: 'vote' });
      say(`  ${g(b, 'Изгнан', 'Изгнана')}: ${C.bold(b.name)}`, `**${g(b, 'Изгнан', 'Изгнана')}: ${b.name}**`);
      say(wasTraitor ? C.red('  ЭТО БЫЛА МАФИЯ.') : C.green(`  ${was} ${roleWord}.`),
          wasTraitor ? '> ЭТО БЫЛА МАФИЯ.' : `> ${was} ${roleWord}.`);
      if (CONFIG.pause) await sleep(CONFIG.pause);
    }

    winner = checkWin(state);
    if (winner) break;
  }

  // ── ФИНАЛ ──
  say(C.mag('\n╔══════════════════════════════════════╗'));
  say(winner === 'faithful'
    ? C.green('   ПОБЕДА ГОРОДА — мафия вычислена')
    : C.red('   ПОБЕДА МАФИИ'),
    `\n## ${winner === 'faithful' ? 'Победа города' : 'Победа мафии'}`);
  say(C.mag('╚══════════════════════════════════════╝'));

  say('\nИтог:', '\n**Итог:**');
  for (const p of state.players) {
    const status = p.alive ? 'остался' : p.outBy === 'night' ? 'ночь' : 'изгнан';
    const rw = p.role === 'traitor' ? 'МАФИЯ' : p.role === 'sheriff' ? 'ШЕРИФ' : 'мирный';
    say(`  ${p.name.padEnd(8)} ${rw.padEnd(10)} ${status}`, `- ${p.name} — ${rw} — ${status}`);
  }

  // ── ТЕЛЕМЕТРИЯ (для расчёта стоимости эфира) ──
  const partyMinutes = estimateAirtime(state);
  say(C.dim(`\nвызовов модели: ${usage.calls}`), null);
  say(C.dim(`токены: ${usage.inTokens} in / ${usage.outTokens} out`), null);
  say(C.dim(`средняя задержка вызова: ${usage.calls ? Math.round(usage.ms / usage.calls) : 0} мс`), null);
  say(C.dim(`раундов: ${state.round}  →  хронометраж в эфире ≈ ${partyMinutes} мин`), null);

  const file = `transcript-${Date.now()}.md`;
  fs.writeFileSync(file, transcript.join('\n'));
  console.log(C.dim(`\nтранскрипт: ${file}`));

  broadcast({
    type: 'stats',
    applied: state.applied.map((a) => ({ kind: a.kind, user: a.user })),
    dropped: state.dropped.map((a) => ({ kind: a.kind, reason: a.reason })),
    rounds: state.round,
  });

  broadcast({ type: 'chapter', title: winner === 'faithful' ? tr('ГОРОД ВЫСТОЯЛ', 'THE CITY SURVIVES') : tr('МАФИЯ ПОБЕДИЛА', 'THE MAFIA WINS'), sub: '' });
  await sleep(CONFIG.beat);
  // финал называет решения зала, а не просто победителя
  state.epilogue = narrate.epilogue(winner, state.players, state.verdicts);
  say(`\n${state.epilogue}`, `\n_${state.epilogue}_`);
  broadcast({ type: 'narrate', text: state.epilogue });
  await sleep(CONFIG.beat * 2);

  broadcast({
    type: 'over',
    winner,
    players: state.players.map((p) => ({ name: p.name, role: p.role, alive: p.alive })),
  });

  const no = recordParty(state, winner);
  console.log(C.dim(`партия #${no} записана в history.json — следующая партия её помнит`));
}

/** Главы нумеруются римскими: мелочь, но именно из таких мелочей
    складывается ощущение фильма, а не таблицы */
function roman(n) {
  const R = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];
  return R[n] || String(n);
}

function checkWin(state) {
  const traitors = state.players.filter((p) => p.alive && p.role === 'traitor').length;
  const faithful = state.players.filter((p) => p.alive && p.role !== 'traitor').length;
  if (traitors === 0) return 'faithful';
  if (traitors >= faithful) return 'traitor';
  return null;
}

// хронометраж по таймингам из плана эфира
function estimateAirtime(state) {
  const perRound = 15 + 15 + CONFIG.linesPerDiscussion * 10 + 45 + 20; // ночь+утро+реплики+голосование+вскрытие
  return Math.round((state.round * perRound) / 60);
}

// ─────────────────────────────── СТАРТ ───────────────────────────────

if (require.main === module) {
  if (PROVIDER !== 'mock' && !API_KEY) {
    console.error('Нет ключа. ANTHROPIC_API_KEY=... node traitors-engine.js');
    console.error('Или прогнать логику без API: PROVIDER=mock node traitors-engine.js --fast');
    process.exit(1);
  }
  runGame().catch((e) => {
    console.error(C.red(`\nОшибка: ${e.message}`));
    process.exit(1);
  });
}

module.exports = { runGame, setBroadcast, setVoteProvider, queueAction, requestSpeech, drainNow, CONFIG };
