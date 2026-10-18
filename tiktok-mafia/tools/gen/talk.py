# варианты рта «говорит» для выбора глазами: автоотбор по силе изменения выбирал кривые пятна
import sys, os, torch, numpy as np, cv2
from PIL import Image, ImageFilter
from diffusers import AutoPipelineForInpainting
torch.set_num_threads(4)
CAST_DIR, OUT = sys.argv[1], sys.argv[2]; os.makedirs(OUT, exist_ok=True)
STYLE = "stylized semi-realistic 3d character, realistic proportions, cinematic side key light, rim light, muted film colors"
NEG = "pixar, cartoon, anime, text, blurry, closed mouth, mustache, deformed lips"
inp = AutoPipelineForInpainting.from_pretrained("stabilityai/sdxl-turbo", torch_dtype=torch.float32)
c = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
for slug in sys.argv[3].split(','):
    base = Image.open(f"{CAST_DIR}/raw-{slug}.png").convert('RGB')
    fs = c.detectMultiScale(cv2.cvtColor(np.array(base), cv2.COLOR_RGB2GRAY), 1.1, 5, minSize=(90, 90))
    x, y, w, h = max(fs, key=lambda f: f[2] * f[3])
    # у мужских лиц губы ниже: маску можно опустить через MOUTH_Y="0.78,1.02"
    y0, y1 = map(float, os.environ.get('MOUTH_Y', '0.70,0.90').split(','))
    box = (x + w*.30, y + h*y0, x + w*.70, y + h*y1)
    a = np.zeros((680, 512), np.uint8); a[int(box[1]):int(box[3]), int(box[0]):int(box[2])] = 255
    m = Image.fromarray(a).filter(ImageFilter.GaussianBlur(5))
    who = sys.argv[4] if len(sys.argv) > 4 else 'person'
    crops = []
    for k in range(6):
        pr = ["slightly open mouth, speaking, lips parted, natural lips, upper teeth visible",
              "mouth open mid-word, talking, natural lips, teeth visible"][k % 2]
        r = inp(prompt=f"{pr}, {STYLE}", negative_prompt=NEG, image=base, mask_image=m, strength=[1.0, .9, .8][k // 2],
                num_inference_steps=4, guidance_scale=0.0, width=512, height=680,
                generator=torch.Generator().manual_seed(100 + k * 17)).images[0]
        im = Image.composite(r.resize(base.size), base, m)
        im.save(f"{OUT}/{slug}-{k}.png")
        crops.append(im.crop((int(x + w*.15), int(y + h*.5), int(x + w*.85), int(y + h*1.05))).resize((210, 165)))
    sheet = Image.new('RGB', (210 * 6, 165))
    for i, cr in enumerate(crops): sheet.paste(cr, (i * 210, 0))
    sheet.save(f"{OUT}/{slug}-sheet.png")
    print(slug, 'ok', flush=True)
