/**
 * СОБЫТИЙНЫЕ КАРТЫ.
 *
 * Реплики модель и так каждый раз пишет новые. Приедается не текст, а форма:
 * ночь — обсуждение — голосование, по кругу. Карты ломают форму.
 *
 * Выпадают не чаще одной за раунд и не с первого раунда — первый должен
 * отыграться чисто, чтобы новый зритель понял правила.
 */

const { tr } = require('./i18n');
const she = (p) => /^женск/.test(p?.voice || '');

const EVENTS = [
  {
    id: 'note',
    chance: 0.22,
    title: tr('АНОНИМНАЯ ЗАПИСКА', 'ANONYMOUS NOTE'),
    // улика на случайного — она может быть и ложной, и это главное
    apply(state, api) {
      const alive = state.players.filter((p) => p.alive);
      const target = api.pick(alive);
      const truthful = target.role === 'traitor';
      state.event = {
        id: 'note',
        target: target.name,
        truthful,
        publicText: tr(
          `Под дверью нашли записку: "Ночью я видел, как ${target.name} ${she(target) ? 'выходила' : 'выходил'} из комнаты". Кто написал — неизвестно.`,
          `A note was slipped under the door: "Last night I saw ${target.name} sneaking out." Nobody knows who wrote it.`),
      };
      return state.event.publicText;
    },
  },
  {
    id: 'shield',
    chance: 0.18,
    title: tr('ЩИТ', 'SHIELD'),
    // один защищён от ночи; знает об этом только он сам
    apply(state, api) {
      const alive = state.players.filter((p) => p.alive);
      const target = api.pick(alive);
      state.shielded = target.name;
      state.event = { id: 'shield', target: target.name };
      return tr('Кто-то из участников получил щит на эту ночь. Дом не знает, кто именно.',
        'Someone got a shield for tonight. Nobody knows who.');
    },
  },
  {
    id: 'silent_night',
    chance: 0.15,
    title: tr('ТИХАЯ НОЧЬ', 'QUIET NIGHT'),
    apply(state) {
      state.skipNight = true;
      state.event = { id: 'silent_night' };
      return tr('Этой ночью никто не выбыл. Все живы — и никто не понимает, что это значит.',
        'Nobody dies tonight. Everyone lives — and nobody knows what that means.');
    },
  },
  {
    id: 'double',
    chance: 0.12,
    title: tr('ДВОЙНОЕ ИЗГНАНИЕ', 'DOUBLE EXILE'),
    apply(state) {
      state.doubleBanish = true;
      state.event = { id: 'double' };
      return tr('Сегодня дом покинут ДВОЕ. Зрители выбирают обоих.',
        'TWO people leave today. You choose both.');
    },
  },
  {
    id: 'open_vote',
    chance: 0.15,
    title: tr('ОТКРЫТОЕ СЛОВО', 'NAME A NAME'),
    // каждый обязан вслух назвать подозреваемого — резко ускоряет расклад
    apply(state) {
      state.openVote = true;
      state.event = { id: 'open_vote' };
      return tr('Каждый обязан прямо сейчас назвать одно имя. Молчать нельзя.',
        'Everyone must name one person right now. Silence is not an option.');
    },
  },
  {
    id: 'return',
    chance: 0.08,
    title: tr('ВОЗВРАЩЕНИЕ', 'THE RETURN'),
    // возвращается тот, кого выгнали ночью (то есть заведомо верный)
    apply(state, api) {
      const dead = state.players.filter((p) => !p.alive && p.outBy === 'night');
      if (!dead.length) return null;
      const back = api.pick(dead);
      back.alive = true;
      back.returned = true;
      state.event = { id: 'return', target: back.name };
      return tr(`${back.name} возвращается в дом. ${she(back) ? 'Она выбыла' : 'Он выбыл'} ночью — значит ${she(back) ? 'она точно ВЕРНАЯ' : 'он точно ВЕРНЫЙ'}.`,
        `${back.name} is back. ${she(back) ? 'She' : 'He'} died in the night — so ${she(back) ? 'she' : 'he'} is definitely INNOCENT.`);
    },
  },
];

/**
 * Выбор события на раунд. Минимум раундов без событий = 1.
 * cooldown не даёт одной и той же карте выпасть два раунда подряд.
 */
function rollEvent(state, api) {
  if (state.round < 2) return null;
  if (state.lastEventRound === state.round - 1 && api.rand() < 0.6) return null;

  const pool = EVENTS.filter((e) => e.id !== state.lastEventId);
  for (const e of pool) {
    if (api.rand() < e.chance) {
      const text = e.apply(state, api);
      if (!text) continue;
      state.lastEventId = e.id;
      state.lastEventRound = state.round;
      return { title: e.title, text };
    }
  }
  return null;
}

/** Сброс разовых флагов после раунда */
function clearEvent(state) {
  state.shielded = null;
  state.skipNight = false;
  state.doubleBanish = false;
  state.openVote = false;
  state.event = null;
}

module.exports = { EVENTS, rollEvent, clearEvent };
