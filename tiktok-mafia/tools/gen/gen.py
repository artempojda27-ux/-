import sys, os, time, torch, numpy as np, cv2
from PIL import Image, ImageFilter
from diffusers import AutoPipelineForText2Image, AutoPipelineForInpainting
from rembg import remove, new_session
torch.set_num_threads(4)
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
# стиль и кадр первыми: CLIP видит только 77 токенов
STYLE = "stylized semi-realistic 3d character, arcane style, realistic proportions, cinematic side key light, rim light, muted film colors"
FRAME = "head and shoulders portrait, whole head in frame with headroom, facing camera, plain grey backdrop"
NEG = "pixar, big eyes, cartoon, chibi, anime, photo, text, cropped head, two people, blurry"
CAST = {
 'margo':  "woman 34, bold red lipstick, glamorous styled hair, burgundy silk blouse, defiant look",
 'david':  "man 41, front view looking straight at camera, short military haircut, strong jaw, dark navy shirt, stern",
 'liza':   "girl 22, dark straight hair, no makeup, oversized olive hoodie, sullen",
 'artur':  "bartender man 29, stubble, messy hair, black t-shirt, half smile",
 'nina':   "woman doctor 37, hair in bun, thin glasses, dark green cardigan",
 'kostya': "lean guy 26, buzz cut, red track jacket, tense eyes",
 'vika':   "woman 31, soft features, shoulder-length chestnut hair, cream knit sweater",
 'oleg':   "man 45, rough weathered face, faded denim work shirt, heavy stare",
 'rita':   "athletic woman 28, dark high ponytail, black sports top, sly smile",
 'slava':  "man 33, front view looking straight at camera, receding hairline, tired eyes, mustard windbreaker",
 'emma':   "woman 24, black bob haircut, delicate features, black turtleneck",
 'gena':   "chubby man 52, graying temples, stretched brown sweater, sleepy face",
 'alina':  "glamorous woman 27, long blonde hair, pink fashionable jacket, posing",
 'rustam': "strong man 35, realistic face, trimmed black beard, black chef jacket, calm",
}
cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
RB = new_session('isnet-general-use')

def faces(img):
    g = cv2.cvtColor(np.array(img), cv2.COLOR_RGB2GRAY)
    return cascade.detectMultiScale(g, 1.1, 5, minSize=(90, 90))

def good(img):
    """Ровно одно лицо, макушка в кадре, лицо не мелкое и по центру."""
    fs = faces(img)
    if len(fs) != 1: return None
    x, y, w, h = fs[0]
    if y - 0.25 * h < 0: return None                 # макушка срезана
    if abs((x + w / 2) - img.width / 2) > img.width * 0.2: return None
    return fs[0]

def mask(size, boxes):
    a = np.zeros((size[1], size[0]), np.uint8)
    for x0, y0, x1, y1 in boxes: a[int(y0):int(y1), int(x0):int(x1)] = 255
    return Image.fromarray(a).filter(ImageFilter.GaussianBlur(6))

only = sys.argv[2].split(',') if len(sys.argv) > 2 and sys.argv[2] else list(CAST)
t2i = AutoPipelineForText2Image.from_pretrained("stabilityai/sdxl-turbo", torch_dtype=torch.float32)
inp = AutoPipelineForInpainting.from_pipe(t2i)
for slug in only:
    if os.path.exists(f"{OUT}/{slug}-angry.png"): continue    # можно перезапускать
    look = CAST[slug]; t = time.time(); fb = None
    print(slug, '…', flush=True)
    raw = f"{OUT}/raw-{slug}.png"; attempt = -1
    for attempt in range(0 if os.path.exists(raw) else 6):
        seed = 1000 + list(CAST).index(slug) * 7 + attempt * 101 + int(os.environ.get("SEED_SHIFT", 0))
        base = t2i(prompt=f"{STYLE}, {look}, {FRAME}", negative_prompt=NEG, num_inference_steps=4, guidance_scale=0.0,
                   width=512, height=680, generator=torch.Generator().manual_seed(seed)).images[0]
        fb = good(base)
        print('  попытка', attempt, 'ок' if fb is not None else 'брак', flush=True)
        if fb is not None: break
    if os.path.exists(raw):
        base = Image.open(raw).convert('RGB'); fb = good(base)
    if fb is None:
        print(slug, 'нет хорошего кадра, беру последний', flush=True)
        fs = faces(base); fb = max(fs, key=lambda f: f[2]*f[3]) if len(fs) else (176, 120, 160, 160)
    x, y, w, h = fb
    # лицо в кадре крупное: маска только по губам, иначе перерисуется вся челюсть
    mouth = (x + w*.32, y + h*.70, x + w*.68, y + h*.90)
    brows = (x + w*.12, y + h*.18, x + w*.88, y + h*.45)
    who = 'woman' if any(k in look for k in ('woman', 'girl')) else 'man'
    frames = {'': base}
    for suf, mood, boxes, st in (('-talk', f"close-up of a {who}'s open mouth, speaking, lips parted, upper teeth visible", [mouth], 1.0),
                                 ('-angry', f"angry {who}, furrowed brows, glaring eyes, tight frowning lips", [mouth, brows], .85)):
        m = mask(base.size, boxes)
        if 'lipstick' in look: mood += ', red lipstick'
        # рот: три попытки, берём ту, где он открыт сильнее всего (больше всего изменилось
        # в области губ) — иначе лип-синк мигает почти одинаковыми кадрами
        best, score = None, -1
        for k in range(3 if suf == '-talk' else 1):
            ed = inp(prompt=f"{mood}, {STYLE}", negative_prompt=NEG + ', closed mouth' * (suf == '-talk'), image=base, mask_image=m, strength=st,
                     num_inference_steps=4, guidance_scale=0.0, width=512, height=680,
                     generator=torch.Generator().manual_seed(7 + k * 31)).images[0]
            im = Image.composite(ed.resize(base.size), base, m)   # вне маски пиксели спокойного кадра
            x0, y0, x1, y1 = map(int, mouth)
            d = np.abs(np.asarray(im, float)[y0:y1, x0:x1] - np.asarray(base, float)[y0:y1, x0:x1]).mean()
            if d > score: best, score = im, d
        frames[suf] = best
    # одна маска фигуры на все три кадра: силуэт не дрожит при лип-синке
    alpha = remove(base, session=RB, only_mask=True).point(lambda v: 255 if v > 128 else 0)
    for suf, im in frames.items():
        im.save(f"{OUT}/raw-{slug}{suf}.png")
        out = Image.new('RGB', im.size, (0, 255, 0)); out.paste(im, (0, 0), alpha)
        out.save(f"{OUT}/{slug}{suf}.png")
    print(slug, f"{time.time()-t:.0f}s attempt={attempt}", flush=True)
