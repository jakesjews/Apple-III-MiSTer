#!/usr/bin/env python3
"""Check four-dot pixel widths in a native 560x192 MiSTer 140-mode capture."""
import argparse

from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("capture", help="PNG from Confidence Video Test 7 (140x192 page 1)")
args = parser.parse_args()
with Image.open(args.capture) as source:
    frame = source.convert("RGB")
if frame.size != (560, 192):
    parser.error(f"expected a native 560x192 capture, got {frame.size}")
if len(set(frame.get_flattened_data())) < 3:
    parser.error("capture must contain the rendered color diagnostic, not a blank screen")
pixels = frame.load()
unequal = sum(
    any(pixels[x + dot, y] != pixels[x, y] for dot in range(1, 4))
    for y in range(192)
    for x in range(0, 560, 4)
)
print(f"{args.capture}: {unequal}/26880 four-dot pixel groups have inconsistent colors")
raise SystemExit(bool(unequal))
