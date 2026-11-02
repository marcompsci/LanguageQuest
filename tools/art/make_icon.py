"""Draws the Language Quest app icon (original pixel art) at 1024x1024."""
import sys
from PIL import Image, ImageDraw
out = sys.argv[1]
S = 64  # pixel grid
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
# Sky and hills
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=(int(120 + 80 * t), int(190 + 40 * t), 245))
d.ellipse([-20, 40, 40, 90], fill=(95, 175, 90))
d.ellipse([24, 44, 90, 96], fill=(124, 196, 106))
d.rectangle([0, 52, S, S], fill=(124, 196, 106))
# Path
d.polygon([(26, 64), (38, 64), (34, 52), (30, 52)], fill=(227, 197, 142))
# Luna (from PixelArt.bodyRows + long hair + yellow scarf), drawn 2x at (16,22)
body = ["................","................",".....SSSSSS.....","....SSSSSSSS....","....SSESSESS....","....SSSSSSSS....",
        ".....SSMMSS.....","......SSSS......","....OOOOOOOO....","...SOOOOOOOOS...","...SOOOOOOOOS...","....OOOOOOOO....",
        "....PPPPPPPP....","....PPP..PPP....","....PPP..PPP....","....KKK..KKK...."]
hair = ["................",".....HHHHHH.....","....HHHHHHHH....","...HH......HH...","...H........H...","...H........H...","...HH......HH...","...HH......HH..."]
col = {"S": (233,180,143),"E": (35,26,38),"M": (176,80,90),"O": (142,92,196),"P": (58,63,92),"K": (59,42,32),"H": (43,27,18),"Y": (242,194,48)}
def put(rows, ox, oy, k=2):
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in col: d.rectangle([ox + x*k, oy + y*k, ox + x*k + k - 1, oy + y*k + k - 1], fill=col[ch])
put(body, 4, 22); put(hair, 4, 22)
scarf = ["................"]*7 + ["....YYYYYYYY....","....YYYYYYYY....",".........YY.....",".........YY....."]
put(scarf, 4, 22)
# Speech bubble with "¡HOLA!" in a tiny pixel font
d.rounded_rectangle([34, 8, 61, 26], radius=4, fill=(255, 253, 245), outline=(43, 35, 64))
d.polygon([(38, 26), (44, 26), (36, 32)], fill=(255, 253, 245), outline=(43, 35, 64))
font = {"¡": ["#","."," #","#","#"], "H": ["#.#","#.#","###","#.#","#.#"], "O": ["###","#.#","#.#","#.#","###"],
        "L": ["#..","#..","#..","#..","###"], "A": [".#.","#.#","###","#.#","#.#"], "!": ["#","#","#",".","#"]}
font["¡"] = ["#", ".", "#", "#", "#"]
x = 37
for ch in "¡HOLA!":
    g = font[ch]
    for yy, row in enumerate(g):
        for xx, c in enumerate(row):
            if c == "#": d.point((x + xx, 14 + yy), fill=(31, 111, 178))
    x += len(g[0]) + 1
img = img.resize((1024, 1024), Image.NEAREST)
img.save(out)
print("wrote", out)
