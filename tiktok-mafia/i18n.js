/**
 * ЯЗЫК ЭФИРА.
 *
 *     STREAM_LANG=en node server.js     — английский (Европа и США)
 *     STREAM_LANG=es node server.js     — испанский; так же de, pt — пакеты в lang/
 *     STREAM_LANG=ru node server.js     — русский (по умолчанию)
 *
 * Не LANG: это системная локаль, она почти всегда выставлена (C.UTF-8,
 * en_US.UTF-8) и включала бы английский эфир сама собой.
 *
 * Русский и английский живут прямо в коде: tr('УТРО', 'MORNING').
 * Остальные языки — пакеты lang/<код>.js: словарь переводит английскую
 * строку, а имена персонажей во всех не-русских эфирах те же, что
 * в английском, — их легко набрать в чате с любой латинской клавиатуры.
 * Новый язык: скопируй lang/es.js, переведи, добавь строки в T в scene.html.
 * Пульт оператора (консоль) остаётся русским.
 */
const fs = require('fs');
const path = require('path');

const PACKS = fs.readdirSync(path.join(__dirname, 'lang'))
  .filter((f) => /^[a-z]{2}\.js$/.test(f)).map((f) => f.slice(0, 2));
const want = (process.env.STREAM_LANG || '').toLowerCase().slice(0, 2);
const LANG = want === 'en' || PACKS.includes(want) ? want : 'ru';
/** латинские имена и английская основа: всё, кроме русского */
const LATIN = LANG !== 'ru';
const PACK = PACKS.includes(LANG) ? require(`./lang/${LANG}`) : null;

const fill = (s, vars) => (vars ? s.replace(/\{(\w+)\}/g, (_, k) => vars[k] ?? '') : s);

/**
 * Строка для эфира: tr('УТРО', 'MORNING').
 * С подстановками английский — шаблон: tr(`Утро, ${n}`, 'Morning, {name}', { name: n }).
 */
function tr(ru, en, vars) {
  if (LANG === 'ru') return ru;
  const s = PACK?.t?.[en];
  if (PACK && s === undefined) console.warn(`[i18n] нет перевода (${LANG}): ${en}`);
  return fill(s ?? en, vars);
}

module.exports = { LANG, LATIN, PACK, PACKS, tr };
