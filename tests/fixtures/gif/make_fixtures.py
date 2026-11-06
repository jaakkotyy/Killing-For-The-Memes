"""Writes the GIF fixtures for tests/unit/test_gif_decoder.gd (all original, generated here).

Each <name>.gif comes with <name>_<i>.png: frame i fully composited, as Pillow decodes it,
so the GDScript decoder is checked against an independent implementation.

    python tests/fixtures/gif/make_fixtures.py
"""
import os
import random

from PIL import Image, ImageSequence

HERE = os.path.dirname(os.path.abspath(__file__))


def save_expected(name):
    path = os.path.join(HERE, name + ".gif")
    with Image.open(path) as gif:
        for i, frame in enumerate(ImageSequence.Iterator(gif)):
            frame.convert("RGBA").save(os.path.join(HERE, "%s_%d.png" % (name, i)))
    return path


def flags(path):
    """Interlace / local palette / disposal flags actually written, to prove what each
    fixture covers."""
    data = open(path, "rb").read()
    found = {"interlaced": False, "local_palette": False, "disposals": set(), "transparency": False, "rects": []}
    pos = 13 + (3 * (2 << (data[10] & 7)) if data[10] & 0x80 else 0)
    while pos < len(data):
        block = data[pos]
        if block == 0x21:
            label = data[pos + 1]
            if label == 0xF9:
                packed = data[pos + 3]
                found["disposals"].add((packed >> 2) & 7)
                found["transparency"] |= bool(packed & 1)
            pos += 2
            while data[pos]:
                pos += data[pos] + 1
            pos += 1
        elif block == 0x2C:
            packed = data[pos + 9]
            found["rects"].append(tuple(int.from_bytes(data[pos + 1 + 2 * i:pos + 3 + 2 * i], "little") for i in range(4)))
            found["interlaced"] |= bool(packed & 0x40)
            found["local_palette"] |= bool(packed & 0x80)
            pos += 10 + (3 * (2 << (packed & 7)) if packed & 0x80 else 0)
            pos += 1
            while data[pos]:
                pos += data[pos] + 1
            pos += 1
        else:
            break
    return found


def three_frames():
    frames = [Image.new("RGB", (8, 6), c) for c in ((255, 0, 0), (0, 255, 0), (0, 0, 255))]
    path = os.path.join(HERE, "three_frames.gif")
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=[100, 200, 50], loop=0)
    return save_expected("three_frames")


def noise():
    """256 colours, 64x48: 12-bit LZW codes and table resets. Interlaced. The second frame
    only changes a rectangle, so Pillow writes a cropped sub-frame we have to composite."""
    rng = random.Random(7)
    palette = [rng.randrange(256) for _ in range(768)]
    first = Image.new("P", (64, 48))
    first.putpalette(palette)
    first.putdata([rng.randrange(256) for _ in range(64 * 48)])
    second = first.copy()
    for y in range(10, 30):
        for x in range(20, 44):
            second.putpixel((x, y), rng.randrange(256))
    path = os.path.join(HERE, "noise.gif")
    first.save(path, save_all=True, append_images=[second], duration=[80, 80], interlace=True, optimize=False)
    return save_expected("noise")


def interlaced():
    """A single interlaced frame (Pillow only interlaces still images)."""
    rng = random.Random(3)
    image = Image.new("P", (37, 29))
    image.putpalette([rng.randrange(256) for _ in range(768)])
    image.putdata([(x * 7 + y * 13) % 256 for y in range(29) for x in range(37)])
    path = os.path.join(HERE, "interlaced.gif")
    image.save(path, interlace=True)
    return save_expected("interlaced")


def transparent():
    """Disposal 2 (restore to background) with transparent pixels."""
    a = Image.new("RGBA", (20, 20), (0, 0, 0, 0))
    a.paste((255, 0, 0, 255), (0, 0, 10, 20))
    b = Image.new("RGBA", (20, 20), (0, 0, 0, 0))
    b.paste((0, 0, 255, 255), (10, 0, 20, 20))
    path = os.path.join(HERE, "transparent.gif")
    a.save(path, save_all=True, append_images=[b], duration=[100, 100], disposal=2, loop=0)
    return save_expected("transparent")


def local_palettes():
    """Frames with their own colour tables."""
    frames = []
    for base in ((200, 30, 30), (30, 200, 30)):
        frame = Image.new("P", (16, 4))
        frame.putpalette([base[0], base[1], base[2], 255 - base[0], 255 - base[1], 255 - base[2]] + [0] * 762)
        frame.putdata([(x // 4) % 2 for x in range(16)] * 4)
        frames.append(frame)
    path = os.path.join(HERE, "local_palettes.gif")
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=[100, 100], optimize=False, interlace=False)
    return save_expected("local_palettes")


if __name__ == "__main__":
    for make in (three_frames, noise, interlaced, transparent, local_palettes):
        path = make()
        print(os.path.basename(path), os.path.getsize(path), "bytes", flags(path))
