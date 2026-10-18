# кадр «моргает»: перерисовываем только глаза спокойного кадра, по 2 варианта на выбор
import sys, os, torch, numpy as np, cv2
from PIL import Image, ImageFilter
from diffusers import AutoPipelineForInpainting
torch.set_num_threads(4)
CAST_DIR, OUT = sys.argv[1], sys.argv[2]; os.makedirs(OUT, exist_ok=True)
STYLE = "stylized semi-realistic 3d character, realistic proportions, cinematic side key light"
NEG = "open eyes, eyeballs, iris, pupils, cartoon, anime, text, blurry, deformed"
inp = AutoPipelineForInpainting.from_pretrained("stabilityai/sdxl-turbo", torch_dtype=torch.float32)
c = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
for slug in sys.argv[3].split(','):
    base = Image.open(f"{CAST_DIR}/raw-{slug}.png").convert('RGB')
    fs = c.detectMultiScale(cv2.cvtColor(np.array(base), cv2.COLOR_RGB2GRAY), 1.1, 5, minSize=(90, 90))
    x, y, w, h = max(fs, key=lambda f: f[2] * f[3])
    box = (x + w*.14, y + h*.34, x + w*.86, y + h*.52)
    a = np.zeros((680, 512), np.uint8); a[int(box[1]):int(box[3]), int(box[0]):int(box[2])] = 255
    m = Image.fromarray(a).filter(ImageFilter.GaussianBlur(4))
    crops = []
    for k in range(2):
        r = inp(prompt=f"eyes closed, eyelids shut, blinking, relaxed face, {STYLE}", negative_prompt=NEG,
                image=base, mask_image=m, strength=[1.0, 1.0][k], num_inference_steps=4, guidance_scale=0.0,
                width=512, height=680, generator=torch.Generator().manual_seed(900 + k * 23)).images[0]
        im = Image.composite(r.resize(base.size), base, m)
        im.save(f"{OUT}/{slug}-{k}.png")
        crops.append(im.crop((int(x), int(y + h*.2), int(x + w), int(y + h*.65))).resize((240, 108)))
    sheet = Image.new('RGB', (480, 108))
    for i, cr in enumerate(crops): sheet.paste(cr, (i * 240, 0))
    sheet.save(f"{OUT}/{slug}-sheet.png")
    print(slug, 'ok', flush=True)
