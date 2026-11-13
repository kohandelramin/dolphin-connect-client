import copy
import hashlib
import hmac
import json
import pathlib
import re
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
    # DD-24: the throwaway key of dolphin/strategy-signature-vector.json (its private half was never kept).
    "strategy-public-key": "ZuS26V7Tw2nnrbswkPHSPvunNt3d1x6Gi+LXDqo3PLc=",
}
# A fake fixed password (D21). The real one exists only as the fork's GitHub Actions secret.
FAKE_FIXED = "fake-fixed-for-tests-only"
FAKE_ENV = {g.FIXED_ENV: FAKE_FIXED}


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

    def test_refuses_a_bad_port_in_the_api_server(self):
        for api in ("https://support.dolphindev.ir:99999/rd", "https://support.dolphindev.ir:abc/rd"):
            errors = g.validate_profile({**PROFILE, "api-server": api}, "production")
            self.assertTrue(any("api-server" in e for e in errors), api)

    def test_accepts_an_ipv6_api_server_and_writes_it_in_brackets(self):
        profile = {**PROFILE, "api-server": "http://[::1]:3010/rd"}
        self.assertEqual(g.validate_profile(profile, "dev"), [])
        self.assertEqual(g.portal_url(profile), "http://[::1]:3010")
        self.assertTrue(g.validate_profile({**PROFILE, "api-server": "http://[2606:4700::1]:3010/rd"}, "dev"))  # public

    def test_refuses_unknown_or_missing_keys(self):
        self.assertTrue(g.validate_profile({**PROFILE, "extra": "x"}, "production"))
        missing = dict(PROFILE)
        del missing["key"]
        self.assertTrue(g.validate_profile(missing, "production"))


class StrategyKeyTest(unittest.TestCase):
    """DD-24: the portal's strategy-signing public key, compiled in; empty only outside production."""

    def test_empty_or_a_raw_32_byte_key(self):
        self.assertEqual(g.validate_profile({**PROFILE, "strategy-public-key": ""}, "dev"), [])
        for bad in ("abc", "!" * 44, base64_of(31), base64_of(33), 7):
            errors = g.validate_profile({**PROFILE, "strategy-public-key": bad}, "production")
            self.assertTrue(any("strategy-public-key" in e for e in errors), bad)
        missing = dict(PROFILE)
        del missing["strategy-public-key"]
        self.assertTrue(g.validate_profile(missing, "production"))

    def test_it_is_a_constant_and_not_a_pushed_option(self):
        rust = g.render_rust(SETTINGS, PROFILE, "production", "customer", "2.0.0")
        self.assertIn(f'pub const STRATEGY_PUBLIC_KEY: &str = "{PROFILE["strategy-public-key"]}";', rust)
        self.assertNotIn('("strategy-public-key"', rust)
        empty = g.render_rust(SETTINGS, {**PROFILE, "strategy-public-key": ""}, "dev", "customer", "2.0.0")
        self.assertIn('pub const STRATEGY_PUBLIC_KEY: &str = "";', empty)

    def test_production_needs_the_key_and_dev_may_leave_it_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            no_key = json.dumps({**PROFILE, "strategy-public-key": ""})
            (root / "dolphin" / "profiles" / "production.json").write_text(no_key, encoding="utf-8")
            (root / "dolphin" / "profiles" / "dev.json").write_text(no_key, encoding="utf-8")
            self.assertEqual(g.main(["production", "customer", "2.0.0"], root, FAKE_ENV), 1)
            self.assertEqual(g.main(["dev", "customer", "2.0.0-dev.1"], root, {}), 0)
            self.assertIn('STRATEGY_PUBLIC_KEY: &str = "";', (root / "src" / "dolphin_generated.rs").read_text(encoding="utf-8"))

    def test_the_committed_profiles(self):
        # The production key is not made yet (the owner runs the portal's gen-signing-key.ts before the release build);
        # dev talks to a local portal that signs nothing.
        for name in ("dev", "production"):
            profile = json.loads((HERE / "profiles" / f"{name}.json").read_text(encoding="utf-8"))
            self.assertEqual(g.validate_profile(profile, name), [], name)
            self.assertIn("strategy-public-key", profile)
        self.assertEqual(json.loads((HERE / "profiles" / "dev.json").read_text(encoding="utf-8"))["strategy-public-key"], "")

    def test_the_vector_key_is_the_test_key(self):
        vector = json.loads((HERE / "strategy-signature-vector.json").read_text(encoding="utf-8"))
        self.assertEqual(vector["public_key"], PROFILE["strategy-public-key"])
        self.assertEqual(g.validate_profile({**PROFILE, "strategy-public-key": vector["public_key"]}, "production"), [])


def base64_of(n):
    import base64
    return base64.b64encode(bytes(range(n))).decode()


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

    def test_an_idle_technician_is_never_disconnected(self):
        # Owner 2026-11-09: no idle cut, in any build; the compiled override wins over what the portal pushes.
        self.assertEqual(SETTINGS["override"].get("allow-auto-disconnect"), "N")
        on = copy.deepcopy(SETTINGS)
        on["override"]["allow-auto-disconnect"] = "Y"
        self.assertTrue(g.validate_settings(on))

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
        s["brand"]["support-phone"] = "021-44280505"
        dart = g.render_brand_dart(s, PROFILE, "2.0.0")
        # The technician app shows the staff panel from the same server as the API.
        self.assertIn("static const String portalUrl = 'https://support.dolphindev.ir';", dart)
        self.assertIn("static const String portalUrl = 'http://127.0.0.1:3010';",
                      g.render_brand_dart(s, {**PROFILE, "api-server": "http://127.0.0.1:3010/rd"}, "2.0.0"))
        self.assertIn("static const String nameFa = 'دلفین کانکت';", dart)
        self.assertIn("static const String supportPhone = '021-44280505';", dart)
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
            self.assertEqual(g.main(["production", "customer", "2.0.0"], root, FAKE_ENV), 1)
            self.assertEqual(g.main(["dev", "customer", "2.0.0"], root, {}), 0)
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
            with_phone = {**SETTINGS, "brand": {**SETTINGS["brand"], "support-phone": "021-44280505"}}
            (root / "dolphin" / "settings.json").write_text(json.dumps(with_phone), encoding="utf-8")
            (root / "dolphin" / "profiles" / "production.json").write_text(json.dumps(PROFILE), encoding="utf-8")
            (root / "dolphin" / "profiles" / "empty.json").write_text(json.dumps({**PROFILE, "key": ""}), encoding="utf-8")
            self.assertEqual(g.main(["production", "customer", "2.0.0"], root, FAKE_ENV), 0)
            self.assertIn('("conn-type", "incoming")', (root / "src" / "dolphin_generated.rs").read_text(encoding="utf-8"))
            self.assertIn("approve-mode", (root / "dolphin" / "build" / "baked-settings.json").read_text(encoding="utf-8"))
            self.assertEqual(g.main(["production", "technician", "2.0.0"], root, FAKE_ENV), 0)
            self.assertIn('("conn-type", "outgoing")', (root / "src" / "dolphin_generated.rs").read_text(encoding="utf-8"))
            self.assertEqual(g.main(["empty", "customer", "2.0.0"], root, FAKE_ENV), 1)
            self.assertEqual(g.main(["production", "guest", "2.0.0"], root, FAKE_ENV), 1)
            self.assertEqual(g.main(["production"], root, FAKE_ENV), 2)


class DisplayNameTest(unittest.TestCase):
    """Owner 2026-11-13: the technician app says «کارشناس» in its name; app-name (paths, service, pipes) stays."""

    def test_the_technician_has_its_own_display_name_and_the_same_app_name(self):
        tech = SETTINGS["variants"]["technician"]
        self.assertEqual(tech["display-name-fa"], "دلفین کانکت کارشناس")
        self.assertEqual(tech["display-name-en"], "Dolphin Connect Technician")
        self.assertEqual(tech["app-name"], "DolphinConnectTech")
        self.assertEqual(g.display_names(SETTINGS, "technician"), ("دلفین کانکت کارشناس", "Dolphin Connect Technician"))
        self.assertEqual(g.display_names(SETTINGS, "customer"), ("دلفین کانکت", "Dolphin Connect"))

    def test_display_names_come_in_pairs_and_are_checked(self):
        for broken in ({"display-name-fa": "دلفین"}, {"display-name-en": "Dolphin"},
                       {"display-name-fa": " ", "display-name-en": "Dolphin"},
                       {"display-name-fa": "دلفین", "display-name-en": 3},
                       {"display-name-fa": "دلفین\n", "display-name-en": "Dolphin"}):
            s = copy.deepcopy(SETTINGS)
            for key in ("display-name-fa", "display-name-en"):
                s["variants"]["technician"].pop(key, None)
            s["variants"]["technician"].update(broken)
            self.assertTrue(any("display-name" in e for e in g.validate_settings(s)), broken)
        s = copy.deepcopy(SETTINGS)
        s["variants"]["customer"].update({"display-name-fa": "دلفین", "display-name-en": "Dolphin"})
        self.assertEqual(g.validate_settings(s), [])

    def test_rust_carries_the_build_display_name(self):
        tech = g.render_rust(SETTINGS, PROFILE, "production", "technician", "2.0.0")
        self.assertIn('pub const DISPLAY_NAME_FA: &str = "دلفین کانکت کارشناس";', tech)
        self.assertIn('pub const DISPLAY_NAME_EN: &str = "Dolphin Connect Technician";', tech)
        cust = g.render_rust(SETTINGS, PROFILE, "production", "customer", "2.0.0")
        self.assertIn('pub const DISPLAY_NAME_FA: &str = "دلفین کانکت";', cust)
        self.assertIn('pub const DISPLAY_NAME_EN: &str = "Dolphin Connect";', cust)

    def test_brand_dart_has_this_build_name_and_the_technician_name(self):
        cust = g.render_brand_dart(SETTINGS, PROFILE, "2.0.0", "customer")
        self.assertIn("static const String nameFa = 'دلفین کانکت';", cust)
        self.assertIn("static const String appNameFa = 'دلفین کانکت';", cust)
        self.assertIn("static const String appNameEn = 'Dolphin Connect';", cust)
        self.assertIn("static const String technicianNameFa = 'دلفین کانکت کارشناس';", cust)
        tech = g.render_brand_dart(SETTINGS, PROFILE, "2.0.0", "technician")
        self.assertIn("static const String nameFa = 'دلفین کانکت';", tech)
        self.assertIn("static const String appNameFa = 'دلفین کانکت کارشناس';", tech)
        self.assertIn("static const String appNameEn = 'Dolphin Connect Technician';", tech)
        # The variant defaults to customer for older callers.
        self.assertEqual(g.render_brand_dart(SETTINGS, PROFILE, "2.0.0"), cust)

    def test_main_writes_the_variant_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "dolphin" / "profiles").mkdir(parents=True)
            (root / "src").mkdir()
            (root / "dolphin" / "settings.json").write_text(json.dumps(SETTINGS), encoding="utf-8")
            (root / "dolphin" / "profiles" / "production.json").write_text(json.dumps(PROFILE), encoding="utf-8")
            self.assertEqual(g.main(["production", "technician", "2.0.0"], root, FAKE_ENV), 0)
            dart = (root / "flutter" / "lib" / "dolphin" / "brand.dart").read_text(encoding="utf-8")
            self.assertIn("static const String appNameFa = 'دلفین کانکت کارشناس';", dart)
            rust = (root / "src" / "dolphin_generated.rs").read_text(encoding="utf-8")
            self.assertIn('pub const DISPLAY_NAME_EN: &str = "Dolphin Connect Technician";', rust)


class VersionTest(unittest.TestCase):
    def test_rust_and_dart_carry_the_dolphin_version_the_portal_and_the_phone(self):
        rust = g.render_rust(SETTINGS, PROFILE, "production", "customer", "2.0.0-rc.1")
        self.assertIn('pub const DOLPHIN_VERSION: &str = "2.0.0-rc.1";', rust)
        self.assertIn('pub const PORTAL_URL: &str = "https://support.dolphindev.ir";', rust)
        self.assertIn('pub const SUPPORT_PHONE: &str = "021-44280505";', rust)
        self.assertIn("static const String version = '2.0.0-rc.1';", g.render_brand_dart(SETTINGS, PROFILE, "2.0.0-rc.1"))
        self.assertEqual(g.portal_url({**PROFILE, "api-server": "http://127.0.0.1:3010/rd"}), "http://127.0.0.1:3010")

    def test_portal_url_matches_what_webview2_reports(self):
        # The bridge compares by prefix with the WebView's normalised Source: lower-case host, no default port.
        for api in ("https://Support.DolphinDev.ir/rd", "https://support.dolphindev.ir:443/rd", "HTTPS://SUPPORT.dolphindev.ir:443/rd"):
            self.assertEqual(g.portal_url({**PROFILE, "api-server": api}), "https://support.dolphindev.ir", api)
        self.assertEqual(g.portal_url({**PROFILE, "api-server": "https://support.dolphindev.ir:8443/rd"}), "https://support.dolphindev.ir:8443")
        self.assertEqual(g.portal_url({**PROFILE, "api-server": "http://127.0.0.1:3010/rd"}), "http://127.0.0.1:3010")
        self.assertEqual(g.portal_url({**PROFILE, "api-server": "http://localhost:80/rd"}), "http://localhost")

    def test_main_refuses_a_version_that_is_not_ours(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "dolphin" / "profiles").mkdir(parents=True)
            (root / "src").mkdir()
            (root / "flutter" / "lib" / "dolphin").mkdir(parents=True)
            (root / "dolphin" / "settings.json").write_text(json.dumps(SETTINGS), encoding="utf-8")
            (root / "dolphin" / "profiles" / "production.json").write_text(json.dumps(PROFILE), encoding="utf-8")
            for bad in ("v2.0.0", "2.0", "2.0.0-beta.1", "1.5.0-dc.4", ""):
                self.assertEqual(g.main(["production", "customer", bad], root, FAKE_ENV), 1, bad)
            self.assertEqual(g.main(["production", "customer", "2.0.0-dev.7"], root, FAKE_ENV), 0)
            self.assertIn('DOLPHIN_VERSION: &str = "2.0.0-dev.7"', (root / "src" / "dolphin_generated.rs").read_text(encoding="utf-8"))


def _root(tmp, settings=None):
    root = pathlib.Path(tmp)
    (root / "dolphin" / "profiles").mkdir(parents=True)
    (root / "src").mkdir()
    (root / "flutter" / "lib" / "dolphin").mkdir(parents=True)
    (root / "dolphin" / "settings.json").write_text(json.dumps(settings or SETTINGS), encoding="utf-8")
    for name in ("production", "dev"):
        (root / "dolphin" / "profiles" / f"{name}.json").write_text(json.dumps(PROFILE), encoding="utf-8")
    return root


def _arrays(rust):
    """The three byte arrays of a rendered src/dolphin_fixed_generated.rs."""
    out = {}
    for name, body in re.findall(r"pub static (\w+): \[u8; \d+\] = \[([^\]]*)\];", rust):
        out[name] = bytes(int(x, 16) for x in body.split(",") if x.strip())
    return out


def _unmask(a):
    return bytes(m ^ x ^ y for m, x, y in zip(a["FIXED_MASKED"], a["FIXED_PAD_A"], a["FIXED_PAD_B"]))


class FixedPasswordTest(unittest.TestCase):
    """Owner decision D21: one fixed password, from a CI secret, obfuscated in both apps, never in git or logs."""

    def test_the_apps_carry_a_derived_value_not_the_password_itself(self):
        secret = g.fixed_secret(FAKE_FIXED)
        self.assertEqual(secret, hmac.new(FAKE_FIXED.encode(), b"dolphin-connect fixed password v1", hashlib.sha256).hexdigest())
        self.assertRegex(secret, r"^[0-9a-f]{64}$")
        self.assertNotIn(FAKE_FIXED, secret)
        self.assertNotEqual(g.fixed_secret(FAKE_FIXED + "x"), secret)

    def test_the_rendered_file_recovers_the_value_but_never_shows_it(self):
        secret = g.fixed_secret(FAKE_FIXED)
        rust = g.render_fixed_rust(secret)
        a = _arrays(rust)
        self.assertEqual(set(a), {"FIXED_MASKED", "FIXED_PAD_A", "FIXED_PAD_B"})
        self.assertEqual({len(v) for v in a.values()}, {64})
        self.assertEqual(_unmask(a).decode("ascii"), secret)
        for plain in (FAKE_FIXED, secret, secret[:16]):
            self.assertNotIn(plain, rust)
        self.assertNotIn(secret.encode(), a["FIXED_MASKED"])
        self.assertIn("Obfuscated, not encrypted", rust)

    def test_every_build_gets_fresh_pads(self):
        secret = g.fixed_secret(FAKE_FIXED)
        self.assertNotEqual(_arrays(g.render_fixed_rust(secret))["FIXED_MASKED"], _arrays(g.render_fixed_rust(secret))["FIXED_MASKED"])
        zero = g.render_fixed_rust(secret, rand=lambda n: bytes(n))
        self.assertEqual(_arrays(zero)["FIXED_MASKED"], secret.encode())  # zero pads: the masking is a plain XOR

    def test_without_a_secret_the_arrays_are_empty(self):
        rust = g.render_fixed_rust(None)
        self.assertEqual({len(v) for v in _arrays(rust).values()}, {0})
        self.assertIn("pub static FIXED_MASKED: [u8; 0] = [];", rust)

    def test_a_weak_or_odd_value_is_refused(self):
        self.assertEqual(g.validate_fixed_password(FAKE_FIXED), [])
        for bad in ("short", " padded-value ", "tab\tinside-it", "newline\ninside"):
            self.assertTrue(g.validate_fixed_password(bad), repr(bad))

    def test_a_production_build_fails_without_the_secret(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            self.assertEqual(g.main(["production", "customer", "2.0.0"], root, {}), 1)
            self.assertEqual(g.main(["production", "technician", "2.0.0"], root, {g.FIXED_ENV: ""}), 1)
            self.assertFalse((root / "src" / "dolphin_fixed_generated.rs").exists())
            self.assertEqual(g.main(["production", "customer", "2.0.0"], root, {g.FIXED_ENV: "short"}), 1)

    def test_both_apps_get_the_same_value_and_no_file_shows_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            secret = g.fixed_secret(FAKE_FIXED)
            for variant in ("customer", "technician"):
                self.assertEqual(g.main(["production", variant, "2.0.0"], root, FAKE_ENV), 0)
                a = _arrays((root / "src" / "dolphin_fixed_generated.rs").read_text(encoding="utf-8"))
                self.assertEqual(_unmask(a).decode(), secret)
            for f in (root / "src" / "dolphin_generated.rs", root / "src" / "dolphin_fixed_generated.rs",
                      root / "flutter" / "lib" / "dolphin" / "brand.dart", root / "dolphin" / "build" / "baked-settings.json"):
                text = f.read_text(encoding="utf-8")
                self.assertNotIn(FAKE_FIXED, text, f)
                self.assertNotIn(secret, text, f)

    def test_a_dev_build_without_the_secret_leaves_the_feature_out(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            self.assertEqual(g.main(["dev", "customer", "2.0.0-dev.1"], root, {}), 0)
            a = _arrays((root / "src" / "dolphin_fixed_generated.rs").read_text(encoding="utf-8"))
            self.assertEqual({len(v) for v in a.values()}, {0})

    def test_checks_may_leave_it_out_on_purpose_in_any_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = _root(tmp)
            self.assertEqual(g.main(["production", "customer", "2.0.0", g.WITHOUT_FIXED], root, FAKE_ENV), 0)
            a = _arrays((root / "src" / "dolphin_fixed_generated.rs").read_text(encoding="utf-8"))
            self.assertEqual({len(v) for v in a.values()}, {0})
            self.assertEqual(g.main(["production", "customer", g.WITHOUT_FIXED], root, {}), 2)

    def test_the_customer_cannot_set_a_permanent_password_or_take_one_from_a_link(self):
        self.assertEqual(SETTINGS["builtin"]["disable-change-permanent-password"], "Y")
        self.assertEqual(SETTINGS["builtin"]["allow-deep-link-password"], "N")
        # The upstream permanent password stays off; the portal switches only Dolphin's own path (dolphin-fixed-password).
        self.assertEqual(SETTINGS["override"]["verification-method"], "use-temporary-password")
        self.assertNotIn("password", SETTINGS["hard"])
        self.assertNotIn("dolphin-fixed-password", json.dumps(SETTINGS))

    def test_the_secret_file_is_git_ignored(self):
        ignore = (HERE.parent / ".gitignore").read_text(encoding="utf-8").splitlines()
        self.assertIn("src/dolphin_fixed_generated.rs", ignore)


if __name__ == "__main__":
    unittest.main()
