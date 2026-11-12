/**
 * ПРЕДЫСТОРИИ.
 *
 * Показываются в начале партии: герой на видео, а рассказчик за кадром
 * говорит, кто он и что скрывает. У каждого есть причина быть под
 * подозрением — это не подсказка, кто мафия (роль меняется каждую
 * партию), а повод следить за человеком с первой минуты.
 */

const { LANG } = require('./i18n');

const STORIES = {
  margo: {
    ru: 'Марго держит салон красоты на набережной. Знает все сплетни города — и кое-что, о чём не рассказывает даже подругам.',
    en: 'Margo runs a beauty salon on the boardwalk. She knows every rumor in town, and one secret she never tells.',
  },
  david: {
    ru: 'Давид отслужил десять лет и привык командовать. После увольнения из армии о нём ходят слухи, которые он не опровергает.',
    en: 'David served ten years and is used to giving orders. Since he left the army, there are rumors he never denies.',
  },
  liza: {
    ru: 'Лиза учится на юриста и подрабатывает по ночам. Где именно — не говорит никому.',
    en: 'Lisa studies law and works night shifts somewhere. Where exactly, she never says.',
  },
  artur: {
    ru: 'Артур — бармен в «Полночи». Он слышит все ночные разговоры города и молчит за хорошие чаевые.',
    en: 'Arthur tends bar at the Midnight. He hears every late-night conversation in town, and keeps quiet for good tips.',
  },
  nina: {
    ru: 'Нина ведёт бухгалтерию половины бизнесов города. Цифры у неё всегда сходятся. Почти всегда.',
    en: 'Nina keeps the books for half the businesses in town. Her numbers always add up. Almost always.',
  },
  kostya: {
    ru: 'Костя развозит заказы на мопеде и знает каждый двор. Последнюю неделю он берёт только ночные смены.',
    en: 'Kevin delivers on a scooter and knows every backyard. This week he only takes night shifts.',
  },
  vika: {
    ru: 'Вика учит детей в школе у парка. Добрая, спокойная — и недавно продала дом за бесценок.',
    en: 'Vicky teaches at the school by the park. Kind and calm, and she just sold her house for next to nothing.',
  },
  oleg: {
    ru: 'Олег — прораб на стройке в порту. Должен деньги людям, которым не принято быть должным.',
    en: 'Owen runs the crew at the harbor site. He owes money to people you should never owe.',
  },
  rita: {
    ru: 'Рита тренирует половину города на пляже. Каждое утро бегает по пирсу — даже в то утро, когда там нашли тело.',
    en: 'Rita trains half the town on the beach. She runs the pier every morning, even the morning the body was found.',
  },
  slava: {
    ru: 'Слава возит людей по ночному городу на такси. Помнит всех пассажиров. Особенно тех, кто платил наличными за молчание.',
    en: 'Steve drives a night cab. He remembers every passenger, especially the ones who paid cash to be forgotten.',
  },
  emma: {
    ru: 'Эмма — дизайнер, приехала в город полгода назад. Никто не знает, откуда, и она не спешит рассказывать.',
    en: 'Emma is a designer who arrived six months ago. Nobody knows from where, and she is in no hurry to tell.',
  },
  gena: {
    ru: 'Гена охраняет полицейский участок по ночам. Видит, кто приходит и уходит. И иногда забывает записать.',
    en: 'Gene guards the police station at night. He sees who comes and goes, and sometimes forgets to write it down.',
  },
  alina: {
    ru: 'Алина ведёт блог о жизни города. Сто тысяч подписчиков ждут сенсацию, и она готова её найти. Любой ценой.',
    en: 'Alina vlogs about city life. A hundred thousand followers want a scoop, and she will get one at any cost.',
  },
  rustam: {
    ru: 'Рустам — шеф-повар в закусочной у трассы. Кухня работает до утра, а через заднюю дверь ходят не только поставщики.',
    en: 'Ross is head chef at the highway diner. The kitchen runs till dawn, and not only suppliers use the back door.',
  },
};

/** Предыстория героя на языке эфира (латинские эфиры — английская основа) */
function storyFor(slug) {
  const s = STORIES[slug];
  if (!s) return '';
  return LANG === 'ru' ? s.ru : s.en;
}

module.exports = { storyFor, STORIES };
