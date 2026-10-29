from PIL import Image, ImageDraw

W, H = 660, 420
img = Image.new("RGB", (W, H), "#f4f5f7")
d = ImageDraw.Draw(img)

# soft vertical gradient
for y in range(H):
    t = y / (H - 1)
    c = (int(246 - 6 * t), int(247 - 6 * t), int(250 - 6 * t))
    d.line([(0, y), (W, y)], fill=c)

# arrow between the two icon slots
y0 = 232
x0, x1 = 262, 400
d.line([(x0, y0), (x1 - 18, y0)], fill="#c9ccd2", width=7)
d.polygon([(x1, y0), (x1 - 24, y0 - 15), (x1 - 24, y0 + 15)], fill="#c9ccd2")

# subtle title
img.save("src/dmg-background.png")
print("bg", img.size)
