import pathlib
import tempfile
import unittest

import rebrand as r


class LangTest(unittest.TestCase):
    def test_persian_values_get_the_persian_name_and_keys_the_english_one(self):
        line = '        ("About RustDesk", "درباره‌ی RustDesk"),'
        self.assertEqual(r.rewrite_lang(line, "fa"), '        ("About Dolphin Connect", "درباره‌ی دلفین کانکت"),')

    def test_other_languages_use_the_english_name(self):
        self.assertEqual(r.rewrite_lang('("Welcome to RustDesk", "Willkommen bei RustDesk"),', "de"),
                         '("Welcome to Dolphin Connect", "Willkommen bei Dolphin Connect"),')

    def test_links_in_translations_go_to_the_support_site(self):
        out = r.rewrite_lang('("doc_link", "https://rustdesk.com/docs/en/"),', "en")
        self.assertEqual(out, '("doc_link", "https://support.dolphindev.ir"),')


class LiteralTest(unittest.TestCase):
    def test_only_string_literals_change(self):
        src = "final t = translate('About RustDesk'); RustDeskMultiWindowManager.instance;"
        out = r.rewrite_literals(src)
        self.assertIn("translate('About Dolphin Connect')", out)
        self.assertIn("RustDeskMultiWindowManager.instance", out)

    def test_links_go_to_the_support_site(self):
        src = 'launchUrl(Uri.parse("https://rustdesk.com/privacy.html")); final u = \'https://rustdesk.com/docs/en/x#y\';'
        out = r.rewrite_literals(src)
        self.assertNotIn("rustdesk.com", out)
        self.assertEqual(out.count("https://support.dolphindev.ir"), 2)

    def test_comments_are_left_alone(self):
        self.assertEqual(r.rewrite_literals("// see 'RustDesk' docs"), "// see 'RustDesk' docs")

    def test_allowed_literals_stay(self):
        allowed = next(iter(r.ALLOW), None)
        if allowed:
            self.assertEqual(r.rewrite_literals(f"x({allowed});"), f"x({allowed});")


class RustTextTest(unittest.TestCase):
    def test_exact_rust_strings_are_rewritten_and_missing_ones_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "src").mkdir()
            (root / "src" / "clipboard.rs").write_text('let s = "RustDesk placeholder to clear the file clipboard";', encoding="utf-8")
            (root / "src" / "auth_2fa.rs").write_text("fn x<'a>() {}", encoding="utf-8")
            problems = r.rewrite_rust(root)
            self.assertIn("Dolphin Connect placeholder", (root / "src" / "clipboard.rs").read_text(encoding="utf-8"))
            self.assertEqual(len(problems), 1)
            self.assertIn("auth_2fa.rs", problems[0])
            self.assertEqual((root / "src" / "auth_2fa.rs").read_text(encoding="utf-8"), "fn x<'a>() {}")


class FaOverlayTest(unittest.TestCase):
    def test_overlay_replaces_values_by_key(self):
        text = '        ("Relay Server", "Relay سرور"),\n        ("Install", "نصب"),'
        out, problems = r.apply_fa_overlay(text, {"Relay Server": "سرور Relay"})
        self.assertEqual(problems, [])
        self.assertIn('("Relay Server", "سرور Relay")', out)
        self.assertIn('("Install", "نصب")', out)

    def test_overlay_fails_on_a_missing_or_repeated_key(self):
        _, missing = r.apply_fa_overlay('("Install", "نصب"),', {"Relay Server": "سرور Relay"})
        self.assertEqual(len(missing), 1)
        _, twice = r.apply_fa_overlay('("A", "x"),\n("A", "y"),', {"A": "z"})
        self.assertEqual(len(twice), 1)

    def test_overlay_escapes_quotes(self):
        out, _ = r.apply_fa_overlay('("k", "v"),', {"k": 'گفت "بله"'})
        self.assertIn('("k", "گفت \\"بله\\"")', out)

    def test_a_value_that_starts_latin_and_ends_persian_fails(self):
        self.assertEqual(len(r.bidi_problems('("Relay Server", "Relay سرور"),')), 1)
        self.assertEqual(len(r.bidi_problems('("Installing ...", "...در حال نصب"),')), 1)
        self.assertEqual(r.bidi_problems('("Relay Server", "سرور Relay"),'), [])
        self.assertEqual(r.bidi_problems('("{} sessions", "{} جلسه"),'), [])
        self.assertEqual(r.bidi_problems('("TCP", "TCP"),'), [])

    def test_overlay_values_are_clean_and_carry_our_name(self):
        for key, value in r.FA_OVERLAY.items():
            self.assertEqual(r.bidi_problems(f'("{key}", "{value}"),'), [], key)
            self.assertNotIn("RustDesk", value, key)

    def test_the_real_persian_file_is_clean_after_overlay_and_rename(self):
        text, problems = r.apply_fa_overlay((r.ROOT / "src" / "lang" / "fa.rs").read_text(encoding="utf-8"))
        self.assertEqual(problems, [])
        self.assertEqual(r.bidi_problems(r.rewrite_lang(text, "fa")), [])

    def test_a_portal_cut_says_so_in_plain_persian(self):
        self.assertIn("پورتال دلفین", r.FA_OVERLAY["Closed manually by web console"])
        self.assertNotIn("کنسول", r.FA_OVERLAY["Closed manually by web console"])


class ScanTest(unittest.TestCase):
    def _tree(self, tmp):
        root = pathlib.Path(tmp)
        (root / "flutter" / "lib").mkdir(parents=True)
        (root / "src" / "ui").mkdir(parents=True)
        (root / "src" / "lang").mkdir(parents=True)
        return root

    def test_scan_reports_leftovers_and_passes_clean_trees(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            (root / "flutter" / "lib" / "a.dart").write_text("final t = 'Dolphin Connect'; // RustDesk", encoding="utf-8")
            self.assertEqual(r.scan(root), [])
            (root / "src" / "ui" / "index.tis").write_text('var t = "RustDesk";', encoding="utf-8")
            self.assertEqual(len(r.scan(root)), 1)

    def test_main_rewrites_then_scans_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            (root / "flutter" / "lib" / "a.dart").write_text("final t = translate('About RustDesk'); // RustDesk", encoding="utf-8")
            (root / "src" / "ui" / "index.html").write_text("<title>RustDesk</title>", encoding="utf-8")
            (root / "src" / "ui" / "common.css").write_text("html { var(accent): #0071ff; }", encoding="utf-8")
            (root / "src" / "lang" / "fa.rs").write_text('("About RustDesk", "درباره‌ی RustDesk"),', encoding="utf-8")
            self.assertEqual(r.main(root, overlay={}), 0)
            self.assertIn("#1462e0", (root / "src" / "ui" / "common.css").read_text(encoding="utf-8"))
            self.assertIn("دلفین کانکت", (root / "src" / "lang" / "fa.rs").read_text(encoding="utf-8"))
            self.assertIn("Dolphin Connect", (root / "src" / "ui" / "index.html").read_text(encoding="utf-8"))

    def test_main_fails_on_reversed_persian(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self._tree(tmp)
            (root / "src" / "lang" / "fa.rs").write_text('("Relay Server", "Relay سرور"),', encoding="utf-8")
            self.assertEqual(r.main(root, overlay={}), 1)


if __name__ == "__main__":
    unittest.main()
