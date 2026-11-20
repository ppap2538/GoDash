"""Toy-brick facade tiles (2026-11-20, Config/Look.BRICKS; our own artwork).

  python -I tools/make_facades_toy.py

Same five tiles and the same rules as tools/make_facades.py (one bay of one floor, 512 px RGBA, the wall drawn
near white so Texture.Color3 tints it with the building's paint, the GLASS CUT OUT so the part behind shows:
toy blue by day, warm lamp light at night), drawn like plastic toy bricks instead of a weathered real street:
flat clean walls, chunky white frames with a light top edge and a darker bottom edge, a soft shine across the
glass, round-cornered doors, and a row of studs along every ledge.
Writes assets/textures/facade/toy_<name>.png.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "facade")
S = 512
SS = 3  # supersampling
WALL = (244, 244, 242)
FRAME = (252, 252, 252)
EDGE_HI = (255, 255, 255)
EDGE_LO = (206, 208, 212)
SHADOW = (198, 200, 204)
LEDGE = (230, 231, 233)
DOOR = (196, 92, 70)
DOOR_LO = (164, 72, 54)
GATE = (120, 128, 140)
RAIL = (250, 250, 250)


def canvas(wall=WALL):
    im = Image.new("RGBA", (S * SS, S * SS), wall + (255,))
    return im, ImageDraw.Draw(im)


def R(d, box, fill, r=0):
    x0, y0, x1, y1 = [v * SS for v in box]
    f = fill if len(fill) == 4 else fill + (255,)
    if r > 0:
        d.rounded_rectangle([x0, y0, x1, y1], radius=r * SS, fill=f)
    else:
        d.rectangle([x0, y0, x1, y1], fill=f)


def hole(im, box, r=6):
    """Cut the glass out (transparent), with round corners, then a soft diagonal shine over it."""
    x0, y0, x1, y1 = [int(v * SS) for v in box]
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([x0, y0, x1, y1], radius=r * SS, fill=255)
    clear = Image.new("RGBA", im.size, (150, 190, 220, 0))
    im.paste(clear, (0, 0), mask)
    # shine: two pale bands, half see-through, so the glass reads glossy over whatever is behind
    shine = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    w, h = x1 - x0, y1 - y0
    for off, width, alpha in ((0.18, 0.16, 110), (0.42, 0.06, 90)):
        cx = x0 + w * off
        sd.polygon([(cx, y1), (cx + w * width, y1), (cx + w * width + h * 0.55, y0), (cx + h * 0.55, y0)], fill=(255, 255, 255, alpha))
    sm = Image.new("L", im.size, 0)
    ImageDraw.Draw(sm).rounded_rectangle([x0, y0, x1, y1], radius=r * SS, fill=255)
    im.paste(Image.alpha_composite(im, shine), (0, 0), sm)


def bevel(d, box, fill, r=8):
    """A plastic block: light top edge, darker bottom edge."""
    x0, y0, x1, y1 = box
    R(d, (x0, y0 + 4, x1, y1 + 4), EDGE_LO, r)
    R(d, (x0, y0, x1, y1), fill, r)
    R(d, (x0 + r * 0.6, y0 + 2, x1 - r * 0.6, y0 + 6), EDGE_HI, 2)


def studs(d, y, x0=0, x1=S, step=32, w=18, h=8, color=LEDGE):
    """A row of studs seen from the front, standing on a ledge whose top is at y."""
    x = x0 + step / 2 - w / 2
    while x + w <= x1:
        R(d, (x, y - h, x + w, y + 1), tuple(max(0, c - 22) for c in color), 3)
        R(d, (x + 1, y - h, x + w - 1, y - 2), color, 3)
        R(d, (x + 3, y - h + 1, x + w * 0.45, y - h + 3), EDGE_HI, 1)
        x += step


def ledge(d, y0, y1):
    R(d, (0, y0 + 4, S, y1 + 4), SHADOW)
    R(d, (0, y0, S, y1), LEDGE)
    R(d, (0, y0, S, y0 + 3), EDGE_HI)
    studs(d, y0)


def window(im, d, box, panes=2, sill=True, shutters=None):
    x0, y0, x1, y1 = box
    bevel(d, (x0 - 10, y0 - 10, x1 + 10, y1 + 10), FRAME, 12)
    f = 12
    pw = (x1 - x0 - f * (panes - 1)) / panes
    for p in range(panes):
        px = x0 + p * (pw + f)
        hole(im, (px, y0, px + pw, y1), 7)
    if shutters:
        sw = (x1 - x0) * 0.28
        for sx in (x0 - 18 - sw, x1 + 18):
            bevel(d, (sx, y0 - 6, sx + sw, y1 + 6), shutters, 8)
            for k in range(1, 6):
                yy = y0 + (y1 - y0) * k / 6
                R(d, (sx + 8, yy - 2, sx + sw - 8, yy + 2), tuple(max(0, c - 30) for c in shutters), 2)
    if sill:
        bevel(d, (x0 - 22, y1 + 14, x1 + 22, y1 + 30), LEDGE, 5)


def aircon(d, x, y, w=96, h=64):
    bevel(d, (x, y, x + w, y + h), (240, 242, 244), 10)
    cx, cy, r = x + w * 0.36, y + h / 2 + 2, h * 0.32
    d.ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS], fill=(120, 128, 140, 255))
    d.ellipse([(cx - r * 0.45) * SS, (cy - r * 0.45) * SS, (cx + r * 0.45) * SS, (cy + r * 0.45) * SS], fill=(200, 206, 214, 255))
    for k in range(4):
        yy = y + 16 + k * 10
        R(d, (x + w * 0.66, yy, x + w - 12, yy + 4), (180, 186, 196), 2)


def door(im, d, box, glass=True):
    x0, y0, x1, y1 = box
    bevel(d, (x0 - 10, y0 - 10, x1 + 10, y1 + 6), FRAME, 12)
    R(d, (x0, y0, x1, y1), DOOR_LO, 10)
    R(d, (x0, y0, x1, y1 - 6), DOOR, 10)
    if glass:
        hole(im, (x0 + 16, y0 + 16, x1 - 16, y0 + (y1 - y0) * 0.38), 8)
    R(d, (x0 + 14, y0 + (y1 - y0) * 0.5, x1 - 14, y0 + (y1 - y0) * 0.5 + 6), DOOR_LO, 3)
    kx = x1 - 22
    ky = y0 + (y1 - y0) * 0.58
    d.ellipse([(kx - 7) * SS, (ky - 7) * SS, (kx + 7) * SS, (ky + 7) * SS], fill=(250, 210, 70, 255))


def save(im, name):
    im = im.resize((S, S), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, "toy_" + name + ".png"), optimize=True)
    print("toy_" + name, im.size)


def apartment():
    """One room of a walk-up block: a balcony door and a window, chunky railing, an air-con, studded slab."""
    im, d = canvas()
    window(im, d, (60, 104, 280, 446), panes=2, sill=False)
    window(im, d, (342, 150, 458, 296), panes=1)
    aircon(d, 352, 352)
    # balcony railing in front of the door
    R(d, (16, 326, 300, 336), RAIL, 4)
    for x in range(24, 296, 26):
        R(d, (x, 336, x + 9, 462), RAIL, 3)
        R(d, (x + 6, 336, x + 9, 462), EDGE_LO, 1)
    ledge(d, 470, 498)
    R(d, (0, 0, S, 12), LEDGE)
    return im


def tower():
    """Curtain wall: big glass panes in white frames, a studded band at each floor."""
    im = Image.new("RGBA", (S * SS, S * SS), (150, 190, 220, 0))
    d = ImageDraw.Draw(im)
    R(d, (0, 0, S, 112), WALL)  # spandrel band, tinted with the building colour
    studs(d, 112, step=32)
    R(d, (0, 112, S, 124), FRAME)
    for i in range(5):
        x = i * S / 4
        R(d, (x - 7, 118, x + 7, S), FRAME)
    R(d, (0, 314, S, 326), FRAME)
    R(d, (0, S - 8, S, S), FRAME)
    # shine over each pane
    for i in range(4):
        x0 = i * S / 4 + 7
        hole(im, (x0, 124, x0 + S / 4 - 14, 314), 2)
        hole(im, (x0, 326, x0 + S / 4 - 14, S - 8), 2)
    return im


def town_upper():
    """Upper floor of one townhouse: two windows with coloured shutters, an air-con, a studded ledge."""
    im, d = canvas()
    window(im, d, (96, 120, 220, 330), panes=1, shutters=(70, 150, 210))
    window(im, d, (322, 120, 446, 330), panes=1, shutters=(70, 150, 210))
    aircon(d, 214, 372, 88, 58)
    ledge(d, 474, 500)
    R(d, (0, 0, 8, S), EDGE_LO)  # party wall line
    return im


def town_ground():
    """Ground floor of one townhouse: a roller shutter over the car space, a front door, a glass strip."""
    im, d = canvas()
    bevel(d, (170, 90, 496, 512), FRAME, 10)
    R(d, (182, 102, 484, 512), GATE)
    for y in range(110, 512, 22):
        R(d, (182, y, 484, y + 12), (150, 158, 170), 3)
        R(d, (182, y, 484, y + 3), (186, 192, 202), 1)
    door(im, d, (40, 160, 140, 512))
    for i in range(6):
        hole(im, (40 + i * 76, 30, 40 + i * 76 + 58, 64), 6)
    R(d, (0, 0, 8, S), EDGE_LO)
    return im


def home():
    """Front of a detached house: a door under a little canopy, a wide window with flower box."""
    im, d = canvas()
    door(im, d, (72, 168, 176, 512))
    bevel(d, (46, 120, 202, 140), (230, 96, 76), 6)  # canopy
    studs(d, 120, 46, 202, step=26, w=14, h=7, color=(230, 96, 76))
    window(im, d, (252, 176, 454, 352), panes=3, sill=True)
    # flower box on the sill
    for k in range(9):
        x = 248 + k * 24
        c = ((236, 80, 110), (250, 200, 60), (255, 140, 180))[k % 3]
        d.ellipse([(x) * SS, (360) * SS, (x + 16) * SS, (376) * SS], fill=c + (255,))
    R(d, (0, 488, S, 512), LEDGE)
    return im


def main():
    save(apartment(), "facade_apartment")
    save(tower(), "facade_tower")
    save(town_upper(), "facade_town_upper")
    save(town_ground(), "facade_town_ground")
    save(home(), "facade_home")


if __name__ == "__main__":
    main()
