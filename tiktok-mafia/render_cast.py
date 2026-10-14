"""
РЕНДЕР КАСТА В BLENDER.

    blender -b -P render_cast.py -- --build
    blender -b -P render_cast.py -- --models ./models

Два режима.

--build   собирает стилизованных персонажей прямо здесь, из примитивов,
          по данным из cast.json. Это не финальный арт, а рабочая болванка:
          объём, свет и тени уже настоящие, так что сцену можно смотреть
          в боевом виде, пока модели не готовы.

--models  берёт твои модели (.blend/.fbx/.glb с именем слага) и рендерит их
          тем же ригом. Вот ради этого режима всё и затевалось: камера,
          свет, размер кадра и имена файлов одинаковые для всех четырнадцати
          персонажей и для всех трёх состояний. Консистентность каста держится
          на риге, а не на аккуратности при экспорте.

Состояния берутся из шейп-ключей модели: `talk` и `angry`. Нет их —
персонаж отрендерится спокойным во всех трёх кадрах, сцена это переживёт.

Что на выходе, для каждого персонажа шесть файлов:
    margo-cut.png        прозрачный, для комнаты
    margo-talk-cut.png
    margo-angry-cut.png
    margo.png            на фоне, для вскрытия роли
    margo-talk.png
    margo-angry.png

cast.json готовится один раз:
    node -e "console.log(JSON.stringify(require('./characters.js').CAST))" > cast.json
"""

import bpy, bmesh, json, math, os, sys
from mathutils import Vector

# ─────────────────────────── параметры ───────────────────────────

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
MODE = 'models' if '--models' in ARGS else 'build'
MODELS_DIR = ARGS[ARGS.index('--models') + 1] if '--models' in ARGS else None

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'assets', 'chars')
W, H = 600, 800
SAMPLES = 32

STATES = [('', None), ('-talk', 'talk'), ('-angry', 'angry')]

# палитры повторяют заглушки, чтобы каст не поменялся при переходе на 3D
PALETTE = [
    ((0.78, 0.60, 0.48), (0.14, 0.08, 0.05), (0.32, 0.07, 0.13)),
    ((0.68, 0.50, 0.36), (0.04, 0.03, 0.04), (0.06, 0.09, 0.17)),
    ((0.85, 0.70, 0.58), (0.25, 0.14, 0.07), (0.14, 0.14, 0.17)),
    ((0.60, 0.43, 0.28), (0.09, 0.06, 0.04), (0.22, 0.15, 0.07)),
    ((0.82, 0.67, 0.55), (0.42, 0.28, 0.10), (0.10, 0.19, 0.14)),
    ((0.70, 0.52, 0.38), (0.06, 0.05, 0.04), (0.26, 0.11, 0.07)),
    ((0.88, 0.73, 0.62), (0.52, 0.38, 0.18), (0.18, 0.10, 0.25)),
    ((0.55, 0.39, 0.25), (0.13, 0.12, 0.11), (0.09, 0.14, 0.09)),
    ((0.75, 0.58, 0.45), (0.62, 0.46, 0.22), (0.30, 0.18, 0.09)),
    ((0.64, 0.46, 0.32), (0.18, 0.09, 0.06), (0.07, 0.10, 0.19)),
    ((0.90, 0.76, 0.67), (0.03, 0.03, 0.04), (0.25, 0.09, 0.14)),
    ((0.50, 0.35, 0.23), (0.40, 0.39, 0.38), (0.14, 0.13, 0.12)),
    ((0.84, 0.69, 0.57), (0.68, 0.53, 0.26), (0.33, 0.13, 0.22)),
    ((0.61, 0.42, 0.28), (0.07, 0.05, 0.04), (0.05, 0.13, 0.12)),
]


def load_cast():
    p = os.path.join(HERE, 'cast.json')
    if not os.path.exists(p):
        raise SystemExit(
            'Нет cast.json. Сделай его так:\n'
            '  node -e "console.log(JSON.stringify(require(\'./characters.js\').CAST))" > cast.json'
        )
    return json.load(open(p, encoding='utf-8'))


def features(look):
    """Внешность берём из описаний в characters.js — тех же, что и в промптах."""
    t = (look or '').lower()
    return {
        'glasses': 'очк' in t,
        'beard': 'борода' in t or 'щетина' in t,
        'balding': 'залыс' in t,
        'gray': 'седе' in t,
        'long': 'длинные' in t or 'до плеч' in t or 'прямые волосы' in t,
        'bob': 'каре' in t,
        'ponytail': 'хвост' in t or 'собранные' in t,
        'heavy': 'полноват' in t or 'крепк' in t,
    }


# ─────────────────────────── сцена и свет ───────────────────────────

def wipe():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.lights):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


def mat(name, rgb, rough=0.62):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = rough
    if 'Specular IOR Level' in bsdf.inputs:       # Blender 4.x
        bsdf.inputs['Specular IOR Level'].default_value = 0.2
    elif 'Specular' in bsdf.inputs:               # Blender 3.x
        bsdf.inputs['Specular'].default_value = 0.2
    return m


def rig():
    """Камера и свет. Один раз на весь каст — в этом весь смысл скрипта.

    Свет повторяет грейд сцены: тёплый ключевой спереди-слева, холодный
    контровой сзади. Контровой обязателен — он отбивает силуэт от фона,
    без него вырезка в комнате выглядит наклеенной."""
    cam_data = bpy.data.cameras.new('cam')
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 3.1
    cam = bpy.data.objects.new('cam', cam_data)
    cam.location = (0, -6, 1.45)
    cam.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    def lamp(name, kind, loc, energy, color, size=3.0):
        d = bpy.data.lights.new(name, kind)
        d.energy = energy
        d.color = color
        if kind == 'AREA':
            d.size = size
        o = bpy.data.objects.new(name, d)
        o.location = loc
        bpy.context.collection.objects.link(o)
        # направляем на грудь персонажа
        direction = Vector((0, 0, 1.3)) - Vector(loc)
        o.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
        return o

    lamp('key',  'AREA', (-2.6, -3.4, 3.4), 420, (1.0, 0.86, 0.68), 3.4)
    lamp('fill', 'AREA', (2.8, -2.6, 1.6),  110, (0.78, 0.82, 1.0), 4.0)
    lamp('rim',  'AREA', (1.6, 3.4, 3.0),   520, (0.72, 0.80, 1.0), 2.4)


def render_settings():
    sc = bpy.context.scene
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    engines = [e.bl_idname for e in bpy.types.RenderEngine.__subclasses__()]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    try:
        sc.eevee.taa_render_samples = SAMPLES
    except Exception:
        pass


def backdrop(on):
    """Фон для портретной версии. Тот же тёмно-бордовый, что в сцене."""
    name = 'backdrop'
    obj = bpy.data.objects.get(name)
    if on and not obj:
        bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 4.5, 1.2))
        p = bpy.context.object
        p.name = name
        p.rotation_euler = (math.radians(90), 0, 0)
        p.data.materials.append(mat('backdrop_mat', (0.18, 0.08, 0.11), 0.95))
    elif not on and obj:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.scene.render.film_transparent = not on


# ─────────────────────── сборка персонажа ───────────────────────

def build_character(idx, look, female, state):
    """Болванка из примитивов: тело, голова, волосы, глаза, рот.

    Намеренно крупные простые формы — стилизация читается на вертикальном
    экране в ленте, а мелкая детализация там всё равно теряется."""
    f = features(look)
    skin, hair, cloth = PALETTE[idx % len(PALETTE)]
    if f['gray']:
        hair = tuple(min(1.0, c + 0.45) for c in hair)

    m_skin, m_hair, m_cloth = mat('skin', skin), mat('hair', hair, 0.8), mat('cloth', cloth, 0.85)
    m_dark = mat('dark', (0.04, 0.03, 0.03), 0.5)
    m_white = mat('white', (0.95, 0.93, 0.9), 0.45)

    def add(prim, loc, scale, material, **kw):
        getattr(bpy.ops.mesh, prim)(location=loc, **kw)
        o = bpy.context.object
        o.scale = scale
        o.data.materials.append(material)
        bpy.ops.object.shade_smooth()
        return o

    heavy = 1.12 if f['heavy'] else 1.0

    # торс и плечи
    add('primitive_uv_sphere_add', (0, 0, 0.28), (0.95 * heavy, 0.62, 0.78), m_cloth)
    add('primitive_cylinder_add', (0, 0, 1.02), (0.17, 0.17, 0.16), m_skin)   # шея

    # голова
    head = add('primitive_uv_sphere_add', (0, 0, 1.46), (0.52 * heavy, 0.50, 0.60), m_skin)

    # волосы
    if f['long'] or (female and not f['bob'] and not f['ponytail']):
        add('primitive_uv_sphere_add', (0, 0.04, 1.44), (0.57, 0.55, 0.72), m_hair)
        add('primitive_uv_sphere_add', (0, 0.10, 1.10), (0.50, 0.42, 0.42), m_hair)
    elif f['bob']:
        add('primitive_uv_sphere_add', (0, 0.03, 1.50), (0.56, 0.54, 0.60), m_hair)
    elif f['ponytail']:
        add('primitive_uv_sphere_add', (0, 0.05, 1.54), (0.54, 0.52, 0.52), m_hair)
        add('primitive_uv_sphere_add', (0, 0.52, 1.44), (0.20, 0.26, 0.30), m_hair)
    else:
        cap = add('primitive_uv_sphere_add', (0, 0.02, 1.54), (0.53, 0.52, 0.46), m_hair)
        if f['balding']:
            cap.scale = (0.50, 0.50, 0.30)
            cap.location.z = 1.62

    if f['beard']:
        add('primitive_uv_sphere_add', (0, -0.10, 1.20), (0.42, 0.40, 0.30), m_hair)
        add('primitive_uv_sphere_add', (0, -0.30, 1.24), (0.26, 0.24, 0.20), m_skin)

    # глаза
    for sx in (-1, 1):
        add('primitive_uv_sphere_add', (sx * 0.19, -0.40, 1.52), (0.10, 0.06, 0.11), m_white)
        add('primitive_uv_sphere_add', (sx * 0.19, -0.45, 1.52), (0.05, 0.03, 0.05), m_dark)
        # бровь: у злого сведена к переносице
        brow = add('primitive_cube_add', (sx * 0.19, -0.44, 1.66), (0.12, 0.03, 0.022), m_hair)
        if state == 'angry':
            brow.rotation_euler = (0, math.radians(sx * -16), 0)
            brow.location.z = 1.63

    # нос
    add('primitive_uv_sphere_add', (0, -0.44, 1.40), (0.07, 0.07, 0.09), m_skin)

    # рот: закрыт / открыт / поджат
    if state == 'talk':
        add('primitive_uv_sphere_add', (0, -0.42, 1.24), (0.13, 0.07, 0.10), m_dark)
    elif state == 'angry':
        mouth = add('primitive_cube_add', (0, -0.44, 1.25), (0.14, 0.02, 0.012), m_dark)
        mouth.rotation_euler = (math.radians(-8), 0, 0)
    else:
        add('primitive_cube_add', (0, -0.44, 1.26), (0.13, 0.02, 0.014), m_dark)

    if f['glasses']:
        for sx in (-1, 1):
            g = add('primitive_torus_add', (sx * 0.19, -0.44, 1.52), (1, 1, 1), m_dark,
                    major_radius=0.13, minor_radius=0.018)
            g.rotation_euler = (math.radians(90), 0, 0)


# ─────────────────────────── рендер ───────────────────────────

def load_model(slug, suffix=''):
    """Твоя модель вместо болванки.

    Два способа задать состояния, оба работают.

    1. Один файл с шейп-ключами `talk` и `angry` — классика, если модель
       делал сам или ригал.
    2. Три отдельных файла: margo.glb, margo-talk.glb, margo-angry.glb.
       Это путь для моделей из нейросети: они приходят без лицевого рига,
       зато никто не мешает сгенерировать три картинки и сделать из них
       три модели. Камера и свет одни на всех, так что на выходе те же
       три кадра. Топология у них разная, но при статичной фронтальной
       камере это никак не проявляется.

    Ищем сначала файл с суффиксом, потом без него."""
    names = [slug + suffix, slug] if suffix else [slug]
    for name in names:
        for ext in ('.blend', '.fbx', '.glb', '.gltf'):
            p = os.path.join(MODELS_DIR, name + ext)
            if os.path.exists(p):
                return _import(p, ext)
    print(f'  модели для {slug}{suffix} нет, пропускаю')
    return False


def _import(p, ext):
    if True:
        if ext == '.blend':
            with bpy.data.libraries.load(p) as (src, dst):
                dst.objects = src.objects
            for o in dst.objects:
                if o:
                    bpy.context.collection.objects.link(o)
        elif ext == '.fbx':
            bpy.ops.import_scene.fbx(filepath=p)
        else:
            bpy.ops.import_scene.gltf(filepath=p)
        fit_to_frame()
        return True


def fit_to_frame():
    """Модели из нейросети приходят в произвольном масштабе и не по центру.
    Вгоняем в тот же кадр, что и болванки, иначе каст будет разнокалиберным."""
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name != 'backdrop']
    if not meshes:
        return

    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[i], w[i]) for i in range(3)))
            hi = Vector((max(hi[i], w[i]) for i in range(3)))

    height = max(1e-6, hi.z - lo.z)
    k = 2.1 / height                      # тот же рост, что у болванок
    center = (lo + hi) / 2

    for o in meshes:
        o.scale = [s * k for s in o.scale]
        o.location = (
            (o.location.x - center.x) * k,
            (o.location.y - center.y) * k,
            (o.location.z - lo.z) * k,
        )


def apply_shape(key_name):
    """Состояния берём из шейп-ключей модели. Нет ключа — остаётся спокойное."""
    for o in bpy.context.scene.objects:
        if o.type != 'MESH' or not o.data.shape_keys:
            continue
        for k in o.data.shape_keys.key_blocks:
            k.value = 1.0 if (key_name and k.name.lower() == key_name) else 0.0


def shoot(path, transparent=True):
    backdrop(not transparent)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    cast = load_cast()
    render_settings()

    for idx, c in enumerate(cast):
        slug = c['slug']
        female = (c.get('voice') or '').startswith('женский')
        print(f'[{idx + 1}/{len(cast)}] {c["name"]}')

        for suffix, key in STATES:
            wipe()
            rig()

            if MODE == 'build':
                build_character(idx, c.get('look', ''), female, key)
            else:
                if not load_model(slug, suffix):
                    break
                apply_shape(key)   # если модель одна и с шейп-ключами

            shoot(os.path.join(OUT, f'{slug}{suffix}-cut.png'), transparent=True)
            shoot(os.path.join(OUT, f'{slug}{suffix}.png'), transparent=False)

    print(f'\nготово: {OUT}')


main()
