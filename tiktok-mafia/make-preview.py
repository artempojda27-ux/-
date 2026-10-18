"""
Собирает preview.html — сцену со всеми картинками внутри одного файла.

Нужен, чтобы смотреть оформление с телефона или отправлять кому-то:
обычная scene.html без сервера и без папки assets покажет монограммы,
а превью носит всё с собой и само крутит демо-партию по кругу.

    python3 make-preview.py

Пересобирать после правок в scene.html или после замены портретов.
"""

import base64, io, json, os
from PIL import Image

DEMO = ['margo', 'david', 'liza', 'artur', 'nina', 'kostya', 'vika', 'oleg']


def packed(path, size, quality=None, fmt='PNG', alpha=False):
    im = Image.open(path)
    im = im.convert('RGBA') if alpha else im.convert('RGB')
    im.thumbnail(size, Image.LANCZOS)
    buf = io.BytesIO()
    if fmt == 'JPEG':
        im.save(buf, 'JPEG', quality=quality, optimize=True)
        mime = 'image/jpeg'
    else:
        # палитра вместо truecolor: файл втрое легче.
        # FASTOCTREE — единственный метод, который умеет сохранять прозрачность
        # портреты идут во весь кадр на крупном плане: 64 цвета давали лесенку на коже
        im = im.quantize(colors=256, method=Image.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG) if alpha else im.quantize(colors=256)
        im.save(buf, 'PNG', optimize=True)
        mime = 'image/png'
    return f"data:{mime};base64," + base64.b64encode(buf.getvalue()).decode()


images = {}
for slug in DEMO:
    for suffix in ('', '-talk', '-angry', '-blink'):
        p = f'assets/chars/{slug}{suffix}-cut.png'
        if os.path.exists(p):
            images[slug + suffix + '-cut'] = packed(p, (420, 560), alpha=True)

places = {}
pdir = os.path.join(HERE, 'assets', 'places') if 'HERE' in dir() else 'assets/places'
for f in sorted(os.listdir(pdir)):
    if f.endswith('-night.jpg'):
        places[f[:-len('-night.jpg')]] = packed(os.path.join(pdir, f), (420, 746), 58, 'JPEG')
    elif f.endswith('.jpg'):
        places[f[:-len('.jpg')] + '-day'] = packed(os.path.join(pdir, f), (420, 746), 58, 'JPEG')

# карты глубины для камеры с параллаксом: маленькие, глубине детали не нужны
depth = {}
for f in sorted(os.listdir(pdir)):
    if f.endswith('-night-depth.png'):
        depth[f[:-len('-night-depth.png')]] = packed(os.path.join(pdir, f), (180, 320), 70, 'JPEG')
    elif f.endswith('-depth.png'):
        depth[f[:-len('-depth.png')] + '-day'] = packed(os.path.join(pdir, f), (180, 320), 70, 'JPEG')

bg_day = packed('assets/bg-day.jpg', (540, 960), 62, 'JPEG')
bg_night = packed('assets/bg-night.jpg', (540, 960), 62, 'JPEG')

s = open('scene.html').read()
s = s.replace('<title>Предатели — сцена</title>', '<title>Предатели — превью сцены</title>')
s = s.replace("#room.day{background-image:url('assets/bg-day.jpg')}",
              f"#room.day{{background-image:url('{bg_day}')}}")
s = s.replace("#room.night{background-image:url('assets/bg-night.jpg');",
              f"#room.night{{background-image:url('{bg_night}');")

inject = "<script>\nwindow.FORCE_DEMO = true;\nwindow.EMBEDDED_PLACES = " + json.dumps(places, ensure_ascii=False) + ";\nwindow.EMBEDDED_DEPTH = " + json.dumps(depth) + ";\nwindow.EMBEDDED_IMAGES = {\n"
inject += ",\n".join(f'  "{k}": "{v}"' for k, v in images.items())
inject += "\n};\n</script>\n"
s = s.replace('<body>\n', '<body>\n' + inject, 1)

open('preview.html', 'w').write(s)
print(f'preview.html собран: {len(images)} портретов внутри, {os.path.getsize("preview.html")//1024} KB')
