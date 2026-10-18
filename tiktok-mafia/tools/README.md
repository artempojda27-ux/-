# Инструменты генерации

Всё это запускалось во временной среде; здесь — чтобы повторить в новой сессии.

## gen/ — каст и город (SDXL-Turbo на CPU, бесплатно)

    python3 -m venv sd && sd/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
    sd/bin/pip install diffusers transformers accelerate safetensors "opencv-python-headless<5" "rembg[cpu]"

- `gen.py` — портреты: спокойный кадр + рот/брови перерисовкой (лицо не плывёт)
- `talk.py`, `blink.py` — варианты рта и моргания, выбираются глазами; `setstate.py` ставит выбранный
- `places.py` — места днём и ночью (ночь из дня + грейд); `depth.py` — карты глубины
- `signs.py` — стирает абракадабру на вывесках и пишет настоящий неон

После — `python3 prepare_art.py` (вырезка, выравнивание).

## liveportrait/ — живые петли персонажей (LivePortrait, MIT, на CPU)

    git clone --depth 1 https://github.com/KwaiVGI/LivePortrait src
    # веса: huggingface KwaiVGI/LivePortrait, только liveportrait/* (InsightFace НЕ нужен)
    cp haar_face.py src/src/utils/
    # в src/src/utils/cropper.py заменить импорт:
    #   from .haar_face import HaarFace as FaceAnalysisDIY

`haar_face.py` — замена InsightFace (его модели только для некоммерческого
использования) на детектор OpenCV: для эфира с донатами это обязательно.

Ведущие клипы: `d13.mp4` (говорит) и `d19.mp4` (слушает) из примеров
LivePortrait, первые 4 с при 20 fps → `drv/talk.mp4`, `drv/idle.mp4`.
`batch.sh slug…` считает обе петли (~10 мин каждая) и через `make-alive.sh`
кладёт WebM с прозрачностью в `assets/alive/`.
