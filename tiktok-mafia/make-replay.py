"""
Собирает replay.html — запись реального прогона, проигранную в боевой сцене.

Отличие от preview.html: там сценарий, написанный руками, а здесь настоящие
события с работающего движка — со своими таймингами, решениями предателей,
голосами зала и покупками. Ровно то, что было бы в эфире.

    python3 make-replay.py

Запись снимается так (сервер и эмулятор уже подняты):

    node -e "const http=require('http'),fs=require('fs');const rec=[];
    http.get('http://localhost:3000/stream',r=>{r.on('data',d=>{
    for(const l of d.toString().split('\\n')) if(l.startsWith('data:')){
    const e=JSON.parse(l.slice(5)); rec.push({t:Date.now(),e});
    if(e.type==='over'){setTimeout(()=>{fs.writeFileSync('run.json',
    JSON.stringify(rec));process.exit(0)},2000)}}})})"
"""

import base64, io, json, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def packed(path, size, quality=None, fmt='PNG', alpha=False):
    im = Image.open(path)
    im = im.convert('RGBA') if alpha else im.convert('RGB')
    im.thumbnail(size, Image.LANCZOS)
    buf = io.BytesIO()
    if fmt == 'JPEG':
        im.save(buf, 'JPEG', quality=quality, optimize=True)
        mime = 'image/jpeg'
    else:
        im = im.quantize(colors=64, method=Image.FASTOCTREE) if alpha else im.quantize(colors=64)
        im.save(buf, 'PNG', optimize=True)
        mime = 'image/png'
    return f"data:{mime};base64," + base64.b64encode(buf.getvalue()).decode()


run = json.load(open(os.path.join(HERE, 'run.json'), encoding='utf-8'))

# картинки кладём только для тех, кто реально играл в этой партии
party = next((x['e'] for x in run if x['e']['type'] == 'party'), None)
slugs = [p['slug'] for p in party['players']] if party else []

images = {}
for slug in slugs:
    for suffix in ('', '-talk', '-angry'):
        p = os.path.join(HERE, 'assets', 'chars', f'{slug}{suffix}-cut.png')
        if os.path.exists(p):
            images[f'{slug}{suffix}-cut'] = packed(p, (300, 400), alpha=True)

places = {}
pdir = os.path.join(HERE, 'assets', 'places') if 'HERE' in dir() else 'assets/places'
for f in sorted(os.listdir(pdir)):
    if f.endswith('-night.jpg'):
        places[f[:-len('-night.jpg')]] = packed(os.path.join(pdir, f), (420, 746), 58, 'JPEG')
    elif f.endswith('.jpg'):
        places[f[:-len('.jpg')] + '-day'] = packed(os.path.join(pdir, f), (420, 746), 58, 'JPEG')

bg_day = packed(os.path.join(HERE, 'assets', 'bg-day.jpg'), (540, 960), 62, 'JPEG')
bg_night = packed(os.path.join(HERE, 'assets', 'bg-night.jpg'), (540, 960), 62, 'JPEG')

s = open(os.path.join(HERE, 'scene.html'), encoding='utf-8').read()
s = s.replace('<title>Предатели — сцена</title>', '<title>Предатели — запись прогона</title>')
s = s.replace("#room.day{background-image:url('assets/bg-day.jpg')}",
              f"#room.day{{background-image:url('{bg_day}')}}")
s = s.replace("#room.night{background-image:url('assets/bg-night.jpg');",
              f"#room.night{{background-image:url('{bg_night}');")

inject = "<script>\nwindow.EMBEDDED_PLACES = " + json.dumps(places, ensure_ascii=False) + ";\nwindow.EMBEDDED_IMAGES = {\n"
inject += ",\n".join(f'  "{k}": "{v}"' for k, v in images.items())
inject += "\n};\nwindow.REPLAY = " + json.dumps(run, ensure_ascii=False) + ";\n</script>\n"
s = s.replace('<body>\n', '<body>\n' + inject, 1)

out = os.path.join(HERE, 'replay.html')
open(out, 'w', encoding='utf-8').write(s)

dur = round((run[-1]['t'] - run[0]['t']) / 1000)
print(f'replay.html собран: {len(run)} событий, {dur} с, {os.path.getsize(out)//1024} KB')
