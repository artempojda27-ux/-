# Замена InsightFace (модели только для некоммерческого использования) на детектор
# лиц OpenCV (Apache 2.0). Нужен лишь грубый старт: пять опорных точек по рамке
# лица, точные 203 точки дальше находит собственная модель LivePortrait (MIT).
import cv2
import numpy as np

_CASCADE = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')


class _Face(dict):
    def __getattr__(self, k):
        return self[k]


class HaarFace:
    def __init__(self, *a, **kw):
        self._last = None

    def prepare(self, *a, **kw):
        pass

    def warmup(self):
        pass

    def get(self, img_bgr, **kw):
        g = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
        fs = _CASCADE.detectMultiScale(g, 1.1, 5, minSize=(60, 60))
        if len(fs) == 0:
            # в видео детектор иногда моргает: держим последнее лицо
            return [self._last] if self._last is not None else []
        x, y, w, h = max(fs, key=lambda f: f[2] * f[3])
        # типичные пропорции лица в рамке Haar: глаза, кончик носа, уголки рта
        pts = np.array([
            [x + .30 * w, y + .40 * h], [x + .70 * w, y + .40 * h],
            [x + .50 * w, y + .60 * h],
            [x + .36 * w, y + .78 * h], [x + .64 * w, y + .78 * h],
        ], dtype=np.float32)
        # растягиваем от центра лица: по пяти кучным точкам LivePortrait взял бы
        # слишком тесный кадр. Направление «глаза → рот» от этого не меняется
        c = np.array([x + .5 * w, y + .59 * h], dtype=np.float32)
        pts = c + (pts - c) * 2.4
        face = _Face(bbox=np.array([x, y, x + w, y + h], dtype=np.float32), landmark_2d_106=pts, kps=pts)
        self._last = face
        return [face]
