// Джарвис: утренний звонок на твой телефон с планом дня.
// Берёт цифры из базы лидов (Supabase) и звонит через Vapi. Говорит голосом, слушает ответы.
//
// Запуск:  node jarvis/call.mjs          — позвонить сейчас
//          node jarvis/call.mjs --dry    — только показать, что он скажет, без звонка
// Нужен Node.js 18+. Ключи берутся из переменных окружения (см. jarvis/README.md).

const env = process.env;
const DRY = process.argv.includes('--dry');
const TZ = env.JARVIS_TZ || 'Europe/Warsaw';
const NAME = env.OWNER_NAME || 'босс';

function need(k) {
  if (!env[k]) { console.error(`Нет переменной ${k}. Смотри jarvis/README.md`); process.exit(1); }
  return env[k];
}

const daysSince = d => d ? Math.floor((Date.now() - new Date(d).getTime()) / 864e5) : 0;

async function leadStats() {
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return null;
  const url = env.SUPABASE_URL.replace(/\/$/, '') + '/rest/v1/leads?select=name,niche,city,status,touched,score';
  const res = await fetch(url, { headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: 'Bearer ' + env.SUPABASE_ANON_KEY } });
  if (!res.ok) { console.error('Supabase ответил', res.status, '— звоню без цифр'); return null; }
  const rows = await res.json();
  const by = s => rows.filter(r => (r.status || 'новый') === s);
  // та же логика, что в консоли: «написал» 2+ дня назад и молчит
  const silent = by('написал').filter(r => daysSince(r.touched) >= 2);
  const hot = by('новый').sort((a, b) => (b.score || 0) - (a.score || 0)).slice(0, 3);
  return {
    total: rows.length,
    new: by('новый').length,
    sent: by('написал').length,
    replied: by('ответил').length,
    meetings: by('встреча').map(r => r.name).filter(Boolean),
    sold: by('продано').length,
    silent: silent.map(r => `${r.name} (${daysSince(r.touched)} дн)`),
    hot: hot.map(r => `${r.name}${r.niche ? ', ' + r.niche : ''}`),
  };
}

function brief(s) {
  const today = new Date().toLocaleDateString('ru-RU', { timeZone: TZ, weekday: 'long', day: 'numeric', month: 'long' });
  const lines = [`Сегодня ${today}.`];
  if (!s) {
    lines.push('Цифр из базы лидов нет: Supabase не подключён. Не выдумывай их, спроси у босса, сколько лидов в работе.');
  } else {
    lines.push(`Всего лидов в базе: ${s.total}. Новых, ещё не написали: ${s.new}. Написали и ждём ответа: ${s.sent}. Ответили: ${s.replied}. Продано: ${s.sold}.`);
    lines.push(`Встречи: ${s.meetings.length ? s.meetings.join(', ') : 'нет'}.`);
    lines.push(`Молчат 2+ дня после письма, им нужно напомнить или позвонить: ${s.silent.length ? s.silent.slice(0, 8).join(', ') : 'никого'}.`);
    lines.push(`Самые перспективные новые: ${s.hot.length ? s.hot.join('; ') : 'нет'}.`);
  }
  if (env.JARVIS_NOTES) lines.push('Заметки босса: ' + env.JARVIS_NOTES);
  return lines.join('\n');
}

const SYSTEM = (facts) => `Ты Джарвис, личный ИИ-ассистент и секретарь. Ты звонишь владельцу маленького агентства (обращайся к нему «${NAME}») утром по телефону.
Агентство находит местные бизнесы без сайта или со слабым сайтом и предлагает им сайт или продвижение. Владелец сканирует лидов в LEADS CONSOLE и пишет письма. Сестра звонит тем, кто прочитал письмо.

Факты на сегодня:
${facts}

Как вести звонок:
1. Поздоровайся бодро, в стиле Джарвиса: вежливо, немного с юмором, уверенно. Одна фраза.
2. Коротко дай сводку: 2–3 самые важные цифры, не все подряд.
3. Предложи план дня из 3–5 конкретных дел с числами. Например: «напомнить пятерым, кто молчит», «найти 20 новых лидов через lead-scout», «передать сестре 3 звонка». Первыми ставь тех, кто молчит, и встречи.
4. Спроси, всё ли так или что-то поменять. Подстройся под ответ.
5. Когда план согласован, повтори его в одном предложении, пожелай удачи и закончи фразой «До связи, ${NAME}».
Это телефон: говори короткими живыми фразами, без списков, без разметки, без английских слов. Цифры называй словами. Не выдумывай факты, которых нет выше.`;

const facts = brief(await leadStats());
const assistant = {
  name: 'Jarvis',
  firstMessageMode: 'assistant-speaks-first-with-model-generated-message',
  model: {
    provider: 'anthropic',
    model: env.JARVIS_MODEL || 'claude-haiku-5-5',
    reasoningEffort: 'none',
    maxTokens: 300,
    temperature: 0.6,
    messages: [{ role: 'system', content: SYSTEM(facts) }],
  },
  voice: {
    provider: '11labs',
    voiceId: env.JARVIS_VOICE_ID || 'pNInz6obpgDQGcFmaJgB',
    model: 'eleven_flash_v2_5',
    language: 'ru',
  },
  transcriber: { provider: 'deepgram', model: 'nova-2', language: 'ru' },
  endCallPhrases: [`До связи, ${NAME}`, 'До связи'],
  voicemailMessage: `${NAME}, это Джарвис. Не дозвонился. План на день ждёт в консоли, перезвони, когда будет минута.`,
  backgroundSound: 'off',
  maxDurationSeconds: 420,
};

if (DRY) {
  console.log('--- Что Джарвис знает сегодня ---\n' + facts + '\n\n--- Промпт ---\n' + assistant.model.messages[0].content);
  process.exit(0);
}

const res = await fetch('https://api.vapi.ai/call', {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + need('VAPI_API_KEY'), 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: 'Jarvis morning brief',
    phoneNumberId: need('VAPI_PHONE_NUMBER_ID'),
    customer: { number: need('MY_PHONE'), name: NAME },
    assistant,
  }),
});
const body = await res.text();
if (!res.ok) { console.error('Vapi ошибка', res.status, body); process.exit(1); }
console.log('Звоню! id звонка:', JSON.parse(body).id);
