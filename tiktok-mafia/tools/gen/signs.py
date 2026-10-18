# Абракадабру на вывесках стираем (cv2.inpaint по маске) и пишем настоящий неон.
# Координаты — в сетке 270×480 превью, умножаются на 4.
import sys, cv2, numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
SRC, DST = sys.argv[1], sys.argv[2]
SERIF = '/usr/share/fonts/truetype/freefont/FreeSerifBoldItalic.ttf'
SANS = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

def wipe(img, boxes):
    a = cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)
    m = np.zeros(a.shape[:2], np.uint8)
    for x0, y0, x1, y1 in boxes: m[y0*4:y1*4, x0*4:x1*4] = 255
    out = cv2.inpaint(a, m, 9, cv2.INPAINT_TELEA)
    # inpaint даёт мыльное пятно — подмешиваем шум, чтобы не было заплатки
    noise = np.random.default_rng(1).normal(0, 6, out.shape)
    out = np.where(m[..., None] > 0, np.clip(out + noise, 0, 255), out).astype(np.uint8)
    return Image.fromarray(cv2.cvtColor(out, cv2.COLOR_BGR2RGB))

def plate(img, x0, y0, x1, y1, fill):
    # табличка под буквами: без неё надпись висит в воздухе
    W, H = img.size
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((x0*4, y0*4, x1*4, y1*4), radius=10, fill=fill + (235,), outline=(30, 20, 18, 255), width=6)
    return Image.alpha_composite(img.convert('RGBA'), layer).convert('RGB')

def neon(img, text, font, size, cx, cy, color, glow=1.0, rot=0):
    W, H = img.size
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = ImageFont.truetype(font, size)
    w, h = d.textbbox((0, 0), text, font=f)[2:]
    d.text((cx * 4 - w // 2, cy * 4 - h // 2), text, font=f, fill=color + (255,))
    if rot: layer = layer.rotate(rot, center=(cx * 4, cy * 4), resample=Image.BICUBIC)
    base = img.convert('RGBA')
    for r, k in ((34, .8), (14, .9), (5, 1.0)):      # ореол неона: три размытия
        g = layer.filter(ImageFilter.GaussianBlur(r))
        g.putalpha(g.getchannel('A').point(lambda v: int(v * k * glow)))
        base = Image.alpha_composite(base, g)
    core = layer.copy()
    # сердцевина трубки почти белая
    px = np.asarray(core).copy(); px[..., :3] = np.clip(px[..., :3] * .7 + 255 * .3, 0, 255)
    return Image.alpha_composite(base, Image.fromarray(px)).convert('RGB')

RED, WARM, CREAM = (255, 40, 50), (255, 120, 40), (255, 210, 150)
jobs = {
  'bar':         ([(92, 28, 230, 158)], [('Midnight', SERIF, 150, 158, 78, RED, 1.0, 8)]),
  'bar-night':   ([(100, 30, 228, 140)], [('Midnight', SERIF, 140, 162, 82, RED, 0.9, 10)]),
  'diner':       ([(105, 160, 178, 198), (112, 262, 245, 302), (75, 140, 112, 185), (10, 170, 50, 220)],
                  [('DINER', SANS, 70, 143, 178, WARM, .7, 0), ('DINER · OPEN 24H', SANS, 64, 178, 283, CREAM, 1.0, 0)]),
  'diner-night': ([(150, 2, 215, 70), (120, 165, 182, 198), (115, 265, 252, 302)],
                  [('EAT', SANS, 90, 182, 34, (90, 170, 255), 1.0, 0), ('DINER', SANS, 64, 150, 182, WARM, .8, 0),
                   ('DINER · OPEN 24H', SANS, 62, 184, 284, CREAM, 1.0, 0)]),
}
plates = {
  'diner':       [(113, 168, 173, 190, (70, 22, 22)), (116, 270, 241, 296, (60, 18, 18))],
  'diner-night': [(120, 172, 180, 193, (40, 14, 14)), (118, 272, 250, 296, (36, 12, 12))],
}
for name, (boxes, texts) in jobs.items():
    im = wipe(Image.open(f'{SRC}/{name}.jpg').convert('RGB'), boxes)
    for pl in plates.get(name, []): im = plate(im, *pl)
    for t in texts: im = neon(im, *t)
    im.save(f'{DST}/{name}.jpg', quality=90)
    print(name, 'ok')
