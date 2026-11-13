import base64
import hashlib
import io
import pathlib
import re
import tempfile
import unittest

from PIL import Image

import brand

RC = '''            VALUE "CompanyName", "Purslane Tech Pte. Ltd." "\\0"
            VALUE "FileDescription", "RustDesk Remote Desktop" "\\0"
            VALUE "FileVersion", VERSION_AS_STRING "\\0"
            VALUE "InternalName", "rustdesk" "\\0"
            VALUE "LegalCopyright", "Copyright \u00a9 2026 Purslane Tech Pte. Ltd. All rights reserved." "\\0"
            VALUE "OriginalFilename", "rustdesk.exe" "\\0"
            VALUE "ProductName", "RustDesk" "\\0"
'''


class RunnerRcTest(unittest.TestCase):
    def test_rewrites_names_and_keeps_upstream_copyright(self):
        out = brand.brand_rc(RC)
        self.assertIn('VALUE "ProductName", "Dolphin Connect" "\\0"', out)
        self.assertIn('VALUE "FileDescription", "Dolphin Connect" "\\0"', out)
        self.assertIn('VALUE "CompanyName", "Dolphin" "\\0"', out)
        self.assertIn('VALUE "OriginalFilename", "DolphinConnect.exe" "\\0"', out)
        self.assertIn('VALUE "InternalName", "DolphinConnect" "\\0"', out)
        self.assertIn("Purslane Tech Pte. Ltd.", out)
        self.assertIn("Dolphin", out.split('"LegalCopyright"')[1].splitlines()[0])
        self.assertIn("VERSION_AS_STRING", out)

    def test_fails_loudly_if_upstream_changes_a_field(self):
        with self.assertRaises(ValueError):
            brand.brand_rc(RC.replace('"ProductName"', '"Product"'))

    def test_the_technician_exe_says_technician(self):
        # Task Manager, the taskbar and the exe's Properties show FileDescription / ProductName.
        out = brand.brand_rc(RC, "technician")
        self.assertIn('VALUE "ProductName", "Dolphin Connect Technician" "\\0"', out)
        self.assertIn('VALUE "FileDescription", "Dolphin Connect Technician" "\\0"', out)
        self.assertIn('VALUE "OriginalFilename", "DolphinConnectTech.exe" "\\0"', out)
        self.assertIn('VALUE "InternalName", "DolphinConnectTech" "\\0"', out)
        self.assertIn('VALUE "CompanyName", "Dolphin" "\\0"', out)
        self.assertEqual(brand.brand_rc(RC, "customer"), brand.brand_rc(RC))

    def test_main_writes_the_variant_into_runner_rc(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            _toy_tree(root)
            brand.main(root, "technician")
            rc = (root / "flutter" / "windows" / "runner" / "Runner.rc").read_text(encoding="utf-8")
            cargo = (root / "Cargo.toml").read_text(encoding="utf-8")
        self.assertIn('"FileDescription", "Dolphin Connect Technician"', rc)
        # Cargo winres is the x86 Sciter build, which is the customer app only.
        self.assertIn('FileDescription = "Dolphin Connect"\n', cargo)

    def test_the_names_come_from_settings_json(self):
        import json
        settings = json.loads((brand.ROOT / "dolphin" / "settings.json").read_text(encoding="utf-8"))
        self.assertEqual(brand.rc_values("technician")["ProductName"], settings["variants"]["technician"]["display-name-en"])
        self.assertEqual(brand.rc_values("customer")["ProductName"], settings["brand"]["display-name-en"])


def _ico_frames(path):
    """Every frame of an .ico as RGBA bytes, by size."""
    out = {}
    with Image.open(path) as ico:
        for size in ico.info["sizes"]:
            ico.size = size
            out[size] = ico.convert("RGBA").tobytes()
    return out


def _png_bytes(path):
    with Image.open(path) as img:
        return img.convert("RGBA").tobytes()


def _toy_tree(root):
    """The files brand.main() rewrites, in a temporary tree (no src/ui.rs: the real one is tested on its own)."""
    for rel in brand.APP_ICO_TARGETS + brand.TRAY_ICO_TARGETS + brand.SETUP_ICO_TARGETS:
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGBA", (32, 32), "red").save(root / rel)
    for rel, side in zip(brand.PNG_TARGETS, (1024, 32, 64, 128, 256)):
        Image.new("RGBA", (side, side), "red").save(root / rel)
    for rel in brand.SVG_TARGETS:
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_text("<svg/>", encoding="utf-8")
    (root / "flutter" / "windows" / "runner" / "Runner.rc").write_text(RC, encoding="utf-8")
    (root / "Cargo.toml").write_text(CARGO, encoding="utf-8")


class IconTest(unittest.TestCase):
    """The owner's icons (2026-11-13): one PNG per size, packed into the .ico files as they are."""

    def test_every_set_has_every_ico_size_at_its_exact_size(self):
        for kind in ("customer", "technician", "tray", "setup-customer", "setup-technician"):
            got = brand.frames(kind)
            self.assertEqual([f.size for f in got], brand.ICO_SIZES, kind)

    def test_a_png_of_the_wrong_size_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            icons = pathlib.Path(tmp)
            for w, _ in brand.ICO_SIZES:
                Image.new("RGBA", (w, w), "white").save(icons / f"customer-{w}.png")
            Image.new("RGBA", (30, 30), "white").save(icons / "customer-32.png")
            with self.assertRaises(ValueError):
                brand.frames("customer", icons)

    def test_the_ico_frames_are_the_pngs_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "app.ico"
            brand.write_ico(brand.frames("customer"), path)
            got = _ico_frames(path)
        self.assertEqual(sorted(got), sorted(brand.ICO_SIZES))
        for w, h in brand.ICO_SIZES:
            self.assertEqual(got[(w, h)], _png_bytes(brand.ICONS / f"customer-{w}.png"), w)

    def test_main_packs_the_variant_and_the_tray_and_defaults_to_customer(self):
        for variant in (None, "customer", "technician"):
            with tempfile.TemporaryDirectory() as tmp:
                root = pathlib.Path(tmp)
                _toy_tree(root)
                rc = brand.main(root) if variant is None else brand.main(root, variant)
                self.assertEqual(rc, 0)
                kind = variant or "customer"
                for rel in brand.APP_ICO_TARGETS:
                    got = _ico_frames(root / rel)
                    for w, h in brand.ICO_SIZES:
                        self.assertEqual(got[(w, h)], _png_bytes(brand.ICONS / f"{kind}-{w}.png"), (rel, w))
                # The downloaded file (the portable packer) has its own installer icon (owner 2026-11-13).
                setup = _ico_frames(root / "res" / "setup.ico")
                for w, h in brand.ICO_SIZES:
                    self.assertEqual(setup[(w, h)], _png_bytes(brand.ICONS / f"setup-{kind}-{w}.png"), ("setup", w))
                tray = _ico_frames(root / "res" / "tray-icon.ico")
                for w, h in brand.ICO_SIZES:
                    self.assertEqual(tray[(w, h)], _png_bytes(brand.ICONS / f"tray-{w}.png"), w)
                # The small PNGs come from the same set at their own size; the 1024 px one is the only resized one.
                for rel, w in (("res/32x32.png", 32), ("res/64x64.png", 64), ("res/128x128.png", 128),
                               ("res/128x128@2x.png", 256)):
                    self.assertEqual(_png_bytes(root / rel), _png_bytes(brand.ICONS / f"{kind}-{w}.png"), rel)
                with Image.open(root / "res" / "icon.png") as big:
                    self.assertEqual(big.size, (1024, 1024))

    def test_the_two_variants_get_different_icons(self):
        self.assertNotEqual(brand.frames("customer")[-1].tobytes(), brand.frames("technician")[-1].tobytes())

    def test_the_installer_icon_differs_from_the_app_icon(self):
        for variant in brand.VARIANTS:
            self.assertNotEqual(brand.frames(variant)[-1].tobytes(), brand.frames(f"setup-{variant}")[-1].tobytes(), variant)

    def test_the_packer_uses_the_installer_icon(self):
        build = (brand.ROOT / "libs" / "portable" / "build.rs").read_text(encoding="utf-8")
        self.assertIn('set_icon("../../res/setup.ico")', build)
        self.assertNotIn('set_icon("../../res/icon.ico")', build)

    def test_an_unknown_variant_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            _toy_tree(root)
            self.assertEqual(brand.main(root, "admin"), 2)

    def test_a_missing_png_size_is_resized_from_the_next_larger_frame(self):
        got = brand.nearest(brand.frames("customer"), (100, 100))
        self.assertEqual(got.size, (100, 100))
        self.assertEqual(brand.nearest(brand.frames("customer"), (48, 48)).tobytes(),
                         _png_bytes(brand.ICONS / "customer-48.png"))

    def test_the_in_app_icon_is_the_full_mark_without_a_tile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            _toy_tree(root)
            brand.main(root)
            svg = (root / "flutter" / "assets" / "icon.svg").read_text(encoding="utf-8")
        self.assertTrue(svg.startswith("<svg"))
        data = re.search(r'href="data:image/png;base64,([A-Za-z0-9+/=]+)"', svg).group(1)
        img = Image.open(io.BytesIO(base64.b64decode(data))).convert("RGBA")
        self.assertEqual(img.size, (256, 256))
        self.assertEqual(img.getpixel((2, 2))[3], 0)  # transparent corner: no tile
        mark = Image.open(brand.MARK).convert("RGBA")
        self.assertEqual(img.tobytes(), brand._square(mark, (256, 256)).tobytes())

    def test_the_old_tile_source_is_gone(self):
        self.assertFalse(hasattr(brand, "ICON"))
        self.assertNotIn("dolphin-connect-icon", (brand.ROOT / "dolphin" / "brand.py").read_text(encoding="utf-8"))


CARGO = '''[package.metadata.winres]
LegalCopyright = "Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved."
ProductName = "RustDesk"
FileDescription = "RustDesk Remote Desktop"
OriginalFilename = "rustdesk.exe"

[target.'cfg(target_os="windows")'.build-dependencies]
winres = "0.1"
'''


class CargoWinresTest(unittest.TestCase):
    def test_rewrites_the_winres_metadata_only(self):
        out = brand.brand_winres(CARGO)
        self.assertIn('ProductName = "Dolphin Connect"', out)
        self.assertIn('FileDescription = "Dolphin Connect"', out)
        self.assertIn('OriginalFilename = "DolphinConnect.exe"', out)
        self.assertIn("portions © Purslane Tech Pte. Ltd. · AGPL-3.0", out)
        self.assertNotIn("RustDesk", out.split("[target")[0])
        self.assertIn('winres = "0.1"', out)

    def test_refuses_an_unexpected_layout(self):
        with self.assertRaises(ValueError):
            brand.brand_winres(CARGO.replace('ProductName = "RustDesk"\n', ""))


def _png_b64(color, size=128):
    buf = io.BytesIO()
    Image.new("RGBA", (size, size), color).save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


UI_RS = """pub fn get_icon() -> String {
    #[cfg(target_os = "macos")]
    {
        "data:image/png;base64,{MAC}".into()
    }
    #[cfg(not(target_os = "macos"))]
    {
        "data:image/png;base64,{OTHER}".into()
    }
}
"""


class WindowIconTest(unittest.TestCase):
    """AUI-11: Sciter's window icon and remote header come from get_icon() in src/ui.rs, not from the .ico files.
    The x86 build is the customer app: both become the customer's 128 px icon."""

    def _src(self):
        return UI_RS.replace("{MAC}", _png_b64((20, 98, 224, 255))).replace("{OTHER}", _png_b64((255, 0, 0, 255)))

    def _decoded(self, text):
        return [Image.open(io.BytesIO(base64.b64decode(b))) for b in re.findall(r"data:image/png;base64,([A-Za-z0-9+/=]+)", text)]

    def _icon(self):
        return Image.open(brand.ICONS / "customer-128.png").convert("RGBA")

    def test_both_icons_become_the_customer_128_png(self):
        out = brand.brand_ui_icons(self._src(), self._icon())
        icons = self._decoded(out)
        self.assertEqual(len(icons), 2)
        expected = self._icon().tobytes()
        for icon in icons:
            self.assertEqual(icon.size, (128, 128))
            self.assertEqual(icon.convert("RGBA").tobytes(), expected)
        self.assertEqual(hashlib.sha256(icons[0].convert("RGBA").tobytes()).hexdigest(), hashlib.sha256(expected).hexdigest())

    def test_refuses_an_unexpected_layout_or_size(self):
        with self.assertRaises(ValueError):
            brand.brand_ui_icons("pub fn get_icon() -> String { String::new() }", self._icon())
        with self.assertRaises(ValueError):
            brand.brand_ui_icons(self._src(), Image.new("RGBA", (64, 64)))

    def test_the_real_ui_rs_has_two_128px_icons_that_are_replaced(self):
        real = (brand.ROOT / "src" / "ui.rs").read_text(encoding="utf-8")
        before = self._decoded(real)
        self.assertEqual([i.size for i in before], [(128, 128), (128, 128)])
        out = brand.brand_ui_icons(real, self._icon())
        expected = self._icon().tobytes()
        after = self._decoded(out)
        self.assertEqual([i.convert("RGBA").tobytes() for i in after], [expected, expected])
        for original in re.findall(r"data:image/png;base64,([A-Za-z0-9+/=]+)", real):
            self.assertNotIn(original[:200], out)


if __name__ == "__main__":
    unittest.main()
