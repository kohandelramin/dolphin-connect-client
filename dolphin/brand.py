"""Apply Dolphin Connect branding to the working tree (run in CI before building; not committed).

Usage: python dolphin/brand.py   (from the repository root; needs Pillow)
"""
import base64
import io
import pathlib
import re
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARK = ROOT / "dolphin" / "brand" / "dolphin-mark.png"
ICO_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
ICO_TARGETS = ["res/icon.ico", "res/tray-icon.ico", "flutter/windows/runner/resources/app_icon.ico"]
PNG_TARGETS = ["res/icon.png", "res/32x32.png", "res/64x64.png", "res/128x128.png", "res/128x128@2x.png"]
SVG_TARGETS = ["flutter/assets/icon.svg"]

RC_VALUES = {
    "CompanyName": "Dolphin",
    "FileDescription": "Dolphin Connect",
    "InternalName": "DolphinConnect",
    "OriginalFilename": "DolphinConnect.exe",
    "ProductName": "Dolphin Connect",
    # AGPL: keep the RustDesk authors' notice and add ours.
    "LegalCopyright": "Dolphin Connect, based on RustDesk. Copyright \u00a9 2026 Purslane Tech Pte. Ltd. and Dolphin. AGPL-3.0.",
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
    size = Image.open(path).size
    _square(mark, size).save(path, format="PNG")


def write_ico(mark, path):
    _square(mark, (256, 256)).save(path, format="ICO", sizes=ICO_SIZES)


def svg_with_png(mark):
    buf = io.BytesIO()
    _square(mark, (256, 256)).save(buf, format="PNG")
    data = base64.b64encode(buf.getvalue()).decode("ascii")
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">'
            f'<image width="256" height="256" href="data:image/png;base64,{data}"/></svg>\n')


def main(root=ROOT):
    mark = Image.open(MARK).convert("RGBA")
    for rel in ICO_TARGETS:
        write_ico(mark, root / rel)
    for rel in PNG_TARGETS:
        write_png(mark, root / rel)
    for rel in SVG_TARGETS:
        (root / rel).write_text(svg_with_png(mark), encoding="utf-8")
    rc = root / "flutter" / "windows" / "runner" / "Runner.rc"
    rc.write_text(brand_rc(rc.read_text(encoding="utf-8")), encoding="utf-8")
    cargo = root / "Cargo.toml"
    cargo.write_text(brand_winres(cargo.read_text(encoding="utf-8")), encoding="utf-8")
    print(f"branded {len(ICO_TARGETS) + len(PNG_TARGETS) + len(SVG_TARGETS)} images, Runner.rc and Cargo.toml winres")
    return 0


if __name__ == "__main__":
    sys.exit(main())
