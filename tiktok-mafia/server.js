/**
 * СЕРВЕР-ХАБ.
 *
 * Держит партию, раздаёт сцену, гонит события в браузер и собирает голоса.
 * Зависимостей нет: сцена слушает через SSE, источники шлют обычным POST.
 *
 *   node server.js            → http://localhost:3000/scene.html
 *
 * Вход  (POST /input):  { type: 'comment'|'gift', user, text, gift, coins }
 * Выход (GET  /stream): поток событий партии для сцены
 *
 * Источников входа два и они взаимозаменяемы:
 *   tiktok-bridge.js  — реальный эфир
 *   emulator.js       — фейковые зрители для отладки без эфира
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const engine = require('./traitors-engine');
const { actionFor, voteWeight, payoutUsd, LADDER } = require('./gifts');
const fsp = require('fs');

const PORT = process.env.PORT || 3000;

// ─────────────────────────── ПОДПИСЧИКИ СЦЕНЫ ───────────────────────────

const clients = new Set();
let lastParty = null; // чтобы сцена, открытая посреди партии, сразу увидела состав

let lastStats = null;

function push(ev) {
  if (ev.type === 'stats') lastStats = ev;
  if (ev.type === 'over') {
    flushCalibration({
      applied: (lastStats && lastStats.applied.length) || 0,
      dropped: (lastStats && lastStats.dropped) || [],
      rounds: (lastStats && lastStats.rounds) || 0,
      winner: ev.winner,
    });
  }
  if (ev.type === 'party') {
    lastParty = ev;
    ALL_NAMES.length = 0;
    ALL_NAMES.push(...ev.players.map((p) => p.name));
    ALIVE.clear();
    for (const p of ev.players) ALIVE.add(p.name);
  }
  if (ev.type === 'out') ALIVE.delete(ev.name);
  const data = `data: ${JSON.stringify(ev)}\n\n`;
  for (const res of clients) {
    try {
      res.write(data);
    } catch {
      clients.delete(res);
    }
  }
}

engine.setBroadcast(push);

// ───────────────────────────── ГОЛОСОВАНИЕ ─────────────────────────────

const vote = {
  open: false,
  lastword: null,     // кому купили последнее слово
  candidates: [],
  tally: {},           // имя → вес
  voted: new Set(),    // один зритель — один голос за окно
};

/**
 * Кого назвал зритель последним.
 * К подарку в TikTok текст не приложить, поэтому цель действия берётся
 * из последнего имени, которое этот зритель написал в чат. Живёт минуту.
 */
const lastNamed = new Map();   // user → { name, at }
const ALIVE = new Set();       // кто ещё в игре: за выбывших голоса не принимаем

/**
 * Журнал калибровки. Пороги подарков нельзя выставить умозрительно —
 * их показывает только живой зал. Пишем каждый подарок с его уровнем,
 * потом `node calibrate.js` говорит, что двигать.
 */
const party = { gifts: [], noTarget: 0 };

function logGift(msg, act, hadTarget) {
  party.gifts.push({ coins: Number(msg.coins) || 1, kind: act.kind, user: msg.user, hadTarget });
  if (!hadTarget && act.kind !== 'vote') party.noTarget++;
}

function flushCalibration(extra) {
  let all = [];
  try { all = JSON.parse(fsp.readFileSync('calibration.json', 'utf8')); } catch {}
  const coins = party.gifts.reduce((s, g) => s + g.coins, 0);
  all.push({
    at: new Date().toISOString(),
    gifts: party.gifts.length,
    coins,
    payoutUsd: payoutUsd(coins),
    noTarget: party.noTarget,
    byKind: party.gifts.reduce((m, g) => ((m[g.kind] = (m[g.kind] || 0) + 1), m), {}),
    ...extra,
  });
  fsp.writeFileSync('calibration.json', JSON.stringify(all.slice(-200), null, 2));
  party.gifts = [];
  party.noTarget = 0;
}
const ALL_NAMES = [];          // имена текущего состава

/**
 * Имя живого участника в тексте.
 * Ищем только среди живых: зал по инерции пишет выбывших ещё минуту после
 * изгнания, и без этой проверки мертвецы копят голоса и лезут в полоски.
 */
function nameIn(text) {
  const t = (text || '').toLowerCase();
  return ALL_NAMES.find((n) => ALIVE.has(n) && t.includes(n.toLowerCase())) || null;
}

function targetFor(msg) {
  const direct = nameIn(msg.text);
  if (direct) return direct;
  const remembered = lastNamed.get(msg.user);
  if (remembered && Date.now() - remembered.at < 60000 && ALIVE.has(remembered.name)) {
    return remembered.name;
  }
  return null;
}

function applyInput(msg) {
  const named = nameIn(msg.text);
  if (named) lastNamed.set(msg.user, { name: named, at: Date.now() });

  if (msg.type === 'gift') {
    const act = actionFor(msg.coins, msg.gift);
    const target = targetFor(msg);

    logGift(msg, act, !!target);

    // последнее слово имеет смысл только во время голосования.
    // Куплено вне окна — не пропадает, а отрабатывает как «дать слово»
    if (act.kind === 'lastword' && target) {
      if (vote.open && !vote.lastword) {
        vote.lastword = target;
        push({ type: 'bought', user: msg.user, label: act.label, target, gift: msg.gift });
        console.log(`${msg.user}: последнее слово → ${target}`);
      } else {
        engine.queueAction({ kind: 'speak', target, user: msg.user, gift: msg.gift, label: 'дать слово' });
      }
      return;
    }

    // без цели действие не применить — тогда подарок просто усиливает голос
    if (act.kind !== 'vote' && target) {
      // объявляет движок, когда действие применится: лимиты и окна могут
      // его отклонить, и обещать заранее нельзя
      engine.queueAction({ kind: act.kind, target, user: msg.user, gift: msg.gift, label: act.label });
      console.log(`${msg.user}: ${act.label} → ${target}`);
      return;
    }

    if (vote.open && target) {
      vote.tally[target] = (vote.tally[target] || 0) + voteWeight(msg.coins);
      push({ type: 'tally', tally: vote.tally });
    }
    return;
  }

  // комментарий — один голос за окно
  if (!vote.open || !named) return;
  if (vote.voted.has(msg.user)) return;
  vote.voted.add(msg.user);
  vote.tally[named] = (vote.tally[named] || 0) + 1;
  push({ type: 'tally', tally: vote.tally });
}

engine.setVoteProvider(async (candidates, seconds) => {
  vote.open = true;
  vote.candidates = candidates;
  vote.tally = Object.fromEntries(candidates.map((n) => [n, 0]));
  vote.voted = new Set();
  vote.lastword = null;

  push({ type: 'vote_open', candidates, seconds });

  let left = seconds;
  let restarted = false;

  while (left > 0) {
    // кто-то купил последнее слово: обвиняемый говорит, голосование заново
    if (vote.lastword && !restarted) {
      const target = vote.lastword;
      vote.lastword = null;
      restarted = true;
      vote.open = false;                     // на время речи голоса не принимаем

      push({ type: 'vote_paused', name: target });
      try {
        await engine.requestSpeech(target, 'lastword');
        await new Promise((r) => setTimeout(r, Number(process.env.LASTWORD_MS) || 9000));
      } catch (e) {
        console.error('речь не получилась:', e.message);
      }

      // голосуем с нуля: иначе речь ничего не решает, а зритель
      // уже отдавший голос не может передумать
      vote.tally = Object.fromEntries(candidates.map((n) => [n, 0]));
      vote.voted = new Set();
      vote.open = true;
      left = Number(process.env.VOTE_RESTART_SECONDS) || 30;
      push({ type: 'vote_restart', name: target, seconds: left });
      push({ type: 'tally', tally: vote.tally });
    }

    // купленное во время голосования должно отрабатывать сразу,
    // а не ждать конца окна. Намеренно без await: улика идёт в модель,
    // и ждать её нельзя — таймер поедет
    engine.drainNow().catch(() => {});

    push({ type: 'tick', left });
    await new Promise((r) => setTimeout(r, 1000));
    left--;
  }

  // добираем голоса ещё 8 секунд: у зрителя картинка отстаёт от твоей на 5-10 сек,
  // и те, кто нажал "по таймеру на экране", попадают именно в это окно
  push({ type: 'tick', left: 0 });
  await new Promise((r) => setTimeout(r, Number(process.env.VOTE_TAIL_MS) || 8000));

  vote.open = false;
  push({ type: 'vote_closed', tally: vote.tally });
  return vote.tally;
});

// ──────────────────────────────── HTTP ────────────────────────────────

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (url.pathname === '/stream') {
    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      connection: 'keep-alive',
    });
    res.write('retry: 1000\n\n');
    clients.add(res);
    res.write(`data: ${JSON.stringify({
      type: 'ladder',
      items: LADDER.map((s) => ({ gift: s.gift, label: s.label, hint: s.hint })),
    })}\n\n`);
    if (lastParty) res.write(`data: ${JSON.stringify(lastParty)}\n\n`);
    req.on('close', () => clients.delete(res));
    return;
  }

  if (url.pathname === '/input' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      try {
        applyInput(JSON.parse(body));
      } catch {}
      res.writeHead(204).end();
    });
    return;
  }

  // статика
  const file = url.pathname === '/' ? '/scene.html' : url.pathname;
  const full = path.join(__dirname, file);
  if (!full.startsWith(__dirname) || !fs.existsSync(full)) {
    res.writeHead(404).end('not found');
    return;
  }
  const MIME = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.svg': 'image/svg+xml',
  };
  const ext = path.extname(file).toLowerCase();
  res.writeHead(200, { 'content-type': MIME[ext] || 'application/octet-stream' });
  fs.createReadStream(full).pipe(res);
});

server.listen(PORT, () => {
  console.log(`сцена:   http://localhost:${PORT}/scene.html`);
  console.log(`вход:    POST http://localhost:${PORT}/input`);
  console.log(`\nждём сцену 3 секунды, потом начинаем партию...\n`);
  setTimeout(runForever, 3000);
});

/** Партии идут одна за другой, пока процесс жив. Между ними пауза на заставку. */
async function runForever() {
  for (;;) {
    try {
      await engine.runGame();
    } catch (e) {
      console.error('партия упала:', e.message);
      push({ type: 'error', text: e.message });
    }
    const gap = Number(process.env.INTERMISSION_MS) || 30000;
    push({ type: 'intermission', seconds: Math.round(gap / 1000) });
    await new Promise((r) => setTimeout(r, gap));
  }
}
