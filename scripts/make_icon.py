#!/usr/bin/env python3
"""Generate the PAC-MAN arcade app icon from procedural vector-style art."""
from __future__ import annotations

import math
import os
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
ICON = RESOURCES / "AppIcon.png"
ICNS = RESOURCES / "AppIcon.icns"

S = 2048
OUT = 1024
MARGIN = 112
CORNER = 420


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_mask(size: int, margin: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((margin, margin, size - margin, size - margin), radius=radius, fill=255)
    return mask


def glow_layer(size: int, painter, blur: int) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    painter(ImageDraw.Draw(layer))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def draw_pacman(draw: ImageDraw.ImageDraw, center, radius: float, fill, mouth_degrees=62):
    cx, cy = center
    box = (cx - radius, cy - radius, cx + radius, cy + radius)
    start = mouth_degrees / 2
    end = 360 - mouth_degrees / 2
    draw.pieslice(box, start=start, end=end, fill=fill)
    # A tiny opaque highlight helps the shape read at icon sizes. (Drawing
    # translucent pixels directly would punch a hole in the icon's alpha.)
    draw.ellipse((cx - radius * 0.52, cy - radius * 0.58,
                  cx - radius * 0.42, cy - radius * 0.48),
                 fill=(255, 244, 150, 255))


def ghost_points(cx: float, cy: float, width: float, height: float):
    radius = width / 2
    head_center = cy - height * 0.13
    left = cx - radius
    right = cx + radius
    bottom = cy + height * 0.50
    top = head_center - radius
    points = [(left, cy + height * 0.20)]
    for i in range(17):
        angle = math.pi + math.pi * i / 16
        points.append((cx + math.cos(angle) * radius, head_center + math.sin(angle) * radius))
    points.extend([
        (right, cy + height * 0.20),
        (cx + width * 0.33, bottom + height * 0.10),
        (cx + width * 0.17, bottom - height * 0.04),
        (cx, bottom + height * 0.10),
        (cx - width * 0.17, bottom - height * 0.04),
        (cx - width * 0.33, bottom + height * 0.10),
        (left, cy + height * 0.20),
    ])
    return points


def main():
    RESOURCES.mkdir(exist_ok=True)
    image = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # Rounded superellipse-like tile with a deep midnight gradient.
    mask = rounded_mask(S, MARGIN, CORNER)
    background = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(background)
    top_color = (4, 7, 22)
    bottom_color = (13, 22, 58)
    for y in range(MARGIN, S - MARGIN):
        t = (y - MARGIN) / max(1, S - 2 * MARGIN)
        bg_draw.line((0, y, S, y), fill=lerp(top_color, bottom_color, t) + (255,))
    image.paste(background, (0, 0), mask)
    draw = ImageDraw.Draw(image)

    # Ambient blue and pink light.
    aura = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    aura_draw = ImageDraw.Draw(aura)
    aura_draw.ellipse((180, 860, 1840, 2130), fill=(28, 62, 220, 70))
    aura_draw.ellipse((1040, 260, 2060, 1220), fill=(216, 38, 120, 42))
    aura = aura.filter(ImageFilter.GaussianBlur(240))
    image.alpha_composite(Image.composite(aura, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    # Maze rails in the corners.
    def draw_maze(d: ImageDraw.ImageDraw, color, width):
        # Top-left circuit.
        d.line((250, 530, 250, 250, 560, 250), fill=color, width=width, joint="curve")
        # Top-right circuit.
        d.line((S - 560, 250, S - 250, 250, S - 250, 500), fill=color, width=width, joint="curve")
        # Bottom-left circuit.
        d.line((250, S - 500, 250, S - 250, 560, S - 250), fill=color, width=width, joint="curve")
        # Bottom-right circuit.
        d.line((S - 560, S - 250, S - 250, S - 250, S - 250, S - 500), fill=color, width=width, joint="curve")

    maze_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_maze(ImageDraw.Draw(maze_glow), (44, 100, 255, 180), 34)
    maze_glow = maze_glow.filter(ImageFilter.GaussianBlur(26))
    image.alpha_composite(maze_glow)
    draw = ImageDraw.Draw(image)
    draw_maze(draw, (74, 140, 255, 235), 12)
    draw_maze(draw, (155, 205, 255, 150), 3)

    # Pellet trail.
    for index, x in enumerate((1120, 1190, 1260, 1330)):
        y = 1305 - index * 18
        r = 14
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 216, 154, 245))

    # Pac-Man.
    pac_center = (700, 1300)
    pac_radius = 430
    pac_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_pacman(ImageDraw.Draw(pac_glow), pac_center, pac_radius + 34, (255, 186, 0, 95), 64)
    pac_glow = pac_glow.filter(ImageFilter.GaussianBlur(70))
    image.alpha_composite(pac_glow)
    draw = ImageDraw.Draw(image)
    draw_pacman(draw, pac_center, pac_radius, (255, 224, 22, 255), 64)
    # Eye.
    eye_x, eye_y = pac_center[0] + 48, pac_center[1] - 178
    draw.ellipse((eye_x - 44, eye_y - 44, eye_x + 44, eye_y + 44), fill=(28, 22, 14, 255))
    draw.ellipse((eye_x - 24, eye_y - 30, eye_x + 2, eye_y - 12), fill=(255, 252, 222, 255))

    # Blinky, in hot pursuit at upper right.
    ghost_cx, ghost_cy = 1410, 690
    ghost_width, ghost_height = 390, 450
    ghost_fill = (255, 47, 72, 255)
    ghost_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(ghost_glow)
    gd.polygon(ghost_points(ghost_cx, ghost_cy, ghost_width + 30, ghost_height + 30), fill=(255, 40, 80, 125))
    ghost_glow = ghost_glow.filter(ImageFilter.GaussianBlur(58))
    image.alpha_composite(ghost_glow)
    draw = ImageDraw.Draw(image)
    draw.polygon(ghost_points(ghost_cx, ghost_cy, ghost_width, ghost_height), fill=ghost_fill)
    # Ghost eyes looking left, toward Pac-Man.
    for side in (-1, 1):
        ex = ghost_cx + side * 78
        ey = ghost_cy - 55
        draw.ellipse((ex - 65, ey - 75, ex + 65, ey + 75), fill=(255, 255, 255, 255))
        draw.ellipse((ex - 42, ey - 36, ex + 22, ey + 48), fill=(31, 48, 195, 255))
        draw.ellipse((ex - 27, ey - 24, ex - 5, ey - 2), fill=(190, 225, 255, 210))

    # Power pellet.
    px, py = 1490, 1330
    for radius, alpha in ((74, 35), (48, 90)):
        pellet_glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        pd = ImageDraw.Draw(pellet_glow)
        pd.ellipse((px - radius, py - radius, px + radius, py + radius), fill=(255, 183, 83, alpha))
        image.alpha_composite(pellet_glow.filter(ImageFilter.GaussianBlur(30)))
    draw = ImageDraw.Draw(image)
    draw.ellipse((px - 34, py - 34, px + 34, py + 34), fill=(255, 214, 163, 255))
    draw.ellipse((px - 19, py - 22, px - 2, py - 5), fill=(255, 249, 228, 200))

    # Fine scanlines and a soft vignette.
    scan = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scan)
    for y in range(0, S, 8):
        sd.line((0, y, S, y), fill=(0, 0, 0, 32))
    scan = Image.composite(scan, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask)
    image.alpha_composite(scan)

    vignette = Image.new("L", (S, S), 0)
    vd = ImageDraw.Draw(vignette)
    vd.ellipse((-S * 0.12, -S * 0.12, S * 1.12, S * 1.12), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(220))
    dark = Image.new("RGBA", (S, S), (0, 0, 0, 105))
    dark.putalpha(Image.eval(vignette, lambda v: 255 - v))
    image.alpha_composite(Image.composite(dark, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    # Preserve transparency outside the rounded tile.
    final_alpha = image.getchannel("A")
    final_alpha = Image.composite(final_alpha, Image.new("L", (S, S), 0), mask)
    image.putalpha(final_alpha)

    image = image.resize((OUT, OUT), Image.Resampling.LANCZOS)
    image.save(ICON)

    ICONSET.mkdir(exist_ok=True)
    sizes = [16, 32, 128, 256, 512]
    for size in sizes:
        image.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / f"icon_{size}x{size}.png")
        image.resize((size * 2, size * 2), Image.Resampling.LANCZOS).save(ICONSET / f"icon_{size}x{size}@2x.png")

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(f"Wrote {ICON.relative_to(ROOT)} and {ICNS.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
