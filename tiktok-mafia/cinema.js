/**
 * КИНО-ВСТАВКИ.
 *
 * Видеоклипы из assets/gta/clips/ идут между сценами партии во весь кадр,
 * как катсцены в игре: ночью кто-то уходит в темноту и убийца идёт следом,
 * утром полиция и тело под простынёй, изгнанного уводят в наручниках или
 * он уходит из города, в финале — пирс на рассвете или машина мафии.
 *
 * Ночные клипы сняты без лиц: убийцу не видно, поэтому они подходят
 * к любому раскладу и ничего не выдают зрителю.
 *
 * Клипа нет на диске — вставка его пропускает, нет ни одного — вставки
 * нет вовсе, и эфир идёт как раньше. CINEMA=off выключает их совсем.
 */

const fs = require('fs');
const path = require('path');

const DIR = path.join(__dirname, 'assets', 'gta', 'clips');
const URL = 'assets/gta/clips/';
const ON = process.env.CINEMA !== 'off';

// длина клипов: почти все по 5 секунд, склейка Марго — 10
const LONG = { 'margo-scene-full': 10000 };
const CLIP_MS = 5040;

const has = (name) => fs.existsSync(path.join(DIR, `${name}.mp4`));

/** Клип по имени или null, если его нет */
function clip(name) {
  return ON && has(name) ? { src: `${URL}${name}.mp4`, ms: LONG[name] || CLIP_MS } : null;
}

/** Персонаж уходит в ночь. У Марго — длинная склейка: бар и дверь */
function walk(slug) {
  return clip(slug === 'margo' ? 'margo-scene-full' : `${slug}-walk`)
    || clip(`${slug}-leaves-bar`);
}

// Пулы клипов. Чем больше в пуле, тем реже зритель видит одно и то же:
// выбор идёт из давно не показанных, а не просто случайно.
const NIGHT = ['night-alley', 'night-steps', 'night-car', 'night-gun', 'night-rooftop',
  'night-elevator', 'night-payphone', 'night-fireescape', 'night-boat', 'night-motel'];
const NIGHT_END = ['night-door', 'night-elevator', 'night-motel'];
const MORNING = ['morning-police', 'morning-tape', 'morning-detective', 'morning-news',
  'morning-evidence', 'morning-crowd'];
const ARREST = [['final-arrest', 'final-backseat'], ['final-chase', 'final-arrest'],
  ['final-arrest', 'final-interrog'], ['final-chase', 'final-backseat']];

// память показов: живёт весь эфир, между партиями тоже
const shown = new Map();
let tick = 0;
/** n клипов из пула, сначала те, что показывали давнее всего; ничья — случайно */
function fresh(pool, n, rand = Math.random) {
  const ok = pool.filter(has);
  // кандидаты — на один больше, чем нужно: иначе пул из 6 по 3 ходит
  // по кругу одними и теми же тройками; порядок внутри — тоже случайный
  const pickd = ok
    .map((name) => ({ name, at: shown.get(name) ?? -1, r: rand() }))
    .sort((a, b) => a.at - b.at || a.r - b.r)
    .slice(0, Math.min(ok.length, n + 1))
    .sort(() => rand() - 0.5)
    .slice(0, n)
    .map((x) => x.name);
  for (const name of pickd) shown.set(name, ++tick);
  return pickd;
}

/** Ночь: жертва уходит одна, следом убийца, и финальный кадр — дверь,
    лифт или мотель. Кто жертва, зритель узнает утром. */
function nightReel(victim) {
  const end = victim ? fresh(NIGHT_END, 1) : [];
  const killer = fresh(NIGHT.filter((n) => !end.includes(n)), victim ? 1 : 2);
  return [victim && walk(victim.slug), ...killer.map(clip), ...end.map(clip)];
}

/** Тихая ночь: убийца вышел, но до двери не дошёл */
function quietReel() {
  return fresh(NIGHT, 1).map(clip);
}

/** Утро после убийства: простыня всегда, вокруг неё — каждый раз другое */
function morningReel() {
  const [a, b, c] = fresh(MORNING, 3);
  return [clip(a), clip(b), clip('morning-sheet'), clip(c)];
}

/** Зал изгнал игрока: мафию уводят в наручниках, мирный уходит из города */
function banishReel(p) {
  if (p.role !== 'traitor') return [walk(p.slug)];
  const ok = ARREST.filter((pair) => pair.every(has));
  const key = (pair) => shown.get(pair.join('+')) ?? -1;
  const pair = ok.sort((a, b) => key(a) - key(b) || Math.random() - 0.5)[0] || ['final-arrest', 'final-backseat'];
  shown.set(pair.join('+'), ++tick);
  return pair.map(clip);
}

/** Открытие партии: город с воздуха и солнечная улица под титры */
function openingReel() {
  return [clip('day-aerial'), clip('day-street')];
}

/** Финал партии */
function finaleReel(winner, survivors) {
  if (winner === 'faithful') return [clip('final-pier')];
  // мафия победила: кто-то из неё напоследок уходит в ночь, и машина — в рассвет
  const boss = survivors.find((p) => p.role === 'traitor');
  return [boss && walk(boss.slug), clip('final-car')];
}

/** Сколько ждать движку, пока вставка идёт в эфире */
const reelMs = (clips) => clips.reduce((s, c) => s + c.ms, 0) + 700;

module.exports = { clip, walk, openingReel, nightReel, quietReel, morningReel, banishReel, finaleReel, reelMs, ON };
