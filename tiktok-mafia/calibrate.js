/**
 * ОТЧЁТ ПО КАЛИБРОВКЕ.
 *
 *   node calibrate.js
 *
 * Читает calibration.json, который сервер пишет после каждой партии,
 * и говорит, что двигать. Смотреть после 10–15 партий с живым залом:
 * на меньшем числе это шум, а не сигнал.
 *
 * Логика простая. Уровень, который не покупали ни разу, стоит слишком
 * дорого — контент есть, а увидеть его нельзя. Уровень, который упирается
 * в потолок каждую партию, стоит слишком дёшево — игра рассыпается.
 * И отдельно считаются подарки, ушедшие впустую: зритель заплатил,
 * а имя назвать забыл.
 */

'use strict';

const fs = require('fs');
const { TIERS } = require('./gifts');

let log = [];
try {
  log = JSON.parse(fs.readFileSync('calibration.json', 'utf8'));
} catch {
  console.log('Пока нет calibration.json — он появится после первой партии на сервере.');
  process.exit(0);
}

if (!log.length) {
  console.log('Журнал пуст.');
  process.exit(0);
}

const n = log.length;
const sum = (f) => log.reduce((s, p) => s + (f(p) || 0), 0);

const coins = sum((p) => p.coins);
const gifts = sum((p) => p.gifts);
const noTarget = sum((p) => p.noTarget);

console.log(`\nПартий в журнале: ${n}`);
console.log(`Подарков: ${gifts}  (${(gifts / n).toFixed(1)} за партию)`);
console.log(`Монет: ${coins}  ≈ $${(coins * 0.0053).toFixed(2)} автору`);
console.log(`В среднем за партию: ${Math.round(coins / n)} монет\n`);

// ── по уровням ──
console.log('УРОВЕНЬ                 куплено   за партию');
const perKind = {};
for (const p of log) for (const [k, v] of Object.entries(p.byKind || {})) perKind[k] = (perKind[k] || 0) + v;

for (const t of TIERS) {
  const got = perKind[t.kind] || 0;
  const per = got / n;
  console.log(
    `${t.label.padEnd(20)} ${String(got).padStart(7)} ${per.toFixed(2).padStart(11)}`
  );
}

// ── отказы ──
const drops = {};
for (const p of log) for (const d of p.dropped || []) {
  const key = `${d.kind} — ${d.reason}`;
  drops[key] = (drops[key] || 0) + 1;
}
if (Object.keys(drops).length) {
  console.log('\nОТКЛОНЕНО');
  for (const [k, v] of Object.entries(drops).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${k}: ${v}`);
  }
}

// ── что делать ──
console.log('\nЧТО ДВИГАТЬ');
const advice = [];

for (const t of TIERS) {
  if (t.kind === 'vote') continue;
  const got = perKind[t.kind] || 0;
  const per = got / n;

  if (got === 0 && n >= 10) {
    advice.push(`«${t.label}» не покупали ни разу за ${n} партий — порог ${t.min} слишком высокий. Опусти на уровень ниже.`);
  } else if (t.perParty && per >= t.perParty * 0.9) {
    advice.push(`«${t.label}» каждую партию упирается в потолок (${t.perParty}) — либо подними порог, либо снизь потолок.`);
  } else if (per > 0 && per < 0.15 && n >= 15) {
    advice.push(`«${t.label}» покупают раз в ${Math.round(1 / per)} партий — редковато, можно опустить порог.`);
  }
}

const limitDrops = Object.entries(drops).filter(([k]) => k.includes('лимит')).reduce((s, x) => s + x[1], 0);
if (limitDrops > n * 0.5) {
  advice.push(`Отказов по лимиту ${limitDrops} — спрос выше, чем пропускает игра. Это деньги мимо: подними порог, чтобы отсеивать ценой, а не отказом.`);
}

if (noTarget > gifts * 0.25) {
  advice.push(`${Math.round(noTarget / gifts * 100)}% подарков ушли без цели — зрители не пишут имя перед подарком. Подсказку на экране надо делать заметнее.`);
}

const lateDrops = Object.entries(drops).filter(([k]) => k.includes('поздний')).reduce((s, x) => s + x[1], 0);
if (lateDrops > n * 0.3) {
  advice.push(`Проверку часто покупают поздно (${lateDrops} раз). Окно можно расширить до 3 раундов, но не дальше: поздняя проверка почти решает партию.`);
}

if (!advice.length) advice.push('Пороги выглядят сбалансированно. Ничего не трогай.');
advice.forEach((a, i) => console.log(`${i + 1}. ${a}`));

console.log(`\nМеньше 10 партий — это шум. Сейчас в журнале ${n}.\n`);
