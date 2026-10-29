from PIL import Image, ImageDraw

S = 4096
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# rounded-square background with vertical gradient
grad = Image.new("RGB", (1, S))
top = (74, 225, 130)
bot = (10, 150, 96)
for y in range(S):
    t = y / (S - 1)
    grad.putpixel((0, y), tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
grad = grad.resize((S, S))

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.225), fill=255)
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)
cx = cy = S / 2

# gauge ring (300 degrees, starting bottom-left)
R = S * 0.315
w = int(S * 0.075)
box = [cx - R, cy - R, cx + R, cy + R]
start, end = 120, 420
d.arc(box, start=start, end=end, fill="white", width=w)

# round caps
import math
for ang in (start, end):
    a = math.radians(ang)
    px, py = cx + R * math.cos(a), cy + R * math.sin(a)
    d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill="white")

# checkmark
lw = int(S * 0.062)
pts = [(cx - R * 0.42, cy + R * 0.02), (cx - R * 0.10, cy + R * 0.33), (cx + R * 0.45, cy - R * 0.32)]
d.line(pts, fill="white", width=lw, joint="curve")
for p in (pts[0], pts[-1]):
    d.ellipse([p[0] - lw / 2, p[1] - lw / 2, p[0] + lw / 2, p[1] + lw / 2], fill="white")

img = img.resize((1024, 1024), Image.LANCZOS)
img.save("icon_1024.png")
print("icon written")
