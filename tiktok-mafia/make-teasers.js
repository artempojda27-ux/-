/**
 * ТИЗЕРЫ ДЛЯ TIKTOK.
 *
 * Короткие вертикальные ролики из готовых клипов: зацепка в первые
 * 2 секунды, история, вопрос в конце («кто мафия? пиши в комменты»).
 * Ничего не генерирует — только режет и подписывает то, что уже есть.
 *
 *   node make-teasers.js          → teasers/ru/*.mp4 и teasers/en/*.mp4
 *   node make-teasers.js ru       → только русские
 *
 * Нужны ffmpeg и playwright (надписи рисуются браузером в прозрачный PNG).
 * Звука в роликах нет специально: в TikTok добавь трендовый звук из
 * библиотеки — так ролик лучше показывают, и с правами всё чисто.
 * Текст держится в безопасной зоне: снизу и справа его закроют кнопки TikTok.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const ROOT = __dirname;
const OUT = path.join(ROOT, 'teasers');
const C = (n) => `assets/gta/clips/${n}.mp4`;
const T = (slug, mood = 'talk') => `assets/gta/talk/${slug}-${mood}.mp4`;

const NAMES = {
  margo: ['Марго', 'Margo'], david: ['Давид', 'David'], liza: ['Лиза', 'Lisa'], artur: ['Артур', 'Arthur'],
  nina: ['Нина', 'Nina'], kostya: ['Костя', 'Kevin'], vika: ['Вика', 'Vicky'], oleg: ['Олег', 'Owen'],
  rita: ['Рита', 'Rita'], slava: ['Слава', 'Steve'], emma: ['Эмма', 'Emma'], gena: ['Гена', 'Gene'],
  alina: ['Алина', 'Alina'], rustam: ['Рустам', 'Ross'],
};
const BIO = {
  margo: ['салон красоты', 'beauty salon owner'], david: ['бывший военный', 'ex-military'],
  rustam: ['шеф-повар', 'head chef'], alina: ['блогер', 'vlogger'], gena: ['ночной охранник', 'night guard'],
  kostya: ['курьер', 'courier'], vika: ['учительница', 'teacher'], rita: ['фитнес-тренер', 'fitness coach'],
  slava: ['таксист', 'cab driver'], nina: ['бухгалтер', 'accountant'], oleg: ['прораб', 'site foreman'],
};

/*
 * Ролик — список планов. План: клип, с какой секунды, сколько, надписи.
 * Надпись: [вид, текст(ru,en), от, до] — время внутри плана.
 * dim — затемнить план (под финальную надпись).
 */
function teasers(L) {
  const t = (ru, en) => (L === 'ru' ? ru : en);
  const n = (s) => NAMES[s][L === 'ru' ? 0 : 1];
  const bio = (s) => BIO[s][L === 'ru' ? 0 : 1];
  const end = (ru, en, subRu, subEn) => ['end', t(ru, en), t(subRu, subEn)];

  return [
    { id: '01-kto-mafiya', shots: [
      ...['margo', 'rustam', 'alina', 'david', 'gena', 'vika', 'kostya'].map((s, i) => ({
        src: T(s), ss: 0.6, d: 1.5,
        over: [['name', n(s), bio(s), 0, 1.5], ...(i < 3 ? [['hook', t('ОДИН ИЗ НИХ <em>УБИЙЦА</em>', 'ONE OF THEM <em>IS A KILLER</em>'), '', 0, 1.5]] : [])],
      })),
      { src: T('margo', 'accuse'), ss: 1, d: 3, dim: true,
        over: [[...end('Кто?', 'Who?', 'Пиши имя в комментарии', 'Drop a name in the comments'), 0.1, 3]] },
    ] },

    { id: '02-nochnaya-kamera', shots: [
      { src: C('nina-walk'), ss: 0.5, d: 3, over: [['cctv', t('КАМЕРА 17', 'CAMERA 17'), '00:41', 0, 3],
        ['cap', t(`${n('nina')} уходит из бара одна`, `${n('nina')} leaves the bar alone`), '', 0.3, 3],
        ['hook', t('ЗАПИСЬ, КОТОРУЮ <em>НЕ ДОЛЖНЫ</em> БЫЛИ УВИДЕТЬ', 'FOOTAGE NOBODY <em>WAS MEANT</em> TO SEE'), '', 0, 3]] },
      { src: C('night-alley'), ss: 0.6, d: 2.8, over: [['cctv', t('КАМЕРА 17', 'CAMERA 17'), '00:43', 0, 2.8],
        ['cap', t('Кто-то идёт следом', 'Someone is following'), '', 0.2, 2.8]] },
      { src: C('night-steps'), ss: 0.6, d: 2.4, over: [['cctv', t('КАМЕРА 21', 'CAMERA 21'), '00:47', 0, 2.4]] },
      { src: C('murder-alley'), ss: 0.3, d: 4.4, over: [['cctv', t('КАМЕРА 21', 'CAMERA 21'), '00:48', 0, 4.4],
        ['cap', t('Тень убийцы', "The killer's shadow"), '', 0.4, 4.4]] },
      { src: C('murder-alley'), ss: 4.2, d: 2.6, dim: true,
        over: [[...end('Кто это был?', 'Who was it?', 'Ответ — в прямом эфире', 'The answer is on LIVE'), 0.1, 2.6]] },
    ] },

    { id: '03-utro', shots: [
      { src: C('morning-police'), ss: 0.5, d: 2.6, over: [['hook', t('УТРО. <em>КТО-ТО</em> НЕ ВЕРНУЛСЯ ДОМОЙ', 'MORNING. <em>SOMEONE</em> NEVER CAME HOME'), '', 0, 2.6]] },
      { src: C('morning-tape'), ss: 0.6, d: 2.2, over: [] },
      { src: C('morning-sheet'), ss: 0.6, d: 3, over: [['cap', t('Пирс, 07:40', 'The pier, 7:40 AM'), '', 0.2, 3]] },
      { src: T('alina', 'defend'), ss: 0.6, d: 2.4, over: [['name', n('alina'), '', 0, 2.4], ['cap', t('«Я была дома. Спала.»', '"I was home. Asleep."'), '', 0.2, 2.4]] },
      { src: T('rustam', 'defend'), ss: 0.6, d: 2.4, over: [['name', n('rustam'), '', 0, 2.4], ['cap', t('«Кухня работала до утра.»', '"The kitchen was open all night."'), '', 0.2, 2.4]] },
      { src: T('gena', 'defend'), ss: 1, d: 2.8, dim: true,
        over: [[...end('Один из них врёт', 'One of them is lying', 'Кто? Пиши в комменты', 'Who? Comment below'), 0.1, 2.8]] },
    ] },

    { id: '04-dopros', shots: [
      { src: C('final-interrog'), ss: 0.5, d: 3, over: [['q', t('ДОПРОС · 08:16', 'INTERROGATION · 8:16 AM'), t('Где вы были этой ночью?', 'Where were you last night?'), 0, 3]] },
      { src: T('vika', 'defend'), ss: 0.6, d: 2.6, over: [['name', n('vika'), '', 0, 2.6], ['cap', t('«У причала. Там была ещё Рита.»', '"At the pier. Rita was there too."'), '', 0.2, 2.6]] },
      { src: T('david', 'defend'), ss: 0.6, d: 2.6, over: [['name', n('david'), '', 0, 2.6], ['cap', t('«Дома. Один. Проверяйте.»', '"Home. Alone. Check it."'), '', 0.2, 2.6]] },
      { src: T('rita', 'talk'), ss: 0.6, d: 2.6, over: [['name', n('rita'), '', 0, 2.6], ['cap', t('«Я не была у причала.»', '"I was never at the pier."'), '', 0.2, 2.6]] },
      { src: T('vika', 'accuse'), ss: 1, d: 3, dim: true,
        over: [[...end('Кто соврал?', 'Who lied?', 'Вика или Рита?', 'Vicky or Rita?'), 0.1, 3]] },
    ] },

    { id: '05-vskrytie', shots: [
      { src: T('kostya', 'accuse'), ss: 0.6, d: 2.2, over: [['hook', t('ЗАЛ РЕШИЛ <em>ИЗГНАТЬ</em> ЕЁ', 'THE CHAT VOTED HER <em>OUT</em>'), '', 0, 2.2], ['cap', t('«Это она! Я видел!»', '"It was her! I saw her!"'), '', 0.2, 2.2]] },
      { src: T('slava', 'accuse'), ss: 0.6, d: 2, over: [['cap', t('«Хватит её защищать!»', '"Stop protecting her!"'), '', 0.1, 2]] },
      { src: T('margo', 'defend'), ss: 0.6, d: 2.8, over: [['name', n('margo'), t('изгнана · 73% голосов', 'voted out · 73%'), 0, 2.8], ['cap', t('«Вы ошибаетесь…»', '"You\'re making a mistake…"'), '', 0.3, 2.8]] },
      { src: C('final-arrest'), ss: 0.4, d: 2.6, dim: true, over: [['big', t('МАРГО БЫЛА…', 'MARGO WAS…'), '', 0.2, 2.6]] },
      { src: C('final-backseat'), ss: 0.6, d: 2.6, dim: true,
        over: [[...end('Мафией?', 'The mafia?', 'Узнай в эфире', 'Find out on LIVE'), 0.1, 2.6]] },
    ] },

    ...[['rustam', 'Рустам — шеф-повар в закусочной у трассы.', 'Кухня работает до утра, а через заднюю дверь ходят <em>не только поставщики</em>.',
      'Ross is head chef at the highway diner.', 'The kitchen runs till dawn, and <em>not only suppliers</em> use the back door.'],
     ['gena', 'Гена охраняет полицейский участок по ночам.', 'Видит, кто приходит и уходит. И иногда <em>забывает записать</em>.',
      'Gene guards the police station at night.', 'He sees who comes and goes, and sometimes <em>forgets to write it down</em>.'],
     ['slava', 'Слава возит людей по ночному городу.', 'Помнит всех пассажиров. Особенно тех, кто платил <em>за молчание</em>.',
      'Steve drives a night cab.', 'He remembers every passenger, especially the ones who paid <em>to be forgotten</em>.']]
      .map(([s, ru1, ru2, en1, en2], i) => ({ id: `0${6 + i}-geroy-${s}`, shots: [
        { src: T(s), ss: 0.6, d: 3.2, over: [['name', n(s), bio(s), 0, 3.2], ['cap', t(ru1, en1), '', 0.2, 3.2]] },
        { src: C(`${s}-walk`), ss: 0.6, d: 3.8, over: [['cap', t(ru2, en2), '', 0.1, 3.8]] },
        { src: T(s, 'defend'), ss: 1, d: 3, dim: true,
          over: [[...end('Мафия или нет?', 'Mafia or not?', 'Решать будете вы', 'You decide'), 0.1, 3]] },
      ] })),

    { id: '09-anons', shots: [
      { src: C('day-aerial'), ss: 0.2, d: 3, over: [['hook', t('<em>ГОРОД ЗАСЫПАЕТ</em>', '<em>THE CITY SLEEPS</em>'), t('интерактивная мафия в прямом эфире', 'interactive mafia, live'), 0.2, 3]] },
      { src: C('life-bar'), ss: 0.6, d: 2, over: [['cap', t('8 жителей. 2 из них — мафия.', '8 people. 2 of them are mafia.'), '', 0.1, 2]] },
      { src: C('night-alley'), ss: 0.6, d: 2, over: [['cap', t('Каждую ночь кто-то пропадает.', 'Every night someone disappears.'), '', 0.1, 2]] },
      { src: C('final-interrog'), ss: 0.6, d: 2.2, over: [['cap', t('Вы допрашиваете. Вы голосуете.', 'You question them. You vote.'), '', 0.1, 2.2]] },
      { src: C('final-arrest'), ss: 0.6, d: 2.2, over: [['cap', t('Ошибётесь — изгоните невиновного.', 'Get it wrong and an innocent walks.'), '', 0.1, 2.2]] },
      { src: C('final-pier'), ss: 0.6, d: 3, dim: true,
        over: [[...end('Сегодня в эфире', 'Tonight, LIVE', 'Подпишись, чтобы не пропустить', 'Follow so you don\'t miss it'), 0.1, 3]] },
    ] },
  ];
}

/* ── надписи: HTML → прозрачный PNG 1080×1920 ── */
const CSS = `
*{margin:0;padding:0;box-sizing:border-box}
body{width:1080px;height:1920px;background:transparent;font-family:'Inter Display','Inter',sans-serif;color:#fff;position:relative;overflow:hidden}
em{font-style:normal;color:#ffcf4a}
.sh{text-shadow:0 4px 22px rgba(0,0,0,.95),0 2px 4px rgba(0,0,0,.9)}
.hook{position:absolute;left:80px;right:150px;top:250px;font-weight:900;font-size:86px;line-height:1.02;letter-spacing:-1px;text-transform:uppercase}
.hook small{display:block;margin-top:22px;font:700 34px/1.2 'DejaVu Sans Mono',monospace;letter-spacing:.12em;text-transform:uppercase;color:#ffcf4a}
.cap{position:absolute;left:80px;right:150px;bottom:620px;font-weight:800;font-size:58px;line-height:1.15}
.cap span{background:rgba(0,0,0,.55);box-decoration-break:clone;-webkit-box-decoration-break:clone;padding:4px 16px;border-radius:10px}
.name{position:absolute;left:80px;bottom:780px;font-weight:900;font-size:96px;line-height:1}
.name small{display:block;margin-top:12px;font:700 32px/1 'DejaVu Sans Mono',monospace;letter-spacing:.18em;text-transform:uppercase;color:#ffcf4a}
.cctv{position:absolute;inset:150px 60px 560px 60px;border:0}
.cctv i{position:absolute;width:70px;height:70px;border-color:rgba(255,255,255,.85);border-style:solid}
.cctv i:nth-child(1){left:0;top:0;border-width:5px 0 0 5px}.cctv i:nth-child(2){right:0;top:0;border-width:5px 5px 0 0}
.cctv i:nth-child(3){left:0;bottom:0;border-width:0 0 5px 5px}.cctv i:nth-child(4){right:0;bottom:0;border-width:0 5px 5px 0}
.cctv b{position:absolute;top:28px;left:34px;font:700 38px/1 'DejaVu Sans Mono',monospace;letter-spacing:.08em}
.cctv b:before{content:'';display:inline-block;width:26px;height:26px;border-radius:50%;background:#ff2a2a;margin-right:16px;vertical-align:-2px}
.cctv u{position:absolute;top:28px;right:34px;text-decoration:none;font:700 38px/1 'DejaVu Sans Mono',monospace}
.q{position:absolute;left:80px;right:80px;top:300px;text-align:center}
.q small{display:block;font:700 34px/1 'DejaVu Sans Mono',monospace;letter-spacing:.2em;color:#ffcf4a}
.q div{margin-top:24px;font-weight:900;font-size:76px;line-height:1.05}
.big{position:absolute;left:60px;right:60px;top:760px;text-align:center;font-weight:900;font-size:120px;letter-spacing:-1px;line-height:1}
.end{position:absolute;left:70px;right:70px;top:640px;text-align:center}
.end div{font-weight:900;font-size:128px;line-height:1;letter-spacing:-2px}
.end small{display:block;margin-top:34px;font-weight:800;font-size:52px;color:#ffcf4a}
`;
function html(kind, a, b) {
  const body = {
    hook: `<div class="hook sh">${a}${b ? `<small>${b}</small>` : ''}</div>`,
    cap: `<div class="cap sh"><span>${a}</span></div>`,
    name: `<div class="name sh">${a}${b ? `<small>${b}</small>` : ''}</div>`,
    cctv: `<div class="cctv sh"><i></i><i></i><i></i><i></i><b>REC · ${a}</b><u>${b}</u></div>`,
    q: `<div class="q sh"><small>${a}</small><div>${b}</div></div>`,
    big: `<div class="big sh">${a}</div>`,
    end: `<div class="end sh"><div>${a}</div><small>${b}</small></div>`,
  }[kind];
  return `<!doctype html><meta charset="utf-8"><style>${CSS}</style>${body}`;
}

function ff(args) { execFileSync('ffmpeg', ['-nostdin', '-loglevel', 'error', '-y', ...args], { stdio: 'inherit' }); }

async function build(L, page, tmp) {
  const dir = path.join(OUT, L);
  fs.mkdirSync(dir, { recursive: true });
  let png = 0;
  for (const tz of teasers(L)) {
    const parts = [];
    for (const [k, sh] of tz.shots.entries()) {
      const inputs = ['-ss', String(sh.ss), '-t', String(sh.d), '-i', path.join(ROOT, sh.src)];
      // свет плана: под финальную надпись кадр темнее и чуть размыт
      let chain = `[0:v]scale=1080:1920:flags=lanczos,setsar=1,fps=30${sh.dim ? ',eq=brightness=-0.07:saturation=0.85,boxblur=5:1' : ''}[v0]`;
      let last = 'v0';
      for (const [j, o] of sh.over.entries()) {
        const [kind, a, b, t0, t1] = o;
        const file = path.join(tmp, `o${png++}.png`);
        await page.setContent(html(kind, a, b));
        await page.screenshot({ path: file, omitBackground: true });
        inputs.push('-loop', '1', '-t', String(sh.d), '-i', file);
        const fadeIn = kind === 'cctv' ? '' : `,fade=t=in:st=${t0}:d=0.18:alpha=1`;
        chain += `;[${j + 1}:v]format=rgba${fadeIn}[o${j}];[${last}][o${j}]overlay=0:0:enable='between(t,${t0},${t1})'[v${j + 1}]`;
        last = `v${j + 1}`;
      }
      const part = path.join(tmp, `${tz.id}-${k}.mp4`);
      ff([...inputs, '-filter_complex', chain, '-map', `[${last}]`, '-t', String(sh.d),
        '-c:v', 'libx264', '-preset', 'medium', '-crf', '19', '-pix_fmt', 'yuv420p', '-r', '30', part]);
      parts.push(part);
    }
    const list = path.join(tmp, `${tz.id}.txt`);
    fs.writeFileSync(list, parts.map((p) => `file '${p}'`).join('\n'));
    const out = path.join(dir, `${tz.id}.mp4`);
    // тихая дорожка: TikTok и монтажки ждут звук в файле; свой звук — из библиотеки TikTok
    ff(['-f', 'concat', '-safe', '0', '-i', list, '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
      '-map', '0:v', '-map', '1:a', '-c:v', 'copy', '-c:a', 'aac', '-shortest', '-movflags', '+faststart', out]);
    const dur = tz.shots.reduce((s, x) => s + x.d, 0);
    console.log(`${L}/${tz.id}.mp4  ${dur.toFixed(1)} с`);
  }
}

(async () => {
  const langs = process.argv[2] ? [process.argv[2]] : ['ru', 'en'];
  const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'teasers-'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
  try { for (const L of langs) await build(L, page, tmp); }
  finally { await browser.close(); fs.rmSync(tmp, { recursive: true, force: true }); }
})();
