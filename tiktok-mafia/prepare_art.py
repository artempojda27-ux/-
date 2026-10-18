"""
ПОДГОТОВКА СГЕНЕРИРОВАННОГО АРТА.

    python3 prepare_art.py

Берёт картинки из art_in/, вырезает фон, приводит всех к одному росту
и раскладывает в assets/chars/ под нужными именами.

Что положить в art_in/ — просто по слагу и состоянию:
    margo.png  margo-talk.png  margo-angry.png  david.png  ...
Любой размер, любой формат. Главное — ровный однотонный фон, и лучше
всего ярко-зелёный: такого цвета в персонаже точно нет, и скрипт сможет
добить остатки фона в просветах, не трогая одежду и волосы.

Две вещи, ради которых это написано.

ФОН вырезается заливкой от краёв, а не по цвету. Разница принципиальная:
вычитание по цвету съедает тёмные волосы, если они того же тона, что задник.
Заливка идёт снаружи внутрь и до фигуры не добирается.

РОСТ приводится к общему. В сцене восемь человек стоят в одном кадре, и если
у одного голова крупнее, а другой ниже посажен, каст рассыпается. Скрипт
находит фигуру, масштабирует под общую высоту и сажает на общую линию —
дальше хоть из разных сеансов генерации, в кадре они будут одним шоу.

На выходе, как и ждёт сцена:
    margo-cut.png   прозрачная вырезка, для комнаты
    margo.png       на фоне, для вскрытия роли
"""

import os
import sys
from collections import deque

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
IN = os.path.join(HERE, 'art_in')
OUT = os.path.join(HERE, 'assets', 'chars')

W, H = 600, 800           # кадр, как у остальных портретов
FIGURE_H = 0.94           # какую долю кадра занимает фигура по высоте
BACKDROP = (46, 20, 28)   # тот же тёмно-бордовый, что в сцене
TOLERANCE = 42            # насколько цвет может отличаться и всё ещё считаться фоном

STATES = ['', '-talk', '-angry', '-blink']   # -blink — глаза закрыты, для моргания на крупном плане


def load_slugs():
    """Слаги берём из cast.json, чтобы не расходиться с движком."""
    import json
    p = os.path.join(HERE, 'cast.json')
    if os.path.exists(p):
        return [(c['slug'], c['name']) for c in json.load(open(p, encoding='utf-8'))]
    # запасной вариант: по тому, что лежит в art_in
    names = set()
    for f in os.listdir(IN):
        base = os.path.splitext(f)[0]
        for s in STATES[1:]:
            if base.endswith(s):
                base = base[: -len(s)]
        names.add(base)
    return [(n, n) for n in sorted(names)]


def close(a, b, tol):
    return abs(a[0] - b[0]) <= tol and abs(a[1] - b[1]) <= tol and abs(a[2] - b[2]) <= tol


def strip_background(img, tol=TOLERANCE):
    """Заливка от краёв: всё, что связано с рамкой и похоже по цвету — фон.

    Именно связность спасает тёмные волосы: они тоже тёмные, но окружены
    фигурой и до них заливка не дотягивается."""
    img = img.convert('RGBA')
    w, h = img.size
    px = img.load()

    # опорный цвет — по верхним углам: нижние у поясного портрета заняты
    # плечами, и с ними «фон» выходит цветом одежды — тогда не режется ничего
    corners = [px[0, 0], px[w - 1, 0], px[2, 2], px[w - 3, 2]]
    ref = tuple(sum(c[i] for c in corners) // 4 for i in range(3))

    seen = bytearray(w * h)
    q = deque()

    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))

    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if not close(px[x, y], ref, tol):
            continue
        px[x, y] = (0, 0, 0, 0)
        q.append((x + 1, y)); q.append((x - 1, y))
        q.append((x, y + 1)); q.append((x, y - 1))

    # Добиваем остатки фона внутри фигуры — просветы между рукой и телом,
    # дырки в причёске. Заливка до них не дотягивается, она идёт от краёв.
    # Делаем это только для насыщенного фона: если просили ровный зелёный,
    # такого цвета в персонаже нет и спутать не с чем. На сером или бежевом
    # фоне пропускаем — там легко съесть одежду.
    if max(ref) - min(ref) > 40:
        tight = tol // 2
        for y in range(h):
            for x in range(w):
                if px[x, y][3] and close(px[x, y], ref, tight):
                    px[x, y] = (0, 0, 0, 0)

    # Кайма. По краю фигуры пиксели полупрозрачные и подмешали цвет фона —
    # вокруг силуэта появляется зелёный ореол. Вычитаем фон обратно
    # пропорционально прозрачности.
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if 0 < a < 250:
                k = a / 255
                px[x, y] = (
                    max(0, min(255, int((r - ref[0] * (1 - k)) / k))),
                    max(0, min(255, int((g - ref[1] * (1 - k)) / k))),
                    max(0, min(255, int((b - ref[2] * (1 - k)) / k))),
                    a,
                )

    return img


def normalize(img):
    """Обрезаем по фигуре, масштабируем под общий рост, сажаем на общую линию."""
    bbox = img.getbbox()
    if not bbox:
        return None
    fig = img.crop(bbox)

    target_h = int(H * FIGURE_H)
    k = target_h / fig.height
    fig = fig.resize((max(1, int(fig.width * k)), target_h), Image.LANCZOS)

    # если после масштабирования не влезает по ширине — ужимаем целиком
    if fig.width > W:
        k2 = W / fig.width
        fig = fig.resize((W, max(1, int(fig.height * k2))), Image.LANCZOS)

    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    canvas.paste(fig, ((W - fig.width) // 2, H - fig.height), fig)
    return canvas


def find_source(slug, state):
    for ext in ('.png', '.webp', '.jpg', '.jpeg'):
        p = os.path.join(IN, f'{slug}{state}{ext}')
        if os.path.exists(p):
            return p
    return None


def main():
    if not os.path.isdir(IN):
        os.makedirs(IN, exist_ok=True)
        print(f'Создал {IN} — положи туда картинки и запусти снова.')
        return

    os.makedirs(OUT, exist_ok=True)
    done, missing = 0, []

    for slug, name in load_slugs():
        for state in STATES:
            src = find_source(slug, state)
            if not src:
                missing.append(f'{slug}{state}')
                continue

            img = strip_background(Image.open(src))
            fig = normalize(img)
            if fig is None:
                print(f'  {slug}{state}: фигуру не нашёл, пропускаю')
                continue

            fig.save(os.path.join(OUT, f'{slug}{state}-cut.png'))

            on_bg = Image.new('RGB', (W, H), BACKDROP)
            on_bg.paste(fig, (0, 0), fig)
            on_bg.save(os.path.join(OUT, f'{slug}{state}.png'))

            done += 1
            print(f'  {slug}{state} — ок')

    print(f'\nготово: {done} картинок')
    if missing:
        print(f'\nне хватает {len(missing)}:')
        # состояния важнее: без спокойного кадра персонаж вообще не появится
        base = [m for m in missing if not m.endswith(('-talk', '-angry', '-blink'))]
        rest = [m for m in missing if m not in base]
        if base:
            print('  обязательные: ' + ', '.join(base))
        if rest:
            print('  состояния (можно позже): ' + ', '.join(rest))
        print('\nЧего нет — подменится: состояния спокойным кадром, спокойный монограммой.')


main()
