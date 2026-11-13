"""Apply Dolphin Connect branding to the working tree (run in CI before building; not committed).

Usage: python dolphin/brand.py [customer|technician]   (from the repository root; needs Pillow; default customer)
"""
import base64
import io
import json
import pathlib
import re
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The full mark (dolphin in the network) on a transparent ground: shown inside the app (flutter/assets/icon.svg).
MARK = ROOT / "dolphin" / "brand" / "dolphin-mark.png"
# The owner's icons (2026-11-13), one PNG per size, drawn for that size: up to 32 px the network mark alone (the dolphin
# line is lost at that size), from 40 px the full mark. customer on a white tile, technician on a blue tile, tray the
# network mark on a white tile at every size. Each frame goes into the .ico as it is: no resampling, no sharpening.
ICONS = ROOT / "dolphin" / "brand" / "icons"
VARIANTS = ("customer", "technician")
# Every size Windows asks for (taskbar 16-24 at 100-150 % scaling, Start 32-48, Explorer up to 256), so it never
# stretches a neighbour size.
ICO_SIZES = [(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)]
APP_ICO_TARGETS = ["res/icon.ico", "flutter/windows/runner/resources/app_icon.ico"]
TRAY_ICO_TARGETS = ["res/tray-icon.ico"]
# The downloaded file (libs/portable, the installer customers and technicians run first) has its own icon: the app
# icon with an aqua download badge (owner 2026-11-13, «نشان دانلود»), from setup-<variant>-<size>.png.
SETUP_ICO_TARGETS = ["res/setup.ico"]
PNG_TARGETS = ["res/icon.png", "res/32x32.png", "res/64x64.png", "res/128x128.png", "res/128x128@2x.png"]
SVG_TARGETS = ["flutter/assets/icon.svg"]

SETTINGS = ROOT / "dolphin" / "settings.json"


def rc_values(variant="customer"):
    """The exe's version-resource names for one variant, from dolphin/settings.json (Task Manager, the taskbar and the
    exe's Properties show FileDescription and ProductName). The technician app says «Technician» (owner 2026-11-13)."""
    settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
    chosen = settings["variants"][variant]
    name = chosen.get("display-name-en", settings["brand"]["display-name-en"])
    app = chosen.get("app-name", settings["app-name"])
    return {
        "CompanyName": "Dolphin",
        "FileDescription": name,
        "InternalName": app,
        "OriginalFilename": f"{app}.exe",
        "ProductName": name,
        # AGPL: keeps the upstream authors' copyright notice; the upstream product name is not shown (own brand).
        "LegalCopyright": "\u00a9 Dolphin \u00b7 portions \u00a9 Purslane Tech Pte. Ltd. \u00b7 AGPL-3.0",
    }


RC_VALUES = rc_values("customer")


def brand_rc(text, variant="customer"):
    for field, value in rc_values(variant).items():
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


def frames(kind, icons=ICONS):
    """The owner's PNGs for one set (customer, technician or tray), one per ICO size, checked to be that size."""
    out = []
    for size in ICO_SIZES:
        path = icons / f"{kind}-{size[0]}.png"
        with Image.open(path) as img:
            frame = img.convert("RGBA")
        if frame.size != size:
            raise ValueError(f"{path.name}: expected {size[0]}x{size[1]}, found {frame.width}x{frame.height}")
        out.append(frame)
    return out


def write_ico(icon_frames, path):
    """One .ico with every frame as it is (Pillow takes a provided frame of the right size without touching it)."""
    largest = max(icon_frames, key=lambda f: f.width)
    largest.save(path, format="ICO", sizes=[f.size for f in icon_frames],
                 append_images=[f for f in icon_frames if f is not largest])


def nearest(icon_frames, size):
    """The frame of this size; when there is none, the closest larger one (else the largest) resized with LANCZOS."""
    for frame in icon_frames:
        if frame.size == size:
            return frame.copy()
    larger = [f for f in icon_frames if f.width >= size[0]]
    source = min(larger, key=lambda f: f.width) if larger else max(icon_frames, key=lambda f: f.width)
    return source.resize(size, Image.LANCZOS)


def write_png(icon_frames, path):
    with Image.open(path) as existing:
        size = existing.size
    nearest(icon_frames, size).save(path, format="PNG")


def _square(mark, size):
    side = max(mark.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
    return canvas.resize(size, Image.LANCZOS)


def svg_with_png(mark):
    """flutter/assets/icon.svg: the full mark without a tile, as the app shows it on its own background."""
    buf = io.BytesIO()
    _square(mark, (256, 256)).save(buf, format="PNG")
    data = base64.b64encode(buf.getvalue()).decode("ascii")
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">'
            f'<image width="256" height="256" href="data:image/png;base64,{data}"/></svg>\n')


UI_ICON = re.compile(r'"data:image/png;base64,[A-Za-z0-9+/=]+"')
UI_ICON_SIZE = (128, 128)  # upstream's get_icon() PNGs are 128x128 (the macOS one on a padded canvas)


def brand_ui_icons(text, icon):
    """src/ui.rs get_icon(): Sciter's window icon and remote header (AUI-11). Both base64 PNGs become [icon]
    (the customer's 128 px frame: the x86 build is the customer app)."""
    if icon.size != UI_ICON_SIZE:
        raise ValueError(f"ui.rs get_icon(): the icon must be {UI_ICON_SIZE[0]}x{UI_ICON_SIZE[1]}")
    start = text.find("pub fn get_icon()")
    if start < 0:
        raise ValueError("ui.rs: get_icon() not found")
    end = text.find("\n}\n", start)
    body = text[start:end]
    buf = io.BytesIO()
    icon.save(buf, format="PNG", optimize=True)
    literal = '"data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode("ascii") + '"'
    new_body, count = UI_ICON.subn(lambda m: literal, body)
    if count != 2:
        raise ValueError(f"ui.rs get_icon(): expected two icon literals, found {count}")
    return text[:start] + new_body + text[end:]


def main(root=ROOT, variant="customer", icons=ICONS, mark_path=MARK):
    if variant not in VARIANTS:
        print(f"unknown variant: {variant} (use {' or '.join(VARIANTS)})", file=sys.stderr)
        return 2
    app, tray, setup = frames(variant, icons), frames("tray", icons), frames(f"setup-{variant}", icons)
    for rel in APP_ICO_TARGETS:
        write_ico(app, root / rel)
    for rel in TRAY_ICO_TARGETS:
        write_ico(tray, root / rel)
    for rel in SETUP_ICO_TARGETS:
        write_ico(setup, root / rel)
    for rel in PNG_TARGETS:
        write_png(app, root / rel)
    with Image.open(mark_path) as img:
        mark = img.convert("RGBA")
    for rel in SVG_TARGETS:
        (root / rel).write_text(svg_with_png(mark), encoding="utf-8")
    rc = root / "flutter" / "windows" / "runner" / "Runner.rc"
    rc.write_text(brand_rc(rc.read_text(encoding="utf-8"), variant), encoding="utf-8")
    cargo = root / "Cargo.toml"
    cargo.write_text(brand_winres(cargo.read_text(encoding="utf-8")), encoding="utf-8")
    ui = root / "src" / "ui.rs"
    if ui.exists():  # absent only in the unit tests' toy trees; the real tree always has it
        customer128 = frames("customer", icons)[ICO_SIZES.index(UI_ICON_SIZE)]
        ui.write_text(brand_ui_icons(ui.read_text(encoding="utf-8"), customer128), encoding="utf-8")
    count = len(APP_ICO_TARGETS) + len(TRAY_ICO_TARGETS) + len(SETUP_ICO_TARGETS) + len(PNG_TARGETS) + len(SVG_TARGETS)
    print(f"branded {count} images ({variant}), Runner.rc and Cargo.toml winres")
    return 0


if __name__ == "__main__":
    sys.exit(main(variant=sys.argv[1] if len(sys.argv) > 1 else "customer"))
