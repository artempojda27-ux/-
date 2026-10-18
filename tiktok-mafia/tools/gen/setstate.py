# ставит выбранный кадр состояния (-talk, -blink…) с силуэтом спокойного кадра
import sys, numpy as np
from PIL import Image
G, slug, state, src = sys.argv[1:5]
calm = np.asarray(Image.open(f"{G}/cast/{slug}.png").convert('RGB'))
bg = (calm[..., 0] == 0) & (calm[..., 1] == 255) & (calm[..., 2] == 0)
im = np.asarray(Image.open(src).convert('RGB')).copy()
Image.fromarray(im).save(f"{G}/cast/raw-{slug}{state}.png")
im[bg] = (0, 255, 0)
Image.fromarray(im).save(f"{G}/cast/{slug}{state}.png")
print(slug, state, '<-', src.rsplit('/', 1)[-1])
