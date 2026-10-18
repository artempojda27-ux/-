import sys, os, time, torch
from PIL import Image
from diffusers import AutoPipelineForText2Image, AutoPipelineForImage2Image
torch.set_num_threads(4)
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
# тот же стиль, что у каста: стилизованное 3D с киношным светом. Людей нет — силуэты рисует сцена
STYLE = "stylized semi-realistic 3d environment, cinematic film still, vertical frame, no people"
DAY = "overcast late afternoon, muted warm film colors"
NIGHT = "deep night, dark sky, blue moonlight, few warm lit windows and lamps, wet reflections"
NEG = "people, person, crowd, text, letters, words, logo, sign, signboard, signage text, watermark, cartoon, anime, blurry"
PLACES = {
 'city':     "panorama of old port city, rooftops, harbor cranes, bay",
 'square':   "old town square, fountain, benches, old building facades",
 'bar':      "bar entrance, red neon glow, fogged windows, brick wall",
 'station':  "small police station, blue lamp over door, police car",
 'depot':    "harbor warehouse, shipping containers, crane, lone street lamp",
 'clinic':   "small clinic entrance, glowing red cross, empty parking",
 'park':     "park alley, sparse lamps, bare trees, empty bench",
 'terminal': "bus station platform, bus with headlights, empty shelter",
 'home':     "soviet five-storey apartment block, courtyard with swings",
 'diner':    "roadside diner by highway, warm windows, parked trucks",
 'church':   "old stone church, stained glass windows, heavy doors, candles",
 'roof':     "flat rooftop of tall building, antennas, city lights below",
 'laundry':  "24 hour laundromat interior, rows of washing machines, fluorescent light",
 'garages':  "rows of rusty garages, puddles, single lamp",
 'club':     "basement club entrance, red light, smoke, concrete stairs down",
 'pier':     "wooden pier, lamps over water, boats moored",
 'bridge':   "steel railway bridge over river, rails, train searchlight",
 'hotel':    "old grand hotel entrance, revolving door, brass lamps, carpeted stairs",
}
import numpy as np
def grade_night(im):
    # ночь не только в промпте: тени в синеву, общий уровень вниз, а тёплые
    # источники (окна, фонари) не трогаем — иначе ночной кадр выходит днём в сумерках
    a = np.asarray(im, float) / 255
    lum = a.mean(2, keepdims=True)
    lights = np.clip((lum - 0.62) / 0.25, 0, 1)
    cool = a * np.array([0.42, 0.52, 0.78]) ** 1.0
    cool = cool ** 1.15
    out = cool * (1 - lights) + a * lights
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype('uint8'))

only = sys.argv[2].split(',') if len(sys.argv) > 2 and sys.argv[2] else list(PLACES)
t2i = AutoPipelineForText2Image.from_pretrained("stabilityai/sdxl-turbo", torch_dtype=torch.float32)
i2i = AutoPipelineForImage2Image.from_pipe(t2i)
for i, pid in enumerate(only):
    if os.path.exists(f"{OUT}/{pid}-night.jpg"): continue
    t = time.time(); look = PLACES[pid]; seed = 3000 + list(PLACES).index(pid) * 13
    day = t2i(prompt=f"{STYLE}, {look}, {DAY}", negative_prompt=NEG, num_inference_steps=4, guidance_scale=0.0,
              width=512, height=912, generator=torch.Generator().manual_seed(seed)).images[0]
    # ночь из дня: то же место, тот же ракурс, другой свет
    night = i2i(prompt=f"{STYLE}, {look}, {NIGHT}", negative_prompt=NEG, image=day, strength=0.8,
                num_inference_steps=4, guidance_scale=0.0, generator=torch.Generator().manual_seed(seed)).images[0]
    night = grade_night(night)
    for name, im in ((pid, day), (f"{pid}-night", night)):
        im.resize((1080, 1920), Image.LANCZOS).save(f"{OUT}/{name}.jpg", quality=88)
    print(pid, f"{time.time()-t:.0f}s", flush=True)
