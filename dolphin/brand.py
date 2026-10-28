"""Apply Dolphin Connect branding to the working tree (run in CI before building; not committed).

Usage: python dolphin/brand.py   (from the repository root; needs Pillow)
"""
import base64
import io
import pathlib
import re
import sys

from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARK = ROOT / "dolphin" / "brand" / "dolphin-mark.png"
# The owner's app icon (2026-10-28): the mark on a rounded light tile, 1024 x 1024. Every icon and small PNG comes from it.
ICON = ROOT / "dolphin" / "brand" / "dolphin-connect-icon.png"
# Every size Windows asks for (taskbar 16-24 at 100-150 % scaling, Start 32-48, Explorer up to 256), so it never
# stretches a neighbour size. Each is rendered on its own from the 1024 px source.
ICO_SIZES = [(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)]
# At this size and below the tile and the thin dolphin line eat the pixels: use the mark alone, cropped tight.
TIGHT_MAX = 32
ICO_TARGETS = ["res/icon.ico", "res/tray-icon.ico", "flutter/windows/runner/resources/app_icon.ico"]
PNG_TARGETS = ["res/icon.png", "res/32x32.png", "res/64x64.png", "res/128x128.png", "res/128x128@2x.png"]
SVG_TARGETS = ["flutter/assets/icon.svg"]

RC_VALUES = {
    "CompanyName": "Dolphin",
    "FileDescription": "Dolphin Connect",
    "InternalName": "DolphinConnect",
    "OriginalFilename": "DolphinConnect.exe",
    "ProductName": "Dolphin Connect",
    # AGPL: keeps the upstream authors' copyright notice; the upstream product name is not shown (own brand).
    "LegalCopyright": "\u00a9 Dolphin \u00b7 portions \u00a9 Purslane Tech Pte. Ltd. \u00b7 AGPL-3.0",
}


def brand_rc(text):
    for field, value in RC_VALUES.items():
        pattern = re.compile(r'(VALUE "' + field + r'", )"[^"]*"')
        text, count = pattern.subn(lambda m: m.group(1) + '"' + value + '"', text)
        if count != 1:
            raise ValueError(f"Runner.rc: expected one {field} value, found {count}")
    return text


WINRES_VALUES = {field: RC_VALUES[field] for field in ("ProductName", "FileDescription", "OriginalFilename", "LegalCopyright")}


def brand_winres(text):
    """Cargo.toml [package.metadata.winres]: the exe properties of the Sciter (x86) build."""
    for field, value in WINRES_VALUES.items():
        pattern = re.compile(r"^(" + field + r' = )"[^"\n]*"$', re.M)
        text, count = pattern.subn(lambda m: m.group(1) + '"' + value + '"', text)
        if count != 1:
            raise ValueError(f"Cargo.toml: expected one winres {field}, found {count}")
    return text


def _square(mark, size):
    side = max(mark.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
    return canvas.resize(size, Image.LANCZOS)


def write_png(mark, path):
    with Image.open(path) as existing:
        size = existing.size
    _square(mark, size).save(path, format="PNG")


def tight(icon):
    """The blue mark without the light tile: crop to the saturated pixels, with a small margin."""
    rgb = icon.convert("RGB")
    sat = rgb.convert("HSV").split()[1].point(lambda v: 255 if v > 90 else 0)
    box = sat.getbbox()
    if not box:
        return icon
    pad = max(box[2] - box[0], box[3] - box[1]) // 24
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(icon.width, box[2] + pad), min(icon.height, box[3] + pad))
    mark = icon.crop(box)
    # Keep only the mark: the tile's light pixels become transparent, so the small icon sits on any taskbar colour.
    # Closing (grow, then shrink) fills the white dolphin line inside the blue disc, so it stays white, not a hole.
    k = max(3, (box[2] - box[0]) // 60) | 1
    alpha = sat.crop(box).filter(ImageFilter.MaxFilter(k)).filter(ImageFilter.MinFilter(k)).filter(ImageFilter.GaussianBlur(0.6))
    return Image.merge("RGBA", (*mark.convert("RGB").split(), alpha))


def render(icon, size, tight_icon=None):
    """One icon size from the large source: LANCZOS, then a light sharpen where detail would go soft."""
    source = tight_icon if (tight_icon is not None and size[0] <= TIGHT_MAX) else icon
    img = _square(source, size)
    if size[0] <= 48:
        img = img.filter(ImageFilter.UnsharpMask(radius=0.6, percent=80, threshold=2))
    return img


def write_ico(icon, path, tray=False):
    """Every size rendered on its own (Pillow would otherwise shrink one 256 px picture). The tray icon is the mark
    alone at every size: it sits on the taskbar's own colour, never on a tile."""
    small = tight(icon)
    frames = [render(small if tray else icon, s, small) for s in ICO_SIZES]
    frames[-1].save(path, format="ICO", sizes=ICO_SIZES, append_images=frames[:-1])


def svg_with_png(mark):
    buf = io.BytesIO()
    _square(mark, (256, 256)).save(buf, format="PNG")
    data = base64.b64encode(buf.getvalue()).decode("ascii")
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">'
            f'<image width="256" height="256" href="data:image/png;base64,{data}"/></svg>\n')


UI_ICON = re.compile(r'"data:image/png;base64,[A-Za-z0-9+/=]+"')
UI_ICON_SIZE = (128, 128)  # upstream's get_icon() PNGs are 128x128 (the macOS one on a padded canvas)


def brand_ui_icons(text, mark):
    """src/ui.rs get_icon(): Sciter's window icon and remote header (AUI-11). Both base64 PNGs become the mark."""
    start = text.find("pub fn get_icon()")
    if start < 0:
        raise ValueError("ui.rs: get_icon() not found")
    end = text.find("\n}\n", start)
    body = text[start:end]
    buf = io.BytesIO()
    _square(mark, UI_ICON_SIZE).save(buf, format="PNG", optimize=True)
    literal = '"data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode("ascii") + '"'
    new_body, count = UI_ICON.subn(lambda m: literal, body)
    if count != 2:
        raise ValueError(f"ui.rs get_icon(): expected two icon literals, found {count}")
    return text[:start] + new_body + text[end:]


def main(root=ROOT):
    mark = Image.open(ICON if ICON.exists() else MARK).convert("RGBA")
    for rel in ICO_TARGETS:
        write_ico(mark, root / rel, tray=rel.endswith("tray-icon.ico"))
    for rel in PNG_TARGETS:
        write_png(mark, root / rel)
    for rel in SVG_TARGETS:
        (root / rel).write_text(svg_with_png(mark), encoding="utf-8")
    rc = root / "flutter" / "windows" / "runner" / "Runner.rc"
    rc.write_text(brand_rc(rc.read_text(encoding="utf-8")), encoding="utf-8")
    cargo = root / "Cargo.toml"
    cargo.write_text(brand_winres(cargo.read_text(encoding="utf-8")), encoding="utf-8")
    ui = root / "src" / "ui.rs"
    if ui.exists():  # absent only in the unit tests' toy trees; the real tree always has it
        ui.write_text(brand_ui_icons(ui.read_text(encoding="utf-8"), mark), encoding="utf-8")
    print(f"branded {len(ICO_TARGETS) + len(PNG_TARGETS) + len(SVG_TARGETS)} images, Runner.rc and Cargo.toml winres")
    return 0


if __name__ == "__main__":
    sys.exit(main())
