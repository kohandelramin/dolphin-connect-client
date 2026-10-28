import base64
import hashlib
import io
import pathlib
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


class IconTest(unittest.TestCase):
    def test_png_targets_keep_their_size_and_ico_has_all_sizes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "res").mkdir()
            Image.new("RGBA", (128, 128), "red").save(root / "res" / "128x128.png")
            Image.new("RGBA", (32, 32), "red").save(root / "res" / "icon.ico")
            mark = Image.new("RGBA", (351, 350), (20, 98, 224, 255))
            brand.write_png(mark, root / "res" / "128x128.png")
            brand.write_ico(mark, root / "res" / "icon.ico")
            self.assertEqual(Image.open(root / "res" / "128x128.png").size, (128, 128))
            sizes = Image.open(root / "res" / "icon.ico").info["sizes"]
            self.assertIn((256, 256), sizes)
            self.assertIn((16, 16), sizes)

    def test_svg_embeds_the_mark_as_png(self):
        svg = brand.svg_with_png(Image.new("RGBA", (351, 350), "blue"))
        self.assertTrue(svg.startswith("<svg"))
        self.assertIn('href="data:image/png;base64,', svg)


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


UI_RS = (
    "pub fn get_icon() -> String {
"
    "    #[cfg(target_os = \"macos\")]
    {
"
    '        "data:image/png;base64,' + "{MAC}" + '".into()
    }
'
    "    #[cfg(not(target_os = \"macos\"))]
    {
"
    '        "data:image/png;base64,' + "{OTHER}" + '".into()
    }
}
'
)


class WindowIconTest(unittest.TestCase):
    """AUI-11: Sciter's window icon and remote header come from get_icon() in src/ui.rs, not from the .ico files."""

    def _src(self):
        return UI_RS.replace("{MAC}", _png_b64((20, 98, 224, 255))).replace("{OTHER}", _png_b64((255, 0, 0, 255)))

    def _decoded(self, text):
        import re
        return [Image.open(io.BytesIO(base64.b64decode(b))) for b in re.findall(r"data:image/png;base64,([A-Za-z0-9+/=]+)", text)]

    def test_both_icons_become_the_dolphin_mark_at_the_same_size(self):
        mark = Image.open(brand.MARK).convert("RGBA")
        out = brand.brand_ui_icons(self._src(), mark)
        icons = self._decoded(out)
        self.assertEqual(len(icons), 2)
        expected = brand._square(mark, (128, 128))
        for icon in icons:
            self.assertEqual(icon.size, (128, 128))
            self.assertEqual(icon.convert("RGBA").tobytes(), expected.tobytes())
        self.assertEqual(hashlib.sha256(icons[0].tobytes()).hexdigest(), hashlib.sha256(expected.tobytes()).hexdigest())

    def test_refuses_an_unexpected_layout(self):
        mark = Image.open(brand.MARK).convert("RGBA")
        with self.assertRaises(ValueError):
            brand.brand_ui_icons("pub fn get_icon() -> String { String::new() }", mark)

    def test_the_real_ui_rs_has_two_128px_icons_that_are_replaced(self):
        mark = Image.open(brand.MARK).convert("RGBA")
        real = (brand.ROOT / "src" / "ui.rs").read_text(encoding="utf-8")
        before = self._decoded(real)
        self.assertEqual([i.size for i in before], [(128, 128), (128, 128)])
        out = brand.brand_ui_icons(real, mark)
        expected = brand._square(mark, (128, 128)).tobytes()
        after = self._decoded(out)
        self.assertEqual([i.convert("RGBA").tobytes() for i in after], [expected, expected])
        for old in before:
            self.assertNotIn(base64.b64encode(_png_bytes(old)).decode("ascii")[:200], out)
        # No RustDesk icon base64 remains: every embedded PNG in get_icon() is the mark.
        self.assertEqual(len(after), 2)


def _png_bytes(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


if __name__ == "__main__":
    unittest.main()
