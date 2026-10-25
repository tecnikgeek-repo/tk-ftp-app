"""Icone di tk-ftp nello stile delle app TK: quadrato navy, cartella bianca, bollino rame con le frecce su/giù.
Uso: python tools/genera_icona.py  (serve Pillow) -> assets/icona.png e assets/icona-adattiva.png,
poi: dart run flutter_launcher_icons"""
import os
from PIL import Image, ImageDraw

QUI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAVY, NAVY2, RAME, RAME_SCURO = (15, 23, 42), (30, 41, 59), (227, 154, 46), (185, 116, 26)
G = 4096  # si disegna grande e si rimpicciolisce: bordi lisci


def sfondo(img):
    lato = img.size[0]
    grad = Image.new("RGB", (lato, lato))
    gd = ImageDraw.Draw(grad)
    for i in range(lato):
        t = i / lato
        gd.line([(0, i), (lato, i)], fill=tuple(int(NAVY2[k] + (NAVY[k] - NAVY2[k]) * t) for k in range(3)))
    maschera = Image.new("L", (lato, lato), 0)
    ImageDraw.Draw(maschera).rounded_rectangle([0, 0, lato - 1, lato - 1], radius=int(lato * .24), fill=255)
    img.paste(grad, (0, 0), maschera)


def simbolo(img, x0, y0, s):
    d = ImageDraw.Draw(img)
    # cartella: linguetta + corpo
    d.rounded_rectangle([x0 + s * .06, y0 + s * .16, x0 + s * .40, y0 + s * .42], radius=s * .05, fill="white")
    d.rounded_rectangle([x0 + s * .06, y0 + s * .24, x0 + s * .80, y0 + s * .76], radius=s * .07, fill="white")
    # bollino rame
    cx, cy, r = x0 + s * .76, y0 + s * .74, s * .22
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=RAME)
    w = s * .035
    # freccia su (sinistra) e giù (destra)
    for dx, su in ((-.07, True), (.07, False)):
        x = cx + s * dx
        alto, basso = cy - s * .12, cy + s * .12
        d.line([(x, alto), (x, basso)], fill="white", width=int(w))
        punta = alto if su else basso
        verso = 1 if su else -1
        d.polygon([(x, punta - verso * w * .6), (x - s * .06, punta + verso * s * .07),
                   (x + s * .06, punta + verso * s * .07)], fill="white")


img = Image.new("RGBA", (G, G), (0, 0, 0, 0))
sfondo(img)
simbolo(img, G * .14, G * .12, G * .76)
img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(QUI, "assets", "icona.png"))

# adattiva: il fondo navy lo mette Android, il simbolo sta nella zona sicura centrale (~62%)
ad = Image.new("RGBA", (G, G), (0, 0, 0, 0))
simbolo(ad, G * .19, G * .17, G * .62)
ad.resize((1024, 1024), Image.LANCZOS).save(os.path.join(QUI, "assets", "icona-adattiva.png"))
print("icone create")
