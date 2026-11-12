"""Erzeugt Resources/AppIcon-1024.png (Polaroid auf dunklem Grund). Benötigt Pillow."""
from PIL import Image, ImageDraw, ImageFilter
import math, os

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# macOS-Icon-Grundform (abgerundetes Quadrat mit Rand)
m = 100
bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(bg)
d.rounded_rectangle([m, m, S - m, S - m], radius=185, fill=(28, 28, 30, 255))
img.alpha_composite(bg)

# Polaroid-Karte
cw, ch = 520, 640
card = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
cd = ImageDraw.Draw(card)
cd.rounded_rectangle([0, 0, cw - 1, ch - 1], radius=18, fill=(244, 243, 239, 255))
pad = 34
pw, ph = cw - 2 * pad, int((cw - 2 * pad) * 1.0)
photo = Image.new("RGBA", (pw, ph), (12, 12, 16, 255))
# weiches Licht im Foto
glow = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([pw * 0.18, ph * 0.12, pw * 0.82, ph * 0.86], fill=(150, 140, 160, 200))
glow = glow.filter(ImageFilter.GaussianBlur(70))
photo.alpha_composite(glow)
# roter Akzent
pd = ImageDraw.Draw(photo)
pd.ellipse([pw * 0.44, ph * 0.56, pw * 0.56, ph * 0.61], fill=(214, 40, 48, 255))
card.alpha_composite(photo, (pad, pad))
# Herz unten links
hx, hy, hs = pad + 10, pad + ph + 52, 46
def heart(draw, x, y, s, fill):
    pts = []
    for t in range(0, 360, 3):
        r = math.radians(t)
        px = 16 * math.sin(r) ** 3
        py = 13 * math.cos(r) - 5 * math.cos(2 * r) - 2 * math.cos(3 * r) - math.cos(4 * r)
        pts.append((x + px * s / 32 + s / 2, y - py * s / 32 + s / 2))
    draw.polygon(pts, fill=fill)
heart(cd, hx, hy, hs, (214, 40, 48, 255))
# Schriftlinie (Platzhalter für Text)
cd.rounded_rectangle([cw - pad - 170, pad + ph + 64, cw - pad - 10, pad + ph + 84], radius=10, fill=(40, 40, 40, 230))

card = card.rotate(-6, resample=Image.BICUBIC, expand=True)
shadow = Image.new("RGBA", card.size, (0, 0, 0, 0))
shadow.paste((0, 0, 0, 150), mask=card.split()[3])
shadow = shadow.filter(ImageFilter.GaussianBlur(22))
ox = (S - card.size[0]) // 2
oy = (S - card.size[1]) // 2 + 6
img.alpha_composite(shadow, (ox + 6, oy + 22))
img.alpha_composite(card, (ox, oy))

out = os.path.join(os.path.dirname(__file__), "..", "Resources", "AppIcon-1024.png")
img.save(out)
print("wrote", out)
