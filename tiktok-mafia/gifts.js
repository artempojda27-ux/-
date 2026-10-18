/**
 * ЛЕСТНИЦА ПОДАРКОВ.
 *
 * Шесть конкретных подарков — шесть действий. Не диапазоны, а именно
 * эти шесть: зритель должен запомнить лестницу за один эфир, а «от 500
 * до 2999 монет» никто запоминать не станет. Список висит на экране.
 *
 * Всё, что прислали мимо лестницы, падает на ближайшую ступень вниз:
 * Sunglasses за 199 отработает как Confetti, Lion за 29999 — как Airplane.
 * Зритель никогда не платит впустую.
 *
 * Цена одна игру не защищает: в удачный вечер кит купит проверку трижды
 * и партия развалится к третьему раунду. Поэтому у каждой ступени потолок
 * на партию, а у проверки ещё и окно применения.
 *
 * Отдельно про Galaxy. Там раньше стоял иммунитет — он снимал человека с
 * изгнания, то есть отменял решение зала задним числом. В формате, где
 * весь смысл в том, что решают зрители, это работает против себя: зал
 * голосовал, а его перебили. «Последнее слово» продаёт ровно то же
 * напряжение — обвиняемый оправдывается под таймер, — но ничего у зрителей
 * не отнимает: они просто голосуют заново, уже послушав его.
 */

const { tr } = require('./i18n');

const LADDER = [
  {
    gift: 'Rose', coins: 1,
    kind: 'vote',
    label: tr('голос с весом', 'weighted vote'),
    hint: tr('усиливает твой голос', 'your vote counts more'),
  },
  {
    gift: 'Doughnut', coins: 30,
    kind: 'speak',
    label: tr('дать слово', 'make them talk'),
    perParty: 6,
    cooldownMs: 40000,
    hint: tr('заставит оправдаться вне очереди', 'they must explain themselves now'),
  },
  {
    gift: 'Confetti', coins: 100,
    kind: 'evidence',
    label: tr('подкинуть улику', 'plant evidence'),
    perParty: 3,
    cooldownMs: 90000,
    hint: tr('против него появится компромат', 'dirt surfaces against them'),
  },
  {
    gift: 'Swan', coins: 699,
    kind: 'shield',
    label: tr('щит', 'shield'),
    perParty: 2,
    hint: tr('спасёт его от ночи', 'protects them tonight'),
  },
  {
    gift: 'Galaxy', coins: 1000,
    kind: 'lastword',
    label: tr('последнее слово', 'last words'),
    perParty: 1,
    hint: tr('он оправдается, и голосуем заново', 'they plead, then we vote again'),
  },
  {
    gift: 'Airplane', coins: 6000,
    kind: 'inspect',
    label: tr('проверка', 'reveal role'),
    perParty: 1,
    minAlive: 6,   // поздняя проверка почти решает партию
    maxRound: 2,   // поэтому только ранним раундом
    hint: tr('вскроет его роль при всех', 'exposes their role to everyone'),
  },
];

/**
 * Какое действие куплено.
 * Сначала по названию подарка, потом по цене — на ближайшую ступень вниз.
 * Между Swan и Galaxy всего 300 монет, а действия разные, поэтому
 * название важнее цены: зритель выбирает подарок глазами, а не по прайсу.
 */
function actionFor(coins, giftName) {
  if (giftName) {
    const byName = LADDER.find(
      (s) => s.gift.toLowerCase() === String(giftName).trim().toLowerCase()
    );
    if (byName) return byName;
  }
  const c = Number(coins) || 1;
  let step = LADDER[0];
  for (const s of LADDER) if (c >= s.coins) step = s;
  return step;
}

function tierByKind(kind) {
  return LADDER.find((s) => s.kind === kind) || null;
}

/**
 * Вес голоса от подарка.
 * Корень, а не прямая пропорция: иначе один кит решает исход в одиночку
 * и остальные перестают голосовать вообще.
 */
function voteWeight(coins) {
  return Math.min(25, Math.round(Math.sqrt(Number(coins) || 1) * 3));
}

/** Примерный доход автора: около половины монет, минус комиссия магазина */
function payoutUsd(coins) {
  return +(coins * 0.0053).toFixed(2);
}

module.exports = { LADDER, TIERS: LADDER, actionFor, tierByKind, voteWeight, payoutUsd };
