"""
Заглушки портретов для проверки механики.

Рисует 14 персонажей в трёх состояниях (спокоен, говорит, злится) и два фона.
Это не арт, а стенд: важно, чтобы лица отличались друг от друга и чтобы
состояния были видны с первого взгляда — тогда на них можно проверить
лип-синк, реакцию на обвинение и вскрытие роли, не дожидаясь генерации.

Имена файлов совпадают с боевыми, так что настоящие портреты потом
просто лягут сверху.
"""

from PIL import Image, ImageDraw
import json, math, os, subprocess

W, H = 600, 800  # 3:4, как в промптах

INK = (20, 16, 16)
BONE = (239, 230, 214)

# по палитре на персонажа: кожа, волосы, одежда. Четырнадцать разных,
# чтобы соседние карточки в сетке не сливались
PALETTE = [
    ((222, 184, 158), (58, 38, 30), (120, 40, 58)),
    ((206, 166, 132), (28, 26, 30), (38, 52, 78)),
    ((232, 200, 176), (92, 62, 42), (64, 64, 72)),
    ((198, 152, 118), (44, 32, 26), (86, 66, 42)),
    ((228, 192, 168), (128, 96, 58), (52, 74, 62)),
    ((210, 170, 140), (34, 30, 28), (98, 52, 40)),
    ((236, 204, 182), (150, 118, 76), (72, 48, 86)),
    ((190, 146, 112), (60, 56, 52), (46, 60, 46)),
    ((216, 176, 148), (176, 142, 92), (104, 72, 48)),
    ((200, 158, 126), (70, 44, 32), (40, 46, 64)),
    ((238, 208, 188), (24, 22, 26), (88, 40, 52)),
    ((184, 140, 108), (120, 118, 114), (60, 58, 54)),
    ((230, 194, 170), (196, 164, 108), (112, 56, 76)),
    ((196, 150, 116), (40, 34, 30), (34, 54, 50)),
]


def features(look):
    """Внешность берём из описаний в characters.js — там уже сказано,
    у кого очки, борода, каре и залысины. Заглушка становится хоть немного
    похожа на то, что потом сгенерируется настоящим артом."""
    t = look.lower()
    return {
        "glasses": "очк" in t,
        "beard": "борода" in t or "щетина" in t,
        "balding": "залыс" in t,
        "gray": "седе" in t,
        "long": "длинные" in t or "до плеч" in t or "прямые волосы" in t,
        "bob": "каре" in t,
        "ponytail": "хвост" in t or "собранные" in t,
        "heavy": "полноват" in t or "крепк" in t,
    }


def portrait(path, seed, state, female, look, transparent=False):
    """transparent=True — версия без фона, чтобы ставить персонажа в комнату.
    Рисуем сразу на прозрачном холсте, а не вычитаем фон по цвету:
    вычитание съедает тёмные волосы, они того же тона, что и задник."""
    f = features(look)
    skin, hair, cloth = PALETTE[seed % len(PALETTE)]

    if transparent:
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
    else:
        img = Image.new("RGB", (W, H), (46, 20, 28))  # тёмно-бордовый фон, как в промптах
        d = ImageDraw.Draw(img)
        # боковой свет: лёгкий градиент слева направо
        for x in range(W):
            k = 1 - abs(x - W * 0.35) / W * 0.5
            d.line([(x, 0), (x, H)], fill=(int(46 * k), int(20 * k), int(28 * k)))

    cx, top = W // 2, 170

    # плечи
    d.ellipse([cx - 230, top + 340, cx + 230, H + 190], fill=cloth)
    d.ellipse([cx - 62, top + 250, cx + 62, top + 400], fill=skin)  # шея

    if f["gray"]:
        hair = tuple(min(255, c + 90) for c in hair)

    # голова: форма слегка разная у всех
    fw = 150 + (seed % 3) * 12 + (18 if f["heavy"] else 0)
    fh = 190 + (seed % 4) * 10
    d.ellipse([cx - fw, top - 40, cx + fw, top + fh * 2 - 40], fill=skin)

    # волосы
    if f["long"] or (female and not f["bob"] and not f["ponytail"]):
        d.ellipse([cx - fw - 18, top - 70, cx + fw + 18, top + fh + 140], fill=hair)
        d.ellipse([cx - fw + 10, top + 10, cx + fw - 10, top + fh * 2 - 40], fill=skin)
    elif f["bob"]:
        d.ellipse([cx - fw - 14, top - 66, cx + fw + 14, top + fh + 20], fill=hair)
        d.ellipse([cx - fw + 8, top + 14, cx + fw - 8, top + fh * 2 - 40], fill=skin)
    elif f["ponytail"]:
        d.ellipse([cx + fw - 30, top + 40, cx + fw + 60, top + 210], fill=hair)
        d.chord([cx - fw - 8, top - 70, cx + fw + 8, top + fh - 30], 180, 360, fill=hair)
    else:
        d.chord([cx - fw - 8, top - 70, cx + fw + 8, top + fh - 20], 180, 360, fill=hair)
    if f["balding"]:
        d.chord([cx - fw + 34, top - 54, cx + fw - 34, top + 74], 180, 360, fill=skin)

    # глаза
    ey = top + 120
    eo = 58
    brow = 18 if state == "angry" else 0
    for sx in (-1, 1):
        d.ellipse([cx + sx * eo - 22, ey - 16, cx + sx * eo + 22, ey + 16], fill=BONE)
        d.ellipse([cx + sx * eo - 9, ey - 9, cx + sx * eo + 9, ey + 9], fill=INK)
        # бровь: у злого сведена к переносице
        d.line(
            [(cx + sx * eo - 30, ey - 44 + (brow if sx > 0 else 0)),
             (cx + sx * eo + 30, ey - 44 + (brow if sx < 0 else 0))],
            fill=hair, width=9,
        )

    if f["glasses"]:
        for sx in (-1, 1):
            d.ellipse([cx + sx * eo - 40, ey - 34, cx + sx * eo + 40, ey + 34],
                      outline=(40, 34, 30), width=6)
        d.line([(cx - 18, ey), (cx + 18, ey)], fill=(40, 34, 30), width=6)

    # нос
    d.line([(cx, ey + 20), (cx - 8, ey + 70)], fill=(0, 0, 0, 40), width=5)

    if f["beard"]:
        d.chord([cx - fw + 16, top + 60, cx + fw - 16, top + fh * 2 - 34], 0, 180, fill=hair)
        d.ellipse([cx - 52, top + 180, cx + 52, top + 260], fill=skin)

    # рот: закрыт / открыт / поджат
    my = top + 215
    if state == "talk":
        d.ellipse([cx - 40, my - 26, cx + 40, my + 34], fill=(92, 34, 40))
        d.ellipse([cx - 26, my + 2, cx + 26, my + 30], fill=(150, 62, 66))
    elif state == "angry":
        d.arc([cx - 46, my - 6, cx + 46, my + 52], 200, 340, fill=(120, 60, 60), width=9)
    else:
        d.line([(cx - 38, my + 10), (cx + 38, my + 10)], fill=(140, 76, 78), width=8)

    # маркер состояния в углу: видно, какой кадр сейчас на экране,
    # не вчитываясь в лицо. В боевых портретах его, понятно, нет
    if state != "calm":
        col = (201, 162, 39) if state == "talk" else (179, 38, 30)
        d.rectangle([W - 58, 24, W - 24, 58], fill=col)

    img.save(path, "PNG")


def background(path, night):
    img = Image.new("RGB", (1080, 1920))
    d = ImageDraw.Draw(img)
    base = (12, 26, 42) if night else (42, 30, 24)
    warm = (60, 40, 30) if not night else (22, 41, 61)
    for y in range(1920):
        k = y / 1920
        d.line([(0, y), (1080, y)],
               fill=tuple(int(base[i] + (warm[i] - base[i]) * (1 - k)) for i in range(3)))
    # окна
    for i in range(3):
        x = 120 + i * 340
        glow = (150, 170, 200) if night else (210, 180, 130)
        d.rounded_rectangle([x, 300, x + 220, 760], 110, fill=glow)
        d.rounded_rectangle([x + 16, 320, x + 204, 740], 100, fill=tuple(int(c * 0.55) for c in glow))
    # стол
    d.polygon([(90, 1500), (990, 1500), (1080, 1750), (0, 1750)],
              fill=(58, 38, 28) if not night else (24, 34, 48))
    img.save(path, "PNG")


cast = json.loads(subprocess.check_output(
    ["node", "-e",
     "console.log(JSON.stringify(require('/mnt/user-data/outputs/characters.js').CAST"
     ".map(c=>({slug:c.slug,name:c.name,voice:c.voice,look:c.look}))))"]).decode())

out = "/mnt/user-data/outputs/assets/chars"
os.makedirs(out, exist_ok=True)

for i, c in enumerate(cast):
    female = c["voice"].startswith("женский")
    for state, suffix in (("calm", ""), ("talk", "-talk"), ("angry", "-angry")):
        portrait(f"{out}/{c['slug']}{suffix}.png", i, state, female, c["look"])

# вырезки без фона — для сцены, где персонажи стоят в комнате
for i, c in enumerate(cast):
    female = c["voice"].startswith("женский")
    for state, suffix in (("calm", ""), ("talk", "-talk"), ("angry", "-angry")):
        portrait(f"{out}/{c['slug']}{suffix}-cut.png", i, state, female, c["look"], transparent=True)

background("/mnt/user-data/outputs/assets/bg-day.jpg", False)
background("/mnt/user-data/outputs/assets/bg-night.jpg", True)

print(f"готово: {len(cast) * 3} портретов + 2 фона")
