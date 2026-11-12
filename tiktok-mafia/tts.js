/**
 * ОЗВУЧКА.
 *
 * Голоса синтезирует сервер — нейроголоса Microsoft Edge (пакет msedge-tts):
 * бесплатно, без ключей, на всех языках эфира, у каждого героя свой голос.
 * Готовая фраза — mp3 в tts-cache/, сцена играет её обычным <audio>.
 * Так голос работает и в OBS, где встроенный синтез браузера часто молчит.
 *
 *   npm install            (один раз — ставит msedge-tts)
 *   TTS=off node server.js — выключить и вернуться к голосам браузера
 *
 * Если пакет не стоит или сервис голосов недоступен, событие уходит без
 * звука, и сцена озвучивает его голосом браузера, как раньше.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { LANG } = require('./i18n');

const DIR = path.join(__dirname, 'tts-cache');   // сервер отдаёт её как /tts-cache/<hash>.mp3
let lib = null;
if (process.env.TTS !== 'off') {
  try { lib = require('msedge-tts'); } catch { lib = null; }
}
const ON = !!lib;
if (ON) fs.mkdirSync(DIR, { recursive: true });

/**
 * Голоса по языку. У персонажа — свой голос и свой тембр (pitch/rate),
 * чтобы зритель узнавал говорящего, не глядя на подпись.
 * Русских голосов у Edge три, поэтому их различает тембр.
 */
const V = {
  en: {
    narrator: ['en-US-GuyNeural', '-4%', '-6Hz'], host: ['en-US-TonyNeural', '+0%', '+0Hz'],
    margo: ['en-US-AriaNeural', '+6%', '+2Hz'], david: ['en-US-DavisNeural', '+0%', '-4Hz'],
    liza: ['en-US-MichelleNeural', '-4%', '+0Hz'], artur: ['en-US-AndrewNeural', '+4%', '+0Hz'],
    nina: ['en-US-SaraNeural', '-2%', '-2Hz'], kostya: ['en-US-BrianNeural', '+8%', '+2Hz'],
    vika: ['en-US-JennyNeural', '+0%', '+0Hz'], oleg: ['en-US-RogerNeural', '-6%', '-6Hz'],
    rita: ['en-US-AvaNeural', '+6%', '+0Hz'], slava: ['en-US-SteffanNeural', '+2%', '+0Hz'],
    emma: ['en-US-EmmaNeural', '-2%', '+0Hz'], gena: ['en-US-ChristopherNeural', '-8%', '-8Hz'],
    alina: ['en-GB-SoniaNeural', '+8%', '+4Hz'], rustam: ['en-US-EricNeural', '-2%', '-4Hz'],
  },
  ru: {
    narrator: ['ru-RU-DmitryNeural', '-6%', '-8Hz'], host: ['ru-RU-DmitryNeural', '+0%', '+0Hz'],
    margo: ['ru-RU-SvetlanaNeural', '+8%', '+6Hz'], david: ['ru-RU-DmitryNeural', '+0%', '-6Hz'],
    liza: ['ru-RU-DariyaNeural', '-6%', '+4Hz'], artur: ['ru-RU-DmitryNeural', '+6%', '+4Hz'],
    nina: ['ru-RU-SvetlanaNeural', '-4%', '-4Hz'], kostya: ['ru-RU-DmitryNeural', '+10%', '+10Hz'],
    vika: ['ru-RU-DariyaNeural', '+0%', '+0Hz'], oleg: ['ru-RU-DmitryNeural', '-8%', '-12Hz'],
    rita: ['ru-RU-SvetlanaNeural', '+8%', '+0Hz'], slava: ['ru-RU-DmitryNeural', '+4%', '+0Hz'],
    emma: ['ru-RU-DariyaNeural', '-4%', '-4Hz'], gena: ['ru-RU-DmitryNeural', '-10%', '-14Hz'],
    alina: ['ru-RU-DariyaNeural', '+10%', '+8Hz'], rustam: ['ru-RU-DmitryNeural', '-4%', '-8Hz'],
  },
};
// испанский, немецкий, португальский: по два мужских и женских голоса, тембр различает героев
const PAIRS = {
  es: { m: ['es-ES-AlvaroNeural', 'es-MX-JorgeNeural'], f: ['es-ES-ElviraNeural', 'es-MX-DaliaNeural'] },
  de: { m: ['de-DE-ConradNeural', 'de-DE-KillianNeural'], f: ['de-DE-KatjaNeural', 'de-DE-AmalaNeural'] },
  pt: { m: ['pt-BR-AntonioNeural', 'pt-PT-DuarteNeural'], f: ['pt-BR-FranciscaNeural', 'pt-PT-RaquelNeural'] },
};
const FEMALE = new Set(['margo', 'liza', 'nina', 'vika', 'rita', 'emma', 'alina']);
const ORDER = ['narrator', 'host', 'margo', 'david', 'liza', 'artur', 'nina', 'kostya', 'vika', 'oleg', 'rita', 'slava', 'emma', 'gena', 'alina', 'rustam'];

function voiceFor(who) {
  const key = who || 'narrator';
  if (V[LANG]) return V[LANG][key] || V[LANG].narrator;
  const p = PAIRS[LANG];
  if (!p) return V.en[key] || V.en.narrator;
  const i = Math.max(0, ORDER.indexOf(key));
  const set = FEMALE.has(key) ? p.f : p.m;
  const shift = ((i * 7) % 5) - 2;   // −2..+2: каждому свой тембр
  return [set[i % 2], `${shift * 3}%`, `${shift * 3}Hz`];
}

// по одному соединению на голос: так быстрее, и фразы не перемешиваются
const conns = new Map();
const queue = new Map();
async function engineFor(voice) {
  if (conns.has(voice)) return conns.get(voice);
  const t = new lib.MsEdgeTTS();
  await t.setMetadata(voice, lib.OUTPUT_FORMAT.AUDIO_24KHZ_48KBITRATE_MONO_MP3);
  conns.set(voice, t);
  return t;
}
function serial(voice, job) {
  const prev = queue.get(voice) || Promise.resolve();
  const next = prev.catch(() => {}).then(job);
  queue.set(voice, next);
  return next;
}

/**
 * Озвучить фразу. Возвращает путь для сцены ('/tts-cache/<hash>.mp3') или null,
 * если озвучка выключена или не удалась. Повторная фраза берётся из кэша.
 */
async function speak(text, who, timeoutMs = 6000) {
  if (!ON || !text) return null;
  const clean = String(text).replace(/@/g, '').replace(/\s+/g, ' ').trim();
  if (!clean) return null;
  const [voice, rate, pitch] = voiceFor(who);
  const hash = crypto.createHash('sha1').update(`${voice}|${rate}|${pitch}|${clean}`).digest('hex').slice(0, 20);
  const file = path.join(DIR, `${hash}.mp3`);
  const url = `/tts-cache/${hash}.mp3`;
  if (fs.existsSync(file) && fs.statSync(file).size > 1000) return url;

  const job = () => new Promise(async (resolve) => {
    const timer = setTimeout(() => resolve(null), timeoutMs);
    try {
      const t = await engineFor(voice);
      const { audioStream } = t.toStream(clean, { rate, pitch });
      const parts = [];
      audioStream.on('data', (d) => parts.push(d));
      audioStream.on('end', () => {
        clearTimeout(timer);
        const buf = Buffer.concat(parts);
        if (buf.length < 1000) return resolve(null);
        fs.writeFileSync(file, buf);
        resolve(url);
      });
      audioStream.on('error', () => { clearTimeout(timer); conns.delete(voice); resolve(null); });
    } catch {
      clearTimeout(timer);
      conns.delete(voice);   // соединение умерло — в следующий раз откроем новое
      resolve(null);
    }
  });
  return serial(voice, job);
}

module.exports = { speak, voiceFor, ON, DIR };
