/**
 * СЮЖЕТ: ДОПРОС, ПОВОРОТЫ, ФИНАЛ «КАК ЭТО БЫЛО».
 *
 * Мафия должна вычисляться логикой, а не угадайкой. Поэтому всё, что здесь
 * показывается зрителю, берётся из настоящих фактов партии:
 *
 *   допрос      утром детектив спрашивает каждого, где он был ночью.
 *               Мирные отвечают правду (где были и кого видели), мафия
 *               может соврать — и ложь можно поймать уликой или свидетелем.
 *   повороты    блокнот убитого шерифа, перехваченный звонок, свидетель —
 *               каждый указывает на настоящую мафию, но не прямо.
 *   финал       восстановление каждой ночи: кто где был и кто убил.
 *               Зритель видит, что разгадка была возможна.
 */

const { tr, LANG } = require('./i18n');

const roman = (n) => ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'][n] || String(n);

/** Записать ночь целиком — из этих записей потом собирается финал */
function recordNight(state, rec) {
  (state.nightLog = state.nightLog || []).push(rec);
}

/** Промпт допроса: короткий ответ на «где вы были ночью» */
function interrogation(player, state, placeName, sawNames) {
  const system = `Ты — ${player.name} в игре «Город засыпает». Тебя допрашивает детектив в полицейском участке.
${player.role === 'traitor'
    ? 'Ты мафия. Ночью ты был там, где указано, но можешь назвать другое место, если правда тебя выдаёт. Ври уверенно и коротко.'
    : 'Ты мирный житель. Говори правду: где был и кого видел. Можно нервничать.'}
Ответ — одна-две фразы, не больше 16 слов, в твоей манере речи.
${LANG === 'ru' ? '' : `Отвечай на языке эфира (${LANG}).`}
ФОРМАТ — только JSON: {"line": "ответ"}`;
  const user = `Детектив: «Где вы были этой ночью?»
Где ты был на самом деле: ${placeName}.
Кого ты там видел: ${sawNames.length ? sawNames.join(', ') : 'никого'}.
Твой ответ:`;
  return { system, user };
}

function mockAlibi(player, placeName, sawNames) {
  const lie = player.role === 'traitor' && Math.random() < 0.6;
  if (LANG === 'ru') {
    return lie ? 'Дома. Спал. Спросите кого хотите.'
      : `Я был${''} у места «${placeName}».${sawNames.length ? ` Там был ещё ${sawNames[0]}.` : ' Один.'}`;
  }
  return lie ? 'Home. Asleep. Ask anyone you like.'
    : `I was at ${placeName}.${sawNames.length ? ` ${sawNames[0]} was there too.` : ' Alone.'}`;
}

/**
 * Поворот утра. Один на утро, только если есть на чём: каждый указывает
 * на правду, но оставляет зрителю работу.
 */
function twist(state, night, ctx) {
  const { pick, byId, clock, g } = ctx;
  const alive = state.players.filter((p) => p.alive);
  const mafia = alive.filter((p) => p.role === 'traitor');
  const innocents = alive.filter((p) => p.role !== 'traitor');
  const options = [];

  // 1. блокнот убитого шерифа: одна из его проверок становится публичной
  if (night && night.victim.role === 'sheriff') {
    const checks = Object.entries(state.checked || {}).filter(([n]) => alive.some((p) => p.name === n));
    if (checks.length) {
      const [name, verdict] = pick(checks);
      const isMafia = verdict === 'МАФИЯ';
      options.push({ w: 5, clip: 'act-inspect', title: tr('БЛОКНОТ ШЕРИФА', "THE SHERIFF'S NOTEBOOK"),
        text: isMafia
          ? tr(`В кармане у ${night.victim.name} нашли блокнот шерифа. Последняя запись: «${name} — мафия».`,
            'In {victim}\'s pocket they found the sheriff\'s notebook. Last entry: "{name} is mafia."', { victim: night.victim.name, name })
          : tr(`В кармане у ${night.victim.name} нашли блокнот шерифа. Последняя запись: «${name} — чист».`,
            'In {victim}\'s pocket they found the sheriff\'s notebook. Last entry: "{name} is clean."', { victim: night.victim.name, name }),
        reveal: { name, mafia: isMafia } });
    }
  }

  // 2. перехваченный звонок: один из двоих — мафия
  if (mafia.length && innocents.length >= 1 && state.placement) {
    const m = pick(mafia);
    const i = pick(innocents);
    const pair = Math.random() < 0.5 ? [m.name, i.name] : [i.name, m.name];
    const place = byId(state.placement[m.name]).name;
    options.push({ w: 2, clip: 'night-payphone', title: tr('ПЕРЕХВАТ ЗВОНКА', 'INTERCEPTED CALL'),
      text: tr(`В ${clock} с таксофона у места «${place}» кто-то звонил и сказал: «Готово». Голос похож на ${pair[0]} или ${pair[1]}.`,
        'At {clock} someone called from a payphone near {place} and said: "It\'s done." The voice sounds like {a} or {b}.',
        { clock, place, a: pair[0], b: pair[1] }) });
  }

  // 3. свидетель: был там же, где убийство, и видел, откуда ушёл убийца
  if (night && night.witnesses && night.witnesses.length && state.placement) {
    const w = night.witnesses.find((n) => alive.some((p) => p.name === n && p.role !== 'traitor'));
    const m = mafia.length ? pick(mafia) : null;
    if (w && m) {
      const from = byId(state.placement[m.name]).name;
      options.push({ w: 3, clip: 'morning-detective', title: tr('СВИДЕТЕЛЬ', 'A WITNESS'),
        text: tr(`${w} признаётся: ночью был у места «${night.where}» и видел, как кто-то пришёл туда со стороны «${from}».`,
          '{name} admits being near {place} last night and seeing someone arrive from the direction of {from}.',
          { name: w, place: night.where, from }) });
    }
  }

  if (!options.length) return null;
  // взвешенный выбор: блокнот шерифа — самый сильный поворот, он вне очереди
  const total = options.reduce((s, o) => s + o.w, 0);
  let r = Math.random() * total;
  for (const o of options) { r -= o.w; if (r <= 0) return o; }
  return options[0];
}

/** Финал «как это было»: каждая ночь и каждое решение зала по порядку */
function truth(state, ctx) {
  const { byId, g } = ctx;
  const mafia = state.players.filter((p) => p.role === 'traitor').map((p) => p.name);
  const sheriff = state.players.find((p) => p.role === 'sheriff');
  const cards = [];
  for (const n of state.nightLog || []) {
    if (!n.victim) continue;
    const killersThere = n.killers.filter((k) => n.placement[k] === n.whereId);
    const killerPlace = byId(n.placement[n.killers[0]]).name;
    cards.push({
      title: tr(`НОЧЬ ${roman(n.round)} · ${n.where}`, 'NIGHT {n} · {place}', { n: roman(n.round), place: n.where }),
      text: killersThere.length
        ? tr(`${n.victim} был${n.female ? 'а' : ''} у места «${n.where}». Там же была мафия: ${killersThere.join(' и ')}.`,
          '{victim} was at {place}. The mafia was right there: {killers}.',
          { victim: n.victim, place: n.where, killers: killersThere.join(tr(' и ', ' and ')) })
        : tr(`${n.victim} остал${n.female ? 'ась' : 'ся'} у места «${n.where}» ${n.female ? 'одна' : 'один'}. Мафия пришла от места «${killerPlace}».`,
          '{victim} was alone at {place}. The mafia came over from {from}.', { victim: n.victim, place: n.where, from: killerPlace }),
    });
  }
  cards.push({
    title: tr('МАФИЯ', 'THE MAFIA'),
    text: tr(`Это были ${mafia.join(' и ')}.`, 'It was {names}.', { names: mafia.join(tr(' и ', ' and ')) })
      + (sheriff ? tr(` Шерифом был${g(sheriff, '', 'а')} ${sheriff.name}.`, ' The sheriff was {name}.', { name: sheriff.name }) : ''),
  });
  return cards;
}

module.exports = { recordNight, interrogation, mockAlibi, twist, truth, roman };
