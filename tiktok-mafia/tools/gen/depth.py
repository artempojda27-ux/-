# карты глубины для параллакса: светлое — близко, тёмное — далеко
import sys, os, torch
from PIL import Image
from transformers import pipeline
torch.set_num_threads(4)
SRC = sys.argv[1]
pipe = pipeline("depth-estimation", model="depth-anything/Depth-Anything-V2-Small-hf", device=-1)
for f in sorted(os.listdir(SRC)):
    if not f.endswith('.jpg') or f.endswith('-depth.jpg'): continue
    im = Image.open(f"{SRC}/{f}").convert('RGB').resize((540, 960))
    d = pipe(im)["depth"].resize((540, 960)).convert('L')
    d.save(f"{SRC}/{f[:-4]}-depth.png")
    print(f, 'ok', flush=True)
