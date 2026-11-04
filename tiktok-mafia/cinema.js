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

const NIGHT = ['night-alley', 'night-steps', 'night-car', 'night-gun', 'night-rooftop'];

/** Ночь: жертва уходит одна, следом шаги убийцы, дверь открывается.
    Кто жертва, зритель узнает утром — сейчас это просто чей-то последний вечер. */
function nightReel(victim, pick) {
  const killer = pick(NIGHT);
  const second = pick(NIGHT.filter((n) => n !== killer));
  return [victim && walk(victim.slug), clip(killer), victim ? clip('night-door') : clip(second)];
}

/** Тихая ночь: убийца вышел, но до двери не дошёл */
function quietReel(pick) {
  return [clip(pick(NIGHT))];
}

/** Утро после убийства */
function morningReel() {
  return [clip('morning-police'), clip('morning-tape'), clip('morning-sheet'), clip('morning-detective')];
}

/** Зал изгнал игрока: мафию уводят в наручниках, мирный уходит из города */
function banishReel(p) {
  return p.role === 'traitor'
    ? [clip('final-arrest'), clip('final-backseat')]
    : [walk(p.slug)];
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

module.exports = { clip, walk, nightReel, quietReel, morningReel, banishReel, finaleReel, reelMs, ON };
