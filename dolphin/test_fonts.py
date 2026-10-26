import hashlib
import pathlib
import unittest

FONTS = pathlib.Path(__file__).resolve().parent.parent / "flutter" / "assets" / "fonts"
# Vazirmatn v33.003 (rastikerdar/vazirmatn, fonts/ttf), SIL OFL 1.1. Git blob SHAs checked against GitHub 2026-10-26.
PINNED = {
    "Vazirmatn-Regular.ttf": "b69fd4c680b8f3f225feabcc655a2c585d97627b8f5f5c0f9985e894069f3a56",
    "Vazirmatn-Medium.ttf": "b986623e4ddef10755e04be39f8ea7bcb1dc08bfe8dd0aa6af395736f256ad4a",
    "Vazirmatn-Bold.ttf": "f635fdbea28f265de395ba83b4b1570dcf2f58d13c65469e61903b1c2d2ae723",
    "Vazirmatn-ExtraBold.ttf": "5181c2e436cf1d5cf1c5631821b43d81881dca040a12c9a442ef5dc0007001cf",
    "OFL.txt": "17e355067c8284f47743a1ee3b1ef7ff684ff0601eda357f9353b10b3016ab31",
}


class FontsTest(unittest.TestCase):
    def test_vazirmatn_files_are_the_pinned_release(self):
        for name, digest in PINNED.items():
            self.assertEqual(hashlib.sha256((FONTS / name).read_bytes()).hexdigest(), digest, name)

    def test_pubspec_declares_the_family(self):
        pubspec = (FONTS.parent.parent / "pubspec.yaml").read_text(encoding="utf-8")
        self.assertIn("- family: Vazirmatn", pubspec)
        for weight in ("Regular", "Medium", "Bold", "ExtraBold"):
            self.assertIn(f"assets/fonts/Vazirmatn-{weight}.ttf", pubspec)


if __name__ == "__main__":
    unittest.main()
