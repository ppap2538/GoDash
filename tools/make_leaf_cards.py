"""Draw the leaf-card textures for the vegetation library (our own artwork, no third-party content).

  python -I tools/make_leaf_cards.py

Writes assets/textures/veg/<name>.png (RGBA, 1024 px) and assets/textures/veg/cards.json, which lists
the UV rectangle of every card. tools/blender_trees.py puts the cards on the trees: each card is a
small leafy branch (or a palm frond, a banana leaf ...) with a transparent background.
Everything is drawn at twice the size and scaled down so the leaf edges are smooth.
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "veg")
SS = 2  # supersampling
SIZE = 1024


def jitter(c, rnd, dh=10, dv=0.14):
    """Small natural variation of a leaf colour (a little yellower / bluer, lighter / darker)."""
    r, g, b = c
    k = 1 + rnd.uniform(-dv, dv)
    t = rnd.uniform(-dh, dh)
    return (max(0, min(255, int((r + t) * k))), max(0, min(255, int(g * k))), max(0, min(255, int((b - t * 0.5) * k))))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def leaf_poly(x, y, ang, length, width, tip=1.0, n=10):
    """Outline of a leaf from its base (x, y) pointing along ang. tip > 1 = long drawn-out point."""
    ca, sa = math.cos(ang), math.sin(ang)
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        w = width * (math.sin(math.pi * t ** (0.75 / tip)) ** 0.9) * 0.5
        px, py = x + ca * length * t, y + sa * length * t
        left.append((px - sa * w, py + ca * w))
        right.append((px + sa * w, py - ca * w))
    return left, right


def draw_leaf(d, x, y, ang, length, width, col, rnd, tip=1.0, veins=True):
    left, right = leaf_poly(x, y, ang, length, width, tip)
    spine = [((a[0] + b[0]) / 2, (a[1] + b[1]) / 2) for a, b in zip(left, right)]
    d.polygon(left + right[::-1], fill=col + (255,))
    # one half a little darker: the leaf folds along its midrib
    d.polygon(spine + right[::-1], fill=shade(col, 0.86) + (255,))
    if veins and length > 40 * SS:
        vc = shade(col, 1.18) + (255,)
        for i in range(2, len(spine) - 1, 2):
            d.line([spine[i], left[min(i + 1, len(left) - 1)]], fill=vc, width=max(1, SS // 2))
            d.line([spine[i], right[min(i + 1, len(right) - 1)]], fill=shade(col, 1.0) + (255,), width=max(1, SS // 2))
    d.line(spine, fill=shade(col, 1.25) + (255,), width=max(1, int(width * 0.05)))


def stem(d, pts, w0, w1, col):
    for i in range(len(pts) - 1):
        t = i / max(1, len(pts) - 2)
        d.line([pts[i], pts[i + 1]], fill=col + (255,), width=max(1, int(w0 + (w1 - w0) * t)))


def curve(x0, y0, ang, length, bend, n=12):
    pts = [(x0, y0)]
    a = ang
    for _ in range(n):
        a += bend / n
        x0 += math.cos(a) * length / n
        y0 += math.sin(a) * length / n
        pts.append((x0, y0))
    return pts, a


def card_broadleaf(d, box, rnd, col, leaf_len=0.24, leaf_w=0.085, tip=1.0, flowers=None):
    """A leafy branch growing up from the bottom centre of the card."""
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    bark = (96, 78, 58)
    main, _ = curve(x0 + W * 0.5, y1 - H * 0.02, -math.pi / 2 + rnd.uniform(-0.12, 0.12), H * 0.72, rnd.uniform(-0.35, 0.35))
    twigs = [main]
    for i in (3, 5, 7, 9):
        side = 1 if (i // 2) % 2 else -1
        bx, by = main[i]
        tw, _ = curve(bx, by, -math.pi / 2 + side * rnd.uniform(0.6, 1.0), H * rnd.uniform(0.2, 0.34), side * rnd.uniform(-0.5, 0.2), 8)
        twigs.append(tw)
    for tw in twigs:
        stem(d, tw, W * 0.016, W * 0.005, bark)
    leaves = []
    for tw in twigs:
        for i in range(1, len(tw)):
            px, py = tw[i]
            base = math.atan2(tw[i][1] - tw[i - 1][1], tw[i][0] - tw[i - 1][0])
            for side in (-1, 1):
                if rnd.random() < 0.88:
                    leaves.append((px, py, base + side * rnd.uniform(0.5, 1.15), H * leaf_len * rnd.uniform(0.7, 1.1)))
        ex, ey = tw[-1]
        base = math.atan2(tw[-1][1] - tw[-2][1], tw[-1][0] - tw[-2][0])
        leaves.append((ex, ey, base + rnd.uniform(-0.2, 0.2), H * leaf_len))
    rnd.shuffle(leaves)
    for i, (px, py, a, L) in enumerate(leaves):
        c = jitter(col, rnd)
        if i < len(leaves) // 3:
            c = shade(c, 0.78)  # leaves behind are in shade
        draw_leaf(d, px, py, a, L, L * leaf_w / leaf_len, c, rnd, tip)
    if flowers:
        for tw in twigs[1:]:
            fx, fy = tw[-1]
            flowers(d, fx, fy, W, rnd)


def card_pinnate(d, box, rnd, col, fine=True, racemes=0):
    """Feathery compound leaves: rain tree (fine leaflets) or golden shower (larger leaflets, flower racemes)."""
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    bark = (104, 86, 64)
    main, _ = curve(x0 + W * 0.5, y1 - H * 0.02, -math.pi / 2 + rnd.uniform(-0.15, 0.15), H * 0.5, rnd.uniform(-0.3, 0.3), 8)
    stem(d, main, W * 0.014, W * 0.006, bark)
    fronds = []
    for i in range(2, len(main)):
        for side in (-1, 1):
            if rnd.random() < 0.9:
                a = -math.pi / 2 + side * rnd.uniform(0.35, 1.25)
                fronds.append((main[i][0], main[i][1], a, H * rnd.uniform(0.3, 0.46), side))
    fronds.append((main[-1][0], main[-1][1], -math.pi / 2 + rnd.uniform(-0.2, 0.2), H * 0.44, 1))
    rnd.shuffle(fronds)
    for fi, (px, py, a, L, side) in enumerate(fronds):
        rachis, _ = curve(px, py, a, L, side * rnd.uniform(-0.1, 0.5), 14 if fine else 7)
        back = fi < len(fronds) // 3
        stem(d, rachis, W * 0.006, W * 0.003, shade(col, 0.7))
        for i in range(1, len(rachis)):
            base = math.atan2(rachis[i][1] - rachis[i - 1][1], rachis[i][0] - rachis[i - 1][0])
            t = i / len(rachis)
            ll = (W * 0.045 if fine else W * 0.085) * (1 - 0.35 * abs(t - 0.45) * 2)
            for s2 in (-1, 1):
                c = jitter(col, rnd)
                if back:
                    c = shade(c, 0.78)
                draw_leaf(d, rachis[i][0], rachis[i][1], base + s2 * rnd.uniform(1.0, 1.35), ll, ll * (0.42 if fine else 0.4), c, rnd, veins=not fine)
    for _ in range(racemes):
        # hanging chain of yellow flowers (ดอกคูน)
        fx = x0 + W * rnd.uniform(0.2, 0.8)
        fy = y0 + H * rnd.uniform(0.25, 0.45)
        chain, _ = curve(fx, fy, math.pi / 2 + rnd.uniform(-0.25, 0.25), H * rnd.uniform(0.3, 0.42), rnd.uniform(-0.3, 0.3), 16)
        stem(d, chain, W * 0.004, W * 0.002, (120, 130, 60))
        for i, (cx, cy) in enumerate(chain):
            n = 3 if i < len(chain) - 3 else 2
            for _k in range(n):
                r = W * rnd.uniform(0.018, 0.03) * (1 - i / len(chain) * 0.5)
                ox, oy = rnd.uniform(-1, 1) * W * 0.035, rnd.uniform(-1, 1) * W * 0.012
                yc = (rnd.randint(238, 252), rnd.randint(196, 216), rnd.randint(20, 60))
                for p in range(5):
                    pa = p * math.tau / 5 + rnd.random()
                    d.ellipse([cx + ox + math.cos(pa) * r * 0.6 - r * 0.6, cy + oy + math.sin(pa) * r * 0.6 - r * 0.6,
                               cx + ox + math.cos(pa) * r * 0.6 + r * 0.6, cy + oy + math.sin(pa) * r * 0.6 + r * 0.6], fill=yc + (255,))
                d.ellipse([cx + ox - r * 0.3, cy + oy - r * 0.3, cx + ox + r * 0.3, cy + oy + r * 0.3], fill=(214, 150, 30, 255))


def card_frond(d, box, rnd, col):
    """Coconut palm frond lying along the card: base on the left, tip on the right."""
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    cy = (y0 + y1) / 2
    rachis, _ = curve(x0 + W * 0.01, cy, rnd.uniform(-0.03, 0.03), W * 0.97, rnd.uniform(-0.05, 0.05), 60)
    for i in range(2, len(rachis)):
        t = i / len(rachis)
        L = H * 0.52 * (0.35 + 0.65 * math.sin(math.pi * min(1, t * 1.15) ** 0.6)) * rnd.uniform(0.86, 1.05)
        base = math.atan2(rachis[i][1] - rachis[i - 1][1], rachis[i][0] - rachis[i - 1][0])
        for side in (-1, 1):
            if rnd.random() < 0.94:
                a = base + side * (1.2 - 0.55 * t) + rnd.uniform(-0.08, 0.08)
                c = jitter(col, rnd, 8, 0.12)
                draw_leaf(d, rachis[i][0], rachis[i][1], a, L, max(3 * SS, H * 0.045), c, rnd, tip=1.6, veins=False)
    stem(d, rachis, H * 0.05, H * 0.012, (150, 150, 84))


def card_banana(d, box, rnd, col):
    """One banana leaf: a broad paddle with a pale midrib and a few wind tears."""
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    cy = (y0 + y1) / 2
    n = 40
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        w = H * 0.46 * (math.sin(math.pi * (0.06 + 0.94 * t) ** 0.7) ** 0.7)
        x = x0 + W * (0.08 + 0.9 * t)
        tear = 0.82 if (i % rnd.randint(5, 9) == 0 and 0.15 < t < 0.9) else 1.0
        top.append((x, cy - w * tear))
        bot.append((x, cy + w * (1.0 if tear == 1.0 else rnd.uniform(0.8, 1.0))))
    d.polygon(top + bot[::-1], fill=col + (255,))
    d.polygon([(x0 + W * 0.08, cy)] + bot[::-1] + [(x0 + W * 0.98, cy)], fill=shade(col, 0.88) + (255,))
    for i in range(1, n, 1):
        x = top[i][0]
        d.line([(x, cy), (x + W * 0.012, top[i][1])], fill=shade(col, 1.1) + (255,), width=SS)
        d.line([(x, cy), (x + W * 0.012, bot[i][1])], fill=shade(col, 0.97) + (255,), width=SS)
    d.line([(x0, cy), (x0 + W * 0.98, cy)], fill=(196, 204, 130, 255), width=max(2, int(H * 0.035)))


def frangipani_flowers(d, fx, fy, W, rnd):
    for _ in range(rnd.randint(3, 5)):
        cx, cy = fx + rnd.uniform(-1, 1) * W * 0.06, fy + rnd.uniform(-1, 0.3) * W * 0.06
        r = W * rnd.uniform(0.03, 0.042)
        for p in range(5):
            pa = p * math.tau / 5 + rnd.random() * 0.4
            d.ellipse([cx + math.cos(pa) * r * 0.75 - r * 0.62, cy + math.sin(pa) * r * 0.75 - r * 0.62,
                       cx + math.cos(pa) * r * 0.75 + r * 0.62, cy + math.sin(pa) * r * 0.75 + r * 0.62], fill=(250, 248, 240, 255))
        d.ellipse([cx - r * 0.5, cy - r * 0.5, cx + r * 0.5, cy + r * 0.5], fill=(246, 206, 70, 255))


def bougainvillea_flowers(d, fx, fy, W, rnd):
    for _ in range(rnd.randint(10, 16)):
        cx, cy = fx + rnd.uniform(-1, 1) * W * 0.12, fy + rnd.uniform(-1, 1) * W * 0.12
        r = W * rnd.uniform(0.02, 0.034)
        c = (rnd.randint(206, 236), rnd.randint(30, 70), rnd.randint(120, 160))
        for p in range(3):
            pa = p * math.tau / 3 + rnd.random()
            draw_leaf(d, cx, cy, pa, r * 2.2, r * 1.5, c, rnd, veins=False)


def card_grass(d, box, rnd, col):
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    for _ in range(90):
        bx = x0 + W * rnd.uniform(0.12, 0.88)
        a = -math.pi / 2 + rnd.uniform(-0.55, 0.55)
        L = H * rnd.uniform(0.35, 0.9)
        blade, _ = curve(bx, y1 - H * 0.01, a, L, rnd.uniform(-0.7, 0.7), 8)
        c = jitter(col, rnd, 14, 0.2)
        stem(d, blade, W * 0.018, W * 0.003, c)


def card_whorl(d, box, rnd, col, flowers=None):
    """Frangipani: thick bare twigs, long leaves in a whorl at each tip."""
    x0, y0, x1, y1 = box
    W, H = x1 - x0, y1 - y0
    bark = (150, 140, 124)
    main, _ = curve(x0 + W * 0.5, y1 - H * 0.02, -math.pi / 2 + rnd.uniform(-0.1, 0.1), H * 0.42, rnd.uniform(-0.3, 0.3), 6)
    tips = []
    stem(d, main, W * 0.035, W * 0.026, bark)
    for side in (-1, 1):
        tw, _ = curve(main[-1][0], main[-1][1], -math.pi / 2 + side * rnd.uniform(0.45, 0.8), H * rnd.uniform(0.16, 0.24), side * -0.3, 5)
        stem(d, tw, W * 0.026, W * 0.02, bark)
        tips.append(tw[-1])
    for tx, ty in tips:
        k = rnd.randint(9, 12)
        order = list(range(k))
        rnd.shuffle(order)
        for i in order:
            a = -math.pi / 2 + (i / (k - 1) - 0.5) * 3.6 + rnd.uniform(-0.1, 0.1)
            L = H * rnd.uniform(0.26, 0.34)
            draw_leaf(d, tx, ty, a, L, L * 0.3, jitter(col, rnd), rnd, tip=0.8)
        if flowers:
            flowers(d, tx, ty - H * 0.03, W, rnd)


def new_canvas(bg):
    return Image.new("RGBA", (SIZE * SS, SIZE * SS), bg + (0,))


def grid(nx, ny):
    cw, ch = SIZE * SS / nx, SIZE * SS / ny
    return [(i * cw, j * ch, (i + 1) * cw, (j + 1) * ch) for j in range(ny) for i in range(nx)]


def uv(box):
    # glTF / Roblox UV: (0,0) = top-left of the image
    s = SIZE * SS
    return [round(box[0] / s, 4), round(box[1] / s, 4), round(box[2] / s, 4), round(box[3] / s, 4)]


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {}

    def save(name, im, boxes, kinds):
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
        im.save(os.path.join(OUT, name + ".png"), optimize=True)
        manifest[name] = [{"uv": uv(b), "kind": k} for b, k in zip(boxes, kinds)]
        print(name, im.size, len(boxes), "cards")

    G_DEEP, G_MANGO, G_RAIN, G_GOLD = (58, 108, 46), (50, 96, 44), (86, 132, 56), (92, 140, 60)
    G_PALM, G_BANANA, G_FRANGI, G_HEDGE, G_GRASS = (74, 120, 52), (104, 152, 62), (72, 120, 56), (62, 112, 50), (118, 142, 70)

    # broadleaf shade tree / mango
    rnd = random.Random(11)
    im = new_canvas(G_DEEP); d = ImageDraw.Draw(im); boxes = grid(2, 2)
    card_broadleaf(d, boxes[0], rnd, G_DEEP)
    card_broadleaf(d, boxes[1], rnd, G_DEEP)
    card_broadleaf(d, boxes[2], rnd, G_MANGO, leaf_len=0.3, leaf_w=0.07, tip=1.4)
    card_broadleaf(d, boxes[3], rnd, G_MANGO, leaf_len=0.3, leaf_w=0.07, tip=1.4)
    save("veg_broadleaf", im, boxes, ["broad", "broad", "mango", "mango"])

    rnd = random.Random(12)
    im = new_canvas(G_RAIN); d = ImageDraw.Draw(im); boxes = grid(2, 2)
    for b in boxes:
        card_pinnate(d, b, rnd, G_RAIN, fine=True)
    save("veg_raintree", im, boxes, ["fine"] * 4)

    rnd = random.Random(13)
    im = new_canvas(G_GOLD); d = ImageDraw.Draw(im); boxes = grid(2, 2)
    card_pinnate(d, boxes[0], rnd, G_GOLD, fine=False)
    card_pinnate(d, boxes[1], rnd, G_GOLD, fine=False)
    card_pinnate(d, boxes[2], rnd, G_GOLD, fine=False, racemes=4)
    card_pinnate(d, boxes[3], rnd, G_GOLD, fine=False, racemes=5)
    save("veg_goldenshower", im, boxes, ["leaf", "leaf", "flower", "flower"])

    rnd = random.Random(14)
    im = new_canvas(G_PALM); d = ImageDraw.Draw(im); boxes = grid(1, 4)
    for b in boxes[:3]:
        card_frond(d, b, rnd, G_PALM)
    card_banana(d, boxes[3], rnd, G_BANANA)
    save("veg_palm", im, boxes, ["frond", "frond", "frond", "banana"])

    rnd = random.Random(15)
    im = new_canvas(G_FRANGI); d = ImageDraw.Draw(im); boxes = grid(2, 2)
    card_whorl(d, boxes[0], rnd, G_FRANGI)
    card_whorl(d, boxes[1], rnd, G_FRANGI, flowers=frangipani_flowers)
    card_whorl(d, boxes[2], rnd, G_FRANGI, flowers=frangipani_flowers)
    card_whorl(d, boxes[3], rnd, G_FRANGI)
    save("veg_frangipani", im, boxes, ["leaf", "flower", "flower", "leaf"])

    rnd = random.Random(16)
    im = new_canvas(G_HEDGE); d = ImageDraw.Draw(im); boxes = grid(2, 2)
    card_broadleaf(d, boxes[0], rnd, G_HEDGE, leaf_len=0.17, leaf_w=0.075)
    card_broadleaf(d, boxes[1], rnd, G_HEDGE, leaf_len=0.17, leaf_w=0.075, flowers=bougainvillea_flowers)
    card_broadleaf(d, boxes[2], rnd, G_HEDGE, leaf_len=0.17, leaf_w=0.075, flowers=bougainvillea_flowers)
    card_grass(d, boxes[3], rnd, G_GRASS)
    save("veg_shrub", im, boxes, ["hedge", "bougainvillea", "bougainvillea", "grass"])

    with open(os.path.join(OUT, "cards.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=1)


if __name__ == "__main__":
    main()
