"""
Заглушки локаций: восемь мест города, день и ночь.

Не арт, а стенд. Важно одно: места должны отличаться с первого взгляда —
силуэтом и цветом. Зритель за пару эфиров должен узнавать склад по кранам,
а клинику по кресту, иначе перебивка по городу читается как мигание
одинаковых тёмных картинок.
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter
import json, os, subprocess, math

W, H = 1080, 1920
OUT = '/mnt/user-data/outputs/assets/places'
os.makedirs(OUT, exist_ok=True)


def sky(d, night, top, bottom):
    for y in range(H):
        k = y / H
        c = tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(3))
        d.line([(0, y), (W, y)], fill=c)


# Свет копим на отдельном слое и в конце складываем с кадром.
# Если рисовать свечение прямо поверх, оно закрашивает здания
# непрозрачными шарами — что и произошло в первой версии.
GLOW = {'layer': None, 'draw': None}


def base(night):
    img = Image.new('RGB', (W, H))
    d = ImageDraw.Draw(img)
    GLOW['layer'] = Image.new('RGB', (W, H), (0, 0, 0))
    GLOW['draw'] = ImageDraw.Draw(GLOW['layer'])
    if night:
        sky(d, night, (10, 18, 32), (26, 34, 48))
    else:
        sky(d, night, (58, 48, 44), (96, 78, 62))
    return img, d


def ground(d, night, y=1500):
    d.rectangle([0, y, W, H], fill=(16, 14, 16) if night else (52, 44, 40))


def glow(d, x, y, r, color):
    g = GLOW['draw']
    steps = 14
    for i in range(steps, 0, -1):
        rr = r * i / steps
        a = (1 - i / steps) ** 2 * 0.55
        g.ellipse([x - rr, y - rr, x + rr, y + rr],
                  fill=tuple(int(c * a) for c in color))


def finish(img):
    blurred = GLOW['layer'].filter(ImageFilter.GaussianBlur(40))
    return ImageChops.add(img, blurred)


def bar(d, night):
    ground(d, night, 1520)
    d.rectangle([140, 780, 940, 1520], fill=(34, 24, 28) if night else (74, 56, 54))
    for i in range(4):                       # окна
        x = 200 + i * 190
        d.rectangle([x, 980, x + 130, 1240], fill=(220, 150, 60) if night else (140, 120, 90))
    d.rectangle([340, 640, 740, 760], fill=(180, 40, 70))      # вывеска
    if night:
        glow(d, 540, 700, 190, (255, 70, 120))
        glow(d, 540, 1100, 150, (255, 180, 80))


def station(d, night):
    ground(d, night, 1560)
    d.rectangle([180, 900, 900, 1560], fill=(38, 42, 54) if night else (92, 92, 98))
    d.rectangle([460, 1240, 620, 1560], fill=(22, 26, 34))     # дверь
    d.rectangle([180, 840, 900, 900], fill=(30, 34, 46))
    d.ellipse([500, 760, 580, 840], fill=(70, 130, 240))       # синяя лампа
    if night:
        glow(d, 540, 800, 160, (60, 120, 255))


def depot(d, night):
    ground(d, night, 1600)
    for i, (x, w, h, c) in enumerate([(80, 300, 220, (120, 70, 50)), (400, 280, 200, (60, 90, 110)),
                                      (700, 300, 240, (90, 100, 70))]):
        d.rectangle([x, 1600 - h, x + w, 1600], fill=tuple(int(v * (0.5 if night else 1)) for v in c))
    d.line([(820, 1600), (820, 560)], fill=(60, 60, 66), width=26)     # кран
    d.line([(820, 620), (300, 620)], fill=(60, 60, 66), width=20)
    d.line([(420, 620), (420, 860)], fill=(50, 50, 56), width=8)
    d.ellipse([160, 900, 200, 940], fill=(230, 200, 130))              # фонарь
    if night:
        glow(d, 180, 920, 200, (255, 210, 120))


def clinic(d, night):
    ground(d, night, 1540)
    d.rectangle([160, 760, 920, 1540], fill=(40, 46, 52) if night else (150, 152, 150))
    for r in range(3):
        for c in range(5):
            x, y = 220 + c * 140, 860 + r * 170
            d.rectangle([x, y, x + 90, y + 110], fill=(190, 220, 230) if night else (110, 120, 128))
    d.rectangle([500, 620, 580, 760], fill=(220, 70, 70))              # крест
    d.rectangle([470, 650, 610, 730], fill=(220, 70, 70))
    if night:
        glow(d, 540, 690, 170, (255, 90, 90))


def park(d, night):
    ground(d, night, 1480)
    d.polygon([(380, 1480), (700, 1480), (900, H), (180, H)],
              fill=(40, 36, 32) if night else (96, 86, 70))            # дорожка
    for x in (150, 330, 760, 950):
        d.rectangle([x, 1050, x + 34, 1480], fill=(30, 26, 24))
        d.ellipse([x - 110, 780, x + 144, 1120], fill=(24, 40, 30) if night else (62, 92, 58))
    for x in (520, 880):                                               # фонари
        d.line([(x, 1480), (x, 1020)], fill=(46, 46, 50), width=12)
        d.ellipse([x - 26, 1000, x + 26, 1052], fill=(240, 220, 160))
        if night:
            glow(d, x, 1026, 170, (255, 220, 140))


def terminal(d, night):
    ground(d, night, 1560)
    d.rectangle([0, 900, W, 960], fill=(44, 44, 50))                   # навес
    for x in range(0, W, 180):
        d.rectangle([x + 20, 960, x + 44, 1560], fill=(40, 40, 46))
    d.rounded_rectangle([260, 1100, 900, 1520], 30,
                        fill=(60, 70, 90) if night else (120, 130, 150))   # автобус
    for i in range(4):
        d.rectangle([300 + i * 150, 1160, 400 + i * 150, 1280], fill=(180, 200, 220))
    d.ellipse([300, 1440, 400, 1540], fill=(20, 20, 22))
    d.ellipse([760, 1440, 860, 1540], fill=(20, 20, 22))
    if night:
        glow(d, 900, 1350, 180, (255, 240, 200))


def home(d, night):
    ground(d, night, 1620)
    d.rectangle([120, 520, 960, 1620], fill=(32, 34, 44) if night else (104, 96, 88))
    for r in range(6):
        for c in range(6):
            x, y = 180 + c * 130, 600 + r * 160
            lit = (r * 6 + c) % 3 == 0
            col = (240, 200, 120) if (night and lit) else ((60, 62, 74) if night else (78, 76, 78))
            d.rectangle([x, y, x + 86, y + 108], fill=col)
    if night:
        glow(d, 540, 1000, 230, (255, 210, 140))


def square(d, night):
    ground(d, night, 1560)
    # фасады по бокам, площадь в центре: кадр сам подсказывает, где стоят люди
    for x, w in ((0, 300), (780, 300)):
        d.rectangle([x, 620, x + w, 1560], fill=(44, 40, 46) if night else (118, 104, 92))
        for r in range(5):
            for c in range(2):
                wx, wy = x + 50 + c * 130, 700 + r * 170
                lit = night and (r + c) % 2 == 0
                d.rectangle([wx, wy, wx + 90, wy + 110],
                            fill=(240, 205, 130) if lit else ((52, 50, 60) if night else (86, 80, 78)))
    d.ellipse([360, 1400, 720, 1560], fill=(60, 60, 68) if night else (150, 146, 140))  # фонтан
    d.rectangle([520, 1180, 560, 1420], fill=(70, 70, 78) if night else (160, 156, 150))
    for x in (250, 830):
        d.line([(x, 1560), (x, 1080)], fill=(46, 46, 50), width=12)
        d.ellipse([x - 26, 1058, x + 26, 1110], fill=(240, 220, 160))
        if night:
            glow(d, x, 1084, 190, (255, 220, 140))


def diner(d, night):
    ground(d, night, 1540)
    d.rectangle([0, 1540, W, H], fill=(24, 24, 28))
    for x in range(40, W, 200):                                        # разметка
        d.rectangle([x, 1700, x + 110, 1724], fill=(200, 190, 160))
    d.rounded_rectangle([220, 1000, 880, 1540], 16,
                        fill=(56, 48, 44) if night else (128, 112, 96))
    d.rectangle([280, 1120, 820, 1320], fill=(250, 220, 150) if night else (150, 140, 120))
    d.rectangle([420, 760, 680, 960], fill=(220, 90, 50))              # вывеска у шоссе
    d.line([(550, 960), (550, 1000)], fill=(60, 56, 52), width=16)
    if night:
        glow(d, 550, 860, 190, (255, 120, 70))
        glow(d, 550, 1220, 170, (255, 220, 150))


DRAW = dict(square=square, bar=bar, station=station, depot=depot, clinic=clinic,
            park=park, terminal=terminal, home=home, diner=diner)

locs = json.loads(subprocess.check_output(
    ['node', '-e',
     "const c=require('/mnt/user-data/outputs/city.js');"
     "console.log(JSON.stringify([c.SQUARE, ...c.LOCATIONS]))"]).decode())

for l in locs:
    for night in (False, True):
        img, d = base(night)
        DRAW[l['id']](d, night)
        # общий грейд: тёплый днём, холодный ночью — чтобы места были одной серией
        img = finish(img)
        tint = Image.new('RGB', (W, H), (18, 26, 44) if night else (60, 40, 26))
        img = Image.blend(img, tint, 0.22 if night else 0.14)
        img.save(f"{OUT}/{l['id']}{'-night' if night else ''}.jpg", 'JPEG', quality=78, optimize=True)

print(f'готово: {len(locs) * 2} фонов локаций')
