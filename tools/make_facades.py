"""Draw the facade tiles for homes, townhouses, apartments and towers (our own artwork).

  python -I tools/make_facades.py

Writes assets/textures/facade/<name>.png (512 px, RGBA). Each tile is one bay of one floor. The
wall is drawn near white so the game can tint it with the building's paint colour
(Texture.Color3); the GLASS IS TRANSPARENT, so the part behind shows through: dark by day, warm
lamp light at night. One part with a tiled Texture replaces dozens of window parts.
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "facade")
S = 512
SS = 3  # supersampling
WALL = (238, 236, 230)
FRAME = (250, 250, 248)
ALU = (176, 182, 188)
DARK = (66, 70, 76)
SHADE = (196, 194, 188)


def canvas(rnd, wall=WALL):
    im = Image.new("RGBA", (S * SS, S * SS), wall + (255,))
    d = ImageDraw.Draw(im)
    # soft blotches so a tinted wall is not one flat colour
    for _ in range(46):
        x, y = rnd.randrange(S * SS), rnd.randrange(S * SS)
        r = rnd.randrange(30 * SS, 110 * SS)
        k = rnd.randint(-7, 5)
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(max(0, min(255, c + k)) for c in wall) + (255,))
    im = im.filter(ImageFilter.GaussianBlur(26 * SS))
    return im, ImageDraw.Draw(im)


def R(d, box, fill):
    x0, y0, x1, y1 = box
    d.rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=fill if len(fill) == 4 else fill + (255,))


def hole(im, box):
    """Cut the glass out (transparent)."""
    x0, y0, x1, y1 = [int(v * SS) for v in box]
    im.paste((40, 44, 44, 0), (x0, y0, x1, y1))


def streaks(d, rnd, x0, x1, y0, n=5):
    """Faint rain stains running down the wall."""
    for _ in range(n):
        x = rnd.uniform(x0, x1)
        L = rnd.uniform(40, 120)
        w = rnd.uniform(3, 7)
        steps = 12
        for i in range(steps):
            k = int(13 * (1 - i / steps))
            d.rectangle([x * SS, (y0 + L * i / steps) * SS, (x + w) * SS, (y0 + L * (i + 1) / steps) * SS],
                        fill=(WALL[0] - k, WALL[1] - k - 1, WALL[2] - k - 3, 255))


def window(im, d, box, panes=2, sill=True, bars=False, louvre=False):
    x0, y0, x1, y1 = box
    R(d, (x0 - 5, y0 - 5, x1 + 5, y1 + 5), (150, 148, 142))  # shadow line round the frame
    R(d, (x0, y0, x1, y1), FRAME)
    f = 7
    pw = (x1 - x0 - f * (panes + 1)) / panes
    top = y0 + f
    if louvre:
        lh = (y1 - y0) * 0.24
        for i in range(5):
            yy = y0 + f + i * (lh - f) / 5
            R(d, (x0 + f, yy, x1 - f, yy + (lh - f) / 5 - 2), (214, 216, 214))
        top = y0 + lh + f
    for p in range(panes):
        px = x0 + f + p * (pw + f)
        hole(im, (px, top, px + pw, y1 - f))
        if bars:
            for k in range(1, 4):
                bx = px + pw * k / 4
                R(d, (bx - 1.5, top, bx + 1.5, y1 - f), DARK)
            R(d, (px, (top + y1 - f) / 2 - 1.5, px + pw, (top + y1 - f) / 2 + 1.5), DARK)
    if sill:
        R(d, (x0 - 10, y1 + 5, x1 + 10, y1 + 14), SHADE)
        R(d, (x0 - 10, y1 + 14, x1 + 10, y1 + 18), (150, 148, 142))


def aircon(d, x, y, w=92, h=62):
    R(d, (x + 4, y + h, x + w - 4, y + h + 6), (120, 122, 126))  # bracket
    R(d, (x, y, x + w, y + h), (228, 230, 232))
    R(d, (x, y, x + w, y + 5), (244, 246, 246))
    cx, cy, r = x + w * 0.36, y + h / 2 + 1, h * 0.36
    d.ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS], fill=(92, 96, 102, 255))
    for k in range(4):
        rr = r * (1 - k * 0.22)
        d.ellipse([(cx - rr) * SS, (cy - rr) * SS, (cx + rr) * SS, (cy + rr) * SS], outline=(176, 180, 186, 255), width=SS)
    for k in range(5):
        yy = y + 12 + k * (h - 22) / 4
        R(d, (x + w * 0.72, yy, x + w - 8, yy + 3), (176, 180, 186))


def save(im, name):
    im = im.resize((S, S), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name + ".png"), optimize=True)
    print(name, im.size)


def apartment(rnd):
    """One room of a walk-up block: balcony door + window behind a steel railing, air-con, floor slab."""
    im, d = canvas(rnd)
    streaks(d, rnd, 30, 480, 20, 6)
    # sliding balcony door and a small window
    window(im, d, (52, 96, 286, 452), panes=2, sill=False)
    window(im, d, (338, 150, 462, 300), panes=1, louvre=True)
    aircon(d, 352, 356)
    # balcony: slab edge and railing in front of the door
    R(d, (0, 468, S, 512), SHADE)
    R(d, (0, 462, S, 470), (150, 148, 142))
    R(d, (14, 318, 498, 327), DARK)
    for x in range(20, 498, 17):
        R(d, (x, 327, x + 4, 464), DARK)
    R(d, (14, 458, 498, 464), DARK)
    # floor line at the top (the slab of the floor above)
    R(d, (0, 0, S, 12), SHADE)
    return im


def tower(rnd):
    """Curtain wall: mostly glass, aluminium mullions, an opaque spandrel band at each floor."""
    im = Image.new("RGBA", (S * SS, S * SS), (40, 44, 44, 0))
    d = ImageDraw.Draw(im)
    R(d, (0, 0, S, 118), (226, 228, 230))  # spandrel: tinted with the building colour
    R(d, (0, 112, S, 122), ALU)
    for i in range(4):
        x = i * S / 4
        R(d, (x - 5, 118, x + 5, S), ALU)
        R(d, (x + S / 8 - 2, 0, x + S / 8 + 2, 118), (206, 208, 212))
    R(d, (S - 5, 118, S, S), ALU)
    R(d, (0, 318, S, 326), ALU)
    R(d, (0, S - 6, S, S), ALU)
    return im


def town_upper(rnd):
    """Upper floor of one townhouse: two louvred windows with grilles, a ledge, an air-con."""
    im, d = canvas(rnd)
    streaks(d, rnd, 40, 470, 30, 5)
    window(im, d, (58, 112, 226, 356), panes=2, louvre=True, bars=True)
    window(im, d, (286, 112, 454, 356), panes=2, louvre=True, bars=True)
    aircon(d, 210, 404, 92, 58)
    R(d, (0, 486, S, 512), SHADE)  # ledge between floors
    R(d, (0, 480, S, 488), (150, 148, 142))
    R(d, (0, 0, 8, S), (214, 212, 206))  # party wall line
    return im


def town_ground(rnd):
    """Ground floor of one townhouse: folding steel gate over the car space, front door, transom."""
    im, d = canvas(rnd)
    # car space behind a folding gate
    R(d, (176, 96, 486, 512), (58, 58, 60))
    for x in range(176, 486, 12):
        R(d, (x, 96, x + 2.5, 512), (150, 154, 160))
    for y in range(120, 512, 44):
        for x in range(176, 486, 24):
            d.line([(x * SS, y * SS), ((x + 12) * SS, (y + 22) * SS), ((x + 24) * SS, y * SS)], fill=(170, 174, 180, 255), width=SS)
    R(d, (170, 88, 492, 98), (120, 122, 128))
    # front door with a glass panel
    R(d, (40, 150, 146, 512), (146, 104, 72))
    R(d, (48, 160, 138, 300), (128, 90, 62))
    hole(im, (58, 172, 128, 288))
    R(d, (48, 318, 138, 496), (128, 90, 62))
    R(d, (124, 330, 132, 350), (220, 200, 120))
    # transom strip of glass blocks above
    for i in range(6):
        hole(im, (40 + i * 76, 30, 40 + i * 76 + 60, 66))
    R(d, (0, 0, 8, S), (214, 212, 206))
    return im


def home(rnd):
    """Front of a detached house: door under a small canopy, a wide window with a grille, a vent."""
    im, d = canvas(rnd)
    streaks(d, rnd, 220, 480, 40, 4)
    # door
    R(d, (70, 150, 176, 512), (120, 84, 58))
    R(d, (80, 162, 166, 330), (104, 72, 50))
    R(d, (80, 346, 166, 498), (104, 72, 50))
    R(d, (152, 336, 160, 356), (220, 200, 120))
    R(d, (46, 126, 200, 142), (150, 148, 142))  # canopy shadow
    R(d, (40, 112, 206, 128), SHADE)
    # window
    window(im, d, (252, 170, 456, 372), panes=3, bars=True)
    # skirting
    R(d, (0, 482, 70, 512), (206, 204, 198))
    R(d, (176, 482, S, 512), (206, 204, 198))
    return im


def main():
    rnd = random.Random(21)
    save(apartment(rnd), "facade_apartment")
    save(tower(rnd), "facade_tower")
    save(town_upper(rnd), "facade_town_upper")
    save(town_ground(rnd), "facade_town_ground")
    save(home(rnd), "facade_home")


if __name__ == "__main__":
    main()
