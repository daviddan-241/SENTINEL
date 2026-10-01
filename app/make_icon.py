from PIL import Image, ImageDraw, ImageFilter
import math

S = 512
img = Image.new("RGB", (S, S))
px = img.load()
# diagonal gradient violet -> cyan -> pink tip
c1 = (139, 92, 246)
c2 = (34, 211, 238)
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S - 2)
        t = min(1.0, max(0.0, t * 1.15))
        px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))

d = ImageDraw.Draw(img, "RGBA")

# soft light blob top-left, dark vignette
blob = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(blob)
bd.ellipse([-140, -170, 300, 230], fill=(255, 255, 255, 70))
blob = blob.filter(ImageFilter.GaussianBlur(70))
img = Image.alpha_composite(img.convert("RGBA"), blob).convert("RGB")
d = ImageDraw.Draw(img, "RGBA")

# dark rounded card
pad = 84
d.rounded_rectangle([pad, pad, S - pad, S - pad], radius=72, fill=(11, 12, 20, 235), outline=(255, 255, 255, 46), width=3)

# vault keyhole
cx, cy = S / 2, S / 2 - 16
d.ellipse([cx - 44, cy - 44, cx + 44, cy + 44], fill=(255, 255, 255, 250))
d.polygon([(cx, cy + 26), (cx - 20, cy + 96), (cx + 20, cy + 96)], fill=(255, 255, 255, 250))
# stack of word-bars underneath
for i, w in enumerate([150, 106, 62]):
    y = cy + 128 + i * 20
    d.rounded_rectangle([cx - w / 2, y, cx + w / 2, y + 9], radius=5, fill=(255, 255, 255, 120 - i * 25))

img = img.filter(ImageFilter.SMOOTH)
img.save("/home/user/app/icon.png")
img.resize((180, 180), Image.LANCZOS).save("/home/user/app/icon180.png")
print("icon written", img.size)
