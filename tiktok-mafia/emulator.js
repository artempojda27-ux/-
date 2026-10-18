/**
 * ЭМУЛЯТОР ЗРИТЕЛЕЙ.
 *
 *   node emulator.js            60 зрителей, средняя активность
 *   node emulator.js 200 hype   200 зрителей, донатят чаще
 *
 * Шлёт в сервер то же самое, что реальный мост. Нужен, чтобы не поднимать
 * эфир ради каждой правки: голосование, полоски и озвучка отлаживаются
 * прямо за столом.
 *
 * Зрители тут не равномерные: есть болтуны, есть молчуны, есть киты.
 * Равномерный поток даёт ровные полоски и врёт про то, как оно будет вживую.
 */

'use strict';

const HUB = process.env.HUB || 'http://localhost:3000/input';
const COUNT = Number(process.argv[2]) || 60;
const HYPE = process.argv[3] === 'hype';

// имена берём из каста: в английском эфире зрители пишут английские
const NAMES = require('./characters').CAST.map((c) => c.name);
const { LANG } = require('./i18n');
// живой чат не пишет голое имя: «vote gene», «its ross!!» — так проверяется и распознавание
const PHRASES = LANG === 'en'
  ? ['{n}', '{n}', 'vote {n}', "it's {n}!!", '{n} is lying', 'kick {n}', '{n} sus']
  : ['{n}', '{n}', '{n} мафия', 'гоните {n}', '{n} врёт'];
const say = (n) => PHRASES[Math.floor(Math.random() * PHRASES.length)].replace('{n}', Math.random() < 0.5 ? n.toLowerCase() : n);
// цены подобраны так, чтобы в отладке засветились все уровни действий
// ровно та лестница, что висит на экране
const GIFTS = [
  { name: 'Rose',     coins: 1,    chance: 0.50 },
  { name: 'Doughnut', coins: 30,   chance: 0.22 },
  { name: 'Confetti', coins: 100,  chance: 0.13 },
  { name: 'Swan',     coins: 699,  chance: 0.08 },
  { name: 'Galaxy',   coins: 1000, chance: 0.05 },
  { name: 'Airplane', coins: 6000, chance: 0.02 },
];

const viewers = Array.from({ length: COUNT }, (_, i) => ({
  user: `viewer_${i}`,
  chatty: Math.random(),                        // как часто вообще пишет
  whale: Math.random() < (HYPE ? 0.12 : 0.04),  // донатит или нет
  bias: NAMES[Math.floor(Math.random() * NAMES.length)], // любимая мишень
}));

async function send(p) {
  try {
    await fetch(HUB, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(p),
    });
  } catch (e) {
    process.stdout.write('!');
  }
}

function rollGift() {
  const r = Math.random();
  let acc = 0;
  for (const g of GIFTS) {
    acc += g.chance;
    if (r <= acc) return g;
  }
  return GIFTS[0];
}

let sent = 0;

setInterval(() => {
  for (const v of viewers) {
    if (Math.random() > v.chatty * (HYPE ? 0.28 : 0.14)) continue;

    // чаще всего голосуют за свою мишень, иногда за случайного
    const name = Math.random() < 0.65 ? v.bias : NAMES[Math.floor(Math.random() * NAMES.length)];

    if (v.whale && Math.random() < 0.18) {
      const g = rollGift();
      // как в жизни: сначала имя в чат, следом подарок без текста
      send({ type: 'comment', user: v.user, text: say(name) });
      send({ type: 'gift', user: v.user, text: '', gift: g.name, coins: g.coins });
    } else {
      send({ type: 'comment', user: v.user, text: say(name) });
    }
    sent++;
  }
  process.stdout.write(`\rотправлено событий: ${sent}   `);
}, 1000);

console.log(`эмулятор: ${COUNT} зрителей${HYPE ? ', режим хайпа' : ''} → ${HUB}`);
console.log('голоса засчитываются только когда открыто окно голосования\n');
