/**
 * ЗАКАДРОВЫЙ ГОЛОС.
 *
 * То, что превращает партию в фильм. Игра сама по себе — это таблица
 * с голосами; рассказчик связывает её в историю: объявляет главы, описывает
 * ночь, находит тело, подводит итог.
 *
 * Реплики шаблонные, а не генерятся каждый раз: у рассказчика должна быть
 * узнаваемая интонация, одна и та же из эфира в эфир. Зритель, зашедший
 * на десятый раз, должен слышать знакомый голос, а не новую импровизацию.
 * Варианты перемешиваются, чтобы не приедалось дословно.
 */

const NIGHT_OPEN = [
  'Город засыпает. Улицы пустеют, и каждый уходит туда, где его никто не ждёт.',
  'Город засыпает. Свет гаснет окно за окном, и кто-то в эту ночь не проснётся.',
  'Город засыпает. Восемь человек расходятся в темноту, и двое из них знают, куда идут.',
];

const MORNING = [
  // имя всегда в именительном падеже и отдельным предложением:
  // склонять его в шаблоне нельзя, «находит Рита» звучит как поломка
  '{name}. Этой ночью город потерял одного из своих.',
  'Утро. {name} не {verned} домой.',
  'Рассвет. Того, кто ещё вчера сидел за общим столом, больше нет.',
];

const PLACE = [
  'Его нашли здесь — {where}. Кто-то этой ночью был совсем рядом.',
  '{where}. Место, где всё закончилось.',
  'Всё случилось здесь — {where}. И кто-то об этом молчит.',
];

const QUIET = [
  'Эта ночь прошла тихо. Никто не пострадал — и никто не понимает почему.',
  'Утро. Все живы. Это пугает сильнее, чем если бы кого-то не стало.',
];

const VOTE = [
  'Город решает. У вас есть время назвать имя.',
  'Слово за городом. Кого сегодня выведут за ворота?',
];

const ENDING = {
  faithful: [
    'Город выстоял. Мафия вычислена, улицы снова спят спокойно. До следующей ночи.',
    'Город победил. Но цена оказалась высокой — и не все дожили до утра.',
  ],
  traitor: [
    'Город проиграл. Мафия осталась среди своих, и никто так и не понял, кто был рядом всё это время.',
    'Город пал. Те, кого искали, сидели за общим столом и кивали вместе со всеми.',
  ],
};

/** Ночное время для карточки локации: чем позже раунд, тем глубже ночь */
function clockFor(round) {
  const base = 22 * 60 + 40;               // 22:40 в первую ночь
  const t = base + (round - 1) * 74;       // дальше сдвигается
  const h = Math.floor(t / 60) % 24;
  const m = t % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

function pickLine(arr, seed) {
  return arr[Math.abs(seed) % arr.length];
}

function fill(tpl, vars) {
  return tpl.replace(/\{(\w+)\}/g, (_, k) => vars[k] ?? '');
}

const ROMAN = ['', 'первый', 'второй', 'третий', 'четвёртый', 'пятый', 'шестой', 'седьмой'];
const cap = (t) => t.charAt(0).toUpperCase() + t.slice(1);
const fem = (p) => /^женск/.test(p?.voice || '');
const list = (ps) => ps.map((p) => p.name).join(', ').replace(/, ([^,]*)$/, ' и $1');

/**
 * Эпилог. Не «город победил», а чем именно зал это сделал: финал называет
 * решение зрителей, которое всё определило. Зритель должен уйти из эфира
 * с мыслью «это мы выгнали шерифа во второй день», а не «ну, мафия выиграла».
 *
 * verdicts — изгнания голосованием по порядку: { round, name, role, pct }.
 */
function epilogue(winner, players, verdicts) {
  const by = (n) => players.find((p) => p.name === n);
  const innocents = verdicts.filter((v) => v.role !== 'traitor').map((v) => by(v.name));
  const caught = verdicts.filter((v) => v.role === 'traitor').map((v) => by(v.name));
  const sheriffOut = verdicts.find((v) => v.role === 'sheriff');
  const traitorsLeft = players.filter((p) => p.role === 'traitor' && p.alive);
  // решающее голосование — самое единодушное изгнание мафии или самая дорогая ошибка
  const key = winner === 'faithful'
    ? verdicts.filter((v) => v.role === 'traitor').sort((a, b) => b.pct - a.pct)[0]
    : sheriffOut || verdicts[verdicts.length - 1];

  const out = [];
  if (winner === 'faithful') {
    out.push(innocents.length
      ? `Город выстоял. Но за воротами остались невиновные: ${list(innocents)}.`
      : 'Город выстоял. Вы ни разу не ошиблись: ни одного невиновного за воротами.');
    if (key) out.push(`${key.name}: ${ROMAN[key.round] || key.round} день, ${key.pct}% зала — и маска упала.`);
  } else {
    if (sheriffOut) {
      // имена не склоняем: «выгнали Костя» — поломка, поэтому имя отдельно
      out.push(`${cap(ROMAN[sheriffOut.round] || String(sheriffOut.round))} день. Зал выгоняет шерифа. ${fem(by(sheriffOut.name)) ? 'Это была' : 'Это был'} ${sheriffOut.name} — и с этого всё рухнуло.`);
    } else if (caught.length) {
      out.push(`${list(caught)} — ${caught.length > 1 ? 'их' : fem(caught[0]) ? 'её' : 'его'} вы вычислили. Но этого не хватило.`);
    } else {
      out.push('Вы ни разу не попали в мафию.');
    }
    if (traitorsLeft.length) {
      out.push(`${list(traitorsLeft)} ${traitorsLeft.length > 1 ? 'сидели' : fem(traitorsLeft[0]) ? 'сидела' : 'сидел'} за общим столом до самого конца.`);
    }
  }
  return out.join(' ');
}

/**
 * «Ранее в Городе». Партии — серии одного сериала: зритель, зашедший
 * сегодня, слышит, чем кончилось вчера, и понимает, что исход тут делают люди.
 */
function previously(last) {
  if (!last) return null;
  const v = (last.verdicts || [])[0];
  const head = v
    ? `Ранее в Городе. ${v.name} — первое решение зала. ${v.role === 'traitor' ? 'Мафия.' : v.role === 'sheriff' ? 'Шериф.' : v.female ? 'Невиновна.' : 'Невиновен.'}`
    : 'Ранее в Городе.';
  return `${head} ${last.epilogue || ''}`.trim();
}

// ───────────────────────── английский эфир ─────────────────────────
// Не перевод, а та же интонация на английском: коротко, сухо, как
// закадровый голос в нуаре. Имена всегда отдельно, без склонений.

const EN = {
  NIGHT_OPEN: [
    'The city sleeps. The streets go quiet, and everyone heads where no one is waiting for them.',
    'The city sleeps. One by one the windows go dark, and someone will not wake up.',
    'The city sleeps. Eight people walk into the dark, and two of them know exactly where they are going.',
  ],
  MORNING: [
    '{name}. Last night the city lost one of its own.',
    'Morning. {name} never made it home.',
    'Dawn. Someone who sat at this table last night is gone.',
  ],
  PLACE: [
    'This is where it happened — {where}. Someone was very close last night.',
    '{where}. This is where it ended.',
    'It all happened here — {where}. And someone is keeping quiet about it.',
  ],
  QUIET: [
    'A quiet night. No one was hurt — and no one understands why.',
    'Morning. Everyone is alive. Somehow that is scarier.',
  ],
  VOTE: [
    'The city decides. Type a name.',
    'Your call, city. Who walks out of the gates tonight?',
  ],
};
const ORD = ['', 'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh'];
const listEn = (ps) => ps.map((p) => p.name).join(', ').replace(/, ([^,]*)$/, ' and $1');
const pron = (p, he, she) => (fem(p) ? she : he);

function epilogueEn(winner, players, verdicts) {
  const by = (n) => players.find((p) => p.name === n);
  const innocents = verdicts.filter((v) => v.role !== 'traitor').map((v) => by(v.name));
  const caught = verdicts.filter((v) => v.role === 'traitor').map((v) => by(v.name));
  const sheriffOut = verdicts.find((v) => v.role === 'sheriff');
  const traitorsLeft = players.filter((p) => p.role === 'traitor' && p.alive);
  const key = winner === 'faithful'
    ? verdicts.filter((v) => v.role === 'traitor').sort((a, b) => b.pct - a.pct)[0]
    : sheriffOut || verdicts[verdicts.length - 1];

  const out = [];
  if (winner === 'faithful') {
    out.push(innocents.length
      ? `The city survived. But innocent people were left outside the gates: ${listEn(innocents)}.`
      : 'The city survived. You never got it wrong — not one innocent sent away.');
    if (key) out.push(`${key.name}: the ${ORD[key.round] || key.round} day, ${key.pct}% of you — and the mask came off.`);
  } else {
    if (sheriffOut) {
      out.push(`Day ${sheriffOut.round}. You voted out the sheriff. It was ${sheriffOut.name} — and that is where it all fell apart.`);
    } else if (caught.length) {
      out.push(`You caught ${listEn(caught)}. It was not enough.`);
    } else {
      out.push('You never once found the mafia.');
    }
    if (traitorsLeft.length) {
      out.push(`${listEn(traitorsLeft)} sat at the same table with you until the very end.`);
    }
  }
  return out.join(' ');
}

function previouslyEn(last) {
  if (!last) return null;
  const v = (last.verdicts || [])[0];
  const head = v
    ? `Previously in the City. ${v.name} — the first verdict. ${v.role === 'traitor' ? 'Mafia.' : v.role === 'sheriff' ? 'The sheriff.' : 'Innocent.'}`
    : 'Previously in the City.';
  return `${head} ${last.epilogue || ''}`.trim();
}

/** 22:40 → 10:40 PM: американскому зрителю 24-часовые часы читаются как армейские */
function clockEn(round) {
  const [h, m] = clockFor(round).split(':').map(Number);
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

const { LANG } = require('./i18n');
const L = LANG === 'en'
  ? EN
  : { NIGHT_OPEN, MORNING, PLACE, QUIET, VOTE };

const narrate = {
  nightOpen: (round) => pickLine(L.NIGHT_OPEN, round * 7 + 3),
  // род подставляем, иначе рассказчик выдаёт «Рита не вернулся домой»
  morning: (round, name, female) =>
    fill(pickLine(L.MORNING, round * 5 + 1), { name, verned: female ? 'вернулась' : 'вернулся' }),
  // место может открыть фразу: «the pier. This is…» — заглавная нужна в обоих языках
  place: (round, where) => cap(fill(pickLine(L.PLACE, round * 11 + 2), { where })),
  quiet: (round) => pickLine(L.QUIET, round),
  vote: (round) => pickLine(L.VOTE, round),
  ending: (winner) => pickLine(ENDING[winner] || ENDING.traitor, Date.now() / 1000 | 0),
  clock: LANG === 'en' ? clockEn : clockFor,
  epilogue: LANG === 'en' ? epilogueEn : epilogue,
  previously: LANG === 'en' ? previouslyEn : previously,
};

module.exports = { narrate };
