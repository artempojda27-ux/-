/**
 * МОСТ С TIKTOK LIVE.
 *
 *   npm i tiktok-live-connector
 *   TIKTOK_USER=твой_ник node tiktok-bridge.js
 *
 * Ключей и токенов не нужно — читается публичный поток эфира.
 * Работает только когда эфир реально идёт: если не подключается,
 * сначала проверь, что эфир запущен и ник указан без собачки.
 *
 * Формат событий на выходе ровно такой же, как у emulator.js,
 * поэтому серверу всё равно, откуда они пришли.
 */

'use strict';

const USER = (process.env.TIKTOK_USER || '').replace(/^@/, '');
const HUB = process.env.HUB || 'http://localhost:3000/input';

if (!USER) {
  console.error('Укажи ник: TIKTOK_USER=nickname node tiktok-bridge.js');
  process.exit(1);
}

let WebcastPushConnection;
try {
  ({ WebcastPushConnection } = require('tiktok-live-connector'));
} catch {
  console.error('Не установлен пакет. Выполни: npm i tiktok-live-connector');
  process.exit(1);
}

async function send(payload) {
  try {
    await fetch(HUB, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    console.error('сервер не отвечает:', e.message);
  }
}

const tiktok = new WebcastPushConnection(USER);

tiktok
  .connect()
  .then((s) => console.log(`подключено к эфиру @${USER} (room ${s.roomId})`))
  .catch((e) => {
    console.error('не подключиться:', e.message);
    console.error('эфир точно идёт прямо сейчас?');
  });

tiktok.on('chat', (d) => {
  send({ type: 'comment', user: d.uniqueId, text: d.comment });
});

tiktok.on('gift', (d) => {
  // у стрик-подарков события сыплются на каждое повторение —
  // засчитываем только когда серия закрылась, иначе один зритель
  // накрутит в десять раз больше, чем реально отправил
  if (d.giftType === 1 && !d.repeatEnd) return;
  const coins = (d.diamondCount || 1) * (d.repeatCount || 1);
  send({
    type: 'gift',
    user: d.uniqueId,
    text: d.comment || '',
    gift: d.giftName,
    coins,
  });
  console.log(`подарок: ${d.uniqueId} → ${d.giftName} (${coins})`);
});

tiktok.on('streamEnd', () => console.log('эфир закончился'));
tiktok.on('disconnected', () => console.log('связь потеряна, переподключение...'));

process.on('SIGINT', () => {
  tiktok.disconnect();
  process.exit(0);
});
