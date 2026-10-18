/**
 * ГОРОД.
 *
 * Ночью все расходятся по местам. Наутро у каждого есть личное знание:
 * где был сам и кого там видел. Это и есть главный смысл локаций —
 * не антураж, а факты.
 *
 * Без них агенты спорят ни о чём и скатываются в «он какой-то подозрительный»,
 * потому что спорить не о чем. С ними у обсуждения появляется предмет:
 * у кого нет алиби, кто соврал про то, где был, кто видел мафию у склада
 * и решает, говорить об этом вслух или помолчать.
 *
 * Свидетель — самая острая роль в игре, и она не назначается, а выпадает:
 * если ты оказался там же, где ночью кого-то убрали, ты кого-то видел.
 */

/**
 * Дневная сцена — площадь. Люди не висят в пустоте и не сидят в абстрактной
 * комнате: днём город собирается здесь, ночью расходится по остальным местам.
 * Персонажи всегда внутри локации, локация всегда под ними.
 */
const SQUARE = { id: 'square', name: 'городская площадь', note: 'где город собирается днём',
  look: 'центральная площадь, фонтан, лавки, фасады старых домов' };

/** Общий план города — для открывающей перебивки, до того как зритель увидит людей. */
const CITY = { id: 'city', name: 'портовый город', note: 'общий план',
  look: 'панорама старого портового города, крыши, краны в порту, залив, огни' };

/**
 * Весь город — 16 мест. В одной партии открыто 8 (см. cityTonight):
 * если раскидать восьмерых по шестнадцати местам, каждый ночью окажется
 * один — исчезнут свидетели и алиби, а на них держится всё обсуждение.
 * Так город от эфира к эфиру разный, а плотность встреч та же.
 */
const LOCATIONS = [
  { id: 'bar',      name: 'бар «Полночь»',   note: 'шумно, людно, алиби сомнительное',
    look: 'барная вывеска, неоновый свет, запотевшие окна, силуэты у стойки' },
  { id: 'station',  name: 'полицейский участок', note: 'дежурная часть, всегда открыто',
    look: 'приземистое здание участка, синяя лампа над входом, служебная машина' },
  { id: 'depot',    name: 'склад у порта',   note: 'пусто и темно, свидетелей обычно нет',
    look: 'портовые контейнеры, кран на фоне неба, одинокий фонарь' },
  { id: 'clinic',   name: 'ночная клиника',  note: 'свет горит, персонал на месте',
    look: 'приёмный покой, светящийся крест над входом, пустая парковка' },
  { id: 'park',     name: 'городской парк',  note: 'фонарей мало, дорожки пустые',
    look: 'аллея с редкими фонарями, голые деревья, пустая скамья' },
  { id: 'terminal', name: 'автовокзал',      note: 'последние рейсы, случайные люди',
    look: 'перрон автовокзала, автобус с горящими фарами, табло рейсов' },
  { id: 'home',     name: 'дома',            note: 'никто не подтвердит',
    look: 'жилая пятиэтажка ночью, часть окон светится, двор с качелями' },
  { id: 'diner',    name: 'закусочная у трассы', note: 'дальнобойщики и кофе',
    look: 'придорожная закусочная, вывеска у шоссе, фуры на обочине' },
  { id: 'church',   name: 'старая церковь',  note: 'двери не запирают, внутри полумрак',
    look: 'каменная церковь, витражи, свечи, тяжёлые двери' },
  { id: 'roof',     name: 'крыша высотки',   note: 'видно весь город, тебя не видит никто',
    look: 'плоская крыша многоэтажки, антенны, огни города внизу' },
  { id: 'laundry',  name: 'прачечная',       note: 'круглосуточная, гудят машины',
    look: 'круглосуточная прачечная, ряды стиральных машин, лампы дневного света' },
  { id: 'garages',  name: 'гаражи',          note: 'лабиринт, ворота, собаки',
    look: 'ряды гаражей с ржавыми воротами, лужи, единственная лампа' },
  { id: 'club',     name: 'подпольный клуб', note: 'громко, темно, никто ничего не помнит',
    look: 'подвальный клуб, красный свет, дым, бетонная лестница вниз' },
  { id: 'pier',     name: 'пирс',            note: 'вода, ветер, рыбаки до рассвета',
    look: 'деревянный пирс, фонари над водой, лодки у причала' },
  { id: 'bridge',   name: 'железнодорожный мост', note: 'ходят товарняки, под мостом пусто',
    look: 'стальной мост над рекой, рельсы, прожектор товарного поезда' },
  { id: 'hotel',    name: 'отель «Империал»', note: 'портье помнит всех, кто проходил',
    look: 'старый отель, вращающаяся дверь, латунная вывеска, ковровая лестница' },
];

/**
 * Куда персонаж ходит чаще всего. Привычка, а не правило: персонаж узнаётся
 * не только по речи, но и по тому, где его обычно видят. Зритель за неделю
 * запомнит, что Артур всегда в баре, — и «вчера он был в парке» станет
 * поводом для вопросов само по себе.
 */
const HAUNTS = {
  margo: 'bar',
  david: 'station',
  liza: 'home',
  artur: 'bar',
  nina: 'clinic',
  kostya: 'terminal',
  vika: 'home',
  oleg: 'depot',
  rita: 'clinic',
  slava: 'diner',
  emma: 'park',
  gena: 'station',
  alina: 'bar',
  rustam: 'diner',
};

const byId = (id) => LOCATIONS.find((l) => l.id === id) || LOCATIONS[0];

/**
 * Какие места открыты в эту партию. Сначала привычные места состава —
 * иначе персонажу некуда пойти «к себе», — потом случайные до count.
 * «Дома» открыты всегда: это место, где алиби нет по определению.
 */
function cityTonight(players, rand, count = 8) {
  const ids = new Set(['home']);
  for (const p of players) ids.add(HAUNTS[p.slug] || 'home');
  const rest = LOCATIONS.map((l) => l.id).filter((id) => !ids.has(id));
  while (ids.size < count && rest.length) {
    ids.add(rest.splice(Math.floor(rand() * rest.length), 1)[0]);
  }
  return [...ids];
}

/**
 * Ночное расселение.
 * Обычно персонаж идёт к себе, иногда — куда-то ещё. Мафия чаще уходит
 * из привычного места: ей нужно оказаться там, где будет жертва.
 */
function placeEveryone(players, rand, open = LOCATIONS.map((l) => l.id)) {
  const placement = {};
  for (const p of players) {
    if (!p.alive) continue;
    const usual = HAUNTS[p.slug] || 'home';
    const wander = p.role === 'traitor' ? 0.75 : 0.32;
    placement[p.name] =
      rand() < wander
        ? open[Math.floor(rand() * open.length)]
        : usual;
  }
  return placement;
}

/** Кто ещё был в этом месте */
function whoWasAt(placement, locId, exclude = []) {
  return Object.entries(placement)
    .filter(([n, l]) => l === locId && !exclude.includes(n))
    .map(([n]) => n);
}

/**
 * Что каждый узнал за ночь.
 * Видишь только тех, кто был с тобой в одном месте. Был один — алиби нет,
 * и это само по себе факт, который придётся объяснять утром.
 */
function nightKnowledge(placement) {
  const out = {};
  for (const [name, loc] of Object.entries(placement)) {
    const others = whoWasAt(placement, loc, [name]);
    const where = byId(loc).name;
    out[name] = others.length
      ? `Ночью ты был: ${where}. Там же видел: ${others.join(', ')}.`
      : `Ночью ты был: ${where}. Один — подтвердить некому.`;
  }
  return out;
}

// Английский эфир: названия мест на экране и в разговоре персонажей
const EN_NAMES = {
  city: 'the harbor city', square: 'the town square',
  bar: 'the Midnight bar', station: 'the police station', depot: 'the harbor warehouse',
  clinic: 'the night clinic', park: 'the city park', terminal: 'the bus terminal',
  home: 'at home', diner: 'the highway diner', church: 'the old church',
  roof: 'the high-rise rooftop', laundry: 'the laundromat', garages: 'the garages',
  club: 'the underground club', pier: 'the pier', bridge: 'the railway bridge',
  hotel: 'the Imperial hotel',
};
if (require('./i18n').LANG === 'en') {
  for (const l of [CITY, SQUARE, ...LOCATIONS]) l.name = EN_NAMES[l.id] || l.name;
}

module.exports = { LOCATIONS, SQUARE, CITY, cityTonight, HAUNTS, byId, placeEveryone, whoWasAt, nightKnowledge };
