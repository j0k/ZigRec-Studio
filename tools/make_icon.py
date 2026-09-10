# -*- coding: utf-8 -*-
r"""Значок приложения: рисуется кодом, а не лежит картинкой.

Значок сделан кодом по двум причинам. Во-первых, его можно пересобрать и
поправить, а не искать исходник через год. Во-вторых, каждый размер рисуется
отдельно, а не сжимается из большого: то, что красиво в 256 пикселях, в 16
превращается в кашу.

Главная проверка значка — **читается ли он в 16 пикселей** на панели задач.
Поэтому здесь нет мелких деталей: крупный тёмный кадр, красная точка записи
и белое кольцо вокруг неё. Три формы, ни одной линии тоньше пикселя.

Запуск:
    python tools\make_icon.py
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ASSETS = os.path.join(REPO, "assets")

SIZES = [16, 32, 48, 64, 128, 256]

# Тёмная плитка, красная точка. Цвета не «фирменные», а рабочие: тёмное
# читается на светлой панели задач и на тёмной, красное значит запись.
TILE_TOP = (32, 38, 52)
TILE_BOTTOM = (14, 17, 24)
RING = (255, 255, 255)
DOT_TOP = (255, 82, 70)
DOT_BOTTOM = (214, 32, 62)


def lerp(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a, b))


def draw_icon(size, scale=8):
    """Нарисовать значок стороной `size`, сглаживая через увеличение."""
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Плитка со скруглением. Радиус в долях стороны, чтобы форма была одна
    # и та же на всех размерах.
    radius = int(s * 0.22)
    tile = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    td = ImageDraw.Draw(tile)
    td.rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=TILE_TOP + (255,))

    # Отвесный градиент: сверху светлее, снизу темнее. Рисуем полосами
    # и обрезаем по маске плитки.
    grad = Image.new("RGBA", (s, s))
    gd = ImageDraw.Draw(grad)
    for y in range(s):
        gd.line([(0, y), (s, y)], fill=lerp(TILE_TOP, TILE_BOTTOM, y / max(s - 1, 1)) + (255,))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # Кадр: тонкая светлая рамка внутри плитки. Она говорит «съёмка области»,
    # и это ровно то, что делает программа.
    inset = s * 0.17
    frame_w = max(1, int(round(s * 0.035)))
    d.rounded_rectangle(
        [inset, inset, s - 1 - inset, s - 1 - inset],
        radius=int(s * 0.09),
        outline=(255, 255, 255, 90),
        width=frame_w,
    )

    # Красная точка записи по центру — главное пятно значка.
    dot_r = s * 0.215
    cx = cy = s / 2
    dot_box = [cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r]

    dot = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dot)
    for y in range(int(cy - dot_r), int(cy + dot_r) + 1):
        t = (y - (cy - dot_r)) / max(dot_r * 2, 1)
        dd.line([(0, y), (s, y)], fill=lerp(DOT_TOP, DOT_BOTTOM, t) + (255,))
    dot_mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(dot_mask).ellipse(dot_box, fill=255)
    img.paste(dot, (0, 0), dot_mask)

    # Белое кольцо вокруг точки: без него красное на тёмном сливается,
    # особенно в мелком размере.
    ring_w = max(1, int(round(s * 0.045)))
    ring_pad = ring_w * 1.6
    d.ellipse(
        [dot_box[0] - ring_pad, dot_box[1] - ring_pad, dot_box[2] + ring_pad, dot_box[3] + ring_pad],
        outline=RING + (235,),
        width=ring_w,
    )

    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(ASSETS, exist_ok=True)
    images = [draw_icon(n) for n in SIZES]

    ico = os.path.join(ASSETS, "zigrec.ico")
    images[-1].save(ico, format="ICO", sizes=[(n, n) for n in SIZES])
    print("значок:", ico)

    # Большой png — для README и витрин: в них .ico не показывают.
    png = os.path.join(ASSETS, "zigrec-256.png")
    images[-1].save(png)
    print("картинка:", png)

    # Полоска со всеми размерами: по ней сразу видно, читается ли мелкий.
    strip_h = max(SIZES)
    strip = Image.new("RGBA", (sum(SIZES) + 16 * len(SIZES), strip_h), (250, 250, 250, 255))
    x = 8
    for img, n in zip(images, SIZES):
        strip.paste(img, (x, (strip_h - n) // 2), img)
        x += n + 16
    proof = os.path.join(ASSETS, "zigrec-sizes.png")
    strip.save(proof)
    print("все размеры рядом:", proof)


if __name__ == "__main__":
    main()
