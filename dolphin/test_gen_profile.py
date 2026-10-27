import copy
import json
import pathlib
import tempfile
import unittest

import gen_profile as g

HERE = pathlib.Path(__file__).parent
SETTINGS = json.loads((HERE / "settings.json").read_text(encoding="utf-8"))
KEY = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw="  # any valid 32-byte key
PROFILE = {
    "custom-rendezvous-server": "remote.dolphindev.ir",
    "relay-server": "remote.dolphindev.ir:21117",
    "key": KEY,
    "api-server": "https://support.dolphindev.ir/rd",
}


class ProfileTest(unittest.TestCase):
    def test_accepts_the_production_shape(self):
        self.assertEqual(g.validate_profile(PROFILE, "production"), [])

    def test_refuses_an_empty_or_malformed_key(self):
        for key in ["", "abc", "!" * 44]:
            errors = g.validate_profile({**PROFILE, "key": key}, "production")
            self.assertTrue(any("key" in e for e in errors), key)

    def test_refuses_plain_http_api_except_on_private_addresses(self):
        self.assertTrue(g.validate_profile({**PROFILE, "api-server": "http://support.dolphindev.ir/rd"}, "production"))
        self.assertEqual(g.validate_profile({**PROFILE, "api-server": "http://127.0.0.1:3010/rd"}, "dev"), [])
        self.assertEqual(g.validate_profile({**PROFILE, "api-server": "http://192.168.1.20:3010/rd"}, "dev"), [])

    def test_refuses_schemes_trailing_slashes_and_missing_relay_port(self):
        self.assertTrue(g.validate_profile({**PROFILE, "custom-rendezvous-server": "https://remote.dolphindev.ir"}, "production"))
        self.assertTrue(g.validate_profile({**PROFILE, "api-server": "https://support.dolphindev.ir/rd/"}, "production"))
        self.assertTrue(g.validate_profile({**PROFILE, "relay-server": "remote.dolphindev.ir"}, "production"))

    def test_refuses_unknown_or_missing_keys(self):
        self.assertTrue(g.validate_profile({**PROFILE, "extra": "x"}, "production"))
        missing = dict(PROFILE)
        del missing["key"]
        self.assertTrue(g.validate_profile(missing, "production"))


class SettingsTest(unittest.TestCase):
    def test_the_committed_settings_pass(self):
        self.assertEqual(g.validate_settings(SETTINGS), [])

    def test_every_security_floor_value_is_enforced(self):
        for section, key, _ in g.FLOOR:
            loosened = copy.deepcopy(SETTINGS)
            loosened[section][key] = "loosened"
            self.assertTrue(g.validate_settings(loosened), key)
            removed = copy.deepcopy(SETTINGS)
            del removed[section][key]
            self.assertTrue(g.validate_settings(removed), key)

    def test_server_keys_belong_to_the_profile_only(self):
        s = copy.deepcopy(SETTINGS)
        s["override"]["api-server"] = "https://evil.example"
        self.assertTrue(any("profile" in e for e in g.validate_settings(s)))

    def test_app_name_is_letters_digits_and_hyphens(self):
        s = copy.deepcopy(SETTINGS)
        s["app-name"] = "Dolphin Connect"
        self.assertTrue(g.validate_settings(s))

    def test_variants_are_exactly_customer_and_technician(self):
        s = copy.deepcopy(SETTINGS)
        s["variants"]["guest"] = {"hard": {}}
        self.assertTrue(g.validate_settings(s))
        s = copy.deepcopy(SETTINGS)
        del s["variants"]["technician"]
        self.assertTrue(g.validate_settings(s))

    def test_each_variant_keeps_its_connection_direction(self):
        for variant in ("customer", "technician"):
            s = copy.deepcopy(SETTINGS)
            s["variants"][variant]["hard"]["conn-type"] = "both"
            self.assertTrue(any("conn-type" in e for e in g.validate_settings(s)), variant)
            s = copy.deepcopy(SETTINGS)
            del s["variants"][variant]["hard"]["conn-type"]
            self.assertTrue(g.validate_settings(s), variant)

    def test_variants_may_only_set_hard_settings_and_app_name(self):
        s = copy.deepcopy(SETTINGS)
        s["variants"]["customer"]["override"] = {"allow-only-conn-window-open": "N"}
        self.assertTrue(g.validate_settings(s))
        s = copy.deepcopy(SETTINGS)
        s["variants"]["technician"]["app-name"] = "Dolphin Tech"
        self.assertTrue(g.validate_settings(s))

    def test_installation_is_allowed(self):
        self.assertEqual(SETTINGS["hard"]["disable-installation"], "N")

    def test_brand_block_is_required_and_checked(self):
        s = copy.deepcopy(SETTINGS)
        del s["brand"]
        self.assertTrue(g.validate_settings(s))
        s = copy.deepcopy(SETTINGS)
        s["brand"]["site"] = "http://support.dolphindev.ir"
        self.assertTrue(any("brand.site" in e for e in g.validate_settings(s)))
        s = copy.deepcopy(SETTINGS)
        s["brand"]["support-phone"] = "call me"
        self.assertTrue(any("support-phone" in e for e in g.validate_settings(s)))


class RenderTest(unittest.TestCase):
    def test_renders_sorted_rust_constants_with_the_profile_in_override(self):
        rust = g.render_rust(SETTINGS, PROFILE, "production", "customer", "2.0.0")
        self.assertIn('pub const APP_NAME: &str = "DolphinConnect";', rust)
        self.assertIn('pub const RENDEZVOUS_SERVER: &str = "remote.dolphindev.ir";', rust)
        self.assertIn(f'("key", "{KEY}")', rust)
        self.assertIn('("api-server", "https://support.dolphindev.ir/rd")', rust)
        override = rust.split("pub const OVERRIDE_SETTINGS")[1].split("];")[0]
        keys = [line.split('"')[1] for line in override.splitlines() if line.strip().startswith('("')]
        self.assertEqual(keys, sorted(keys))
        hard = rust.split("pub const HARD_SETTINGS")[1]
        self.assertIn('("conn-type", "incoming")', hard)
        self.assertIn('("disable-installation", "N")', hard)

    def test_the_technician_variant_is_outgoing_with_its_own_name(self):
        rust = g.render_rust(SETTINGS, PROFILE, "production", "technician", "2.0.0")
        self.assertIn('("conn-type", "outgoing")', rust.split("pub const HARD_SETTINGS")[1])
        self.assertIn('pub const APP_NAME: &str = "DolphinConnectTech";', rust)

    def test_brand_dart_has_the_values_escaped(self):
        s = copy.deepcopy(SETTINGS)
        s["brand"]["support-phone"] = "021-12345678"
        dart = g.render_brand_dart(s, PROFILE, "2.0.0")
        # The technician app shows the staff panel from the same server as the API.
        self.assertIn("static const String portalUrl = 'https://support.dolphindev.ir';", dart)
        self.assertIn("static const String portalUrl = 'http://127.0.0.1:3010';",
                      g.render_brand_dart(s, {**PROFILE, "api-server": "http://127.0.0.1:3010/rd"}, "2.0.0"))
        self.assertIn("static const String nameFa = 'دلفین کانکت';", dart)
        self.assertIn("static const String supportPhone = '021-12345678';", dart)
        self.assertIn("static const String siteLabel = 'support.dolphindev.ir';", dart)
        self.assertEqual(g.dart_str("it's"), "'it\\'s'")

    def test_production_needs_a_support_phone(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "dolphin" / "profiles").mkdir(parents=True)
            (root / "src").mkdir()
            (root / "flutter" / "lib" / "dolphin").mkdir(parents=True)
            s = copy.deepcopy(SETTINGS)
            s["brand"]["support-phone"] = ""
            (root / "dolphin" / "settings.json").write_text(json.dumps(s), encoding="utf-8")
            (root / "dolphin" / "profiles" / "production.json").write_text(json.dumps(PROFILE), encoding="utf-8")
            (root / "dolphin" / "profiles" / "dev.json").write_text(json.dumps(PROFILE), encoding="utf-8")
            self.assertEqual(g.main(["production", "customer", "2.0.0"], root), 1)
            self.assertEqual(g.main(["dev", "customer", "2.0.0"], root), 0)
            self.assertIn("class DolphinBrand", (root / "flutter" / "lib" / "dolphin" / "brand.dart").read_text(encoding="utf-8"))

    def test_rust_strings_are_escaped_and_control_characters_refused(self):
        self.assertEqual(g.rust_str('a"b\\c'), '"a\\"b\\\\c"')
        with self.assertRaises(ValueError):
            g.rust_str("a\nb")

    def test_baked_settings_are_server_settings_without_the_profile(self):
        baked = g.baked_settings(SETTINGS)
        self.assertEqual(baked["approve-mode"], "password")
        self.assertEqual(baked["verification-method"], "use-temporary-password")
        self.assertNotIn("api-server", baked)
        self.assertNotIn("lang", baked)

    def test_main_writes_both_files_and_fails_on_an_empty_key_or_unknown_variant(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "dolphin" / "profiles").mkdir(parents=True)
            (root / "src").mkdir()
            (root / "flutter" / "lib" / "dolphin").mkdir(parents=True)
            with_phone = {**SETTINGS, "brand": {**SETTINGS["brand"], "support-phone": "021-12345678"}}
            (root / "dolphin" / "settings.json").write_text(json.dumps(with_phone), encoding="utf-8")
            (root / "dolphin" / "profiles" / "production.json").write_text(json.dumps(PROFILE), encoding="utf-8")
            (root / "dolphin" / "profiles" / "empty.json").write_text(json.dumps({**PROFILE, "key": ""}), encoding="utf-8")
            self.assertEqual(g.main(["production", "customer", "2.0.0"], root), 0)
            self.assertIn('("conn-type", "incoming")', (root / "src" / "dolphin_generated.rs").read_text(encoding="utf-8"))
            self.assertIn("approve-mode", (root / "dolphin" / "build" / "baked-settings.json").read_text(encoding="utf-8"))
            self.assertEqual(g.main(["production", "technician", "2.0.0"], root), 0)
            self.assertIn('("conn-type", "outgoing")', (root / "src" / "dolphin_generated.rs").read_text(encoding="utf-8"))
            self.assertEqual(g.main(["empty", "customer", "2.0.0"], root), 1)
            self.assertEqual(g.main(["production", "guest", "2.0.0"], root), 1)
            self.assertEqual(g.main(["production"], root), 2)


class VersionTest(unittest.TestCase):
    def test_rust_and_dart_carry_the_dolphin_version_the_portal_and_the_phone(self):
        rust = g.render_rust(SETTINGS, PROFILE, "production", "customer", "2.0.0-rc.1")
        self.assertIn('pub const DOLPHIN_VERSION: &str = "2.0.0-rc.1";', rust)
        self.assertIn('pub const PORTAL_URL: &str = "https://support.dolphindev.ir";', rust)
        self.assertIn('pub const SUPPORT_PHONE: &str = "021-44200250";', rust)
        self.assertIn("static const String version = '2.0.0-rc.1';", g.render_brand_dart(SETTINGS, PROFILE, "2.0.0-rc.1"))
        self.assertEqual(g.portal_url({**PROFILE, "api-server": "http://127.0.0.1:3010/rd"}), "http://127.0.0.1:3010")

    def test_main_refuses_a_version_that_is_not_ours(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "dolphin" / "profiles").mkdir(parents=True)
            (root / "src").mkdir()
            (root / "flutter" / "lib" / "dolphin").mkdir(parents=True)
            (root / "dolphin" / "settings.json").write_text(json.dumps(SETTINGS), encoding="utf-8")
            (root / "dolphin" / "profiles" / "production.json").write_text(json.dumps(PROFILE), encoding="utf-8")
            for bad in ("v2.0.0", "2.0", "2.0.0-beta.1", "1.5.0-dc.4", ""):
                self.assertEqual(g.main(["production", "customer", bad], root), 1, bad)
            self.assertEqual(g.main(["production", "customer", "2.0.0-dev.7"], root), 0)
            self.assertIn('DOLPHIN_VERSION: &str = "2.0.0-dev.7"', (root / "src" / "dolphin_generated.rs").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
